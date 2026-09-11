import 'dart:io';

import 'harness/dummy_metrics.dart';
import 'harness/harness.dart';

import 'package:dmetrics/dmetrics.dart';

void main() {
  testFixtures(
    Directory('test/harness/fixtures/ifcount'),
    analyze: analyze,
    metrics: [IfCountMetric()],
  );
  testFixtures(
    Directory('test/harness/fixtures/multi'),
    analyze: analyze,
    metrics: [IfCountMetric(), ConstantMetric()],
  );
}
