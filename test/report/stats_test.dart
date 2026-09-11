import 'package:metra/metra.dart';
import 'package:test/test.dart';

void main() {
  final metrics = [CyclomaticMetric()];
  // Values: low 1, mid 2, hidden/high/twin 3 (ternary ×2), name 9 (case ×8).
  const content = '''
int low() => 0;
// ignore: metra_cyclomatic
int hidden(int x) => x > 0 ? (x > 1 ? 2 : 1) : 0;
int high(int x) => x > 0 ? (x > 1 ? 2 : 1) : 0;
int twin(int x) => x > 0 ? (x > 1 ? 2 : 1) : 0;
int mid(int x) {
  if (x > 0) return 1;
  return 0;
}
String name(int x) => switch (x) {
  1 => 'one',
  2 => 'two',
  3 => 'three',
  4 => 'four',
  5 => 'five',
  6 => 'six',
  7 => 'seven',
  8 => 'eight',
  _ => 'many',
};
''';
  const source = SourceFile(
    path: 'lib/a.dart',
    content: content,
    configRoot: '.',
  );
  RunResult run(
    AnalysisConfig config, [
    List<SourceFile> sources = const [source],
  ]) => RunResult(
    metrics: metrics,
    config: config,
    report: analyze(sources, metrics, config),
  );
  const thresholded = AnalysisConfig(
    roots: {
      '.': RootConfig(
        metrics: {
          'cyclomatic': MetricConfig(threshold: Threshold(warn: 2, fail: 3)),
        },
      ),
    },
  );
  const bare = AnalysisConfig(roots: {'.': RootConfig()});

  group('computeStats', () {
    final m = computeStats(run(thresholded)).metrics['cyclomatic']!;

    test('bands and nearest-rank percentiles over the rolled-up value', () {
      expect(m.scopes, 6);
      expect(
        [for (final b in m.bands) '${b.label}=${b.count}'],
        ['1–5=5', '6–9=1', '10–14=0', '15–19=0', '20+=0'],
      );
      expect(m.bands.first.share, closeTo(5 / 6, 1e-9));
      final p = m.percentiles!;
      expect([p.p50, p.p90, p.p95, p.p99, p.max], [3, 9, 9, 9, 9]);
    });

    test('shares use each result\'s own threshold and ignore suppression', () {
      final t = m.thresholds!;
      expect(t.uniform, const Threshold(warn: 2, fail: 3));
      expect(t.atOrAboveWarn.count, 5);
      expect(t.atOrAboveWarn.share, closeTo(5 / 6, 1e-9));
      expect(t.atOrAboveWarn.tableShaped, 1);
      expect(t.atOrAboveFail.count, 4);
      expect(t.atOrAboveFail.tableShaped, 1);
    });

    test('sweep counts scopes at or above each candidate', () {
      expect(
        [for (final s in m.sweep) '${s.atOrAbove}:${s.share.count}'],
        ['5:1', '8:1', '10:0', '12:0', '15:0', '20:0', '25:0', '30:0'],
      );
      expect(m.sweep.first.share.tableShaped, 1);
    });

    test('contributor mix is the share of summed increments, descending', () {
      expect(m.contributorMix.keys, ['case', 'ternary', 'if']);
      expect(m.contributorMix['case'], closeTo(8 / 15, 1e-9));
      expect(m.contributorMix['ternary'], closeTo(6 / 15, 1e-9));
      expect(m.contributorMix['if'], closeTo(1 / 15, 1e-9));
    });

    test('sibling clusters: same value and summary, at or above warn', () {
      final c = m.siblingClusters.single;
      expect(c.value, 3);
      expect(c.contributorSummary, {'ternary': 2});
      expect(
        [
          for (final s in c.scopes)
            '${s.path}:${s.line} ${s.kind} ${s.qualifiedName}',
        ],
        [
          'lib/a.dart:3 function hidden',
          'lib/a.dart:4 function high',
          'lib/a.dart:5 function twin',
        ],
      );
    });

    test('no thresholds: shares absent, clusters floor at the top decile', () {
      final m = computeStats(run(bare)).metrics['cyclomatic']!;
      expect(m.thresholds, isNull);
      expect(m.percentiles!.p90, 9);
      expect(m.siblingClusters, isEmpty);
    });

    test('per-root thresholds: counted individually, no uniform pair', () {
      const config = AnalysisConfig(
        roots: {
          'a': RootConfig(
            metrics: {
              'cyclomatic': MetricConfig(
                threshold: Threshold(warn: 2, fail: 3),
              ),
            },
          ),
          'b': RootConfig(
            metrics: {
              'cyclomatic': MetricConfig(
                threshold: Threshold(warn: 9, fail: 9),
              ),
            },
          ),
        },
      );
      final m = computeStats(
        run(config, const [
          SourceFile(path: 'a/x.dart', content: content, configRoot: 'a'),
          SourceFile(path: 'b/x.dart', content: content, configRoot: 'b'),
        ]),
      ).metrics['cyclomatic']!;
      expect(m.scopes, 12);
      expect(m.thresholds!.uniform, isNull);
      expect(m.thresholds!.atOrAboveWarn.count, 5 + 1);
      expect(m.thresholds!.atOrAboveFail.count, 4 + 1);
    });

    test('nothing analyzed: zero scopes, no percentiles', () {
      final stats = computeStats(run(bare, const []));
      expect(stats.files, 0);
      final m = stats.metrics['cyclomatic']!;
      expect(m.scopes, 0);
      expect(m.percentiles, isNull);
      expect(m.bands.map((b) => b.count), everyElement(0));
      expect(m.contributorMix, isEmpty);
    });
  });

  group('renderStatsConsole', () {
    test('sections in order, aligned columns, clusters listed', () {
      final lines = renderStatsConsole(computeStats(run(thresholded)))
          .trimRight()
          .split('\n');
      expect(lines, [
        'cyclomatic • 6 scopes in 1 file',
        'Distribution',
        '  1–5        5  83.3%  ████████████████████',
        '  6–9        1  16.7%  ████',
        '  10–14      0   0.0%',
        '  15–19      0   0.0%',
        '  20+        0   0.0%',
        '  p50 3 • p90 9 • p95 9 • p99 9 • max 9',
        'Thresholds • warn ≥ 2, fail ≥ 3',
        '  ≥ warn     5  83.3%  1 table-shaped',
        '  ≥ fail     4  66.7%  1 table-shaped',
        'Sweep • scopes at or above each candidate',
        '  ≥ 5        1  16.7%  1 table-shaped',
        '  ≥ 8        1  16.7%  1 table-shaped',
        '  ≥ 10       0   0.0%',
        '  ≥ 12       0   0.0%',
        '  ≥ 15       0   0.0%',
        '  ≥ 20       0   0.0%',
        '  ≥ 25       0   0.0%',
        '  ≥ 30       0   0.0%',
        'Contributor mix • share of summed increments',
        '  case 53.3% • ternary 40.0% • if 6.7%',
        'Sibling clusters • same value and contributor mix, ≥ warn',
        '  cyclomatic 3 • ternary ×2 • 3 scopes',
        '    lib/a.dart:3 function hidden',
        '    lib/a.dart:4 function high',
        '    lib/a.dart:5 function twin',
      ]);
    });

    test('no thresholds and no clusters say so', () {
      final text = renderStatsConsole(computeStats(run(bare)));
      expect(text, contains('Thresholds • none configured\n'));
      expect(
        text,
        endsWith(
          'Sibling clusters • same value and contributor mix, top decile\n'
          '  none\n',
        ),
      );
    });

    test('a palette bolds headings and paints the threshold counts', () {
      final text = renderStatsConsole(
        computeStats(run(thresholded)),
        palette: Palette.ansi,
      );
      expect(text, startsWith('\x1B[1mcyclomatic\x1B[0m • 6 scopes'));
      expect(text, contains('  ≥ warn \x1B[33m    5\x1B[0m  83.3%'));
      expect(text, contains('  ≥ fail \x1B[31m    4\x1B[0m  66.7%'));
      expect(text, contains('\x1B[2m1 table-shaped\x1B[0m'));
    });

    test(
      'diagnostics first, parse errors in the header, empty run says so',
      () {
        final r = RunResult(
          metrics: metrics,
          config: bare,
          report: analyze(
            const [
              SourceFile(
                path: 'lib/b.dart',
                content: 'int f() => 0\n',
                configRoot: '.',
              ),
            ],
            metrics,
            bare,
          ),
          diagnostics: const [
            RunDiagnostic(path: 'x.dart', message: 'could not read file'),
          ],
        );
        final lines = renderStatsConsole(computeStats(r)).split('\n');
        expect(lines.first, 'x.dart: error: could not read file');
        expect(
          lines[1],
          'cyclomatic • 1 scope in 1 file • 1 file with parse errors',
        );
        expect(
          renderStatsConsole(computeStats(run(bare, const []))),
          'No files analyzed.\ncyclomatic • 0 scopes in 0 files\n',
        );
      },
    );
  });

  test('renderStatsJson: its own document, shares as fractions', () {
    final json = jsonStats(
      computeStats(run(thresholded)),
      status: RunStatus.violations,
    );
    expect(json['schemaVersion'], statsSchemaVersion);
    expect(json['status'], 'ok');
    expect(json['summary'], {'files': 1, 'filesWithErrors': 0});
    final m = json['metrics'] as Map;
    final c = m['cyclomatic'] as Map;
    expect(c['scopes'], 6);
    expect((c['bands'] as List).first, {
      'label': '1–5',
      'from': 1,
      'to': 5,
      'count': 5,
      'share': 5 / 6,
    });
    expect((c['bands'] as List).last['to'], isNull);
    expect(c['percentiles'], {
      'p50': 3,
      'p90': 9,
      'p95': 9,
      'p99': 9,
      'max': 9,
    });
    expect((c['thresholds'] as Map)['uniform'], {'warn': 2, 'fail': 3});
    expect((c['thresholds'] as Map)['atOrAboveFail'], {
      'count': 4,
      'share': 4 / 6,
      'tableShaped': 1,
    });
    expect((c['sweep'] as List).first, {
      'atOrAbove': 5,
      'count': 1,
      'share': 1 / 6,
      'tableShaped': 1,
    });
    expect((c['contributorMix'] as Map).keys, ['case', 'ternary', 'if']);
    final cluster = (c['siblingClusters'] as List).single as Map;
    expect(cluster['value'], 3);
    expect(cluster['contributorSummary'], {'ternary': 2});
    expect((cluster['scopes'] as List).length, 3);
    expect(
      jsonStats(computeStats(run(bare)), status: RunStatus.errors)['status'],
      'errors',
    );
    expect(
      renderStatsJson(computeStats(run(bare))),
      startsWith('{\n  "schemaVersion": 1,'),
    );
  });
}
