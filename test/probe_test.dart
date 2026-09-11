import 'dart:io';

import 'package:metra/metra.dart';

import 'harness/harness.dart';
import 'probe/nesting_probe.dart';

/// The nesting probe is the M1 proof of the traversal contract (SPEC §8).
void main() {
  testFixtures(
    Directory('test/probe/fixtures'),
    analyze: analyze,
    metrics: [NestingProbe()],
    invariants: {
      'nesting': ResultInvariants(
        base: null,
        rollUp: (measured, children) =>
            children.fold(measured, (m, c) => c > m ? c : m),
      ),
    },
  );
}
