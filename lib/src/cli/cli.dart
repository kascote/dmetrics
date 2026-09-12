/// `dmetrics analyze [<file>|<dir> ...] [--json] [--config <path>]
/// [--fail-on warn|fail] [--set <key>=<value>] [--threshold <spec>]` (§7.1),
/// and `dmetrics stats` / `dmetrics deps` with the same targets and config
/// handling. `dmetrics agent` takes no targets: it prints the guide an LLM
/// agent reads before interpreting a report.
///
/// Exit codes (§7.2): 0 clean, 1 violations, 2 analysis incomplete, 3 usage.
/// `stats` and `deps` never exit 1: violations are their subject, not their
/// outcome. In `--json` mode nothing but the document goes to stdout.
library;

import 'package:args/args.dart';

import '../config/loader.dart';
import '../config/threshold.dart';
import '../engine/metric.dart';
import '../io/analyze_paths.dart';
import '../report/ansi.dart';
import '../report/run_result.dart';
import '../metrics/cognitive/cognitive.dart';
import '../metrics/coupling/coupling.dart';
import '../metrics/cyclomatic/cyclomatic.dart';
import '../report/console_reporter.dart';
import '../report/deps.dart';
import '../report/json_reporter.dart';
import '../report/stats.dart';
import '../version.dart';
import 'agent_guide.dart';

const exitUsage = 3;

/// The compiled-in metric set (N3).
List<Metric> defaultMetrics() => [
  CyclomaticMetric(),
  CognitiveMetric(),
  CouplingMetric(),
];

/// Options every command takes: targets and config handling, output mode.
ArgParser _commonParser(String jsonHelp) => ArgParser()
  ..addFlag('json', negatable: false, help: jsonHelp)
  ..addOption(
    'config',
    valueHelp: 'path',
    help: 'Use one analysis_options.yaml as the config root for every file.',
  )
  ..addMultiOption(
    'set',
    splitCommas: false,
    valueHelp: 'key=value',
    help:
        'Fix a run-global setting for the whole run, e.g. '
        'cyclomatic.count_case_arms=false or closure_rollup=include_in_parent.',
  )
  ..addMultiOption(
    'threshold',
    splitCommas: false,
    valueHelp: 'metric=warn:N,fail:M',
    help: 'Override a metric\'s thresholds in every config root.',
  )
  ..addOption(
    'color',
    allowed: ['auto', 'always', 'never'],
    defaultsTo: 'auto',
    help:
        'Console output: auto colors when stdout is a terminal, NO_COLOR is '
        'unset and TERM is not dumb.',
  )
  ..addFlag('help', abbr: 'h', negatable: false, help: 'Show this help.');

ArgParser buildAnalyzeParser() =>
    _commonParser('Write the JSON report to stdout.')
      ..addOption(
        'fail-on',
        allowed: ['warn', 'fail'],
        valueHelp: 'warn|fail',
        help: 'Lowest verdict that counts as a violation (exit 1).',
      )
      ..addOption(
        'json-contributors',
        allowed: ['full', 'summary'],
        defaultsTo: 'full',
        help: 'summary drops the per-contributor list from the JSON report.',
      )
      ..addFlag(
        'all',
        negatable: false,
        help:
            'Console output: print every scope, not only warn/fail/suppressed.',
      );

ArgParser buildStatsParser() =>
    _commonParser('Write the stats document to stdout.');

ArgParser buildDepsParser() =>
    _commonParser('Write the dependency graph document to stdout.')
      ..addOption(
        'top',
        defaultsTo: '10',
        valueHelp: 'N',
        help:
            'Console output: rows per hub table and members listed per cycle.',
      )
      ..addOption(
        'depth',
        defaultsTo: '1',
        valueHelp: 'N',
        help:
            'Directory graph: levels kept under lib/src (or lib), so 1 folds '
            'lib/src/a/b/x.dart into `a` and 2 into `a/b`.',
      );

const _exitCodes =
    'Exit codes: 0 clean, 1 violations (analyze only), 2 analysis incomplete\n'
    '(parse errors, unreadable files, invalid config), 3 usage error.';

