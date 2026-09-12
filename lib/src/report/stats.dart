/// `dmetrics stats`: the threshold-calibration numbers a field trial computes
/// by hand, derived from a finished [RunResult] and nothing else. Per metric:
/// the value distribution (bands and percentiles), the share of scopes at or
/// above the applied thresholds, a sweep over candidate thresholds, the
/// contributor mix over the whole run, and sibling clusters (scopes with the
/// same value and the same contributor summary, a duplication hint).
///
/// Metric-agnostic (G4): values, kinds and increments only. Suppressions are
/// ignored on purpose: stats describe the code, not the verdicts.
library;

import 'dart:convert';

import '../engine/report.dart';
import '../engine/result.dart';
import '../version.dart';
import 'ansi.dart';
import 'format.dart';
import 'run_result.dart';

const statsSchemaVersion = 1;

/// Lower bounds of the distribution bands: `1–5, 6–9, 10–14, 15–19, 20+`.
const bandEdges = [1, 6, 10, 15, 20];

/// Candidate thresholds for the sweep.
const sweepCandidates = [5, 8, 10, 12, 15, 20, 25, 30];

class RunStats {
  final int files;
  final int filesWithErrors;
  final List<RunDiagnostic> diagnostics;

  /// Keyed by metric id, sorted.
  final Map<String, MetricStats> metrics;

  const RunStats({
    required this.files,
    required this.filesWithErrors,
    required this.diagnostics,
    required this.metrics,
  });
}

class MetricStats {
  final String metricId;
  final int scopes;
  final List<Band> bands;

  /// Null when there are no scopes.
  final Percentiles? percentiles;

  /// Null when no result carried a threshold.
  final ThresholdStats? thresholds;
  final List<SweepPoint> sweep;

  /// Kind to its share of the summed increments, descending.
  final Map<String, double> contributorMix;
  final List<SiblingCluster> siblingClusters;

  const MetricStats({
    required this.metricId,
    required this.scopes,
    required this.bands,
    required this.percentiles,
    required this.thresholds,
    required this.sweep,
    required this.contributorMix,
    required this.siblingClusters,
  });
}

class Band {
  final num from;

  /// Inclusive upper bound, null for the open last band.
  final num? to;
  final int count;
  final double share;

  const Band({
    required this.from,
    required this.to,
    required this.count,
    required this.share,
  });

  String get label => to == null ? '$from+' : '$from–$to';
}

class Percentiles {
  final num p50;
  final num p90;
  final num p95;
  final num p99;
  final num max;

  const Percentiles({
    required this.p50,
    required this.p90,
    required this.p95,
    required this.p99,
    required this.max,
  });
}

class ThresholdStats {
  /// The one threshold every thresholded result shares, or null when roots
  /// disagree (each result is still counted against its own).
  final Threshold? uniform;
  final Share atOrAboveWarn;
  final Share atOrAboveFail;

  const ThresholdStats({
    required this.uniform,
    required this.atOrAboveWarn,
    required this.atOrAboveFail,
  });
}

/// Scopes matching some cut, and how many of those are table-shaped.
class Share {
  final int count;
  final double share;
  final int tableShaped;

  const Share({
    required this.count,
    required this.share,
    required this.tableShaped,
  });
}

class SweepPoint {
  final num atOrAbove;
  final Share share;

  const SweepPoint({required this.atOrAbove, required this.share});
}

class SiblingCluster {
  final num value;
  final Map<String, int> contributorSummary;
  final List<ClusterMember> scopes;

  const SiblingCluster({
    required this.value,
    required this.contributorSummary,
    required this.scopes,
  });
}

class ClusterMember {
  final String path;
  final int line;
  final String kind;
  final String qualifiedName;

  const ClusterMember({
    required this.path,
    required this.line,
    required this.kind,
    required this.qualifiedName,
  });
}

RunStats computeStats(RunResult result) {
  final summary = result.summary;
  final ids = {for (final m in result.metrics) m.id};
  for (final f in result.files) {
    for (final s in f.scopes) {
      ids.addAll(s.results.keys);
    }
  }
  final sorted = ids.toList()..sort();
  return RunStats(
    files: summary.files,
    filesWithErrors: summary.filesWithErrors,
    diagnostics: result.diagnostics,
    metrics: {for (final id in sorted) id: _metricStats(id, result)},
  );
}

