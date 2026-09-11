/// Annotated-fixture test harness (SPEC §8, M0).
///
/// Drives the engine over in-memory sources, asserts per-scope expectations
/// from `// expect:` annotations, and checks the §6.1 / §6.3 invariants on
/// every result.
library;

import 'dart:io';

import 'package:dmetrics/dmetrics.dart';
import 'package:test/test.dart';

import 'fixture.dart';
import 'invariants.dart';
import 'runner.dart';

export 'fixture.dart';
export 'invariants.dart';
export 'runner.dart';

/// Loads a fixture from disk; [path] in the report is relative to [root].
Fixture loadFixture(File file, {required Directory root}) {
  final rel = file.absolute.path
      .substring(root.absolute.path.length)
      .replaceAll('\\', '/')
      .replaceFirst(RegExp('^/'), '');
  return Fixture.parse(rel, file.readAsStringSync());
}

/// Registers one `test()` per `*.dart` file under [dir] (recursively), each
/// running the fixture through [analyze] with [metrics].
void testFixtures(
  Directory dir, {
  required Analyze analyze,
  required List<Metric> metrics,
  Map<String, ResultInvariants> invariants = const {},
  AnalysisConfig? baseConfig,
}) {
  final files =
      dir
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));
  if (files.isEmpty) {
    throw StateError('no fixtures under ${dir.path}');
  }
  for (final file in files) {
    final fixture = loadFixture(file, root: dir);
    test(fixture.path, () {
      expectFixturePasses(
        fixture,
        analyze: analyze,
        metrics: metrics,
        invariants: invariants,
        baseConfig: baseConfig,
      );
    });
  }
}

/// Runs [fixture] and fails the current test with every violation at once.
void expectFixturePasses(
  Fixture fixture, {
  required Analyze analyze,
  required List<Metric> metrics,
  Map<String, ResultInvariants> invariants = const {},
  AnalysisConfig? baseConfig,
}) {
  final outcome = runFixture(
    fixture,
    analyze: analyze,
    metrics: metrics,
    invariants: invariants,
    baseConfig: baseConfig,
  );
  if (!outcome.passed) {
    fail('fixture ${fixture.path} failed:\n${outcome.describe()}');
  }
}
