/// Console report: one line per finding in `dart analyze` style, then a
/// summary. Only warn / fail / suppressed results and diagnostics print by
/// default; [all] prints every scope. Metric-agnostic: `value` and verdict
/// for any metric, contributor summary and the table-shaped marker when
/// there is one.
library;

import '../config/config.dart';
import '../engine/report.dart';
import '../engine/result.dart';
import 'run_result.dart';

String renderConsole(RunResult result, {bool all = false}) {
  final out = StringBuffer();
  final rollup = result.config.run.closureRollup;

  for (final d in result.diagnostics) {
    out.writeln(
      _diagnosticLine(d.path, d.line, d.column, d.severity, d.message),
    );
  }

  for (final f in result.files) {
    for (final d in f.diagnostics) {
      out.writeln(
        _diagnosticLine(
          f.path,
          d.span.start.line + 1,
          d.span.start.column + 1,
          d.severity,
          d.message,
        ),
      );
    }
    for (final s in f.scopes) {
      final ids = s.results.keys.toList()..sort();
      for (final id in ids) {
        final r = s.results[id]!;
        if (!all && r.verdict == Verdict.ok && r.suppressed == null) continue;
        out.writeln(_resultLine(f, s, id, r, rollup));
      }
    }
  }

  final summary = result.summary;
  final v = summary.verdicts;
  final parts = <String>[
    '${_n(summary.scopes, 'scope')} in ${_n(summary.files, 'file')}',
    if (summary.filesWithErrors > 0)
      '${_n(summary.filesWithErrors, 'file')} with parse errors',
    '${v[Verdict.fail]} fail, ${v[Verdict.warn]} warn, ${v[Verdict.ok]} ok, '
        '${summary.suppressed} suppressed',
    'status: ${result.status.name}',
  ];
  if (summary.files == 0 && result.diagnostics.isEmpty) {
    out.writeln('No files analyzed.');
  }
  out.writeln(parts.join(' • '));
  return out.toString();
}

String _diagnosticLine(
  String? path,
  int? line,
  int? column,
  Severity severity,
  String message,
) {
  final where = [
    ?path,
    if (line != null) '$line',
    if (column != null) '$column',
  ].join(':');
  return [if (where.isNotEmpty) where, severity.name, message].join(' • ');
}

String _resultLine(
  FileReport f,
  ScopeResult s,
  String metricId,
  MetricResult r,
  ClosureRollup rollup,
) {
  final start = s.scope.span.start;
  final tag = r.suppressed != null
      ? 'suppressed (${r.suppressed!.kind == SuppressionKind.ignore ? 'ignore' : 'ignore_for_file'})'
      : r.verdict.name;
  final t = r.threshold;
  var value = '$metricId ${r.value}';
  if (rollup == ClosureRollup.includeInParent && r.includes.isNotEmpty) {
    value +=
        ' (measured ${r.measured} + ${r.value - r.measured} from '
        '${_n(r.includes.length, 'nested scope')})';
  }
  if (t != null) value += ' [warn ≥ ${t.warn}, fail ≥ ${t.fail}]';
  final summary = r.measurement.contributorSummary;
  final table = r.measurement.tableShape;
  return [
    '${f.path}:${start.line + 1}:${start.column + 1}',
    tag,
    '${s.scope.kind.label} ${s.scope.qualifiedName}',
    value,
    if (summary.isNotEmpty)
      summary.entries.map((e) => '${e.key} ×${e.value}').join(', '),
    if (table != null) 'table-shaped: ${table.kind}',
  ].join(' • ');
}

String _n(int count, String noun) => '$count $noun${count == 1 ? '' : 's'}';
