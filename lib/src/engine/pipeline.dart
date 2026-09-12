/// Per-file result pipeline: aggregate → suppress → evaluate thresholds
/// (§6.3). Verdicts are computed on the aggregated value, so a reported
/// number can never disagree with its verdict.
library;

import '../config/config.dart';
import 'driver.dart';
import 'measurement.dart';
import 'metric.dart';
import 'report.dart';
import 'result.dart';
import 'scope.dart';
import 'suppress.dart';

/// Turns raw measurements into [ScopeResult]s in report order (start offset,
/// then end offset).
List<ScopeResult> buildResults({
  required List<ScopeMeasurements> measured,
  required List<Metric> metrics,
  required Map<String, MetricConfig> effective,
  required RunConfig run,
  Suppressions suppressions = Suppressions.none,
}) {
  final ordered = [...measured]..sort(_byStartThenEnd);
  final results = {
    for (final m in ordered) m.scope.id: <String, MetricResult>{},
  };

  for (final metric in metrics) {
    final scopes = [
      for (final m in ordered)
        if (m.measurements.containsKey(metric.id)) m,
    ];
    final aggregated = _aggregate(metric, scopes, run.closureRollup);
    final threshold = effectiveThreshold(effective[metric.id], metric);
    final forFile = suppressions.forFile(metric.id);
    for (final s in scopes) {
      final (value, includes) = aggregated[s.scope.id]!;
      // A line ignore reaches only the outermost measured scopes starting on
      // its line, so ignoring a method never ignores its closures.
      final line = s.scope.span.start.line;
      final outermost =
          s.scope.nearestAncestor(metric.measures)?.span.start.line != line;
      final suppressed =
          forFile ?? (outermost ? suppressions.forLine(line, metric.id) : null);
      results[s.scope.id]![metric.id] = MetricResult(
        measurement: s.measurements[metric.id]!,
        value: value.value,
        includes: includes,
        threshold: threshold,
        verdict: suppressed != null
            ? Verdict.ok
            : threshold?.evaluate(value.value) ?? Verdict.ok,
        suppressed: suppressed,
      );
    }
  }

  return [
    for (final m in ordered)
      ScopeResult(scope: m.scope, results: results[m.scope.id]!),
  ];
}

/// Bottom-up roll-up for one metric. Children of a scope are the measured
/// scopes whose nearest ancestor of a kind this metric measures is that
/// scope; each child's value is already its own aggregate.
Map<ScopeId, (Measurement, List<ScopeId>)> _aggregate(
  Metric metric,
  List<ScopeMeasurements> scopes,
  ClosureRollup policy,
) {
  final out = <ScopeId, (Measurement, List<ScopeId>)>{};
  if (policy == ClosureRollup.separate) {
    for (final s in scopes) {
      out[s.scope.id] = (s.measurements[metric.id]!, const []);
    }
    return out;
  }

  final children = <ScopeId, List<ScopeMeasurements>>{};
  for (final s in scopes) {
    final parent = s.scope.nearestAncestor(metric.measures);
    if (parent != null) children.putIfAbsent(parent.id, () => []).add(s);
  }

  // Children end before their parents, so ascending end offset (ties broken
  // by the wider span last) is a post-order.
  final postOrder = [...scopes]
    ..sort((a, b) {
      final c = a.scope.span.end.offset.compareTo(b.scope.span.end.offset);
      return c != 0
          ? c
          : b.scope.span.start.offset.compareTo(a.scope.span.start.offset);
    });
  for (final s in postOrder) {
    final direct = children[s.scope.id] ?? const [];
    final childMeasurements = [for (final c in direct) out[c.scope.id]!.$1];
    final own = s.measurements[metric.id]!;
    final rolled = direct.isEmpty ? own : metric.rollUp(own, childMeasurements);
    out[s.scope.id] = (rolled, [for (final c in direct) c.scope.id]);
  }
  return out;
}

/// Start offset, then end offset. A library spans its whole file, so when a
/// file is a single declaration the two share a span; the container sorts
/// first (later kinds in the enum are the wider ones).
int _byStartThenEnd(ScopeMeasurements a, ScopeMeasurements b) {
  final start = a.scope.span.start.offset.compareTo(b.scope.span.start.offset);
  if (start != 0) return start;
  final end = a.scope.span.end.offset.compareTo(b.scope.span.end.offset);
  return end != 0 ? end : b.scope.kind.index.compareTo(a.scope.kind.index);
}

/// The threshold a result reports: the configured one, else the metric's
/// built-in default; `thresholds: none` ([Threshold.none]) means null.
Threshold? effectiveThreshold(MetricConfig? config, Metric metric) {
  final t = config?.threshold ?? metric.defaultThreshold;
  return t == Threshold.none ? null : t;
}
