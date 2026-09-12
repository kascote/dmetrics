/// The outcome of one invocation: the engine's report plus everything the
/// I/O layer found out around it, with the §7.2 status and exit code.
library;

import '../config/config.dart';
import '../config/threshold.dart';
import '../engine/metric.dart';
import '../engine/report.dart';

enum RunStatus {
  ok(0),
  violations(1),
  errors(2);

  final int exitCode;

  const RunStatus(this.exitCode);
}

/// A problem not attached to a parsed file: unreadable files, config errors.
class RunDiagnostic {
  /// Run-root-relative path, or null for run-wide problems.
  final String? path;
  final int? line;
  final int? column;
  final String message;
  final Severity severity;

  const RunDiagnostic({
    required this.message,
    this.path,
    this.line,
    this.column,
    this.severity = Severity.error,
  });

  @override
  String toString() {
    final where = [
      if (path != null) path,
      if (line != null) '$line',
      if (column != null) '$column',
    ].join(':');
    return where.isEmpty
        ? '${severity.name}: $message'
        : '$where: ${severity.name}: $message';
  }
}

class RunSummary {
  final int files;
  final int filesWithErrors;
  final int scopes;
  final Map<Verdict, int> verdicts;
  final int suppressed;

  const RunSummary({
    required this.files,
    required this.filesWithErrors,
    required this.scopes,
    required this.verdicts,
    required this.suppressed,
  });
}

class RunResult {
  final List<Metric> metrics;
  final AnalysisConfig config;

  /// Null when config problems prevented analysis from running.
  final Report? report;
  final List<RunDiagnostic> diagnostics;

  const RunResult({
    required this.metrics,
    required this.config,
    required this.report,
    this.diagnostics = const [],
  });

  List<FileReport> get files => report?.files ?? const [];

  /// Errors win over violations (§7.2).
  RunStatus get status {
    if (diagnostics.any((d) => d.severity == Severity.error) ||
        files.any((f) => f.partial)) {
      return RunStatus.errors;
    }
    return hasViolations ? RunStatus.violations : RunStatus.ok;
  }

  int get exitCode => status.exitCode;

  /// Any non-suppressed verdict at or above `fail_on`.
  bool get hasViolations {
    final floor = config.run.failOn == FailOn.warn
        ? Verdict.warn
        : Verdict.fail;
    for (final f in files) {
      for (final s in f.scopes) {
        for (final r in s.results.values) {
          if (r.suppressed == null && r.verdict.index >= floor.index) {
            return true;
          }
        }
      }
    }
    return false;
  }

  RunSummary get summary {
    final verdicts = {for (final v in Verdict.values) v: 0};
    var scopes = 0;
    var suppressed = 0;
    for (final f in files) {
      scopes += f.scopes.length;
      for (final s in f.scopes) {
        for (final r in s.results.values) {
          verdicts[r.verdict] = verdicts[r.verdict]! + 1;
          if (r.suppressed != null) suppressed++;
        }
      }
    }
    return RunSummary(
      files: files.length,
      filesWithErrors: files.where((f) => f.partial).length,
      scopes: scopes,
      verdicts: verdicts,
      suppressed: suppressed,
    );
  }
}
