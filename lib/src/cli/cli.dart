/// `dmetrics analyze [<file>|<dir> ...] [--json] [--config <path>]
/// [--fail-on warn|fail] [--set <key>=<value>] [--threshold <spec>]
/// [--baseline <path>] [--no-baseline] [--top N]` (§7.1), and
/// `dmetrics stats` / `dmetrics deps` / `dmetrics baseline` with the same
/// targets and config handling. `dmetrics agent` and `dmetrics init` take no
/// targets: the first prints the guide an LLM agent reads before
/// interpreting a report, the second installs a pointer to it in the
/// project's instructions file.
///
/// Exit codes (§7.2): 0 clean, 1 violations, 2 analysis incomplete, 3 usage.
/// `stats`, `deps` and `baseline` never exit 1: violations are their
/// subject, not their outcome. In `--json` mode nothing but the document
/// goes to stdout.
library;

import 'dart:io';

import 'package:args/args.dart';
import 'package:path/path.dart' as p;

import '../config/loader.dart';
import '../config/threshold.dart';
import '../engine/metric.dart';
import '../io/analyze_paths.dart';
import '../io/baseline_files.dart';
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
import 'agent.dart';

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
      )
      ..addOption(
        'baseline',
        valueHelp: 'path',
        help:
            'Compare against this baseline file in every config root, '
            'instead of each root\'s own.',
      )
      ..addFlag(
        'no-baseline',
        negatable: false,
        help: 'Compare against no baseline: every violation counts.',
      )
      ..addOption(
        'top',
        defaultsTo: '10',
        valueHelp: 'N',
        help: 'Console output: rows in the changed-since-baseline section.',
      );

/// `baseline` measures like `analyze` and writes instead of judging, so it
/// takes no output or verdict options.
ArgParser buildBaselineParser() => ArgParser()
  ..addOption(
    'config',
    valueHelp: 'path',
    help: 'Use one analysis_options.yaml as the config root for every file.',
  )
  ..addMultiOption(
    'set',
    splitCommas: false,
    valueHelp: 'key=value',
    help: 'Fix a run-global setting for the whole run, as analyze does.',
  )
  ..addOption(
    'output',
    valueHelp: 'path',
    help:
        'Write here instead of the config root\'s baseline path. '
        'Single-root runs only.',
  )
  ..addFlag('help', abbr: 'h', negatable: false, help: 'Show this help.');

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
    'Exit codes: 0 clean, 1 violations (analyze only: new or worse than the\n'
    'baseline when there is one), 2 analysis incomplete (parse errors,\n'
    'unreadable files, invalid config or baseline), 3 usage error.';

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
  'init' =>
    'Usage: $toolName init [options]\n\n'
        'Writes a short block into the project\'s instructions file (CLAUDE.md\n'
        'or AGENTS.md) that tells an LLM agent to run $toolName once per task\n'
        'and to read the guide (`$toolName agent`) before interpreting a\n'
        'report. The block sits between `$blockStart` and `$blockEnd`\n'
        'markers, so a re-run replaces it and leaves the rest of the file\n'
        'alone. `--skill` also writes the guide as a skill for Claude Code or\n'
        'Codex; both read the same SKILL.md format from their own directory.\n\n'
        '${buildInitParser().usage}\n\n'
        'Exit codes: 0 written, 2 a file could not be written, 3 usage error.',
  'baseline' =>
    'Usage: $toolName baseline [<file>|<dir> ...] [options]\n\n'
        'Measures the same way analyze does, then records every scope\'s\n'
        'values in each config root\'s baseline file (`baseline:` in\n'
        'analysis_options.yaml, default dmetrics_baseline.json next to it).\n'
        'Entries for files under the targets are replaced, the rest kept, so\n'
        'naming one file refreshes that file. analyze then reports each\n'
        'result as new, worse, baselined or changed, and exit 1 means new or\n'
        'worse. Refuses to write when analysis is incomplete.\n\n'
        '${buildBaselineParser().usage}\n\n'
        'Exit codes: 0 written, 2 analysis incomplete or a file could not be\n'
        'written, 3 usage error.',
  'deps' =>
    'Usage: $toolName deps [<file>|<dir> ...] [options]\n\n'
        'Measures the same way analyze does, then prints the dependency graph\n'
        'of the run as a whole: edge counts, the largest cycles, the libraries\n'
        'with the highest fan-out and fan-in with their instability, and the\n'
        'graph folded onto directories with the edges that close a directory\n'
        'cycle marked. Complete only when the whole package is in the run.\n\n'
        '${buildDepsParser().usage}\n\n$_exitCodes',
  _ =>
    'Usage: $toolName analyze  [<file>|<dir> ...] [options]\n'
        '       $toolName baseline [<file>|<dir> ...] [options]\n'
        '       $toolName stats    [<file>|<dir> ...] [options]\n'
        '       $toolName deps     [<file>|<dir> ...] [options]\n'
        '       $toolName agent\n'
        '       $toolName init     [options]\n\n'
        'analyze  Measure code metrics and print one consolidated report,\n'
        '         compared against the baseline when there is one.\n'
        'baseline Record the run as the baseline analyze compares against.\n'
        'stats    Distribution, threshold shares, sweep, contributor mix and\n'
        '         sibling clusters per metric, for calibrating thresholds.\n'
        'deps     The dependency graph of the run: cycles, hubs by fan-out\n'
        '         and fan-in, and the graph folded onto directories.\n'
        'agent    The guide an LLM agent reads before interpreting a report.\n'
        'init     Point the project\'s CLAUDE.md (or AGENTS.md) at that guide.\n\n'
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
  final early = _answerWithoutAnalysis(args, out, err, runRoot);
  if (early != null) return early;
  final command = args.first;
  if (!const {'analyze', 'stats', 'deps', 'baseline'}.contains(command)) {
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
    _insideRunRoot(
      parsed,
      command == 'baseline' ? 'output' : 'baseline',
      runRoot,
    );
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
      // Only analyze judges, so only analyze compares.
      baselinePath: command == 'analyze' ? parsed.option('baseline') : null,
      noBaseline: command != 'analyze' || parsed.flag('no-baseline'),
    );
  } on UsageError catch (e) {
    err.writeln(e.message);
    return exitUsage;
  }
  if (command == 'baseline') {
    return _emitBaseline(parsed, result, out, err, runRoot);
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

/// The invocations that need no analysis: usage, `--version`, `agent` and
/// `init`. Returns the exit code, or null when [args] name a command that
/// runs.
int? _answerWithoutAnalysis(
  List<String> args,
  StringSink out,
  StringSink err,
  String runRoot,
) {
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
    case 'agent' || 'init':
      return _runTextCommand(args.first, args.sublist(1), out, err, runRoot);
    default:
      return null;
  }
}

