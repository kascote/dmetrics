import 'dart:io';

import 'package:dmetrics/dmetrics.dart';

import 'harness/harness.dart';

/// Executable spec: one annotated fixture per §6.1 row minimum (G6).
void main() {
  testFixtures(
    Directory('test/fixtures/cyclomatic'),
    analyze: analyze,
    metrics: [CyclomaticMetric()],
  );
}
