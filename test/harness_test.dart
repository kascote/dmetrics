import 'package:metra/metra.dart';
import 'package:source_span/source_span.dart' as ss;
import 'package:test/test.dart';

import 'harness/dummy_metrics.dart';
import 'harness/harness.dart';

void main() {
  group('Fixture.parse', () {
    test('leading annotation targets the next line', () {
      final f = Fixture.parse('x.dart', '// expect: ifcount=3\nvoid m() {}\n');
      expect(f.expectations.keys, [2]);
      expect(f.expectations[2]!['ifcount']!.value, 3);
      expect(f.expectations[2]!['ifcount']!.rolled, isNull);
      expect(f.expectations[2]!['ifcount']!.annotationLine, 1);
    });

    test('rejects an annotation that shares a line with code', () {
      expect(
        () => Fixture.parse('x.dart', 'void m() { // expect: ifcount=1\n}\n'),
        throwsA(isA<FixtureFormatException>()),
      );
    });

    test('stacked leading annotations merge onto one target', () {
      final f = Fixture.parse(
        'x.dart',
        '// expect: a=1\n// expect: b=2 rolled=5\nvoid m() {}\n',
      );
      expect(f.expectations.keys, [3]);
      expect(f.expectations[3]!.keys, unorderedEquals(['a', 'b']));
      expect(f.expectations[3]!['b']!.rolled, 5);
      expect(f.hasRolled, isTrue);
    });

    test('several metrics on one line, rolled binds to the preceding one', () {
      final f = Fixture.parse(
        'x.dart',
        '// expect: a=1 rolled=4 b=2\nvoid m() {}\n',
      );
      final byMetric = f.expectations[2]!;
      expect(byMetric['a']!.rolled, 4);
      expect(byMetric['b']!.rolled, isNull);
      expect(f.metrics, {'a', 'b'});
    });

    test('file directives: partial and run settings', () {
      final f = Fixture.parse(
        'x.dart',
        '// expect: partial\n// run: cyclomatic.count_case_arms=false k=3\nvoid m() {}\n',
      );
      expect(f.expectPartial, isTrue);
      expect(f.runSettings, {'cyclomatic.count_case_arms': 'false', 'k': '3'});
      expect(f.expectations, isEmpty);
    });

    test('none marks a line where no scope may start', () {
      final f = Fixture.parse('x.dart', '// expect: none\nvoid m();\n');
      expect(f.noneLines, {2});
      expect(f.expectations, isEmpty);
    });

    test('rejects rolled without a preceding metric', () {
      expect(
        () => Fixture.parse('x.dart', '// expect: rolled=4\nvoid m() {}\n'),
        throwsA(isA<FixtureFormatException>()),
      );
    });

    test('rejects non-numeric values and bare words', () {
      expect(
        () => Fixture.parse('x.dart', '// expect: a=lots\nvoid m() {}\n'),
        throwsA(isA<FixtureFormatException>()),
      );
      expect(
        () => Fixture.parse('x.dart', '// expect: bogus\nvoid m() {}\n'),
        throwsA(isA<FixtureFormatException>()),
      );
      expect(
        () => Fixture.parse('x.dart', '// expect:\nvoid m() {}\n'),
        throwsA(isA<FixtureFormatException>()),
      );
    });

    test('rejects duplicate expectations for one metric on one target', () {
      expect(
        () => Fixture.parse(
          'x.dart',
          '// expect: a=1\n// expect: a=2\nvoid m() {}\n',
        ),
        throwsA(isA<FixtureFormatException>()),
      );
    });
  });

  group('runFixture against the engine', () {
    FixtureOutcome run(
      String source, {
      List<Metric>? metrics,
      Analyze engine = analyze,
    }) => runFixture(
      Fixture.parse('t.dart', source),
      analyze: engine,
      metrics: metrics ?? [IfCountMetric()],
    );

    // An engine that measures correctly but never rolls up.
    Report noRollUp(List<SourceFile> s, List<Metric> m, AnalysisConfig c) {
      final r = analyze(s, m, c);
      return Report(
        config: r.config,
        files: [
          for (final f in r.files)
            FileReport(
              source: f.source,
              diagnostics: f.diagnostics,
              scopes: [
                for (final sc in f.scopes)
                  ScopeResult(
                    scope: sc.scope,
                    results: {
                      for (final e in sc.results.entries)
                        e.key: MetricResult(
                          measurement: e.value.measurement,
                          value: e.value.measured,
                          includes: const [],
                          threshold: e.value.threshold,
                          verdict: e.value.verdict,
                          suppressed: e.value.suppressed,
                        ),
                    },
                  ),
              ],
            ),
        ],
      );
    }

    test('passes a correct fixture', () {
      final o = run('''
// expect: ifcount=2
int f(int a) {
  if (a > 0) return 1;
  return 0;
}
''');
      expect(o.failures, isEmpty, reason: o.describe());
    });

    test('reports a wrong expected value with contributor locations', () {
      final o = run('''
// expect: ifcount=1
int f(int a) {
  if (a > 0) return 1;
  return 0;
}
''');
      expect(o.failures, hasLength(1));
      expect(o.failures.single.line, 1);
      expect(o.failures.single.message, contains('expected 1, measured 2'));
      expect(o.failures.single.message, contains('if@3:3'));
    });

    test('reports a measured scope with no expectation', () {
      final o = run('int f() => 0;\n');
      expect(o.failures, hasLength(1));
      expect(o.failures.single.message, contains('no expectation'));
      expect(o.failures.single.message, contains('`f`'));
    });

    test('reports an expectation with no scope, listing scope lines', () {
      final o = run('''
// expect: ifcount=1

// expect: ifcount=1
int f() => 0;
''');
      expect(o.failures, hasLength(1));
      expect(o.failures.single.line, 2);
      expect(o.failures.single.message, contains('no scope starts on line 2'));
      expect(o.failures.single.message, contains('scopes start on lines: 4'));
    });

    test('reports an ambiguous line with two scopes', () {
      final o = run('''
// expect: ifcount=1
void f() { [1].forEach((x) {}); }
''');
      expect(o.failures, hasLength(1));
      expect(o.failures.single.message, contains('ambiguous: 2 scopes'));
    });

    test('reports a violated `none`', () {
      final o = run('''
// expect: none
int f() => 0;
''');
      expect(o.failures, hasLength(1));
      expect(o.failures.single.message, contains('`expect: none`'));
    });

    test('a clean fixture with parse errors must declare partial', () {
      final o = run('''
// expect: ifcount=1
int f() => 0
''');
      expect(
        o.failures.map((f) => f.message).join(),
        contains('no `expect: partial`'),
      );
    });

    test('partial declared on a clean file is a failure', () {
      final o = run('''
// expect: partial
// expect: ifcount=1
int f() => 0;
''');
      expect(o.failures, hasLength(1));
      expect(o.failures.single.message, contains('parsed cleanly'));
    });

    test('an unknown metric in an expectation is reported', () {
      final o = run('''
// expect: ifcount=1 cognitive=1
int f() => 0;
''');
      expect(
        o.failures.map((f) => f.message).join(),
        contains('unknown metric `cognitive`'),
      );
    });

    test(
      'rolled= runs include_in_parent and catches a non-aggregating engine',
      () {
        final o = run(engine: noRollUp, '''
// expect: ifcount=2 rolled=3
void f(List<int> xs) {
  if (xs.isEmpty) return;
  // expect: ifcount=2
  xs.forEach((x) {
    if (x > 0) print(x);
  });
}
''');
        final messages = o.failures.map((f) => f.message).join('\n');
        expect(messages, contains('[include_in_parent]'));
        expect(messages, contains('expected rolled 3, got value 2'));
        expect(messages, contains('missing from includes'));
        // The `separate` pass itself is clean.
        expect(
          o.failures.where((f) => !f.message.contains('[include_in_parent]')),
          isEmpty,
        );
      },
    );

    test('run settings reach the engine config', () {
      AnalysisConfig? seen;
      Report spy(List<SourceFile> s, List<Metric> m, AnalysisConfig c) {
        seen = c;
        return analyze(s, m, c);
      }

      final o = runFixture(
        Fixture.parse(
          't.dart',
          '// run: cyclomatic.count_case_arms=false n=2\n',
        ),
        analyze: spy,
        metrics: [IfCountMetric()],
      );
      expect(o.failures, isEmpty, reason: o.describe());
      expect(seen!.run.settings, {'cyclomatic.count_case_arms': false, 'n': 2});
    });
  });

  group('checkResultInvariants on hand-built results', () {
    const content = '''
void m() {
  if (a) {}
  f(() {
    if (b) {}
    if (c) {}
  });
}
''';
    final file = ss.SourceFile.fromString(content, url: 't.dart');
    final source = const SourceFile(
      path: 't.dart',
      content: content,
      configRoot: '.',
    );
    final fileCtx = ScopeContext(
      id: const ScopeId('t.dart'),
      kind: ScopeKind.file,
      parent: null,
      span: file.span(0, content.length),
      qualifiedName: 't.dart',
      partial: false,
    );
    final method = ScopeContext(
      id: const ScopeId('t.dart::method:m'),
      kind: ScopeKind.method,
      parent: fileCtx,
      span: file.span(0, content.length - 1),
      qualifiedName: 'm',
      partial: false,
    );
    final closure = ScopeContext(
      id: const ScopeId('t.dart::method:m::closure#1'),
      kind: ScopeKind.closure,
      parent: method,
      span: file.span(
        content.indexOf('f(() {') + 2,
        content.indexOf('});') + 1,
      ),
      qualifiedName: 'm.<closure#1>',
      partial: false,
    );
    Contributor ifAt(String text) {
      final at = content.indexOf(text);
      return Contributor(
        kind: 'if',
        increment: 1,
        span: file.span(at, at + text.length),
      );
    }

    Measurement measure(ScopeContext s, List<Contributor> cs) => Measurement(
      metricId: 'ifcount',
      scope: s.id,
      value: 1 + cs.length,
      contributors: cs,
    );
    MetricResult result(
      Measurement m, {
      num? value,
      List<ScopeId> includes = const [],
    }) => MetricResult(
      measurement: m,
      value: value ?? m.value,
      includes: includes,
      threshold: null,
      verdict: Verdict.ok,
      suppressed: null,
    );

    final closureM = measure(closure, [ifAt('if (b)'), ifAt('if (c)')]);
    final methodM = measure(method, [ifAt('if (a)')]);

    List<String> check(
      MetricResult parent,
      MetricResult child,
      ClosureRollup policy,
    ) {
      final scopes = [
        ScopeResult(scope: method, results: {'ifcount': parent}),
        ScopeResult(scope: closure, results: {'ifcount': child}),
      ];
      final report = FileReport(
        source: source,
        diagnostics: const [],
        scopes: scopes,
      );
      return [
        for (final s in scopes)
          ...checkResultInvariants(
            file: report,
            scope: s,
            metricId: 'ifcount',
            result: s.results['ifcount']!,
            measures: ScopeKind.measuredInV1,
            policy: policy,
            invariants: ResultInvariants.cyclomaticStyle,
          ),
      ];
    }

    test('separate: sound results pass', () {
      expect(
        check(result(methodM), result(closureM), ClosureRollup.separate),
        isEmpty,
      );
    });

    test(
      'include_in_parent: 2 + (3 - 1) = 4 with the child included passes',
      () {
        expect(
          check(
            result(methodM, value: 4, includes: [closure.id]),
            result(closureM),
            ClosureRollup.includeInParent,
          ),
          isEmpty,
        );
      },
    );

    test('include_in_parent: wrong aggregate is caught', () {
      final v = check(
        result(methodM, value: 5, includes: [closure.id]),
        result(closureM),
        ClosureRollup.includeInParent,
      );
      expect(
        v.join(),
        contains('value=5 but rollUp(measured=2, children=[3]) = 4'),
      );
    });

    test('include_in_parent: includes must list every direct child', () {
      final v = check(
        result(methodM, value: 2),
        result(closureM),
        ClosureRollup.includeInParent,
      );
      expect(v.join(), contains('missing from includes'));
    });

    test('separate: a non-empty includes or value != measured is caught', () {
      final v = check(
        result(methodM, value: 4, includes: [closure.id]),
        result(closureM),
        ClosureRollup.separate,
      );
      expect(v.join(), contains('policy separate but value=4'));
      expect(v.join(), contains('policy separate but includes='));
    });

    test('measured must equal base + Σ contributors', () {
      final bad = Measurement(
        metricId: 'ifcount',
        scope: method.id,
        value: 7,
        contributors: methodM.contributors,
      );
      final v = check(result(bad), result(closureM), ClosureRollup.separate);
      expect(
        v.join(),
        contains('measured=7 but base 1 + Σ contributors 1 = 2'),
      );
    });

    test('contributors must lie inside the scope span', () {
      final outside = Measurement(
        metricId: 'ifcount',
        scope: closure.id,
        value: 2,
        contributors: [ifAt('if (a)')],
      );
      final v = check(result(methodM), result(outside), ClosureRollup.separate);
      expect(v.join(), contains('lies outside the scope span'));
    });

    test('scope.partial must agree with the file', () {
      final partialMethod = ScopeContext(
        id: method.id,
        kind: method.kind,
        parent: fileCtx,
        span: method.span,
        qualifiedName: method.qualifiedName,
        partial: true,
      );
      final report = FileReport(
        source: source,
        diagnostics: const [],
        scopes: [
          ScopeResult(
            scope: partialMethod,
            results: {'ifcount': result(methodM)},
          ),
        ],
      );
      final v = checkResultInvariants(
        file: report,
        scope: report.scopes.single,
        metricId: 'ifcount',
        result: result(methodM),
        measures: ScopeKind.measuredInV1,
        policy: ClosureRollup.separate,
        invariants: ResultInvariants.cyclomaticStyle,
      );
      expect(v.join(), contains('scope.partial=true but file.partial=false'));
    });
  });
}
