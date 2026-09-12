import 'package:dmetrics/dmetrics.dart';
import 'package:test/test.dart';

void main() {
  final metrics = [CyclomaticMetric().spec];
  LoadedConfig? load(String yaml, {String source = 'analysis_options.yaml'}) =>
      parseDmetricsConfig(yaml, source: source, metrics: metrics);

  group('parseDmetricsConfig', () {
    test('thresholds: none opts out of the built-in default', () {
      final c = load(
        'dmetrics:\n  metrics:\n    cyclomatic: {thresholds: none}\n',
      )!;
      expect(c.problems, isEmpty);
      expect(c.root.metrics['cyclomatic']!.threshold, Threshold.none);
    });

    test('no dmetrics section: not a config root', () {
      expect(load('linter:\n  rules: [x]\n'), isNull);
      expect(load(''), isNull);
      expect(load('# only a comment\n'), isNull);
    });

    test('empty section: a root with defaults', () {
      final c = load('dmetrics:\n')!;
      expect(c.problems, isEmpty);
      expect(c.runValues, isEmpty);
      expect(c.root.source, 'analysis_options.yaml');
      expect(c.root.metrics, isEmpty);
      expect(c.root.exclude, RootConfig.defaultExclude);
    });

    test('the full shape', () {
      final c = load('''
dmetrics:
  fail_on: warn
  closure_rollup: include_in_parent
  include: ['lib/**', 'bin/**']
  exclude: ['**.g.dart']
  metrics:
    cyclomatic:
      enabled: true
      thresholds: {warn: 8, fail: 12}
      count_case_arms: false
  overrides:
    - paths: ['lib/src/generated/**']
      metrics:
        cyclomatic:
          enabled: false
    - paths: ['lib/src/parser/**']
      metrics:
        cyclomatic:
          thresholds: {warn: 15, fail: 25}
''')!;
      expect(c.problems, isEmpty);
      expect(c.runValues, {
        'fail_on': FailOn.warn,
        'closure_rollup': ClosureRollup.includeInParent,
        'cyclomatic.count_case_arms': false,
      });
      expect(c.root.include, ['lib/**', 'bin/**']);
      expect(c.root.exclude, ['**.g.dart']);
      expect(c.root.metrics['cyclomatic']!.enabled, isTrue);
      expect(
        c.root.metrics['cyclomatic']!.threshold,
        const Threshold(warn: 8, fail: 12),
      );
      expect(c.root.overrides, hasLength(2));

      // Effective config per path: last matching override wins.
      final root = c.root;
      expect(
        root.metric('cyclomatic', relativePath: 'lib/a.dart').threshold,
        const Threshold(warn: 8, fail: 12),
      );
      expect(
        root
            .metric('cyclomatic', relativePath: 'lib/src/generated/x.dart')
            .isEnabled,
        isFalse,
      );
      expect(
        root
            .metric('cyclomatic', relativePath: 'lib/src/parser/x.dart')
            .threshold,
        const Threshold(warn: 15, fail: 25),
      );
      // Discovery selection.
      expect(root.selects('lib/a.dart'), isTrue);
      expect(root.selects('lib/a.g.dart'), isFalse);
      expect(root.selects('test/a.dart'), isFalse);
    });

    test('invalid YAML is a problem with a position', () {
      final c = load('dmetrics:\n  metrics: [\n')!;
      expect(c.problems, hasLength(1));
      expect(c.problems.single.message, contains('invalid YAML'));
      expect(c.problems.single.source, 'analysis_options.yaml');
      expect(c.problems.single.line, isNotNull);
    });

    test('problems: unknown keys, metrics, settings, bad values', () {
      final c = load('''
dmetrics:
  fail_on: maybe
  closure_rollup: nope
  bogus: 1
  include: 'lib/**'
  metrics:
    cognitive: {}
    cyclomatic:
      enabled: yes please
      thresholds: {warn: 12, fail: 8}
      count_case_arms: 3
      no_such_knob: true
''')!;
      final messages = c.problems.map((p) => p.message).toList();
      expect(messages, [
        contains('`fail_on` must be one of warn, fail'),
        contains('`closure_rollup` must be one of separate, include_in_parent'),
        contains('unknown key `bogus`'),
        contains('`include` must be a list'),
        contains('unknown metric `cognitive`'),
        contains('`enabled` must be true or false'),
        contains(
          '`thresholds` must be `{warn: n, fail: m}` with n <= m, or `none`',
        ),
        contains('`count_case_arms` must be a boolean'),
        contains('unknown setting `no_such_knob`'),
      ]);
      for (final p in c.problems) {
        expect(p.line, isNotNull, reason: p.message);
        expect(p.column, isNotNull, reason: p.message);
      }
    });

    test('a run-global key inside overrides is a config error', () {
      final c = load('''
dmetrics:
  overrides:
    - paths: ['test/**']
      metrics:
        cyclomatic:
          count_case_arms: false
    - paths: ['x/**']
      fail_on: warn
      metrics: {}
    - metrics: {}
''')!;
      final messages = c.problems.map((p) => p.message).toList();
      expect(messages, [
        contains(
          '`count_case_arms` is run-global and cannot be set in `overrides`',
        ),
        contains('`fail_on` is not allowed in `overrides`'),
        contains('missing `paths`'),
      ]);
      expect(c.runValues, isEmpty);
    });
  });

  group('resolveRun', () {
    LoadedConfig root(String source, String yaml) =>
        load(yaml, source: source)!;

    test('defaults with no config roots', () {
      final r = resolveRun(roots: {'.': null}, metrics: metrics);
      expect(r.problems, isEmpty);
      expect(r.config.run.closureRollup, ClosureRollup.separate);
      expect(r.config.run.failOn, FailOn.fail);
      expect(r.config.run.settings, {
        'cyclomatic.count_null_coalescing': true,
        'cyclomatic.count_case_arms': true,
      });
      expect(r.config.roots.keys, ['.']);
    });

    test('run-global values from a root apply run-wide', () {
      final r = resolveRun(
        roots: {
          'a': root('a/analysis_options.yaml', '''
dmetrics:
  fail_on: warn
  metrics:
    cyclomatic: {count_null_coalescing: false}
'''),
          'b': null,
        },
        metrics: metrics,
      );
      expect(r.problems, isEmpty);
      expect(r.config.run.failOn, FailOn.warn);
      expect(r.config.run.settings['cyclomatic.count_null_coalescing'], false);
      expect(r.config.run.settings['cyclomatic.count_case_arms'], true);
      expect(r.config.roots['a']!.source, 'a/analysis_options.yaml');
      expect(r.config.roots['b']!.source, isNull);
    });

    test(
      'two roots disagreeing on a run-global key is an error naming both',
      () {
        final roots = {
          'a': root('a/analysis_options.yaml', 'dmetrics:\n  fail_on: warn\n'),
          'b': root('b/analysis_options.yaml', 'dmetrics:\n  fail_on: fail\n'),
          'c': root('c/analysis_options.yaml', 'dmetrics:\n  fail_on: warn\n'),
        };
        final r = resolveRun(roots: roots, metrics: metrics);
        expect(r.problems, hasLength(1));
        final m = r.problems.single.message;
        expect(m, contains('`fail_on` differs between config roots'));
        expect(
          m,
          contains(
            'a/analysis_options.yaml, c/analysis_options.yaml says warn',
          ),
        );
        expect(m, contains('b/analysis_options.yaml says fail'));
        expect(m, contains('--set fail_on='));

        // --set fixes it for the whole run.
        final fixed = resolveRun(
          roots: roots,
          metrics: metrics,
          cli: const CliOverrides(set: {'fail_on': 'warn'}),
        );
        expect(fixed.problems, isEmpty);
        expect(fixed.config.run.failOn, FailOn.warn);
      },
    );

    test('--set: knobs, enums, unknown keys, bad values', () {
      final r = resolveRun(
        roots: {'.': null},
        metrics: metrics,
        cli: const CliOverrides(
          set: {
            'cyclomatic.count_case_arms': 'false',
            'closure_rollup': 'include_in_parent',
          },
        ),
      );
      expect(r.problems, isEmpty);
      expect(r.config.run.settings['cyclomatic.count_case_arms'], false);
      expect(r.config.run.closureRollup, ClosureRollup.includeInParent);

      final bad = resolveRun(
        roots: {'.': null},
        metrics: metrics,
        cli: const CliOverrides(
          set: {
            'cyclomatic.count_case_arms': 'maybe',
            'closure_rollup': 'nested',
            'nope': '1',
          },
        ),
      );
      expect(bad.problems.map((p) => p.message), [
        contains('invalid value `maybe` for `cyclomatic.count_case_arms`'),
        contains('invalid value `nested` for `closure_rollup`'),
        contains('unknown run-global key `nope`'),
      ]);
    });

    test('--threshold is forced into every root above overrides', () {
      final r = resolveRun(
        roots: {
          'a': root('a/analysis_options.yaml', '''
dmetrics:
  metrics:
    cyclomatic: {thresholds: {warn: 1, fail: 2}}
  overrides:
    - paths: ['**']
      metrics:
        cyclomatic: {thresholds: {warn: 3, fail: 4}}
'''),
          'b': null,
        },
        metrics: metrics,
        cli: const CliOverrides(
          thresholds: {'cyclomatic': Threshold(warn: 8, fail: 12)},
        ),
      );
      for (final root in r.config.roots.values) {
        expect(
          root.metric('cyclomatic', relativePath: 'x.dart').threshold,
          const Threshold(warn: 8, fail: 12),
        );
      }
    });
  });

  test('pathRelativeToRoot', () {
    expect(pathRelativeToRoot('lib/a.dart', '.'), 'lib/a.dart');
    expect(pathRelativeToRoot('pkg/lib/a.dart', 'pkg'), 'lib/a.dart');
    expect(pathRelativeToRoot('pkg/lib/a.dart', 'pkg/'), 'lib/a.dart');
    expect(pathRelativeToRoot('other/a.dart', 'pkg'), 'other/a.dart');
  });
}
