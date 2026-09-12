import 'dart:io';

import 'package:dmetrics/dmetrics.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// I/O layer on real temp directories (§5.2, §8 config roots).
void main() {
  late Directory tmp;
  final metrics = [CyclomaticMetric()];
  final specs = [for (final m in metrics) m.spec];

  setUp(() => tmp = Directory.systemTemp.createTempSync('dmetrics_io_'));
  tearDown(() => tmp.deleteSync(recursive: true));

  void write(String rel, String content) {
    final f = File(p.join(tmp.path, rel));
    f.parent.createSync(recursive: true);
    f.writeAsStringSync(content);
  }

  const fn = 'int f(int x) => x > 0 ? (x > 1 ? 2 : 1) : 0;\n';

  DiscoveredSources expand(List<String> targets, {String? configPath}) =>
      Discovery(
        runRoot: tmp.path,
        metrics: specs,
        configPath: configPath,
      ).expand(targets);

  group('target expansion', () {
    test('directories recurse, skip dot-dirs and default excludes; files are explicit', () {
      write('pubspec.yaml', 'name: x\n');
      write('lib/a.dart', fn);
      write('lib/sub/b.dart', fn);
      write('lib/c.g.dart', fn);
      write('lib/d.freezed.dart', fn);
      write('lib/notes.txt', 'x');
      write('.dart_tool/x.dart', fn);
      write('build/out.dart', fn);
      final d = expand(['lib', 'lib/c.g.dart']);
      expect(d.missingTargets, isEmpty);
      expect(d.diagnostics, isEmpty);
      expect(d.sources.map((s) => s.path), [
        'lib/a.dart',
        'lib/c.g.dart', // explicit: bypasses the exclude
        'lib/sub/b.dart',
      ]);
      expect(d.sources.map((s) => s.configRoot).toSet(), {'.'});
      expect(d.roots, {'.': null});
    });

    test('no targets means the run root', () {
      write('pubspec.yaml', 'name: x\n');
      write('lib/a.dart', fn);
      expect(expand([]).sources.map((s) => s.path), ['lib/a.dart']);
    });

    test('missing targets are reported, not analyzed', () {
      write('lib/a.dart', fn);
      final d = expand(['lib', 'nope.dart', 'no/dir']);
      expect(d.missingTargets, ['nope.dart', 'no/dir']);
      expect(d.sources, hasLength(1));
    });

    test('a file named twice is analyzed once', () {
      write('lib/a.dart', fn);
      final d = expand(['lib/a.dart', 'lib', './lib/a.dart']);
      expect(d.sources.map((s) => s.path), ['lib/a.dart']);
    });

    test(
      'absolute targets and targets above the run root get relative paths',
      () {
        write('pkg/pubspec.yaml', 'name: pkg\n');
        write('pkg/lib/a.dart', fn);
        final inner = Discovery(
          runRoot: p.join(tmp.path, 'pkg', 'lib'),
          metrics: specs,
        );
        final d = inner.expand([p.join(tmp.path, 'pkg')]);
        expect(d.sources.single.path, 'a.dart');
        expect(d.sources.single.configRoot, '..');
      },
    );
  });

  group('language version', () {
    test('the sdk lower bound of the nearest pubspec, per package', () {
      write('pubspec.yaml', 'name: x\nenvironment:\n  sdk: ^3.12.0\n');
      write('lib/a.dart', fn);
      write(
        'pkg/pubspec.yaml',
        "name: y\nenvironment:\n  sdk: '>=3.0.0 <4.0.0'\n",
      );
      write('pkg/lib/deep/b.dart', fn);
      final d = expand(['lib', 'pkg']);
      expect(
        {for (final s in d.sources) s.path: s.languageVersion},
        {
          'lib/a.dart': LanguageVersion(3, 12),
          'pkg/lib/deep/b.dart': LanguageVersion(3, 0),
        },
      );
    });

    test('no pubspec, no sdk entry, or a broken pubspec means latest', () {
      write('lib/a.dart', fn);
      write('noenv/pubspec.yaml', 'name: x\n');
      write('noenv/lib/b.dart', fn);
      write('broken/pubspec.yaml', 'environment: [\n');
      write('broken/lib/c.dart', fn);
      final d = expand(['lib', 'noenv', 'broken']);
      expect(d.sources.map((s) => s.languageVersion), everyElement(isNull));
      expect(d.sources, hasLength(3));
    });

    test('the language version does not depend on the config root', () {
      // A dmetrics section below the package root makes `lib` the config
      // root; the language version still comes from the package's pubspec.
      write('pubspec.yaml', 'name: y\nenvironment:\n  sdk: ^3.8.0\n');
      write(
        'lib/analysis_options.yaml',
        'dmetrics:\n  metrics:\n    cyclomatic: {thresholds: {warn: 3}}\n',
      );
      write('lib/a.dart', fn);
      final d = expand(['lib']);
      expect(d.sources.single.configRoot, 'lib');
      expect(d.sources.single.languageVersion, LanguageVersion(3, 8));
    });
  });

  group('package URI', () {
    test('files under a package lib/ get package:<name>/<path>', () {
      write('pubspec.yaml', 'name: x\n');
      write('lib/a.dart', fn);
      write('lib/src/deep/b.dart', fn);
      write('bin/t.dart', fn);
      write('test/t_test.dart', fn);
      write('pkg/pubspec.yaml', 'name: y\n');
      write('pkg/lib/c.dart', fn);
      final d = expand(['lib', 'bin', 'test', 'pkg']);
      expect(
        {for (final s in d.sources) s.path: s.packageUri?.toString()},
        {
          'bin/t.dart': null,
          'lib/a.dart': 'package:x/a.dart',
          'lib/src/deep/b.dart': 'package:x/src/deep/b.dart',
          'pkg/lib/c.dart': 'package:y/c.dart',
          'test/t_test.dart': null,
        },
      );
    });

    test('no pubspec or no name means no package URI', () {
      write('lib/a.dart', fn);
      write('noname/pubspec.yaml', 'environment:\n  sdk: ^3.0.0\n');
      write('noname/lib/b.dart', fn);
      final d = expand(['lib', 'noname']);
      expect(d.sources.map((s) => s.packageUri), everyElement(isNull));
      expect(d.sources, hasLength(2));
    });
  });

  group('config roots', () {
    test('nearest analysis_options.yaml with a dmetrics section', () {
      write('pubspec.yaml', 'name: x\n');
      write(
        'analysis_options.yaml',
        'dmetrics:\n  metrics:\n    cyclomatic: {thresholds: {warn: 1, fail: 2}}\n',
      );
      write('lib/a.dart', fn);
      write('lib/nested/analysis_options.yaml', 'dmetrics:\n  exclude: []\n');
      write('lib/nested/b.dart', fn);
      write('lib/nested/deep/c.g.dart', fn);
      write('lib/other/analysis_options.yaml', 'linter:\n  rules: []\n');
      write('lib/other/d.dart', fn);
      final d = expand(['lib']);
      expect(
        {for (final s in d.sources) s.path: s.configRoot},
        {
          'lib/a.dart': '.',
          'lib/nested/b.dart': 'lib/nested',
          'lib/nested/deep/c.g.dart':
              'lib/nested', // that root's exclude is empty
          'lib/other/d.dart': '.', // no dmetrics key: not a root
        },
      );
      expect(d.roots.keys, unorderedEquals(['.', 'lib/nested']));
      expect(d.roots['.']!.source, 'analysis_options.yaml');
      expect(d.roots['lib/nested']!.source, 'lib/nested/analysis_options.yaml');
    });

    test('include/exclude of the root apply to discovered files only', () {
      write('pubspec.yaml', 'name: x\n');
      write(
        'analysis_options.yaml',
        "dmetrics:\n  include: ['lib/**']\n  exclude: ['lib/skip/**']\n",
      );
      write('lib/a.dart', fn);
      write('lib/skip/b.dart', fn);
      write('test/c.dart', fn);
      expect(expand(['.']).sources.map((s) => s.path), ['lib/a.dart']);
      expect(
        expand(['test/c.dart', 'lib/skip/b.dart']).sources.map((s) => s.path),
        ['lib/skip/b.dart', 'test/c.dart'],
      );
    });

    test(
      'package root without a dmetrics section is a defaults root',
      () {
        write('mono/pkg_a/pubspec.yaml', 'name: a\n');
        write('mono/pkg_a/lib/a.dart', fn);
        write('mono/pkg_b/pubspec.yaml', 'name: b\n');
        write(
          'mono/pkg_b/analysis_options.yaml',
          'dmetrics:\n  fail_on: warn\n',
        );
        write('mono/pkg_b/lib/a.dart', fn);
        write('loose.dart', fn);
        final d = expand(['mono', 'loose.dart']);
        expect(
          {for (final s in d.sources) s.path: s.configRoot},
          {
            'loose.dart':
                '.', // no pubspec anywhere below the fs root: run root
            'mono/pkg_a/lib/a.dart': 'mono/pkg_a',
            'mono/pkg_b/lib/a.dart': 'mono/pkg_b',
          },
        );
        expect(d.roots['mono/pkg_a'], isNull);
        expect(d.roots['mono/pkg_b']!.runValues, {'fail_on': FailOn.warn});
      },
      skip: _hasPubspecAbove(Directory.systemTemp.path)
          ? 'a pubspec.yaml above the temp dir would become the root'
          : null,
    );

    test('--config forces one root for every file', () {
      write('pubspec.yaml', 'name: x\n');
      write('conf/analysis_options.yaml', 'dmetrics:\n  fail_on: warn\n');
      write('lib/analysis_options.yaml', 'dmetrics:\n  fail_on: fail\n');
      write('lib/a.dart', fn);
      write('other/b.dart', fn);
      final d = expand(['.'], configPath: 'conf/analysis_options.yaml');
      expect(d.sources.map((s) => s.configRoot).toSet(), {'conf'});
      expect(d.roots.keys, ['conf']);
      expect(d.roots['conf']!.runValues, {'fail_on': FailOn.warn});
    });

    test('a missing --config file is a missing target', () {
      write('lib/a.dart', fn);
      expect(expand(['lib'], configPath: 'nope.yaml').missingTargets, [
        'nope.yaml',
      ]);
    });

    test('config problems surface through analyzePaths as errors', () {
      write('pubspec.yaml', 'name: x\n');
      write('analysis_options.yaml', 'dmetrics:\n  fail_on: sometimes\n');
      write('lib/a.dart', fn);
      final r = analyzePaths(['lib'], metrics: metrics, runRoot: tmp.path);
      expect(r.status, RunStatus.errors);
      expect(r.exitCode, 2);
      expect(
        r.report,
        isNull,
        reason: 'analysis does not run under a bad config',
      );
      expect(r.diagnostics.single.path, 'analysis_options.yaml');
      expect(r.diagnostics.single.line, 2);
      expect(
        r.diagnostics.single.message,
        contains('`fail_on` must be one of'),
      );
    });

    test('conflicting run-global knobs across roots: exit 2 unless --set', () {
      write('a/pubspec.yaml', 'name: a\n');
      write(
        'a/analysis_options.yaml',
        'dmetrics:\n  metrics:\n    cyclomatic: {count_case_arms: false}\n',
      );
      write('a/lib/x.dart', fn);
      write('b/pubspec.yaml', 'name: b\n');
      write(
        'b/analysis_options.yaml',
        'dmetrics:\n  metrics:\n    cyclomatic: {count_case_arms: true}\n',
      );
      write('b/lib/x.dart', fn);
      final r = analyzePaths(['a', 'b'], metrics: metrics, runRoot: tmp.path);
      expect(r.exitCode, 2);
      expect(
        r.diagnostics.single.message,
        contains('a/analysis_options.yaml says false'),
      );
      expect(
        r.diagnostics.single.message,
        contains('b/analysis_options.yaml says true'),
      );

      final fixed = analyzePaths(
        ['a', 'b'],
        metrics: metrics,
        runRoot: tmp.path,
        cli: const CliOverrides(set: {'cyclomatic.count_case_arms': 'true'}),
      );
      expect(fixed.exitCode, 0);
      expect(fixed.files.map((f) => f.path), ['a/lib/x.dart', 'b/lib/x.dart']);
    });
  });

  group('analyzePaths', () {
    test(
      'per-root thresholds yield per-file verdicts; explicit files count',
      () {
        write('a/pubspec.yaml', 'name: a\n');
        write(
          'a/analysis_options.yaml',
          'dmetrics:\n  metrics:\n    cyclomatic: {thresholds: {warn: 2, fail: 3}}\n',
        );
        write('a/lib/x.dart', fn);
        write('b/pubspec.yaml', 'name: b\n');
        write('b/lib/x.dart', fn);
        final r = analyzePaths(
          ['a', 'b/lib/x.dart'],
          metrics: metrics,
          runRoot: tmp.path,
        );
        expect(r.status, RunStatus.violations);
        expect(r.exitCode, 1);
        final byPath = {
          for (final f in r.files)
            f.path: f.scopes.single.results['cyclomatic']!,
        };
        expect(byPath['a/lib/x.dart']!.verdict, Verdict.fail);
        expect(byPath['b/lib/x.dart']!.verdict, Verdict.ok);
        expect(r.summary.verdicts, {
          Verdict.ok: 1,
          Verdict.warn: 0,
          Verdict.fail: 1,
        });
      },
    );

    test('an empty target set is exit 0 with zero files', () {
      write('pubspec.yaml', 'name: x\n');
      write('lib/only.g.dart', fn);
      final r = analyzePaths(['lib'], metrics: metrics, runRoot: tmp.path);
      expect(r.exitCode, 0);
      expect(r.summary.files, 0);
      expect(r.report, isNotNull);
    });

    test(
      'parse errors: exit 2 wins over violations, scopes still measured',
      () {
        write('pubspec.yaml', 'name: x\n');
        write(
          'analysis_options.yaml',
          'dmetrics:\n  metrics:\n    cyclomatic: {thresholds: {warn: 1, fail: 2}}\n',
        );
        write('lib/bad.dart', 'int f(int x) => x > 0 ? 1 : 0\n');
        final r = analyzePaths(['lib'], metrics: metrics, runRoot: tmp.path);
        expect(r.status, RunStatus.errors);
        expect(r.hasViolations, isTrue);
        expect(r.summary.filesWithErrors, 1);
        expect(r.files.single.scopes.single.scope.partial, isTrue);
      },
    );

    test('a missing target throws a usage error', () {
      expect(
        () => analyzePaths(['nope'], metrics: metrics, runRoot: tmp.path),
        throwsA(
          isA<UsageError>().having(
            (e) => e.message,
            'message',
            contains('nope'),
          ),
        ),
      );
    });
  });
}

bool _hasPubspecAbove(String dir) {
  for (var d = dir; ; d = p.dirname(d)) {
    if (File(p.join(d, 'pubspec.yaml')).existsSync()) return true;
    if (p.dirname(d) == d) return false;
  }
}
