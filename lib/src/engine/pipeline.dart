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

/// Turns raw measurements into [ScopeResult]s in report order (start offset,
/// then end offset).
List<ScopeResult> buildResults({
  required List<ScopeMeasurements> measured,
  required List<Metric> metrics,
  required RootConfig root,
  required RunConfig run,
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
    final threshold = root.metric(metric.id).threshold;
    for (final s in scopes) {
      final (value, includes) = aggregated[s.scope.id]!;
      // Suppression detection lands with the I/O layer (M3); until then
      // nothing is suppressed.
      const Suppression? suppressed = null;
      results[s.scope.id]![metric.id] = MetricResult(
        measurement: s.measurements[metric.id]!,
        value: value.value,
        includes: includes,
        threshold: threshold,
        verdict: threshold?.evaluate(value.value) ?? Verdict.ok,
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

int _byStartThenEnd(ScopeMeasurements a, ScopeMeasurements b) {
  final c = a.scope.span.start.offset.compareTo(b.scope.span.start.offset);
  return c != 0
      ? c
      : a.scope.span.end.offset.compareTo(b.scope.span.end.offset);
}