/// Top-level usage, or one command\'s when [command] is given.
String usage([String? command]) => switch (command) {
  'analyze' =>
    'Usage: $toolName analyze [<file>|<dir> ...] [options]\n\n'
        'Measures code metrics over the given files and directories (default:\n'
        'the current directory) and prints one consolidated report.\n\n'
        '${buildAnalyzeParser().usage}\n\n$_exitCodes',
  'stats' =>
    'Usage: $toolName stats [<file>|<dir> ...] [options]\n\n'
        'Measures the same way analyze does, then prints per metric the value\n'
        'distribution, the share of scopes at or above the thresholds, a sweep\n'
        'over candidate thresholds, the contributor mix and sibling clusters\n'
        '(same value and contributor mix). For calibrating thresholds.\n\n'
        '${buildStatsParser().usage}\n\n$_exitCodes',
  'agent' =>
    'Usage: $toolName agent\n\n'
        'Prints the guide for an LLM agent working in a project that uses\n'
        '$toolName: when to run it, how to read a report line, what each\n'
        'metric measures and what to do about a warning. No options.',
  'deps' =>
    'Usage: $toolName deps [<file>|<dir> ...] [options]\n\n'
        'Measures the same way analyze does, then prints the dependency graph\n'
        'of the run as a whole: edge counts, the largest cycles, the libraries\n'
        'with the highest fan-out and fan-in with their instability, and the\n'
        'graph folded onto directories with the edges that close a directory\n'
        'cycle marked. Complete only when the whole package is in the run.\n\n'
        '${buildDepsParser().usage}\n\n$_exitCodes',
  _ =>
    'Usage: $toolName analyze [<file>|<dir> ...] [options]\n'
        '       $toolName stats   [<file>|<dir> ...] [options]\n'
        '       $toolName deps    [<file>|<dir> ...] [options]\n'
        '       $toolName agent\n\n'
        'analyze  Measure code metrics and print one consolidated report.\n'
        'stats    Distribution, threshold shares, sweep, contributor mix and\n'
        '         sibling clusters per metric, for calibrating thresholds.\n'
        'deps     The dependency graph of the run: cycles, hubs by fan-out\n'
        '         and fan-in, and the graph folded onto directories.\n'
        'agent    The guide an LLM agent reads before interpreting a report.\n\n'
        'Run `$toolName <command> --help` for the command\'s options.\n\n'
        '$_exitCodes',
};

/// Runs the CLI and returns the exit code. [runRoot] is the working
/// directory paths are reported relative to. [stdoutIsTerminal] and
/// [environment] feed `--color auto`; the defaults never color.
int runCli(
  List<String> args, {
  required StringSink out,
  required StringSink err,
  required String runRoot,
  List<Metric>? metrics,
  bool stdoutIsTerminal = false,
  Map<String, String> environment = const {},
}) {
  final early = _answerWithoutAnalysis(args, out, err);
  if (early != null) return early;
  final command = args.first;
  if (!const {'analyze', 'stats', 'deps'}.contains(command)) {
    err.writeln('Unknown command `$command`.\n\n${usage()}');
    return exitUsage;
  }

  final ArgResults parsed;
  final CliOverrides cli;
  try {
    parsed = _parserFor(command).parse(args.sublist(1));
    if (parsed.flag('help')) {
      out.writeln(usage(command));
      return 0;
    }
    cli = _overridesFor(command, parsed);
  } on FormatException catch (e) {
    err.writeln('${e.message}\n\n${usage(command)}');
    return exitUsage;
  } on UsageError catch (e) {
    err.writeln('${e.message}\n\n${usage(command)}');
    return exitUsage;
  }

  final RunResult result;
  try {
    result = analyzePaths(
      parsed.rest,
      metrics: metrics ?? defaultMetrics(),
      runRoot: runRoot,
      cli: cli,
      configPath: parsed.option('config'),
    );
  } on UsageError catch (e) {
    err.writeln(e.message);
    return exitUsage;
  }

  final palette = parsed.flag('json')
      ? Palette.plain
      : resolveColor(
          ColorMode.values.byName(parsed.option('color')!),
          stdoutIsTerminal: stdoutIsTerminal,
          environment: environment,
        );
  return switch (command) {
    'stats' => _emitStats(parsed, result, out, palette),
    'deps' => _emitDeps(parsed, result, out, palette),
    _ => _emitReport(parsed, result, out, palette),
  };
}

/// The invocations that need no analysis: usage, `--version` and `agent`.
/// Returns the exit code, or null when [args] name a command that runs.
int? _answerWithoutAnalysis(List<String> args, StringSink out, StringSink err) {
  if (args.isEmpty) {
    err.writeln(usage());
    return exitUsage;
  }
  switch (args.first) {
    case '--help' || '-h':
      out.writeln(usage());
      return 0;
    case '--version':
      out.writeln('$toolName $toolVersion');
      return 0;
    case 'agent':
      return _emitAgentGuide(args.sublist(1), out, err);
    default:
      return null;
  }
}

