import 'package:metra/metra.dart';

import 'fixture.dart';
import 'invariants.dart';

class FixtureFailure {
  final String path;
  final int? line;
  final String message;

  const FixtureFailure(this.path, this.line, this.message);

  @override
  String toString() =>
      line == null ? '$path: $message' : '$path:$line: $message';
}

class FixtureOutcome {
  final Fixture fixture;
  final List<FixtureFailure> failures;

  const FixtureOutcome(this.fixture, this.failures);

  bool get passed => failures.isEmpty;

  String describe() => failures.map((f) => '  $f').join('\n');
}

/// Runs one fixture through [analyze] and checks every expectation and
/// invariant. When any expectation carries `rolled=`, the fixture is run a
/// second time under `include_in_parent` and aggregated values are checked.
FixtureOutcome runFixture(
  Fixture fixture, {
  required Analyze analyze,
  required List<Metric> metrics,
  Map<String, ResultInvariants> invariants = const {},
  AnalysisConfig? baseConfig,
}) {
  final failures = <FixtureFailure>[];
  void fail(int? line, String message) =>
      failures.add(FixtureFailure(fixture.path, line, message));

  final knownMetrics = {for (final m in metrics) m.id};
  for (final byMetric in fixture.expectations.values) {
    for (final e in byMetric.values) {
      if (!knownMetrics.contains(e.metric)) {
        fail(
          e.annotationLine,
          'expectation names unknown metric `${e.metric}` (run has $knownMetrics)',
        );
      }
    }
  }

  final base = baseConfig ?? const AnalysisConfig();
  final run = base.run.copyWith(
    settings: {...base.run.settings, ..._coerceSettings(fixture.runSettings)},
  );
  final sources = [
    SourceFile(path: fixture.path, content: fixture.content, configRoot: '.'),
  ];

  for (final policy in [
    ClosureRollup.separate,
    if (fixture.hasRolled) ClosureRollup.includeInParent,
  ]) {
    final config = base.copyWith(run: run.copyWith(closureRollup: policy));
    final Report report;
    try {
      report = analyze(sources, metrics, config);
    } catch (e, st) {
      fail(null, 'analyze threw under ${policy.name}: $e\n$st');
      continue;
    }
    _checkReport(report, fixture, metrics, policy, invariants, fail);
  }

  return FixtureOutcome(fixture, failures);
}

void _checkReport(
  Report report,
  Fixture fixture,
  List<Metric> metrics,
  ClosureRollup policy,
  Map<String, ResultInvariants> invariants,
  void Function(int? line, String message) fail,
) {
  final tag = policy == ClosureRollup.separate ? '' : ' [include_in_parent]';

  if (report.files.length != 1 || report.files.single.path != fixture.path) {
    fail(
      null,
      'expected a report for exactly `${fixture.path}`, got ${report.files.map((f) => f.path).toList()}$tag',
    );
    return;
  }
  final file = report.files.single;

  if (fixture.expectPartial) {
    if (!file.partial) {
      fail(
        null,
        'fixture declares `expect: partial` but the file parsed cleanly$tag',
      );
    }
  } else if (file.diagnostics.isNotEmpty) {
    fail(
      null,
      'fixture has parse diagnostics but no `expect: partial`:$tag\n'
      '${file.diagnostics.map((d) => '    $d').join('\n')}',
    );
  }

  final seenIds = <ScopeId>{};
  for (final s in file.scopes) {
    if (!seenIds.add(s.id)) fail(_line(s), 'duplicate scope id `${s.id}`$tag');
  }

  final byLine = <int, List<ScopeResult>>{};
  for (final s in file.scopes) {
    byLine.putIfAbsent(_line(s), () => []).add(s);
  }
  final scopeLines = (byLine.keys.toList()..sort()).join(', ');

  for (final scope in file.scopes) {
    final line = _line(scope);
    final ambiguous = byLine[line]!.length > 1;
    final expected = fixture.expectations[line] ?? const {};

    for (final metric in metrics) {
      final result = scope.results[metric.id];
      final exp = expected[metric.id];
      if (result == null) continue;
      if (ambiguous) continue; // reported once per line below
      if (exp == null) {
        if (fixture.noneLines.contains(line)) continue; // reported below
        fail(
          line,
          'scope `${scope.scope.qualifiedName}` (${scope.scope.kind.label}) '
          'has a `${metric.id}` result but no expectation$tag: '
          'measured=${result.measured} ${result.measurement.contributorSummary}',
        );
        continue;
      }
      if (result.measured != exp.value) {
        fail(
          exp.annotationLine,
          '`${scope.scope.qualifiedName}` ${metric.id}: expected '
          '${exp.value}, measured ${result.measured}$tag '
          '(contributors: ${_describeContributors(result.measurement)})',
        );
      }
      if (policy == ClosureRollup.includeInParent) {
        final want = exp.rolled ?? exp.value;
        if (result.value != want) {
          fail(
            exp.annotationLine,
            '`${scope.scope.qualifiedName}` ${metric.id}: expected rolled '
            '$want, got value ${result.value}$tag '
            '(measured ${result.measured}, includes ${result.includes})',
          );
        }
      }
      for (final v in checkResultInvariants(
        file: file,
        scope: scope,
        metricId: metric.id,
        result: result,
        measures: metric.measures,
        policy: policy,
        invariants: invariants[metric.id] ?? ResultInvariants.cyclomaticStyle,
      )) {
        fail(line, 'invariant: $v$tag');
      }
    }
  }

  for (final entry in fixture.expectations.entries) {
    final line = entry.key;
    final scopes = byLine[line] ?? const [];
    if (scopes.isEmpty) {
      fail(
        line,
        'no scope starts on line $line$tag (scopes start on lines: $scopeLines)',
      );
      continue;
    }
    if (scopes.length > 1) {
      fail(
        line,
        'ambiguous: ${scopes.length} scopes start on line $line$tag: '
        '${scopes.map((s) => s.scope.qualifiedName).join(', ')}',
      );
      continue;
    }
    final scope = scopes.single;
    for (final exp in entry.value.values) {
      if (!scope.results.containsKey(exp.metric)) {
        fail(
          exp.annotationLine,
          'expected `${exp.metric}` on `${scope.scope.qualifiedName}` but the '
          'scope has no result for it$tag (has: ${scope.results.keys.toList()})',
        );
      }
    }
  }

  for (final line in fixture.noneLines) {
    final scopes = byLine[line];
    if (scopes != null) {
      fail(
        line,
        '`expect: none` but ${scopes.map((s) => '${s.scope.kind.label} ${s.scope.qualifiedName}').join(', ')} starts here$tag',
      );
    }
  }
}

int _line(ScopeResult s) => s.scope.span.start.line + 1;

String _describeContributors(Measurement m) {
  if (m.contributors.isEmpty) return 'none';
  return m.contributors
      .map(
        (c) => '${c.kind}@${c.span.start.line + 1}:${c.span.start.column + 1}',
      )
      .join(', ');
}

/// `// run:` values are strings; give the engine typed values where obvious.
Map<String, Object?> _coerceSettings(Map<String, String> raw) => {
  for (final e in raw.entries)
    e.key: switch (e.value) {
      'true' => true,
      'false' => false,
      final v => num.tryParse(v) ?? v,
    },
};
