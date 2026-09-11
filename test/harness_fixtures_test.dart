import 'dart:io';

import 'harness/dummy_metrics.dart';
import 'harness/harness.dart';
import 'harness/stub_engine.dart';

void main() {
  testFixtures(
    Directory('test/harness/fixtures/ifcount'),
    analyze: stubAnalyze,
    metrics: [IfCountMetric()],
  );
  testFixtures(
    Directory('test/harness/fixtures/multi'),
    analyze: stubAnalyze,
    metrics: [IfCountMetric(), ConstantMetric()],
  );
}
