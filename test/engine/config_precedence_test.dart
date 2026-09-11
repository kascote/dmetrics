import 'package:dmetrics/dmetrics.dart';
import 'package:test/test.dart';

/// Per-root overrides and CLI layers as the engine applies them (§8).
void main() {
  const content = '''
int f(int x) => x > 0 ? (x > 1 ? 2 : 1) : 0;
''';

  MetricResult resultIn(Report r, String path) => r.files
      .firstWhere((f) => f.path == path)
      .scopes
      .single
      .results['cyclomatic']!;

  test('overrides match the path relative to the config root, last wins', () {
    final root = RootConfig(
      metrics: const {
        'cyclomatic': MetricConfig(threshold: Threshold(warn: 10, fail: 20)),
      },
      overrides: [
        ConfigOverride(
          paths: ['lib/**'],
          metrics: const {
            'cyclomatic': MetricConfig(threshold: Threshold(warn: 1, fail: 2)),
          },
        ),
        ConfigOverride(
          paths: ['lib/gen/**'],
          metrics: const {'cyclomatic': MetricConfig(enabled: false)},
        ),
        ConfigOverride(
          paths: ['lib/gen/keep.dart'],
          metrics: const {'cyclomatic': MetricConfig(enabled: true)},
        ),
      ],
    );
    final r = analyze(
      [
        const SourceFile(
          path: 'pkg/lib/a.dart',
          content: content,
          configRoot: 'pkg',
        ),
        const SourceFile(
          path: 'pkg/lib/gen/a.dart',
          content: content,
          configRoot: 'pkg',
        ),
        const SourceFile(
          path: 'pkg/lib/gen/keep.dart',
          content: content,
          configRoot: 'pkg',
        ),
        const SourceFile(
          path: 'pkg/test/a.dart',
          content: content,
          configRoot: 'pkg',
        ),
        // Same relative path, a root that a `lib/**` glob would match if it
        // saw the run-root-relative path; it must not.
        const SourceFile(
          path: 'lib/pkg/lib/a.dart',
          content: content,
          configRoot: 'lib/pkg/lib',
        ),
      ],
      [CyclomaticMetric()],
      AnalysisConfig(roots: {'pkg': root, 'lib/pkg/lib': root}),
    );
    expect(resultIn(r, 'pkg/lib/a.dart').verdict, Verdict.fail);
    expect(
      resultIn(r, 'pkg/lib/a.dart').threshold,
      const Threshold(warn: 1, fail: 2),
    );
    expect(resultIn(r, 'pkg/test/a.dart').verdict, Verdict.ok);
    expect(
      resultIn(r, 'pkg/test/a.dart').threshold,
      const Threshold(warn: 10, fail: 20),
    );
    expect(
      r.files
          .firstWhere((f) => f.path == 'pkg/lib/gen/a.dart')
          .scopes
          .single
          .results,
      isEmpty,
    );
    // Enabled again by the later, more specific override; threshold from the
    // earlier `lib/**` override still applies.
    expect(
      resultIn(r, 'pkg/lib/gen/keep.dart').threshold,
      const Threshold(warn: 1, fail: 2),
    );
    expect(
      resultIn(r, 'lib/pkg/lib/a.dart').threshold,
      const Threshold(warn: 10, fail: 20),
    );
  });

  test('forced (CLI) thresholds beat overrides', () {
    final root = RootConfig(
      overrides: [
        ConfigOverride(
          paths: ['**'],
          metrics: const {
            'cyclomatic': MetricConfig(threshold: Threshold(warn: 1, fail: 2)),
          },
        ),
      ],
      forced: const {
        'cyclomatic': MetricConfig(threshold: Threshold(warn: 50, fail: 60)),
      },
    );
    final r = analyze(
      [const SourceFile(path: 'a.dart', content: content, configRoot: '.')],
      [CyclomaticMetric()],
      AnalysisConfig(roots: {'.': root}),
    );
    expect(
      resultIn(r, 'a.dart').threshold,
      const Threshold(warn: 50, fail: 60),
    );
    expect(resultIn(r, 'a.dart').verdict, Verdict.ok);
  });
}
