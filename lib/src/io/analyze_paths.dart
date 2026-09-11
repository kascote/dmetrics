/// `analyzePaths`: the I/O layer composed with the pure engine (§5.2).
library;

import '../config/loader.dart';
import '../engine/engine.dart';
import '../engine/metric.dart';
import '../engine/report.dart' show Severity;
import '../report/run_result.dart';
import 'discovery.dart';

/// Bad targets or flags: exit 3 (§7.2). Not an analysis outcome.
class UsageError implements Exception {
  final String message;

  const UsageError(this.message);

  @override
  String toString() => message;
}

/// Expands [targets] under [runRoot], resolves config roots and CLI layers,
/// and runs the engine. Config problems abort analysis with `status: errors`
/// rather than measuring under a config the user did not ask for. Throws
/// [UsageError] when a target or `--config` file does not exist.
RunResult analyzePaths(
  List<String> targets, {
  required List<Metric> metrics,
  required String runRoot,
  CliOverrides cli = const CliOverrides(),
  String? configPath,
}) {
  final discovered = Discovery(
    runRoot: runRoot,
    metrics: metrics,
    configPath: configPath,
  ).expand(targets);
  if (discovered.missingTargets.isNotEmpty) {
    throw UsageError(
      'no such file or directory: ${discovered.missingTargets.join(', ')}',
    );
  }

  final resolved = resolveRun(
    roots: discovered.roots,
    metrics: metrics,
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
  return RunResult(
    metrics: metrics,
    config: resolved.config,
    report: analyze(discovered.sources, metrics, resolved.config),
    diagnostics: diagnostics,
  );
}