typedef _Row = ({FileReport file, ScopeResult scope, MetricResult result});

MetricStats _metricStats(String metricId, RunResult result) {
  final rows = <_Row>[
    for (final f in result.files)
      for (final s in f.scopes)
        if (s.results[metricId] case final r?) (file: f, scope: s, result: r),
  ];
  final values = [for (final r in rows) r.result.value]..sort();
  final percentiles = values.isEmpty
      ? null
      : Percentiles(
          p50: _rank(values, 50),
          p90: _rank(values, 90),
          p95: _rank(values, 95),
          p99: _rank(values, 99),
          max: values.last,
        );
  final applied = {for (final r in rows) ?r.result.threshold};
  return MetricStats(
    metricId: metricId,
    scopes: values.length,
    bands: _bands(values),
    percentiles: percentiles,
    thresholds: applied.isEmpty
        ? null
        : ThresholdStats(
            uniform: applied.length == 1 ? applied.single : null,
            atOrAboveWarn: _cut(rows, (r) => _atLeast(r, Verdict.warn)),
            atOrAboveFail: _cut(rows, (r) => _atLeast(r, Verdict.fail)),
          ),
    sweep: [
      for (final c in sweepCandidates)
        SweepPoint(atOrAbove: c, share: _cut(rows, (r) => r.value >= c)),
    ],
    contributorMix: _contributorMix(rows),
    siblingClusters: _siblingClusters(rows, percentiles?.p90),
  );
}

/// The scopes passing [test], and how many of those are table-shaped.
Share _cut(List<_Row> rows, bool Function(MetricResult) test) {
  var count = 0;
  var tables = 0;
  for (final r in rows) {
    if (!test(r.result)) continue;
    count++;
    if (r.result.measurement.tableShape != null) tables++;
  }
  return Share(
    count: count,
    share: rows.isEmpty ? 0 : count / rows.length,
    tableShaped: tables,
  );
}

/// Values below the first edge land in the first band.
List<Band> _bands(List<num> sorted) => [
  for (var i = 0; i < bandEdges.length; i++)
    _band(sorted, i == 0 ? null : bandEdges[i], i),
];

Band _band(List<num> sorted, num? from, int i) {
  final to = i + 1 < bandEdges.length ? bandEdges[i + 1] - 1 : null;
  final count = sorted
      .where((v) => (from == null || v >= from) && (to == null || v <= to))
      .length;
  return Band(
    from: bandEdges[i],
    to: to,
    count: count,
    share: sorted.isEmpty ? 0 : count / sorted.length,
  );
}

/// Kind to its share of the summed increments over the whole run, descending.
Map<String, double> _contributorMix(List<_Row> rows) {
  final byKind = <String, num>{};
  num total = 0;
  for (final r in rows) {
    for (final c in r.result.measurement.contributors) {
      byKind[c.kind] = (byKind[c.kind] ?? 0) + c.increment;
      total += c.increment;
    }
  }
  final entries =
      [for (final e in byKind.entries) MapEntry(e.key, e.value / total)]
        ..sort((a, b) {
          final byShare = b.value.compareTo(a.value);
          return byShare != 0 ? byShare : a.key.compareTo(b.key);
        });
  return {for (final e in entries) e.key: e.value};
}

/// Groups of two or more scopes with the same value and the same contributor
/// summary, at or above the result's own warn threshold (or the top decile
/// [p90] when no threshold applies). Scopes without contributors never
/// cluster: a hundred trivial getters are not a duplication hint.
List<SiblingCluster> _siblingClusters(List<_Row> rows, num? p90) {
  final groups = <String, List<_Row>>{};
  for (final r in rows) {
    final summary = r.result.measurement.contributorSummary;
    final floor = r.result.threshold?.warn ?? p90;
    if (summary.isEmpty || floor == null || r.result.value < floor) continue;
    final kinds = summary.keys.toList()..sort();
    final key = [
      r.result.value,
      for (final k in kinds) '$k=${summary[k]}',
    ].join(',');
    (groups[key] ??= []).add(r);
  }
  return [
    for (final g in groups.values)
      if (g.length >= 2)
        SiblingCluster(
          value: g.first.result.value,
          contributorSummary: g.first.result.measurement.contributorSummary,
          scopes: [
            for (final r in g)
              ClusterMember(
                path: r.file.path,
                line: r.scope.scope.span.start.line + 1,
                kind: r.scope.scope.kind.label,
                qualifiedName: r.scope.scope.qualifiedName,
              ),
          ],
        ),
  ]..sort(_clusterOrder);
}

