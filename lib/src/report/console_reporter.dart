/// Console report: one line per finding in `dart analyze` style, then a
/// summary. Only warn / fail / suppressed results and diagnostics print by
/// default; [all] prints every scope. Metric-agnostic: `value` and verdict
/// for any metric, contributor summary and the table-shaped marker when
/// there is one, plus a note for the one `detail` shape it knows (cycle
/// membership); any other `detail` is left to the JSON report.
///
/// With a baseline, the tag carries the result's status (`fail (new)`,
/// `fail (worse, was 11)`, `fail (baselined)` dimmed like a suppression so
/// accepted debt reads as background) and the drift that did not print as
/// a finding gets its own section, largest delta first, [top] rows.
library;

import '../baseline/compare.dart';
import '../config/config.dart';
import '../config/threshold.dart';
import '../engine/report.dart';
import '../engine/result.dart';
import 'ansi.dart';
import 'run_result.dart';

String renderConsole(
  RunResult result, {
  bool all = false,
  int top = 10,
  Palette palette = Palette.plain,
}) {
  final out = StringBuffer();
  final baseline = result.baseline;

  for (final d in result.diagnostics) {
    out.writeln(
      _diagnosticLine(d.path, d.line, d.column, d.severity, d.message, palette),
    );
  }
  final drift = _writeFindings(result, out, all: all, palette: palette);
  if (drift.isNotEmpty) out.write(_driftSection(drift, top, palette));

  if (result.summary.files == 0 && result.diagnostics.isEmpty) {
    out.writeln('No files analyzed.');
  }
  if (baseline != null && baseline.counts.stale > 0) {
    out.writeln(
      '${_n(baseline.counts.stale, 'baseline entry', 'baseline entries')} '
      'fixed or gone; `dmetrics baseline` refreshes the file.',
    );
  }
  out.writeln(_summaryLine(result, palette));
  return out.toString();
}

/// Per file: its parse diagnostics, then one line per result that prints.
/// Returns the changed results that did not print, for the drift section.
List<_Drift> _writeFindings(
  RunResult result,
  StringBuffer out, {
  required bool all,
  required Palette palette,
}) {
  final rollup = result.config.run.closureRollup;
  final baseline = result.baseline;
  final drift = <_Drift>[];
  for (final f in result.files) {
    for (final d in f.diagnostics) {
      out.writeln(
        _diagnosticLine(
          f.path,
          d.span.start.line + 1,
          d.span.start.column + 1,
          d.severity,
          d.message,
          palette,
        ),
      );
    }
    for (final s in f.scopes) {
      final ids = s.results.keys.toList()..sort();
      for (final id in ids) {
        final r = s.results[id]!;
        final match = baseline?.of(s.id, id);
        if (!all && r.verdict == Verdict.ok && r.suppressed == null) {
          if (match?.status == BaselineStatus.changed) {
            drift.add(_Drift(f, s, id, r, match!.value!));
          }
          continue;
        }
        out.writeln(_resultLine(f, s, id, r, match, rollup, palette));
      }
    }
  }
  return drift;
}

String _summaryLine(RunResult result, Palette palette) {
  final summary = result.summary;
  final v = summary.verdicts;
  final baseline = result.baseline;
  return [
    '${_n(summary.scopes, 'scope')} in ${_n(summary.files, 'file')}',
    if (summary.filesWithErrors > 0)
      '${_n(summary.filesWithErrors, 'file')} with parse errors',
    [
      _count(v[Verdict.fail]!, 'fail', palette.red),
      _count(v[Verdict.warn]!, 'warn', palette.yellow),
      _count(v[Verdict.ok]!, 'ok', palette.green),
      _count(summary.suppressed, 'suppressed', palette.dim),
    ].join(', '),
    if (baseline != null) _baselineClause(baseline.counts, palette),
    'status: ${_status(result.status, palette)}',
  ].join(' • ');
}

/// `baseline: 3 baselined, 1 new, 2 fixed` with the nonzero counts, new and
/// worse painted red, fixed green.
String _baselineClause(BaselineCounts c, Palette palette) {
  final parts = [
    if (c.baselined > 0) '${palette.dim('${c.baselined}')} baselined',
    if (c.added > 0) '${palette.red('${c.added}')} new',
    if (c.worse > 0) '${palette.red('${c.worse}')} worse',
    if (c.fixed > 0) '${palette.green('${c.fixed}')} fixed',
    if (c.changed > 0) '${palette.dim('${c.changed}')} changed',
    if (c.gone > 0) '${palette.dim('${c.gone}')} gone',
  ];
  return 'baseline: ${parts.isEmpty ? 'no changes' : parts.join(', ')}';
}

