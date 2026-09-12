import 'dart:io';

import 'package:dmetrics/dmetrics.dart';

import 'harness/harness.dart';

/// Base 0 and `measured + Σ child.value`: the cognitive definition.
const cognitiveInvariants = ResultInvariants(base: 0, rollUp: _sumChildren);

num _sumChildren(num measured, List<num> childValues) =>
    childValues.fold<num>(measured, (acc, v) => acc + v);

/// Executable spec: one annotated fixture per counting-table row minimum.
void main() {
  testFixtures(
    Directory('test/fixtures/cognitive'),
    analyze: analyze,
    metrics: [CognitiveMetric()],
    invariants: {CognitiveMetric.metricId: cognitiveInvariants},
  );
}
