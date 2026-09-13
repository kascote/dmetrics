import 'package:dmetrics/dmetrics.dart';
import 'package:test/test.dart';

/// The baseline: file format, matcher and statuses, over in-memory runs.
void main() {
  final metrics = [CyclomaticMetric()];
  const config = AnalysisConfig(
    roots: {
      '.': RootConfig(
        metrics: {
          'cyclomatic': MetricConfig(threshold: Threshold(warn: 3, fail: 5)),
        },
      ),
    },
  );

  /// A function of cyclomatic [value] (nested ternaries).
  String fn(String name, int value) =>
      'int $name(int x) => ${'x > 0 ? ' * (value - 1)}0${' : 1' * (value - 1)};\n';

  Report run(Map<String, String> files, {AnalysisConfig? cfg}) => analyze(
    [
      for (final e in files.entries)
        SourceFile(path: e.key, content: e.value, configRoot: '.'),
    ],
    metrics,
    cfg ?? config,
  );

  Map<String, Object?> knobs([AnalysisConfig? cfg]) =>
      runKnobs(metrics, (cfg ?? config).run);

  LoadedBaseline snapshot(
    Report report, {
    String path = 'dmetrics_baseline.json',
    List<String>? covered,
  }) {
    final location = BaselineLocation(path);
    final file = updateBaseline(
      existing: null,
      location: location,
      run: knobs(),
      metrics: covered ?? ['cyclomatic'],
      recorded: recordRun(report),
      inRun: (_) => true,
    );
    return LoadedBaseline(
      location: location,
      file: decodeBaseline(encodeBaseline(file)),
    );
  }

  ComparisonOutcome compare(
    Report report,
    LoadedBaseline baseline, {
    AnalysisConfig? cfg,
  }) => compareBaselines(
    report: report,
    baselines: {'.': baseline},
    run: knobs(cfg),
    config: (cfg ?? config).run,
  );

  BaselineMatch? matchOf(
    BaselineComparison c,
    Report r,
    String path,
    String local,
  ) => c.of(ScopeId.inFile(path, local), 'cyclomatic');

  group('file format', () {
    test('one scope per line, sorted, round-trips', () {
      final report = run({
        'lib/b.dart': fn('b', 2),
        'lib/a.dart': '${fn('z', 1)}${fn('a', 4)}',
      });
      final text = encodeBaseline(snapshot(report).file);
      final lines = text.trimRight().split('\n');
      expect(lines.first, '{');
      expect(lines, contains('  "metrics": ["cyclomatic"],'));
      final scopeLines = lines.where((l) => l.contains('"fingerprint"'));
      expect(scopeLines, hasLength(3));
      expect(scopeLines.map((l) => l.trim().split('": ').first), [
        '"function:a',
        '"function:z',
        '"function:b',
      ]);
      expect(
        scopeLines.first,
        matches(
          r'^      "function:a": \{"fingerprint":"[0-9a-f]{8}","cyclomatic":4\},$',
        ),
      );
      expect(
        lines.indexOf('    "lib/a.dart": {'),
        lessThan(lines.indexOf('    "lib/b.dart": {')),
      );
      final decoded = decodeBaseline(text);
      expect(decoded.files['lib/a.dart']!['function:a']!.values, {
        'cyclomatic': 4,
      });
      expect(encodeBaseline(decoded), text);
    });

    test('decode names what is wrong', () {
      expect(
        () => decodeBaseline('nope'),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            startsWith('invalid JSON'),
          ),
        ),
      );
      expect(
        () => decodeBaseline('{"schemaVersion": 2}'),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('schemaVersion'),
          ),
        ),
      );
      expect(
        () => decodeBaseline(
          '{"schemaVersion": 1, "run": {}, "metrics": ["cyclomatic"], '
          '"files": {"lib/a.dart": {"function:a": {"cyclomatic": 1}}}}',
        ),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('function:a'),
          ),
        ),
      );
    });

    test('paths are stored relative to the file and rebased on load', () {
      const location = BaselineLocation('packages/x/tool/base.json');
      expect(location.fromRunRoot('packages/x/lib/a.dart'), '../lib/a.dart');
      expect(location.toRunRoot('../lib/a.dart'), 'packages/x/lib/a.dart');
      const atRoot = BaselineLocation('dmetrics_baseline.json');
      expect(atRoot.fromRunRoot('lib/a.dart'), 'lib/a.dart');
      expect(atRoot.toRunRoot('lib/a.dart'), 'lib/a.dart');
    });

    test(
      'update replaces the run\'s files, keeps the rest, drops on knob change',
      () {
        const location = BaselineLocation('dmetrics_baseline.json');
        final first = snapshot(
          run({'lib/a.dart': fn('a', 2), 'lib/b.dart': fn('b', 2)}),
        ).file;
        final partial = updateBaseline(
          existing: first,
          location: location,
          run: knobs(),
          metrics: ['cyclomatic'],
          recorded: recordRun(run({'lib/a.dart': fn('a', 4)})),
          inRun: (path) => path == 'lib/a.dart',
        );
        expect(
          partial.files.keys,
          unorderedEquals(['lib/a.dart', 'lib/b.dart']),
        );
        expect(
          partial.files['lib/a.dart']!['function:a']!.values['cyclomatic'],
          4,
        );
        expect(
          partial.files['lib/b.dart']!['function:b']!.values['cyclomatic'],
          2,
        );

        // A directory target drops entries for files no longer under it.
        final pruned = updateBaseline(
          existing: first,
          location: location,
          run: knobs(),
          metrics: ['cyclomatic'],
          recorded: recordRun(run({'lib/a.dart': fn('a', 2)})),
          inRun: (path) => path.startsWith('lib/'),
        );
        expect(pruned.files.keys, ['lib/a.dart']);

        final rewritten = updateBaseline(
          existing: first,
          location: location,
          run: {...knobs(), 'closure_rollup': 'include_in_parent'},
          metrics: ['cyclomatic'],
          recorded: recordRun(run({'lib/a.dart': fn('a', 2)})),
          inRun: (path) => path == 'lib/a.dart',
        );
        expect(rewritten.files.keys, ['lib/a.dart']);
      },
    );
  });

  group('matcher', () {
    test('same code: every result unchanged, counts empty', () {
      final report = run({'lib/a.dart': fn('a', 6)});
      final c = compare(report, snapshot(report)).comparison!;
      expect(c.byRoot, {'.': 'dmetrics_baseline.json'});
      expect(
        matchOf(c, report, 'lib/a.dart', 'function:a')!.status,
        BaselineStatus.baselined,
      );
      expect(c.counts.baselined, 1);
      expect(c.counts.stale, 0);
    });

    test('a rename with the same body matches by fingerprint', () {
      final before = run({'lib/a.dart': fn('a', 6)});
      final after = run({'lib/a.dart': fn('renamed', 6)});
      final c = compare(after, snapshot(before)).comparison!;
      final m = matchOf(c, after, 'lib/a.dart', 'function:renamed')!;
      expect(m.status, BaselineStatus.baselined);
      expect(m.value, 6);
      expect(c.counts.gone, 0);
    });

    test('a move between files in the run matches by fingerprint', () {
      final before = run({'lib/a.dart': fn('a', 6), 'lib/b.dart': fn('b', 1)});
      final after = run({
        'lib/a.dart': fn('z', 1),
        'lib/b.dart': '${fn('b', 1)}${fn('a', 6)}',
      });
      final c = compare(after, snapshot(before)).comparison!;
      expect(
        matchOf(c, after, 'lib/b.dart', 'function:a')!.status,
        BaselineStatus.baselined,
      );
      expect(
        matchOf(c, after, 'lib/a.dart', 'function:z')!.status,
        BaselineStatus.added,
      );
      expect(c.counts.added, 0, reason: 'a new ok scope is not a violation');
      expect(c.counts.gone, 0);
    });

    test('a rename plus a body edit reads as new and gone', () {
      final before = run({'lib/a.dart': fn('a', 6)});
      final after = run({'lib/a.dart': fn('b', 7)});
      final c = compare(after, snapshot(before)).comparison!;
      expect(
        matchOf(c, after, 'lib/a.dart', 'function:b')!.status,
        BaselineStatus.added,
      );
      expect(c.counts.added, 1);
      expect(c.counts.gone, 1);
    });

    test('an ambiguous fingerprint matches nothing', () {
      final before = run({'lib/a.dart': '${fn('a', 6)}${fn('b', 6)}'});
      final after = run({'lib/a.dart': '${fn('c', 6)}${fn('d', 6)}'});
      final c = compare(after, snapshot(before)).comparison!;
      expect(
        matchOf(c, after, 'lib/a.dart', 'function:c')!.status,
        BaselineStatus.added,
      );
      expect(
        matchOf(c, after, 'lib/a.dart', 'function:d')!.status,
        BaselineStatus.added,
      );
      expect(c.counts.gone, 2);
    });

    test('closures match by fingerprint before ordinal, so an insertion does not shift them', () {
      String method(List<String> closures) =>
          'void m() {\n${closures.map((c) => '  final f = $c;\n').join()}}\n';
      const a =
          '(int x) => x > 0 ? x > 1 ? x > 2 ? x > 3 ? x > 4 ? 5 : 4 : 3 : 2 : 1 : 0';
      const b =
          '(int y) => y > 0 ? y > 1 ? y > 2 ? y > 3 ? y > 4 ? y > 5 ? 6 : 5 : 4 : 3 : 2 : 1 : 0';
      const inserted = '(int z) => z';
      final before = run({
        'lib/a.dart': method([a, b]),
      });
      final after = run({
        'lib/a.dart': method([inserted, a, b]),
      });
      final c = compare(after, snapshot(before)).comparison!;
      expect(
        matchOf(c, after, 'lib/a.dart', 'function:m::closure#1')!.status,
        BaselineStatus.added,
      );
      expect(
        matchOf(c, after, 'lib/a.dart', 'function:m::closure#2')!.status,
        BaselineStatus.baselined,
      );
      expect(
        matchOf(c, after, 'lib/a.dart', 'function:m::closure#2')!.value,
        6,
      );
      expect(
        matchOf(c, after, 'lib/a.dart', 'function:m::closure#3')!.value,
        7,
      );
      expect(c.counts.gone, 0);

      // An edited closure still matches by ordinal when nothing moved.
      final edited = run({
        'lib/a.dart': method([a, '(int y) => y > 0 ? 1 : 0']),
      });
      final e = compare(edited, snapshot(before)).comparison!;
      final second = matchOf(e, edited, 'lib/a.dart', 'function:m::closure#2')!;
      expect(second.status, BaselineStatus.changed);
      expect(second.value, 7);
      expect(e.counts.fixed, 1);
    });
  });

  group('status', () {
    test('worse, baselined, changed and fixed against fail_on: fail', () {
      final before = run({
        'lib/a.dart':
            '${fn('up', 5)}${fn('same', 5)}${fn('down', 6)}${fn('fixed', 5)}${fn('drift', 1)}',
      });
      final after = run({
        'lib/a.dart':
            '${fn('up', 6)}${fn('same', 5)}${fn('down', 5)}${fn('fixed', 2)}${fn('drift', 2)}',
      });
      final c = compare(after, snapshot(before)).comparison!;
      BaselineStatus status(String name) =>
          matchOf(c, after, 'lib/a.dart', 'function:$name')!.status;
      expect(status('up'), BaselineStatus.worse);
      expect(status('same'), BaselineStatus.baselined);
      expect(status('down'), BaselineStatus.baselined);
      expect(status('fixed'), BaselineStatus.changed);
      expect(status('drift'), BaselineStatus.changed);
      expect(c.counts.worse, 1);
      expect(c.counts.baselined, 2);
      expect(c.counts.changed, 2);
      expect(c.counts.fixed, 1);
      expect(
        c.accepts(ScopeId.inFile('lib/a.dart', 'function:same'), 'cyclomatic'),
        isTrue,
      );
      expect(
        c.accepts(ScopeId.inFile('lib/a.dart', 'function:up'), 'cyclomatic'),
        isFalse,
      );
    });

    test('fail_on: warn moves the floor', () {
      final warnConfig = config.copyWith(
        run: const RunConfig(failOn: FailOn.warn),
      );
      final before = run({'lib/a.dart': fn('a', 3)}, cfg: warnConfig);
      final after = run({'lib/a.dart': fn('a', 4)}, cfg: warnConfig);
      final c = compare(after, snapshot(before), cfg: warnConfig).comparison!;
      expect(
        matchOf(c, after, 'lib/a.dart', 'function:a')!.status,
        BaselineStatus.worse,
      );
    });

    test('a suppression added since is not a fix and never a violation', () {
      final before = run({'lib/a.dart': fn('a', 6)});
      final after = run({
        'lib/a.dart': '// ignore: dmetrics_cyclomatic\n${fn('a', 7)}',
      });
      final c = compare(after, snapshot(before)).comparison!;
      expect(
        matchOf(c, after, 'lib/a.dart', 'function:a')!.status,
        BaselineStatus.changed,
      );
      expect(c.counts.fixed, 0);
      final result = RunResult(
        metrics: metrics,
        config: config,
        report: after,
        baseline: c,
      );
      expect(result.hasViolations, isFalse);
    });

    test('exit 1 means new or worse', () {
      final before = run({'lib/a.dart': fn('a', 6)});
      RunResult result(Report r) => RunResult(
        metrics: metrics,
        config: config,
        report: r,
        baseline: compare(r, snapshot(before)).comparison,
      );
      expect(result(before).hasViolations, isFalse);
      expect(result(run({'lib/a.dart': fn('a', 7)})).hasViolations, isTrue);
      expect(
        result(run({'lib/a.dart': '${fn('a', 6)}${fn('b', 6)}'})).hasViolations,
        isTrue,
      );
      expect(
        result(run({'lib/a.dart': '${fn('a', 6)}${fn('b', 1)}'})).hasViolations,
        isFalse,
      );
    });

    test('a metric the file does not cover is compared as if there were no baseline', () {
      final report = run({'lib/a.dart': fn('a', 6)});
      final c = compare(
        report,
        snapshot(report, covered: ['cognitive']),
      ).comparison!;
      expect(matchOf(c, report, 'lib/a.dart', 'function:a'), isNull);
      expect(c.counts.isEmpty, isTrue);
      final result = RunResult(
        metrics: metrics,
        config: config,
        report: report,
        baseline: c,
      );
      expect(result.hasViolations, isTrue);
    });

    test('different knobs are a problem and the file is skipped', () {
      final report = run({'lib/a.dart': fn('a', 6)});
      final other = config.copyWith(
        run: const RunConfig(settings: {'cyclomatic.count_case_arms': false}),
      );
      final outcome = compare(report, snapshot(report), cfg: other);
      expect(outcome.comparison, isNull);
      expect(outcome.problems, hasLength(1));
      expect(outcome.problems.single.path, 'dmetrics_baseline.json');
      expect(
        outcome.problems.single.message,
        stringContainsInOrder([
          'count_case_arms=true',
          ' vs ',
          'count_case_arms=false',
        ]),
      );
    });

    test('files outside the run are ignored on both sides', () {
      final before = run({'lib/a.dart': fn('a', 6), 'lib/b.dart': fn('b', 6)});
      final after = run({'lib/a.dart': fn('a', 6)});
      final c = compare(after, snapshot(before)).comparison!;
      expect(c.counts.gone, 0);
      expect(c.counts.baselined, 1);
    });
  });
}
