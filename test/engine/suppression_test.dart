import 'package:metra/metra.dart';
import 'package:test/test.dart';

import 'recording_metric.dart';

void main() {
  const threshold = AnalysisConfig(
    roots: {
      '.': RootConfig(
        metrics: {
          'cyclomatic': MetricConfig(threshold: Threshold(warn: 2, fail: 3)),
        },
      ),
    },
  );

  Map<String, MetricResult> run(String content) => {
    for (final s in analyze(
      [src(content)],
      [CyclomaticMetric()],
      threshold,
    ).files.single.scopes)
      s.scope.qualifiedName: s.results['cyclomatic']!,
  };

  group('suppressions (§8)', () {
    test('ignore on the line before the declaration', () {
      final r = run('''
// ignore: metra_cyclomatic
int a(int x) => x > 0 ? (x > 1 ? 2 : 1) : 0;
int b(int x) => x > 0 ? (x > 1 ? 2 : 1) : 0;
''');
      expect(r['a']!.suppressed?.kind, SuppressionKind.ignore);
      expect(r['a']!.verdict, Verdict.ok);
      expect(r['a']!.value, 3, reason: 'the measurement is preserved');
      expect(r['b']!.suppressed, isNull);
      expect(r['b']!.verdict, Verdict.fail);
    });

    test('ignore as a trailing comment on the first line', () {
      final r = run('''
int a(int x) => // ignore: metra_cyclomatic
    x > 0 ? (x > 1 ? 2 : 1) : 0;
''');
      expect(r['a']!.suppressed?.kind, SuppressionKind.ignore);
      expect(r['a']!.suppressed!.span.start.line + 1, 1);
    });

    test('metra alone names every metric; other names do not apply', () {
      final r = run('''
// ignore: metra
int a(int x) => x > 0 ? (x > 1 ? 2 : 1) : 0;
// ignore: metra_cognitive, unused_element
int b(int x) => x > 0 ? (x > 1 ? 2 : 1) : 0;
// ignore: unused_element, metra_cyclomatic
int c(int x) => x > 0 ? (x > 1 ? 2 : 1) : 0;
''');
      expect(r['a']!.suppressed, isNotNull);
      expect(r['b']!.suppressed, isNull);
      expect(r['c']!.suppressed, isNotNull);
    });

    test('an ignore two lines up, or with metadata in between, is ignored', () {
      final r = run('''
// ignore: metra_cyclomatic

int a(int x) => x > 0 ? (x > 1 ? 2 : 1) : 0;
''');
      expect(r['a']!.suppressed, isNull);
    });

    test('ignore before metadata suppresses the annotated declaration', () {
      final r = run('''
// ignore: metra_cyclomatic
@deprecated
int a(int x) => x > 0 ? (x > 1 ? 2 : 1) : 0;
''');
      expect(r['a']!.suppressed, isNotNull);
    });

    test('a suppression on a method does not suppress its closures', () {
      final r = run('''
class C {
  // ignore: metra_cyclomatic
  void m(List<int> xs) {
    if (xs.isEmpty) return;
    xs.forEach((x) {
      if (x > 0 || x < -1 || x == 5) print(x);
    });
  }
}
''');
      expect(r['C.m']!.suppressed, isNotNull);
      expect(r['C.m.<closure#1>']!.suppressed, isNull);
      expect(r['C.m.<closure#1>']!.verdict, Verdict.fail);
    });

    test('a closure on the method\'s first line is not reached either', () {
      final r = run('''
// ignore: metra_cyclomatic
void m(List<int> xs) => xs.forEach((x) {
  if (x > 0 || x < -1 || x == 5) print(x);
});
''');
      expect(r['m']!.suppressed, isNotNull);
      expect(r['m.<closure#1>']!.suppressed, isNull);
    });

    test('a closure can be suppressed on its own line', () {
      final r = run('''
void m(List<int> xs) {
  // ignore: metra_cyclomatic
  xs.forEach((x) {
    if (x > 0 || x < -1 || x == 5) print(x);
  });
}
''');
      expect(r['m']!.suppressed, isNull);
      expect(r['m.<closure#1>']!.suppressed?.kind, SuppressionKind.ignore);
    });

    test('ignore_for_file anywhere suppresses every scope for that metric', () {
      final r = run('''
int a(int x) => x > 0 ? (x > 1 ? 2 : 1) : 0;
class C {
  int b(int x) => x > 0 ? (x > 1 ? 2 : 1) : 0;
}
// ignore_for_file: metra_cyclomatic
''');
      for (final res in r.values) {
        expect(res.suppressed?.kind, SuppressionKind.ignoreForFile);
        expect(res.verdict, Verdict.ok);
      }
      expect(r['a']!.suppressed!.span.start.line + 1, 5);
    });

    test('ignore_for_file for another metric changes nothing', () {
      final r = run('''
// ignore_for_file: metra_cognitive
int a(int x) => x > 0 ? (x > 1 ? 2 : 1) : 0;
''');
      expect(r['a']!.suppressed, isNull);
    });

    test('an ignore inside a string literal is not a comment', () {
      final r = run('''
const s = '// ignore: metra_cyclomatic';
int a(int x) => x > 0 ? (x > 1 ? 2 : 1) : 0;
''');
      expect(r['a']!.suppressed, isNull);
    });
  });

  group('Suppressions.scan', () {
    test('collects kinds, names and spans', () {
      final s = analyzeSuppressions('''
// ignore_for_file: metra, foo
void f() {} // ignore:metra_x
''');
      expect(s.comments.map((c) => c.toString()), [
        'ignoreForFile {metra, foo} @1',
        'ignore {metra_x} @2',
      ]);
      expect(s.forFile('anything'), isNotNull);
      expect(s.forLine(1, 'x'), isNotNull);
      expect(s.forLine(2, 'x'), isNotNull, reason: 'line after');
      expect(s.forLine(0, 'x'), isNull);
      expect(s.forLine(1, 'y'), isNull);
    });
  });
}

Suppressions analyzeSuppressions(String content) {
  Suppressions? seen;
  final probe = _SuppressionProbe((s) => seen = s);
  analyze([src(content)], [probe], const AnalysisConfig());
  return seen!;
}

/// Reaches the parsed suppressions through the public API by re-scanning the
/// unit the driver hands to the first node event.
class _SuppressionProbe extends RecordingMetric {
  final void Function(Suppressions) onUnit;

  _SuppressionProbe(this.onUnit);

  @override
  void onEnterNode(node, ScopeContext ctx) {
    if (ctx.kind == ScopeKind.file && node.parent == null) {
      onUnit(Suppressions.scan(node.beginToken, ctx.span.file));
    }
  }
}