/// Highest value first, then largest, then by first member's name.
int _clusterOrder(SiblingCluster a, SiblingCluster b) {
  final byValue = b.value.compareTo(a.value);
  if (byValue != 0) return byValue;
  final bySize = b.scopes.length.compareTo(a.scopes.length);
  if (bySize != 0) return bySize;
  return a.scopes.first.qualifiedName.compareTo(b.scopes.first.qualifiedName);
}

/// Against the result's own threshold, suppression ignored.
bool _atLeast(MetricResult r, Verdict floor) {
  final t = r.threshold;
  return t != null && t.evaluate(r.value).index >= floor.index;
}

/// Nearest-rank percentile over ascending [sorted].
num _rank(List<num> sorted, int p) {
  final k = (p / 100 * sorted.length).ceil().clamp(1, sorted.length);
  return sorted[k - 1];
}

// --- Console ---------------------------------------------------------------

String renderStatsConsole(RunStats stats, {Palette palette = Palette.plain}) {
  final out = StringBuffer();
  for (final d in stats.diagnostics) {
    out.writeln(d.toString());
  }
  if (stats.files == 0 && stats.diagnostics.isEmpty) {
    out.writeln('No files analyzed.');
  }
  var first = true;
  for (final m in stats.metrics.values) {
    if (!first) out.writeln();
    first = false;
    _renderMetric(out, m, stats, palette);
  }
  return out.toString();
}

void _renderMetric(
  StringBuffer out,
  MetricStats m,
  RunStats stats,
  Palette palette,
) {
  final header = [
    palette.bold(m.metricId),
    '${plural(m.scopes, 'scope')} in ${plural(stats.files, 'file')}',
    if (stats.filesWithErrors > 0)
      '${plural(stats.filesWithErrors, 'file')} with parse errors',
  ];
  out.writeln(header.join(' • '));
  if (m.scopes == 0) return;
  _renderDistribution(out, m, palette);
  _renderThresholds(out, m, palette);
  out.writeln('${palette.bold('Sweep')} • scopes at or above each candidate');
  for (final s in m.sweep) {
    out.writeln(_shareLine('≥ ${s.atOrAbove}', s.share, (x) => x, palette));
  }
  out.writeln(
    '${palette.bold('Contributor mix')} • share of summed increments',
  );
  out.writeln(
    '  ${m.contributorMix.entries.map((e) => '${e.key} ${pct(e.value).trim()}').join(' • ')}',
  );
  _renderClusters(out, m, palette);
}

void _renderDistribution(StringBuffer out, MetricStats m, Palette palette) {
  out.writeln(palette.bold('Distribution'));
  final widest = m.bands.fold(0, (w, b) => b.count > w ? b.count : w);
  for (final b in m.bands) {
    final bar = widest == 0 ? 0 : (b.count / widest * 20).round();
    out.writeln(
      '  ${b.label.padRight(6)} ${countCol(b.count)} ${pct(b.share)}'
      '${bar > 0 ? '  ${palette.dim('█' * bar)}' : ''}',
    );
  }
  final p = m.percentiles!;
  out.writeln(
    '  p50 ${p.p50} • p90 ${p.p90} • p95 ${p.p95} • p99 ${p.p99} • max ${p.max}',
  );
}

