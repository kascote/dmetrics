/// `analyzePaths`: the I/O layer composed with the pure engine (§5.2).
library;

import '../baseline/compare.dart';
import '../config/loader.dart';
import '../engine/engine.dart';
import '../engine/metric.dart';
import '../engine/report.dart' show Severity;
import '../report/run_result.dart';
import 'baseline_files.dart';
import 'discovery.dart';

/// Bad targets or flags: exit 3 (§7.2). Not an analysis outcome.
class UsageError implements Exception {
  final String message;

  const UsageError(this.message);

  @override
  String toString() => message;
}

/// Expands [targets] under [runRoot], resolves config roots and CLI layers,
/// runs the engine, then compares against each root's baseline unless
/// [noBaseline] ([baselinePath] forces one file for every root). Config
/// problems abort analysis with `status: errors` rather than measuring
/// under a config the user did not ask for. Throws [UsageError] when a
/// target or `--config` file does not exist.
RunResult analyzePaths(
  List<String> targets, {
  required List<Metric> metrics,
  required String runRoot,
  CliOverrides cli = const CliOverrides(),
  String? configPath,
  String? baselinePath,
  bool noBaseline = false,
}) {
  final specs = [for (final m in metrics) m.spec];
  final discovered = Discovery(
    runRoot: runRoot,
    metrics: specs,
    configPath: configPath,
  ).expand(targets);
  if (discovered.missingTargets.isNotEmpty) {
    throw UsageError(
      'no such file or directory: ${discovered.missingTargets.join(', ')}',
    );
  }

  final resolved = resolveRun(
    roots: discovered.roots,
    metrics: specs,
    cli: cli,
  );
  final diagnostics = [
    ...discovered.diagnostics,
    for (final p in resolved.problems)
      RunDiagnostic(
        path: p.source,
        line: p.line,
        column: p.column,
        message: p.message,
        severity: Severity.error,
      ),
  ];
  if (resolved.problems.isNotEmpty) {
    return RunResult(
      metrics: metrics,
      config: resolved.config,
      report: null,
      diagnostics: diagnostics,
    );
  }
  final report = analyze(discovered.sources, metrics, resolved.config);
  final baselines = readBaselines(
    resolved.config,
    runRoot: runRoot,
    forcedPath: baselinePath,
    disabled: noBaseline,
  );
  final compared = compareBaselines(
    report: report,
    baselines: baselines.byRoot,
    run: runKnobs(metrics, resolved.config.run),
    config: resolved.config.run,
    inRun: RunTargets(runRoot, targets).contains,
  );
  return RunResult(
    metrics: metrics,
    config: resolved.config,
    report: report,
    diagnostics: [
      ...diagnostics,
      ...baselines.diagnostics,
      for (final b in compared.problems)
        RunDiagnostic(path: b.path, message: b.message),
    ],
    baseline: compared.comparison,
  );
}
