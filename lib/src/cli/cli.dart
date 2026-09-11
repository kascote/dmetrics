/// `metra analyze [<file>|<dir> ...] [--json] [--config <path>]
/// [--fail-on warn|fail] [--set <key>=<value>] [--threshold <spec>]` (§7.1).
///
/// Exit codes (§7.2): 0 clean, 1 violations, 2 analysis incomplete, 3 usage.
/// In `--json` mode nothing but the report goes to stdout.
library;

import 'package:args/args.dart';

import '../config/loader.dart';
import '../engine/metric.dart';
import '../engine/result.dart';
import '../io/analyze_paths.dart';
import '../report/run_result.dart';
import '../metrics/cyclomatic/cyclomatic.dart';
import '../report/console_reporter.dart';
import '../report/json_reporter.dart';
import '../version.dart';

const exitUsage = 3;

/// The compiled-in metric set (N3).
List<Metric> defaultMetrics() => [CyclomaticMetric()];

ArgParser buildAnalyzeParser() => ArgParser()
  ..addFlag('json', negatable: false, help: 'Write the JSON report to stdout.')
  ..addOption(
    'config',
    valueHelp: 'path',
    help: 'Use one analysis_options.yaml as the config root for every file.',
  )
  ..addOption(
    'fail-on',
    allowed: ['warn', 'fail'],
    valueHelp: 'warn|fail',
    help: 'Lowest verdict that counts as a violation (exit 1).',
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
    'json-contributors',
    allowed: ['full', 'summary'],
    defaultsTo: 'full',
    help: 'summary drops the per-contributor list from the JSON report.',
  )
  ..addFlag(
    'all',
    negatable: false,
    help: 'Console output: print every scope, not only warn/fail/suppressed.',
  )
  ..addFlag('help', abbr: 'h', negatable: false, help: 'Show this help.');

String usage() =>
    'Usage: $toolName analyze [<file>|<dir> ...] [options]\n\n'
    'Measures code metrics over the given files and directories (default: the\n'
    'current directory) and prints one consolidated report.\n\n'
    '${buildAnalyzeParser().usage}\n\n'
    'Exit codes: 0 clean, 1 violations, 2 analysis incomplete (parse errors,\n'
    'unreadable files, invalid config), 3 usage error.';

/// Runs the CLI and returns the exit code. [runRoot] is the working
/// directory paths are reported relative to.
int runCli(
  List<String> args, {
  required StringSink out,
  required StringSink err,
  required String runRoot,
  List<Metric>? metrics,
}) {
  if (args.isEmpty || args.first == '--help' || args.first == '-h') {
    (args.isEmpty ? err : out).writeln(usage());
    return args.isEmpty ? exitUsage : 0;
  }
  if (args.first == '--version') {
    out.writeln('$toolName $toolVersion');
    return 0;
  }
  if (args.first != 'analyze') {
    err.writeln('Unknown command `${args.first}`.\n\n${usage()}');
    return exitUsage;
  }

  final ArgResults parsed;
  try {
    parsed = buildAnalyzeParser().parse(args.sublist(1));
  } on FormatException catch (e) {
    err.writeln('${e.message}\n\n${usage()}');
    return exitUsage;
  }
  if (parsed.flag('help')) {
    out.writeln(usage());
    return 0;
  }

  final CliOverrides cli;
  try {
    cli = parseCliOverrides(
      set: parsed.multiOption('set'),
      thresholds: parsed.multiOption('threshold'),
      failOn: parsed.option('fail-on'),
    );
  } on UsageError catch (e) {
    err.writeln('${e.message}\n\n${usage()}');
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
    out.write(renderConsole(result, all: parsed.flag('all')));
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
