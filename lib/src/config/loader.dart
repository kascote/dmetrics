/// Config loading (SPEC §8): the `dmetrics:` section of `analysis_options.yaml`
/// and the reconciliation of run-global settings across roots and CLI flags.
///
/// File shape:
///
/// ```yaml
/// dmetrics:
///   fail_on: fail                    # run-global: warn | fail
///   closure_rollup: separate         # run-global: separate | include_in_parent
///   include: [lib/**]                # per-root discovery globs; default: all
///   exclude: ['**.g.dart']           # per-root; default: **.g.dart, **.freezed.dart
///   metrics:
///     cyclomatic:
///       enabled: true
///       thresholds: {warn: 8, fail: 12} # or `none` to drop the built-in default
///       count_case_arms: true        # run-global knob, declared by the metric
///       count_null_coalescing: true
///   overrides:                       # thresholds and enablement only
///     - paths: [test/**]
///       metrics:
///         cyclomatic: {thresholds: {warn: 15, fail: 25}}
/// ```
///
/// Globs match the file path relative to the config root. Run-global keys
/// must agree across every root in a run unless `--set` fixes them.
library;

import 'package:source_span/source_span.dart' show SourceSpan;
import 'package:yaml/yaml.dart';

import '../engine/metric.dart';
import '../engine/result.dart';
import 'config.dart';

/// The YAML key the config lives under.
const configKey = 'dmetrics';

/// Something wrong with a config file or the combination of config files.
class ConfigProblem {
  /// Run-root-relative path of the file, or null for cross-file problems.
  final String? source;

  /// 1-based, when the problem points at a YAML node.
  final int? line;
  final int? column;
  final String message;

  const ConfigProblem(this.message, {this.source, this.line, this.column});

  factory ConfigProblem.at(String message, String source, SourceSpan? span) =>
      ConfigProblem(
        message,
        source: source,
        line: span == null ? null : span.start.line + 1,
        column: span == null ? null : span.start.column + 1,
      );

  @override
  String toString() {
    final where = [
      if (source != null) source,
      if (line != null) '$line',
      if (column != null) '$column',
    ].join(':');
    return where.isEmpty ? message : '$where: $message';
  }
}

/// One parsed config file.
class LoadedConfig {
  /// Run-root-relative path of the file.
  final String source;
  final RootConfig root;

  /// Run-global values this file states, keyed as in [RunConfig.settings]
  /// plus [RunConfig.keyClosureRollup] and [RunConfig.keyFailOn].
  final Map<String, Object?> runValues;
  final List<ConfigProblem> problems;

  const LoadedConfig({
    required this.source,
    required this.root,
    required this.runValues,
    required this.problems,
  });
}

/// Parses the `dmetrics:` section of [text]. Returns null when there is none
/// (the file then does not make its directory a config root).
LoadedConfig? parseDmetricsConfig(
  String text, {
  required String source,
  required List<Metric> metrics,
}) {
  final YamlNode doc;
  try {
    doc = loadYamlNode(text, sourceUrl: Uri.file(source));
  } on YamlException catch (e) {
    return LoadedConfig(
      source: source,
      root: RootConfig(source: source),
      runValues: const {},
      problems: [
        ConfigProblem.at('invalid YAML: ${e.message}', source, e.span),
      ],
    );
  }
  if (doc is! YamlMap) return null;
  final section = doc.nodes[configKey];
  if (section == null) return null;
  return _Parser(source, metrics).parse(section);
}

class _Parser {
  final String source;
  final Map<String, Metric> metrics;
  final problems = <ConfigProblem>[];
  final runValues = <String, Object?>{};

  _Parser(this.source, List<Metric> metrics)
    : metrics = {for (final m in metrics) m.id: m};

  void problem(String message, YamlNode? node) =>
      problems.add(ConfigProblem.at(message, source, node?.span));

  LoadedConfig parse(YamlNode section) {
    var root = RootConfig(source: source);
    if (section is YamlScalar && section.value == null) {
      // `dmetrics:` with nothing under it: a root with defaults.
    } else if (section is! YamlMap) {
      problem('`$configKey` must be a map', section);
    } else {
      for (final entry in section.nodes.entries) {
        final key = '${(entry.key as YamlNode).value}';
        final node = entry.value;
        switch (key) {
          case RunConfig.keyFailOn:
            final v = _enumValue(node, key, FailOn.values.map((f) => f.name));
            if (v != null) runValues[key] = FailOn.fromLabel(v);
          case RunConfig.keyClosureRollup:
            final v = _enumValue(
              node,
              key,
              ClosureRollup.values.map((c) => c.label),
            );
            if (v != null) runValues[key] = ClosureRollup.fromLabel(v);
          case 'include':
            final globs = _stringList(node, key);
            if (globs != null) root = root.copyWith(include: globs);
          case 'exclude':
            final globs = _stringList(node, key);
            if (globs != null) root = root.copyWith(exclude: globs);
          case 'metrics':
            root = root.copyWith(
              metrics: _metricsMap(node, allowRunGlobal: true),
            );
          case 'overrides':
            root = root.copyWith(overrides: _overrides(node));
          default:
            problem(
              'unknown key `$key` under `$configKey`',
              entry.key as YamlNode,
            );
        }
      }
    }
    return LoadedConfig(
      source: source,
      root: root,
      runValues: runValues,
      problems: problems,
    );
  }

