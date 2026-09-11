import 'dart:convert';
import 'dart:io';

import 'package:metra/metra.dart';
import 'package:test/test.dart';

/// The JSON schema is the public interface (§7.3): a golden file pins the
/// rendering, and the SPEC.md specimen pins the shape. Regenerate with
/// `UPDATE_GOLDENS=1 dart test test/report/json_golden_test.dart`.
void main() {
  final metrics = [CyclomaticMetric()];
  final source = SourceFile(
    path: 'lib/src/parser.dart',
    content: File('test/golden/src/lib/src/parser.dart').readAsStringSync(),
    configRoot: '.',
  );
  const config = AnalysisConfig(
    roots: {
      '.': RootConfig(
        source: 'analysis_options.yaml',
        metrics: {
          'cyclomatic': MetricConfig(
            enabled: true,
            threshold: Threshold(warn: 8, fail: 12),
          ),
        },
      ),
    },
  );
  final result = RunResult(
    metrics: metrics,
    config: config,
    report: analyze([source], metrics, config),
  );

  test('golden: test/golden/report.json', () {
    final golden = File('test/golden/report.json');
    final rendered = '${renderJson(result)}\n';
    if (Platform.environment['UPDATE_GOLDENS'] == '1') {
      golden.writeAsStringSync(rendered);
    }
    expect(rendered, golden.readAsStringSync());
  });

  test('matches the §7.3 specimen: values that are fixed by the spec', () {
    final json = jsonReport(result);
    expect(json['status'], 'violations');
    final scopes = (json['files'] as List).single['scopes'] as List;
    expect(scopes, hasLength(2));
    final method = scopes[0] as Map;
    final closure = scopes[1] as Map;
    expect(method['id'], 'lib/src/parser.dart::method:Parser.parseExpr');
    expect(method['parent'], isNull);
    expect(
      closure['id'],
      'lib/src/parser.dart::method:Parser.parseExpr::closure#1',
    );
    expect(closure['parent'], method['id']);
    expect(closure['name'], '<closure#1>');
    final r = (method['results'] as Map)['cyclomatic'] as Map;
    expect(r['measured'], 13);
    expect(r['value'], 13);
    expect(r['verdict'], 'fail');
    expect(r['contributorSummary'], {'case': 6, 'when': 2, 'if': 3, '??': 1});
    expect(r['contributors'], hasLength(12));
    expect(json['summary'], {
      'files': 1,
      'filesWithErrors': 0,
      'scopes': 2,
      'verdicts': {'ok': 1, 'warn': 0, 'fail': 1},
      'suppressed': 0,
    });
  });

  test('matches the §7.3 specimen: key structure', () {
    final specimen = jsonDecode(_specimenFromSpec()) as Map<String, Object?>;
    final actual = jsonReport(result);
    final diffs = <String>[];
    _compareShape(specimen, actual, r'$', diffs);
    expect(diffs, isEmpty, reason: diffs.join('\n'));
  });

  test('--json-contributors=summary drops the list, keeps the summary', () {
    final json = jsonReport(result, contributors: ContributorDetail.summary);
    final r =
        ((((json['files'] as List).single['scopes'] as List).first
                    as Map)['results']
                as Map)['cyclomatic']
            as Map;
    expect(r.containsKey('contributors'), isFalse);
    expect(r['contributorSummary'], {'case': 6, 'when': 2, 'if': 3, '??': 1});
  });

  test('suppressed and rolled-up results serialize per the contract', () {
    const content = '''
// ignore: metra_cyclomatic
void m(List<int> xs) {
  if (xs.isEmpty) return;
  xs.forEach((x) {
    if (x > 0) print(x);
  });
}
''';
    final r = RunResult(
      metrics: metrics,
      config: const AnalysisConfig(
        run: RunConfig(closureRollup: ClosureRollup.includeInParent),
      ),
      report: analyze(
        [const SourceFile(path: 'a.dart', content: content, configRoot: '.')],
        metrics,
        const AnalysisConfig(
          run: RunConfig(closureRollup: ClosureRollup.includeInParent),
        ),
      ),
    );
    final json = jsonReport(r);
    expect((json['run'] as Map)['closure_rollup'], 'include_in_parent');
    final scopes = (json['files'] as List).single['scopes'] as List;
    final method = (scopes[0]['results'] as Map)['cyclomatic'] as Map;
    expect(method['measured'], 2);
    expect(method['value'], 3);
    expect(method['includes'], ['a.dart::function:m::closure#1']);
    expect(method['verdict'], 'ok');
    expect((method['suppressed'] as Map)['kind'], 'ignore');
    expect(((method['suppressed'] as Map)['span'] as Map)['start'], {
      'line': 1,
      'column': 1,
      'offset': 0,
    });
    expect((json['summary'] as Map)['suppressed'], 1);
  });

  test('config problems render as a report with no files', () {
    final r = RunResult(
      metrics: metrics,
      config: const AnalysisConfig(),
      report: null,
      diagnostics: const [
        RunDiagnostic(
          path: 'analysis_options.yaml',
          line: 3,
          column: 5,
          message: 'bad',
        ),
      ],
    );
    final json = jsonReport(r);
    expect(json['status'], 'errors');
    expect(json['files'], isEmpty);
    expect(json['diagnostics'], [
      {
        'path': 'analysis_options.yaml',
        'severity': 'error',
        'message': 'bad',
        'line': 3,
        'column': 5,
      },
    ]);
    expect((json['summary'] as Map)['files'], 0);
  });
}

/// The ```json block under "### 7.3" in SPEC.md.
String _specimenFromSpec() {
  final spec = File('SPEC.md').readAsStringSync();
  final start = spec.indexOf('### 7.3');
  final open = spec.indexOf('```json', start);
  final close = spec.indexOf('```', open + 7);
  return spec.substring(open + 7, close);
}

/// Recursively checks that [actual] has exactly the keys of [expected] (plus
/// [extraAllowed]) with the same JSON types; null in either side is a
/// wildcard; lists compare their first elements.
void _compareShape(
  Object? expected,
  Object? actual,
  String path,
  List<String> diffs, {
  Set<String> extraAllowed = const {},
}) {
  if (expected == null || actual == null) return;
  if (expected is Map && actual is Map) {
    for (final k in expected.keys) {
      if (!actual.containsKey(k)) diffs.add('$path: missing key `$k`');
    }
    for (final k in actual.keys) {
      if (!expected.containsKey(k) && !extraAllowed.contains('$path.$k')) {
        diffs.add('$path: unexpected key `$k`');
      }
    }
    for (final k in expected.keys) {
      if (actual.containsKey(k)) {
        _compareShape(
          expected[k],
          actual[k],
          '$path.$k',
          diffs,
          extraAllowed: extraAllowed,
        );
      }
    }
  } else if (expected is List && actual is List) {
    if (expected.isNotEmpty && actual.isNotEmpty) {
      _compareShape(
        expected.first,
        actual.first,
        '$path[0]',
        diffs,
        extraAllowed: extraAllowed,
      );
    }
  } else if (expected.runtimeType != actual.runtimeType &&
      !(expected is num && actual is num)) {
    diffs.add('$path: ${expected.runtimeType} vs ${actual.runtimeType}');
  }
}
