import 'package:metra/metra.dart';
import 'package:test/test.dart';

void main() {
  MetricResult resultOf(
    String content, {
    Map<String, Object?> settings = const {},
  }) {
    final report = analyze(
      [SourceFile(path: 'lib/c.dart', content: content, configRoot: '.')],
      [CyclomaticMetric()],
      AnalysisConfig(run: RunConfig(settings: settings)),
    );
    return report.files.single.scopes.single.results['cyclomatic']!;
  }

  List<(String, String)> contributorsOf(String content) {
    final r = resultOf(content);
    return [for (final c in r.measurement.contributors) (c.kind, c.span.text)];
  }

  group('contributor kinds and spans', () {
    test('statements point at their header', () {
      expect(
        contributorsOf('''
void f(int a, List<int> xs) {
  if (a > 0) {}
  if (a case 1 when a > 0) {}
  for (final x in xs) {}
  await for (final x in s) {}
  while (a > 0) {}
  do {} while (a > 0);
}
'''),
        [
          ('if', 'if (a > 0)'),
          ('if-case', 'if (a case 1 when a > 0)'),
          ('when', 'when a > 0'),
          ('loop', 'for (final x in xs)'),
          ('loop', 'await for (final x in s)'),
          ('loop', 'while (a > 0)'),
          ('loop', 'do'),
        ],
      );
    });

    test('operators point at the operator token', () {
      expect(
        contributorsOf('''
int f(int? a, int b) {
  var x = a ?? 0;
  x ??= b;
  return a != null && b > 0 || x > 0 ? x : b;
}
'''),
        [
          ('??', '??'),
          ('??=', '??='),
          ('&&', '&&'),
          ('||', '||'),
          ('ternary', '?'),
        ],
      );
    });

    test('switch arms point at the pattern, catch at the clause header', () {
      expect(
        contributorsOf('''
void f(Object o) {
  switch (o) {
    case int x when x > 0:
      break;
    case 1 || 2:
      break;
    case _:
      break;
  }
  try {} on E catch (e) {} on E {} catch (e) {}
}
'''),
        [
          ('case', 'int x'),
          ('when', 'when x > 0'),
          ('case', '1 || 2'),
          ('pattern-or', '||'),
          ('catch', 'on E catch (e)'),
          ('catch', 'on E'),
          ('catch', 'catch (e)'),
        ],
      );
    });

    test('contributors are in source order', () {
      final r = resultOf('''
int f(int a) => a > 0 ? (a > 1 && a > 2 ? 1 : 2) : 3;
''');
      final offsets = r.measurement.contributors.map(
        (c) => c.span.start.offset,
      );
      expect(offsets, [...offsets]..sort());
    });
  });

  group('knobs', () {
    test('defaults count case arms and null coalescing', () {
      expect(
        resultOf('int f(int? a) => a ?? switch (a) { 1 => 1, _ => 0 };')
            .measured,
        3,
      );
    });

    test('count_case_arms=false: one per switch, kind switch', () {
      final r = resultOf(
        'int f(int a) => switch (a) { 1 => 1, 2 => 2, _ => 0 };',
        settings: {CyclomaticMetric.knobCaseArms: false},
      );
      expect(r.measured, 2);
      expect(r.measurement.contributors.single.kind, 'switch');
      expect(r.measurement.contributors.single.span.text, 'switch (a)');
    });

    test('count_null_coalescing=false drops ?? and ??= only', () {
      final r = resultOf(
        'int f(int? a) { var x = a ?? 0; x ??= 1; return x > 0 ? x : 0; }',
        settings: {CyclomaticMetric.knobNullCoalescing: false},
      );
      expect(r.measured, 2);
    });

    test('a non-boolean knob value is a config error', () {
      expect(
        () => resultOf(
          'void f() {}',
          settings: {CyclomaticMetric.knobCaseArms: 'no'},
        ),
        throwsArgumentError,
      );
    });
  });

  test('a parse failure inside a scope still yields a partial measurement', () {
    final report = analyze(
      [
        const SourceFile(
          path: 'x.dart',
          content: 'void f(int a) { if (a > 0 { } }',
          configRoot: '.',
        ),
      ],
      [CyclomaticMetric()],
      const AnalysisConfig(),
    );
    final file = report.files.single;
    expect(file.partial, isTrue);
    expect(file.scopes.single.scope.partial, isTrue);
    expect(
      file.scopes.single.results['cyclomatic']!.measured,
      greaterThanOrEqualTo(1),
    );
  });
}
