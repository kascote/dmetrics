import 'package:metra/metra.dart';
import 'package:test/test.dart';

import '../harness/dummy_metrics.dart';
import 'recording_metric.dart';

void main() {
  const content = '''
void low() {}
void mid(int a) {
  if (a > 0) {}
  if (a > 1) {}
  if (a > 2) {}
}
void high(int a) {
  if (a > 0) {}
  if (a > 1) {}
  if (a > 2) {}
  if (a > 3) {}
  if (a > 4) {}
}
''';

  Map<String, MetricResult> resultsOf(Report r, [int file = 0]) => {
    for (final s in r.files[file].scopes)
      s.scope.qualifiedName: s.results['ifcount']!,
  };

  group('thresholds and verdicts', () {
    test('no threshold configured: every verdict is ok, threshold null', () {
      final r = analyze(
        [src(content)],
        [IfCountMetric()],
        const AnalysisConfig(),
      );
      for (final res in resultsOf(r).values) {
        expect(res.threshold, isNull);
        expect(res.verdict, Verdict.ok);
      }
    });

    test('warn and fail are inclusive lower bounds', () {
      final r = analyze(
        [src(content)],
        [IfCountMetric()],
        const AnalysisConfig(
          roots: {
            '.': RootConfig(
              metrics: {
                'ifcount': MetricConfig(threshold: Threshold(warn: 4, fail: 6)),
              },
            ),
          },
        ),
      );
      final res = resultsOf(r);
      expect(res['low']!.verdict, Verdict.ok);
      expect(res['mid']!.verdict, Verdict.warn);
      expect(res['high']!.verdict, Verdict.fail);
      expect(res['mid']!.threshold, const Threshold(warn: 4, fail: 6));
    });

    test('thresholds and enablement are per config root', () {
      final r = analyze(
        [
          const SourceFile(path: 'a/x.dart', content: content, configRoot: 'a'),
          const SourceFile(path: 'b/x.dart', content: content, configRoot: 'b'),
          const SourceFile(path: 'c/x.dart', content: content, configRoot: 'c'),
        ],
        [IfCountMetric(), RecordingMetric()],
        const AnalysisConfig(
          roots: {
            'a': RootConfig(
              metrics: {
                'ifcount': MetricConfig(threshold: Threshold(warn: 2, fail: 4)),
              },
            ),
            'b': RootConfig(
              metrics: {
                'ifcount': MetricConfig(
                  threshold: Threshold(warn: 10, fail: 20),
                ),
              },
            ),
            'c': RootConfig(metrics: {'ifcount': MetricConfig(enabled: false)}),
          },
        ),
      );
      expect(resultsOf(r, 0)['mid']!.verdict, Verdict.fail);
      expect(resultsOf(r, 1)['mid']!.verdict, Verdict.ok);
      // Disabled in root c: no ifcount results, other metrics unaffected.
      for (final s in r.files[2].scopes) {
        expect(s.results.keys, ['recording']);
      }
    });
  });

  group('aggregation (§6.3)', () {
    const nested = '''
void outer(List<int> xs) {
  if (xs.isEmpty) return;
  xs.forEach((x) {
    if (x > 0) return;
    [x].forEach((y) {
      if (y > 1) print(y);
    });
  });
}
''';

    test('separate: value == measured and includes is empty', () {
      final r = analyze(
        [src(nested)],
        [IfCountMetric()],
        const AnalysisConfig(),
      );
      for (final res in resultsOf(r).values) {
        expect(res.value, res.measured);
        expect(res.includes, isEmpty);
      }
    });

    test('include_in_parent: 2 → 3 → 4 with direct children in includes', () {
      final r = analyze(
        [src(nested)],
        [IfCountMetric()],
        const AnalysisConfig(
          run: RunConfig(closureRollup: ClosureRollup.includeInParent),
        ),
      );
      final res = resultsOf(r);
      expect(res['outer']!.measured, 2);
      expect(res['outer']!.value, 4);
      expect(res['outer']!.includes.map((i) => i.value), [
        'lib/c.dart::function:outer::closure#1',
      ]);
      expect(res['outer.<closure#1>']!.value, 3);
      expect(res['outer.<closure#1>']!.includes.map((i) => i.value), [
        'lib/c.dart::function:outer::closure#1::closure#1',
      ]);
      expect(res['outer.<closure#1>.<closure#1>']!.value, 2);
      expect(res['outer.<closure#1>.<closure#1>']!.includes, isEmpty);
    });

    test('verdicts apply to the aggregated value', () {
      final r = analyze(
        [src(nested)],
        [IfCountMetric()],
        const AnalysisConfig(
          run: RunConfig(closureRollup: ClosureRollup.includeInParent),
          roots: {
            '.': RootConfig(
              metrics: {
                'ifcount': MetricConfig(threshold: Threshold(warn: 3, fail: 4)),
              },
            ),
          },
        ),
      );
      final res = resultsOf(r);
      expect(res['outer']!.verdict, Verdict.fail);
      expect(res['outer.<closure#1>']!.verdict, Verdict.warn);
      expect(res['outer.<closure#1>.<closure#1>']!.verdict, Verdict.ok);
    });

    test('roll-up is per metric: a max metric and a sum metric disagree', () {
      final probeLike = _MaxMetric();
      final r = analyze(
        [src(nested)],
        [IfCountMetric(), probeLike],
        const AnalysisConfig(
          run: RunConfig(closureRollup: ClosureRollup.includeInParent),
        ),
      );
      final outer = r.files.single.scopes.first;
      expect(outer.results['ifcount']!.value, 4);
      expect(outer.results['max']!.value, 2);
    });
  });
}

/// Every scope measures 2; roll-up is max, so nothing ever exceeds 2.
class _MaxMetric extends IfCountMetric {
  @override
  String get id => 'max';

  @override
  Measurement rollUp(Measurement parent, List<Measurement> children) =>
      Measurement(
        metricId: parent.metricId,
        scope: parent.scope,
        value: children.fold(parent.value, (m, c) => c.value > m ? c.value : m),
        contributors: parent.contributors,
      );
}
