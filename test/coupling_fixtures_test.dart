import 'dart:io';

import 'package:dmetrics/dmetrics.dart';

import 'harness/harness.dart';

/// Base 0, no children: a library holds no measured scope of this metric.
const couplingInvariants = ResultInvariants(base: 0, rollUp: _measuredOnly);

num _measuredOnly(num measured, List<num> childValues) => measured;

/// Executable spec: one annotated fixture per counting-table row minimum.
/// Fixtures are single files, so every relative target is a library of the
/// fixture's package that is not in the run, which counts like a source.
void main() {
  testFixtures(
    Directory('test/fixtures/coupling'),
    analyze: analyze,
    metrics: [CouplingMetric()],
    invariants: {CouplingMetric.metricId: couplingInvariants},
  );
}