/// `agent` and `init` take no targets, so a stray path is a usage error
/// rather than silently printing the guide: the caller most likely meant
/// `analyze`. Exit 2 when `init` cannot write, the same code as an analysis
/// that could not complete.
int _runTextCommand(
  String command,
  List<String> rest,
  StringSink out,
  StringSink err,
  String runRoot,
) {
  try {
    final parser = command == 'agent' ? buildAgentParser() : buildInitParser();
    final parsed = parser.parse(rest);
    if (parsed.flag('help')) {
      out.writeln(usage(command));
      return 0;
    }
    if (command == 'init') {
      out.write(runInit(parsed, runRoot: runRoot));
      return 0;
    }
    if (parsed.rest.isNotEmpty) {
      throw UsageError(
        '`agent` takes no arguments, got `${parsed.rest.join(' ')}`',
      );
    }
    out.write(agentGuide);
    return 0;
  } on FormatException catch (e) {
    err.writeln('${e.message}\n\n${usage(command)}');
    return exitUsage;
  } on UsageError catch (e) {
    err.writeln('${e.message}\n\n${usage(command)}');
    return exitUsage;
  } on FileSystemException catch (e) {
    err.writeln(
      'could not write ${e.path}: ${e.osError?.message ?? e.message}',
    );
    return 2;
  }
}

ArgParser _parserFor(String command) => switch (command) {
  'stats' => buildStatsParser(),
  'deps' => buildDepsParser(),
  'baseline' => buildBaselineParser(),
  _ => buildAnalyzeParser(),
};

/// Exit 0 written, 2 when analysis was incomplete (the report is printed
/// so the reader sees why, and nothing is written: a baseline over
/// recovered ASTs would accept numbers that are not the code's) or a file
/// could not be written, 3 for `--output` across several roots.
int _emitBaseline(
  ArgResults parsed,
  RunResult result,
  StringSink out,
  StringSink err,
  String runRoot,
) {
  if (result.status == RunStatus.errors) {
    out.write(renderConsole(result));
    err.writeln('analysis incomplete: baseline not written');
    return RunStatus.errors.exitCode;
  }
  final output = parsed.option('output');
  if (output != null && result.config.roots.length > 1) {
    err.writeln(
      '--output needs a single config root; this run has '
      '${result.config.roots.length} (${(result.config.roots.keys.toList()..sort()).join(', ')})',
    );
    return exitUsage;
  }
  try {
    final written = writeBaselines(
      result,
      runRoot: runRoot,
      targets: parsed.rest,
      outputPath: output,
    );
    if (written.isEmpty) {
      out.writeln('No baseline written: no files analyzed.');
    }
    for (final w in written) {
      out.writeln(
        'wrote ${w.path}: ${_n(w.scopes, 'scope')} in ${_n(w.files, 'file')}, '
        '${w.violations} at or above warn',
      );
    }
    return 0;
  } on FileSystemException catch (e) {
    err.writeln(
      'could not write ${e.path}: ${e.osError?.message ?? e.message}',
    );
    return RunStatus.errors.exitCode;
  }
}

String _n(int count, String noun) => '$count $noun${count == 1 ? '' : 's'}';

/// A baseline stores paths relative to itself, so a file outside the run
/// root would hold `..` chains the run cannot resolve back. Usage error.
void _insideRunRoot(ArgResults parsed, String option, String runRoot) {
  if (!parsed.options.contains(option)) return;
  final value = parsed.option(option);
  if (value == null) return;
  final root = p.normalize(p.absolute(runRoot));
  final abs = p.normalize(p.isAbsolute(value) ? value : p.join(root, value));
  if (!p.isWithin(root, abs)) {
    throw UsageError(
      '--$option must be inside the current directory, got `$value`',
    );
  }
}

/// The CLI layer of the config, after the command's own options are checked
/// (`deps` validates its integers here so a bad one is a usage error before
/// any analysis runs).
CliOverrides _overridesFor(String command, ArgResults parsed) {
  if (command == 'deps') {
    _positive(parsed, 'top');
    _positive(parsed, 'depth');
  }
  if (command == 'analyze') {
    _positive(parsed, 'top');
    if (parsed.option('baseline') != null && parsed.flag('no-baseline')) {
      throw const UsageError('--baseline and --no-baseline exclude each other');
    }
  }
  return parseCliOverrides(
    set: parsed.multiOption('set'),
    thresholds: command == 'baseline'
        ? const []
        : parsed.multiOption('threshold'),
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
    out.write(
      renderConsole(
        result,
        all: parsed.flag('all'),
        top: _positive(parsed, 'top'),
        palette: palette,
      ),
    );
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