/// `agent` has no options and no targets, so anything after it but `--help`
/// is a usage error: a stray path would silently print the guide instead of
/// telling the caller they meant `analyze`.
int _emitAgentGuide(List<String> rest, StringSink out, StringSink err) {
  if (rest.isEmpty) {
    out.write(agentGuide);
    return 0;
  }
  if (rest.length == 1 && (rest.first == '--help' || rest.first == '-h')) {
    out.writeln(usage('agent'));
    return 0;
  }
  err.writeln(
    '`agent` takes no arguments, got `${rest.join(' ')}`.\n\n${usage('agent')}',
  );
  return exitUsage;
}

ArgParser _parserFor(String command) => switch (command) {
  'stats' => buildStatsParser(),
  'deps' => buildDepsParser(),
  _ => buildAnalyzeParser(),
};

/// The CLI layer of the config, after the command's own options are checked
/// (`deps` validates its integers here so a bad one is a usage error before
/// any analysis runs).
CliOverrides _overridesFor(String command, ArgResults parsed) {
  if (command == 'deps') {
    _positive(parsed, 'top');
    _positive(parsed, 'depth');
  }
  return parseCliOverrides(
    set: parsed.multiOption('set'),
    thresholds: parsed.multiOption('threshold'),
    failOn: command == 'analyze' ? parsed.option('fail-on') : null,
  );
}

/// Exit 0 or 2, like stats: the graph is the subject, not a verdict.
int _emitDeps(
  ArgResults parsed,
  RunResult result,
  StringSink out,
  Palette palette,
) {
  final deps = computeDeps(result, depth: _positive(parsed, 'depth'));
  if (parsed.flag('json')) {
    out.writeln(renderDepsJson(deps, status: result.status));
  } else {
    out.write(
      renderDepsConsole(deps, top: _positive(parsed, 'top'), palette: palette),
    );
  }
  return result.status == RunStatus.errors ? RunStatus.errors.exitCode : 0;
}

int _positive(ArgResults parsed, String option) {
  final raw = parsed.option(option)!;
  final n = int.tryParse(raw);
  if (n == null || n < 1) {
    throw UsageError('--$option expects a positive integer, got `$raw`');
  }
  return n;
}

/// Exit 0 or 2: violations are the subject of stats, not its outcome.
int _emitStats(
  ArgResults parsed,
  RunResult result,
  StringSink out,
  Palette palette,
) {
  final stats = computeStats(result);
  if (parsed.flag('json')) {
    out.writeln(renderStatsJson(stats, status: result.status));
  } else {
    out.write(renderStatsConsole(stats, palette: palette));
  }
  return result.status == RunStatus.errors ? RunStatus.errors.exitCode : 0;
}

int _emitReport(
  ArgResults parsed,
  RunResult result,
  StringSink out,
  Palette palette,
) {
  if (parsed.flag('json')) {
    out.writeln(
      renderJson(
        result,
        contributors: parsed.option('json-contributors') == 'summary'
            ? ContributorDetail.summary
            : ContributorDetail.full,
      ),
    );
  } else {
    out.write(renderConsole(result, all: parsed.flag('all'), palette: palette));
  }
  return result.exitCode;
}

/// Parses `--set`, `--threshold` and `--fail-on` into the CLI layer.
CliOverrides parseCliOverrides({
  List<String> set = const [],
  List<String> thresholds = const [],
  String? failOn,
}) {
  final settings = <String, String>{};
  for (final s in set) {
    final eq = s.indexOf('=');
    if (eq <= 0 || eq == s.length - 1) {
      throw UsageError('--set expects key=value, got `$s`');
    }
    settings[s.substring(0, eq)] = s.substring(eq + 1);
  }
  if (failOn != null) settings['fail_on'] = failOn;

  final forced = <String, Threshold>{};
  for (final t in thresholds) {
    final m = _thresholdSpec.firstMatch(t);
    if (m == null) {
      throw UsageError(
        '--threshold expects metric=warn:N,fail:M (in either order), got `$t`',
      );
    }
    final warn = num.parse((m.namedGroup('warn') ?? m.namedGroup('warn2'))!);
    final fail = num.parse((m.namedGroup('fail') ?? m.namedGroup('fail2'))!);
    if (warn > fail) {
      throw UsageError('--threshold: warn must not exceed fail in `$t`');
    }
    forced[m.namedGroup('metric')!] = Threshold(warn: warn, fail: fail);
  }
  return CliOverrides(set: settings, thresholds: forced);
}

final _thresholdSpec = RegExp(
  r'^(?<metric>[a-z][a-z0-9_]*)='
  r'(?:warn:(?<warn>\d+(?:\.\d+)?),fail:(?<fail>\d+(?:\.\d+)?)'
  r'|fail:(?<fail2>\d+(?:\.\d+)?),warn:(?<warn2>\d+(?:\.\d+)?))$',
);