  String? _enumValue(YamlNode node, String key, Iterable<String> allowed) {
    final v = node is YamlScalar ? node.value : null;
    if (v is String && allowed.contains(v)) return v;
    problem('`$key` must be one of ${allowed.join(', ')}', node);
    return null;
  }

  List<String>? _stringList(YamlNode node, String key) {
    if (node is YamlList && node.nodes.every((n) => n.value is String)) {
      return [for (final n in node.nodes) n.value as String];
    }
    problem('`$key` must be a list of glob strings', node);
    return null;
  }

  Map<String, MetricConfig> _metricsMap(
    YamlNode node, {
    required bool allowRunGlobal,
  }) {
    if (node is! YamlMap) {
      problem('`metrics` must be a map keyed by metric id', node);
      return const {};
    }
    final out = <String, MetricConfig>{};
    for (final entry in node.nodes.entries) {
      final id = '${(entry.key as YamlNode).value}';
      final metric = metrics[id];
      if (metric == null) {
        problem(
          'unknown metric `$id` (known: ${metrics.keys.join(', ')})',
          entry.key as YamlNode,
        );
        continue;
      }
      out[id] = _metricConfig(metric, entry.value, allowRunGlobal);
    }
    return out;
  }

  MetricConfig _metricConfig(
    Metric metric,
    YamlNode node,
    bool allowRunGlobal,
  ) {
    if (node is! YamlMap) {
      problem('`${metric.id}` must be a map', node);
      return const MetricConfig();
    }
    bool? enabled;
    Threshold? threshold;
    for (final entry in node.nodes.entries) {
      final key = '${(entry.key as YamlNode).value}';
      final value = entry.value;
      switch (key) {
        case 'enabled':
          if (value.value is bool) {
            enabled = value.value as bool;
          } else {
            problem('`enabled` must be true or false', value);
          }
        case 'thresholds':
          threshold = _threshold(value);
        default:
          final fullKey = '${metric.id}.$key';
          if (!metric.settingDefaults.containsKey(fullKey)) {
            problem(
              'unknown setting `$key` for `${metric.id}`',
              entry.key as YamlNode,
            );
          } else if (!allowRunGlobal) {
            problem(
              '`$key` is run-global and cannot be set in `overrides`',
              entry.key as YamlNode,
            );
          } else {
            final checked = checkSettingValue(
              fullKey,
              value.value,
              metric.settingDefaults[fullKey],
            );
            if (checked == null) {
              problem(
                '`$key` must be a ${_typeName(metric.settingDefaults[fullKey])}',
                value,
              );
            } else {
              runValues[fullKey] = value.value;
            }
          }
      }
    }
    return MetricConfig(enabled: enabled, threshold: threshold);
  }

  Threshold? _threshold(YamlNode node) {
    if (node is YamlScalar && node.value == 'none') return Threshold.none;
    if (node is YamlMap) {
      final warn = node.nodes['warn']?.value;
      final fail = node.nodes['fail']?.value;
      if (warn is num && fail is num && warn <= fail) {
        return Threshold(warn: warn, fail: fail);
      }
    }
    problem(
      '`thresholds` must be `{warn: n, fail: m}` with n <= m, or `none`',
      node,
    );
    return null;
  }

  List<ConfigOverride> _overrides(YamlNode node) {
    if (node is! YamlList) {
      problem('`overrides` must be a list', node);
      return const [];
    }
    final out = <ConfigOverride>[];
    for (final item in node.nodes) {
      if (item is! YamlMap) {
        problem('each override must be a map with `paths` and `metrics`', item);
        continue;
      }
      final paths = item.nodes['paths'];
      final globs = paths == null ? null : _stringList(paths, 'paths');
      if (paths == null) problem('override is missing `paths`', item);
      final metricsNode = item.nodes['metrics'];
      if (metricsNode == null) problem('override is missing `metrics`', item);
      for (final entry in item.nodes.entries) {
        final key = '${(entry.key as YamlNode).value}';
        if (key != 'paths' && key != 'metrics') {
          problem(
            '`$key` is not allowed in `overrides` (thresholds and enablement only)',
            entry.key as YamlNode,
          );
        }
      }
      if (globs == null || metricsNode == null) continue;
      out.add(
        ConfigOverride(
          paths: globs,
          metrics: _metricsMap(metricsNode, allowRunGlobal: false),
        ),
      );
    }
    return out;
  }
}

String _typeName(Object? sample) => switch (sample) {
  bool() => 'boolean',
  int() => 'integer',
  num() => 'number',
  String() => 'string',
  _ => sample.runtimeType.toString(),
};

