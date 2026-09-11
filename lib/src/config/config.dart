/// Configuration model (SPEC §8): run-global settings that must agree across
/// every config root, and per-root settings that may differ.
library;

import 'package:glob/glob.dart';

import '../engine/result.dart';

/// Aggregation policy for closures and local functions (§6.3).
enum ClosureRollup {
  separate('separate'),
  includeInParent('include_in_parent');

  final String label;

  const ClosureRollup(this.label);

  static ClosureRollup? fromLabel(String label) {
    for (final v in values) {
      if (v.label == label) return v;
    }
    return null;
  }
}

enum FailOn {
  warn,
  fail;

  static FailOn? fromLabel(String label) {
    for (final v in values) {
      if (v.name == label) return v;
    }
    return null;
  }
}

/// Run-global settings: identical across every config root in a run.
class RunConfig {
  static const keyClosureRollup = 'closure_rollup';
  static const keyFailOn = 'fail_on';

  final ClosureRollup closureRollup;
  final FailOn failOn;

  /// Counting knobs keyed `<metric>.<knob>`, e.g. `cyclomatic.count_case_arms`.
  /// Metrics read their own keys and apply documented defaults.
  final Map<String, Object?> settings;

  const RunConfig({
    this.closureRollup = ClosureRollup.separate,
    this.failOn = FailOn.fail,
    this.settings = const {},
  });

  RunConfig copyWith({
    ClosureRollup? closureRollup,
    FailOn? failOn,
    Map<String, Object?>? settings,
  }) => RunConfig(
    closureRollup: closureRollup ?? this.closureRollup,
    failOn: failOn ?? this.failOn,
    settings: settings ?? this.settings,
  );
}

/// Per-metric settings layer. A null field inherits from the layer below
/// (built-in defaults at the bottom: enabled, no threshold).
class MetricConfig {
  final bool? enabled;
  final Threshold? threshold;

  const MetricConfig({this.enabled, this.threshold});

  bool get isEnabled => enabled ?? true;

  /// [over] wins wherever it says something.
  MetricConfig apply(MetricConfig over) => MetricConfig(
    enabled: over.enabled ?? enabled,
    threshold: over.threshold ?? threshold,
  );

  @override
  String toString() => 'MetricConfig(enabled: $enabled, threshold: $threshold)';
}

/// A path-glob `overrides` block: thresholds and enablement only (§8).
class ConfigOverride {
  /// Globs matched against the file path relative to the config root.
  final List<String> paths;
  final Map<String, MetricConfig> metrics;

  late final List<Glob> _globs = [for (final p in paths) Glob(p)];

  ConfigOverride({required this.paths, required this.metrics});

  bool matches(String relativePath) =>
      _globs.any((g) => g.matches(relativePath));
}

/// Per-root settings: may differ between config roots.
///
/// Precedence within a root, highest first: [forced] (CLI flags), the last
/// matching entry of [overrides], [metrics], built-in defaults.
class RootConfig {
  static const defaultExclude = ['**.g.dart', '**.freezed.dart'];

  /// Run-root-relative path of the config file, or null for built-in
  /// defaults.
  final String? source;

  /// Keyed by metric id. Metrics absent here are enabled with no threshold.
  final Map<String, MetricConfig> metrics;

  final List<ConfigOverride> overrides;

  /// CLI-level layer (`--threshold`), applied last.
  final Map<String, MetricConfig> forced;

  /// Discovery globs relative to the root; null means every `.dart` file.
  final List<String>? include;

  /// Discovery globs relative to the root.
  final List<String> exclude;

  const RootConfig({
    this.source,
    this.metrics = const {},
    this.overrides = const [],
    this.forced = const {},
    this.include,
    this.exclude = defaultExclude,
  });

  static const RootConfig defaults = RootConfig();

  /// The effective settings for [id] in the file at [relativePath] (relative
  /// to this root, the path a glob sees).
  MetricConfig metric(String id, {required String relativePath}) {
    var out = metrics[id] ?? const MetricConfig();
    for (final o in overrides) {
      final over = o.metrics[id];
      if (over != null && o.matches(relativePath)) out = out.apply(over);
    }
    final f = forced[id];
    return f == null ? out : out.apply(f);
  }

  /// Whether discovery under a directory picks up [relativePath]. Files named
  /// explicitly on the command line bypass this.
  bool selects(String relativePath) {
    final inc = include;
    if (inc != null && !inc.any((p) => Glob(p).matches(relativePath))) {
      return false;
    }
    return !exclude.any((p) => Glob(p).matches(relativePath));
  }

  RootConfig copyWith({
    String? source,
    Map<String, MetricConfig>? metrics,
    List<ConfigOverride>? overrides,
    Map<String, MetricConfig>? forced,
    List<String>? include,
    List<String>? exclude,
  }) => RootConfig(
    source: source ?? this.source,
    metrics: metrics ?? this.metrics,
    overrides: overrides ?? this.overrides,
    forced: forced ?? this.forced,
    include: include ?? this.include,
    exclude: exclude ?? this.exclude,
  );
}

/// Everything the engine needs besides sources and metrics.
class AnalysisConfig {
  final RunConfig run;

  /// Keyed by run-root-relative config root, matching `SourceFile.configRoot`.
  final Map<String, RootConfig> roots;

  const AnalysisConfig({
    this.run = const RunConfig(),
    this.roots = const {'.': RootConfig.defaults},
  });

  RootConfig root(String configRoot) =>
      roots[configRoot] ?? RootConfig.defaults;

  AnalysisConfig copyWith({RunConfig? run, Map<String, RootConfig>? roots}) =>
      AnalysisConfig(run: run ?? this.run, roots: roots ?? this.roots);
}

/// [path] relative to [configRoot], both run-root-relative with forward
/// slashes: the path a glob matches against. `.` and `` mean the run root.
String pathRelativeToRoot(String path, String configRoot) {
  if (configRoot.isEmpty || configRoot == '.') return path;
  final prefix = configRoot.endsWith('/') ? configRoot : '$configRoot/';
  return path.startsWith(prefix) ? path.substring(prefix.length) : path;
}