void _renderThresholds(StringBuffer out, MetricStats m, Palette palette) {
  final t = m.thresholds;
  if (t == null) {
    out.writeln('${palette.bold('Thresholds')} • none configured');
    return;
  }
  final u = t.uniform;
  out.writeln(
    '${palette.bold('Thresholds')} • '
    '${u == null ? 'per root' : 'warn ≥ ${u.warn}, fail ≥ ${u.fail}'}',
  );
  out.writeln(_shareLine('≥ warn', t.atOrAboveWarn, palette.yellow, palette));
  out.writeln(_shareLine('≥ fail', t.atOrAboveFail, palette.red, palette));
}

void _renderClusters(StringBuffer out, MetricStats m, Palette palette) {
  out.writeln(
    '${palette.bold('Sibling clusters')} • same value and contributor mix, '
    '${m.thresholds == null ? 'top decile' : '≥ warn'}',
  );
  if (m.siblingClusters.isEmpty) out.writeln('  none');
  for (final c in m.siblingClusters) {
    final summary = c.contributorSummary.entries
        .map((e) => '${e.key} ×${e.value}')
        .join(', ');
    out.writeln(
      '  ${m.metricId} ${c.value} • $summary • ${plural(c.scopes.length, 'scope')}',
    );
    for (final s in c.scopes) {
      out.writeln('    ${s.path}:${s.line} ${s.kind} ${s.qualifiedName}');
    }
  }
}

String _shareLine(
  String label,
  Share s,
  String Function(String) paint,
  Palette palette,
) {
  final count = s.count == 0 ? countCol(s.count) : paint(countCol(s.count));
  return '  ${label.padRight(6)} $count ${pct(s.share)}'
      '${s.tableShaped > 0 ? '  ${palette.dim('${s.tableShaped} table-shaped')}' : ''}';
}

// --- JSON ------------------------------------------------------------------

String renderStatsJson(RunStats stats, {RunStatus? status}) =>
    const JsonEncoder.withIndent('  ')
        .convert(jsonStats(stats, status: status));

/// A document of its own, not the analyze report: shares are fractions in
/// `[0, 1]`, `status` is `ok` or `errors` (violations are not a stats concern).
Map<String, Object?> jsonStats(RunStats stats, {RunStatus? status}) => {
  'schemaVersion': statsSchemaVersion,
  'tool': {'name': toolName, 'version': toolVersion},
  'status': status == RunStatus.errors ? 'errors' : 'ok',
  'summary': {'files': stats.files, 'filesWithErrors': stats.filesWithErrors},
  'diagnostics': [
    for (final d in stats.diagnostics)
      {
        'path': d.path,
        'severity': d.severity.name,
        'message': d.message,
        'line': d.line,
        'column': d.column,
      },
  ],
  'metrics': {for (final e in stats.metrics.entries) e.key: _metric(e.value)},
};

Map<String, Object?> _metric(MetricStats m) => {
  'scopes': m.scopes,
  'bands': [
    for (final b in m.bands)
      {
        'label': b.label,
        'from': b.from,
        'to': b.to,
        'count': b.count,
        'share': b.share,
      },
  ],
  'percentiles': switch (m.percentiles) {
    null => null,
    final p => {
      'p50': p.p50,
      'p90': p.p90,
      'p95': p.p95,
      'p99': p.p99,
      'max': p.max,
    },
  },
  'thresholds': switch (m.thresholds) {
    null => null,
    final t => {
      'uniform': t.uniform == null
          ? null
          : {'warn': t.uniform!.warn, 'fail': t.uniform!.fail},
      'atOrAboveWarn': _share(t.atOrAboveWarn),
      'atOrAboveFail': _share(t.atOrAboveFail),
    },
  },
  'sweep': [
    for (final s in m.sweep) {'atOrAbove': s.atOrAbove, ..._share(s.share)},
  ],
  'contributorMix': m.contributorMix,
  'siblingClusters': [
    for (final c in m.siblingClusters)
      {
        'value': c.value,
        'contributorSummary': c.contributorSummary,
        'scopes': [
          for (final s in c.scopes)
            {
              'path': s.path,
              'line': s.line,
              'kind': s.kind,
              'qualifiedName': s.qualifiedName,
            },
        ],
      },
  ],
};

Map<String, Object?> _share(Share s) => {
  'count': s.count,
  'share': s.share,
  'tableShaped': s.tableShaped,
};
