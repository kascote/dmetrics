import 'dart:io';

import 'package:dmetrics/dmetrics.dart';

import 'cognitive_fixtures_test.dart' show cognitiveInvariants;
import 'harness/harness.dart';

/// Both shipped metrics on one traversal, each checked against its own
/// invariants and roll-up rule.
void main() {
  testFixtures(
    Directory('test/fixtures/both'),
    analyze: analyze,
    metrics: [CyclomaticMetric(), CognitiveMetric()],
    invariants: {
      CyclomaticMetric.metricId: ResultInvariants.cyclomaticStyle,
      CognitiveMetric.metricId: cognitiveInvariants,
    },
  );
}
