import 'package:source_span/source_span.dart' show FileSpan;

import '../config/config.dart';
import 'result.dart';
import 'scope.dart';
import 'source.dart';

enum Severity { error, warning, info }

/// A parse diagnostic attached to a file report.
class Diagnostic {
  final String message;
  final FileSpan span;
  final Severity severity;

  const Diagnostic({
    required this.message,
    required this.span,
    required this.severity,
  });

  @override
  String toString() =>
      '${severity.name}: $message @${span.start.line + 1}:${span.start.column + 1}';
}

/// One measured scope with its per-metric results, keyed by metric id.
class ScopeResult {
  final ScopeContext scope;
  final Map<String, MetricResult> results;

  const ScopeResult({required this.scope, required this.results});

  ScopeId get id => scope.id;

  @override
  String toString() => 'ScopeResult(${scope.id}: $results)';
}

class FileReport {
  final SourceFile source;
  final List<Diagnostic> diagnostics;

  /// Measured scopes in report order (start offset, then end offset).
  final List<ScopeResult> scopes;

  const FileReport({
    required this.source,
    required this.diagnostics,
    required this.scopes,
  });

  String get path => source.path;

  /// True when parsing reported errors; scopes are then best-effort.
  bool get partial => diagnostics.any((d) => d.severity == Severity.error);

  ScopeResult? scopeById(ScopeId id) {
    for (final s in scopes) {
      if (s.id == id) return s;
    }
    return null;
  }
}

/// The engine's output for one run.
class Report {
  final AnalysisConfig config;
  final List<FileReport> files;

  const Report({required this.config, required this.files});
}