/// A changed result below the floor that would otherwise not print.
class _Drift {
  final FileReport file;
  final ScopeResult scope;
  final String metricId;
  final MetricResult result;
  final num was;

  const _Drift(this.file, this.scope, this.metricId, this.result, this.was);

  num get delta => result.value - was;
}

String _driftSection(List<_Drift> drift, int top, Palette palette) {
  drift.sort((a, b) {
    final byDelta = b.delta.abs().compareTo(a.delta.abs());
    if (byDelta != 0) return byDelta;
    final byPath = a.file.path.compareTo(b.file.path);
    if (byPath != 0) return byPath;
    return a.scope.scope.span.start.offset.compareTo(
      b.scope.scope.span.start.offset,
    );
  });
  final shown = drift.take(top).toList();
  final out = StringBuffer();
  out.writeln(
    shown.length == drift.length
        ? 'Changed since baseline (${drift.length}):'
        : 'Changed since baseline (${shown.length} of ${drift.length}, '
              'largest delta first):',
  );
  for (final d in shown) {
    final start = d.scope.scope.span.start;
    final sign = d.delta > 0 ? '+' : '−';
    final delta = '$sign${d.delta.abs()}';
    out.writeln(
      [
        '${d.file.path}:${start.line + 1}:${start.column + 1}',
        d.delta > 0 ? palette.yellow(delta) : palette.green(delta),
        '${d.scope.scope.kind.label} ${d.scope.scope.qualifiedName}',
        '${d.metricId} ${d.result.value} (was ${d.was})',
      ].join(' • '),
    );
  }
  return out.toString();
}

String _diagnosticLine(
  String? path,
  int? line,
  int? column,
  Severity severity,
  String message,
  Palette palette,
) {
  final where = [
    ?path,
    if (line != null) '$line',
    if (column != null) '$column',
  ].join(':');
  final tag = switch (severity) {
    Severity.error => palette.red(severity.name),
    Severity.warning => palette.yellow(severity.name),
    Severity.info => palette.dim(severity.name),
  };
  return [if (where.isNotEmpty) where, tag, message].join(' • ');
}

/// `2 fail` with the number painted; a zero count stays plain.
String _count(int n, String label, String Function(String) paint) =>
    '${n == 0 ? '$n' : paint('$n')} $label';

String _status(RunStatus status, Palette palette) => switch (status) {
  RunStatus.ok => palette.green(status.name),
  RunStatus.violations => palette.yellow(status.name),
  RunStatus.errors => palette.red(status.name),
};

String _resultLine(
  FileReport f,
  ScopeResult s,
  String metricId,
  MetricResult r,
  BaselineMatch? match,
  ClosureRollup rollup,
  Palette palette,
) {
  final start = s.scope.span.start;
  final tag = r.suppressed != null
      ? palette.dim(
          'suppressed (${r.suppressed!.kind == SuppressionKind.ignore ? 'ignore' : 'ignore_for_file'})',
        )
      : _verdictTag(r.verdict, match, palette);
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
    if (table != null) palette.dim('table-shaped: ${table.kind}'),
    ?_detailNote(r.measurement.detail),
  ].join(' • ');
}

/// The verdict, with the baseline status when there is one. Baselined debt
/// is dimmed whole, like a suppression: it is accepted, not news.
String _verdictTag(Verdict verdict, BaselineMatch? match, Palette palette) {
  final word = switch (verdict) {
    Verdict.fail => palette.red(verdict.name),
    Verdict.warn => palette.yellow(verdict.name),
    Verdict.ok => palette.dim(verdict.name),
  };
  return switch (match?.status) {
    null || BaselineStatus.unchanged => word,
    BaselineStatus.added => '$word (new)',
    BaselineStatus.worse => '$word (worse, was ${match!.value})',
    BaselineStatus.baselined => palette.dim('${verdict.name} (baselined)'),
    BaselineStatus.changed => '$word (was ${match!.value})',
  };
}

/// `cycle of 3` when a dependency metric reports the scope as a member of an
/// import cycle: `detail.cycle` lists the members, this scope included.
String? _detailNote(Object? detail) {
  if (detail is! Map) return null;
  final cycle = detail['cycle'];
  if (cycle is! List || cycle.length < 2) return null;
  return 'cycle of ${cycle.length}';
}

String _n(int count, String noun, [String? many]) =>
    '$count ${count == 1 ? noun : many ?? '${noun}s'}';