/// [value] coerced to the type of [sample], or null when it does not fit.
/// Strings from `--set` are parsed; YAML values must already be typed.
Object? checkSettingValue(String key, Object? value, Object? sample) {
  switch (sample) {
    case bool():
      if (value is bool) return value;
      if (value == 'true') return true;
      if (value == 'false') return false;
      return null;
    case int():
      if (value is int) return value;
      if (value is String) return int.tryParse(value);
      return null;
    case num():
      if (value is num) return value;
      if (value is String) return num.tryParse(value);
      return null;
    case String():
      return value is String ? value : null;
    default:
      return value;
  }
}

/// Command-line layers (§8 precedence 1).
class CliOverrides {
  /// `--set key=value`, raw. Wins over every config file, run-wide.
  final Map<String, String> set;

  /// `--threshold metric=warn:n,fail:m`, applied in every root.
  final Map<String, Threshold> thresholds;

  const CliOverrides({this.set = const {}, this.thresholds = const {}});
}

class ResolvedRun {
  final AnalysisConfig config;
  final List<ConfigProblem> problems;

  const ResolvedRun(this.config, this.problems);
}

/// Builds the [AnalysisConfig] for a run from every root's loaded config
/// (null: a root using built-in defaults), the CLI layer, and the metrics'
/// declared knob defaults. Run-global keys that disagree between roots are
/// a problem unless `--set` fixes them (§8).
ResolvedRun resolveRun({
  required Map<String, LoadedConfig?> roots,
  required List<Metric> metrics,
  CliOverrides cli = const CliOverrides(),
}) {
  final problems = <ConfigProblem>[
    for (final r in roots.values)
      if (r != null) ...r.problems,
  ];

  // Every run-global key with its default; the sample gives the type.
  final defaults = <String, Object?>{
    RunConfig.keyClosureRollup: ClosureRollup.separate,
    RunConfig.keyFailOn: FailOn.fail,
    for (final m in metrics) ...m.settingDefaults,
  };

  final values = {...defaults};
  _applyRootValues(values, roots, cli, problems);
  _applyCliSet(values, defaults, cli, problems);

  return ResolvedRun(_assemble(values, roots, cli), problems);
}

/// Precedence 3: values the roots state, which must agree with each other
/// unless `--set` names the key.
void _applyRootValues(
  Map<String, Object?> values,
  Map<String, LoadedConfig?> roots,
  CliOverrides cli,
  List<ConfigProblem> problems,
) {
  for (final key in values.keys.toList()) {
    // value → the sources that state it, for the conflict message.
    final stated = <Object?, List<String>>{};
    for (final r in roots.values) {
      if (r == null || !r.runValues.containsKey(key)) continue;
      stated.putIfAbsent(r.runValues[key], () => []).add(r.source);
    }
    if (stated.length > 1 && !cli.set.containsKey(key)) {
      final sides = stated.entries
          .map((e) => '${e.value.join(', ')} says ${_show(e.key)}')
          .join('; ');
      problems.add(
        ConfigProblem(
          'run-global `$key` differs between config roots ($sides); '
          'pass --set $key=<value> to fix it for the whole run',
        ),
      );
    } else if (stated.length == 1) {
      values[key] = stated.keys.single;
    }
  }
}

/// Precedence 1: `--set key=value`, typed against the key's default.
void _applyCliSet(
  Map<String, Object?> values,
  Map<String, Object?> defaults,
  CliOverrides cli,
  List<ConfigProblem> problems,
) {
  for (final entry in cli.set.entries) {
    final key = entry.key;
    if (!defaults.containsKey(key)) {
      problems.add(
        ConfigProblem(
          '--set: unknown run-global key `$key` (known: ${defaults.keys.join(', ')})',
        ),
      );
      continue;
    }
    final Object? parsed = switch (key) {
      RunConfig.keyClosureRollup => ClosureRollup.fromLabel(entry.value),
      RunConfig.keyFailOn => FailOn.fromLabel(entry.value),
      _ => checkSettingValue(key, entry.value, defaults[key]),
    };
    if (parsed == null) {
      problems.add(
        ConfigProblem('--set: invalid value `${entry.value}` for `$key`'),
      );
    } else {
      values[key] = parsed;
    }
  }
}

/// The final config: resolved run-global values split into the typed
/// [RunConfig] fields and the metric settings map, plus every root's
/// per-root config with `--threshold` forced on top.
AnalysisConfig _assemble(
  Map<String, Object?> values,
  Map<String, LoadedConfig?> roots,
  CliOverrides cli,
) {
  final forced = {
    for (final e in cli.thresholds.entries)
      e.key: MetricConfig(threshold: e.value),
  };
  return AnalysisConfig(
    run: RunConfig(
      closureRollup: values[RunConfig.keyClosureRollup] as ClosureRollup,
      failOn: values[RunConfig.keyFailOn] as FailOn,
      settings: {
        for (final e in values.entries)
          if (e.key != RunConfig.keyClosureRollup &&
              e.key != RunConfig.keyFailOn)
            e.key: e.value,
      },
    ),
    roots: {
      for (final e in roots.entries)
        e.key: (e.value?.root ?? RootConfig.defaults).copyWith(forced: forced),
    },
  );
}

String _show(Object? v) => switch (v) {
  ClosureRollup() => v.label,
  FailOn() => v.name,
  _ => '$v',
};
