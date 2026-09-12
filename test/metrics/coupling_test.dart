import 'dart:io';

import 'package:dmetrics/dmetrics.dart';
import 'package:test/test.dart';

/// Whole-graph behavior of the coupling metric: what the single-file
/// fixtures cannot show. Edges between run sources, fan-in, cycles, parts
/// folded into their library, and the same number whether a file is
/// measured alone or with its package.
void main() {
  SourceFile pkg(String path, String content, {String package = 'x'}) =>
      SourceFile(
        path: path,
        content: content,
        configRoot: '.',
        packageUri: path.startsWith('lib/')
            ? Uri.parse('package:$package/${path.substring(4)}')
            : null,
      );

  Map<String, MetricResult> couplingOf(Report report) => {
    for (final f in report.files)
      for (final s in f.scopes)
        if (s.scope.kind == ScopeKind.library)
          s.scope.qualifiedName: s.results[CouplingMetric.metricId]!,
  };

  Report run(List<SourceFile> sources, [AnalysisConfig? config]) =>
      analyze(sources, [CouplingMetric()], config ?? const AnalysisConfig());

  group('over a package', () {
    final a = pkg('lib/a.dart', '''
import 'b.dart';
import 'package:x/c.dart';
import 'package:x/c.dart' show C;
import 'm.dart';
export 'src/e.dart';
export 'b.dart';
import 'package:meta/meta.dart';
import 'dart:async';

void f() {}
''');
    final b = pkg('lib/b.dart', "import 'c.dart';\n");
    final c = pkg(
      'lib/c.dart',
      "import 'a.dart';\nimport 'package:y/y.dart';\n",
    );
    final d = pkg(
      'lib/d.dart',
      "import 'package:collection/collection.dart';\n",
    );
    final report = run([a, b, c, d]);
    final results = couplingOf(report);

    test('counts distinct imported libraries of the run package', () {
      expect(results['package:x/a.dart']!.value, 3);
      expect(results['package:x/a.dart']!.measurement.contributorSummary, {
        'import': 3,
      });
      expect(results['package:x/a.dart']!.measurement.tableShape, isNull);
      expect(results['package:x/b.dart']!.value, 1);
      expect(results['package:x/c.dart']!.value, 1);
      expect(results['package:x/d.dart']!.value, 0);
    });

    test(
      'detail: dependencies, missing, exports, external, dependents, cycle',
      () {
        expect(results['package:x/a.dart']!.measurement.detail, {
          'dependencies': [
            'package:x/b.dart',
            'package:x/c.dart',
            'package:x/m.dart',
          ],
          'missing': ['package:x/m.dart'],
          'exports': ['package:x/src/e.dart'],
          'external': ['package:meta/meta.dart'],
          'dependents': ['package:x/c.dart'],
          'cycle': ['package:x/a.dart', 'package:x/b.dart', 'package:x/c.dart'],
        });
        expect(results['package:x/c.dart']!.measurement.detail, {
          'dependencies': ['package:x/a.dart'],
          'missing': <String>[],
          'exports': <String>[],
          'external': ['package:y/y.dart'],
          'dependents': ['package:x/a.dart', 'package:x/b.dart'],
          'cycle': ['package:x/a.dart', 'package:x/b.dart', 'package:x/c.dart'],
        });
        final dDetail = results['package:x/d.dart']!.measurement.detail as Map;
        expect(dDetail, isNot(contains('cycle')));
        expect(dDetail['dependents'], isEmpty);
      },
    );

    test('a file measured alone scores the same as in its package', () {
      final alone = couplingOf(run([a]))['package:x/a.dart']!;
      expect(alone.value, 3);
      expect(alone.measurement.contributorSummary, {'import': 3});
      final detail = alone.measurement.detail as Map;
      expect(detail['dependencies'], [
        'package:x/b.dart',
        'package:x/c.dart',
        'package:x/m.dart',
      ]);
      expect(detail['missing'], detail['dependencies']);
      expect(detail['exports'], ['package:x/src/e.dart']);
      expect(detail['dependents'], isEmpty);
      expect(detail, isNot(contains('cycle')));
    });

    test('a cycle through an export, and a library outside it', () {
      final r = couplingOf(
        run([
          pkg('lib/p.dart', "export 'q.dart';\n"),
          pkg('lib/q.dart', "import 'p.dart';\n"),
          pkg('lib/r.dart', "import 'p.dart';\n"),
        ]),
      );
      final cycle = ['package:x/p.dart', 'package:x/q.dart'];
      final p = r['package:x/p.dart']!;
      expect(p.value, 0);
      expect((p.measurement.detail as Map)['cycle'], cycle);
      expect((p.measurement.detail as Map)['dependents'], [
        'package:x/q.dart',
        'package:x/r.dart',
      ]);
      expect(
        (r['package:x/q.dart']!.measurement.detail as Map)['cycle'],
        cycle,
      );
      expect(
        r['package:x/r.dart']!.measurement.detail as Map,
        isNot(contains('cycle')),
      );
    });

    test('a long chain with no cycle has no cycle', () {
      final n = 3000;
      final r = couplingOf(
        run([
          for (var i = 0; i < n; i++)
            pkg('lib/l$i.dart', i + 1 < n ? "import 'l${i + 1}.dart';\n" : ''),
        ]),
      );
      expect(r.length, n);
      expect(r.values.every((v) => v.measurement.detail is Map), isTrue);
      expect(
        r.values.any((v) => (v.measurement.detail as Map).containsKey('cycle')),
        isFalse,
      );
    });
  });

  group('parts', () {
    final results = couplingOf(
      run([
        pkg('lib/lib.dart', '''
import 'b.dart';
part 'p.dart';
part 'gen.g.dart';
'''),
        pkg('lib/p.dart', '''
part of 'lib.dart';
import 'b.dart';
import 'q.dart';
part 'pp.dart';
'''),
        pkg('lib/pp.dart', "part of 'p.dart';\nimport 'r.dart';\n"),
        pkg('lib/b.dart', ''),
        pkg('lib/q.dart', ''),
        pkg('lib/r.dart', ''),
      ]),
    );

    test('a part opens no library scope', () {
      expect(results.keys, isNot(contains('package:x/p.dart')));
      expect(results.keys, isNot(contains('package:x/pp.dart')));
    });

    test('directives of parts, and parts of parts, fold into the library', () {
      final lib = results['package:x/lib.dart']!;
      expect(lib.value, 3);
      expect(lib.measurement.contributorSummary, {'import': 1, 'part': 2});
      final part = lib.measurement.contributors.where((c) => c.kind == 'part');
      expect(part.map((c) => c.span.text).toSet(), {"part 'p.dart';"});
      expect((lib.measurement.detail as Map)['dependencies'], [
        'package:x/b.dart',
        'package:x/q.dart',
        'package:x/r.dart',
      ]);
    });

    test('fan-in through a part names the library', () {
      expect(
        (results['package:x/q.dart']!.measurement.detail as Map)['dependents'],
        ['package:x/lib.dart'],
      );
    });
  });

  group('library scope placement', () {
    test('starts at the first token, after leading comments', () {
      const source = '''
// Copyright.

/// Doc.
library;

import 'a.dart';
''';
      final report = run([pkg('lib/a.dart', source)]);
      final lib = report.files.single.scopes.single.scope;
      expect(lib.span.start.offset, source.indexOf('library;'));
      expect(lib.span.end.offset, source.length);
    });

    test('an ignore on the line before the first directive suppresses', () {
      final report = run([
        pkg('lib/a.dart', '''
// ignore: dmetrics_coupling
import 'b.dart';
'''),
      ]);
      final r = report.files.single.scopes.single.results['coupling']!;
      expect(r.suppressed?.kind, SuppressionKind.ignore);
    });
  });

  group('reporters', () {
    final sources = [
      pkg('lib/a.dart', "import 'b.dart';\nimport 'c.dart';\n"),
      pkg('lib/b.dart', "import 'a.dart';\n"),
      pkg('lib/c.dart', ''),
    ];
    const config = AnalysisConfig(
      roots: {
        '.': RootConfig(
          metrics: {
            CouplingMetric.metricId: MetricConfig(
              threshold: Threshold(warn: 1, fail: 2),
            ),
          },
        ),
      },
    );
    final metrics = [CouplingMetric()];
    final result = RunResult(
      metrics: metrics,
      config: config,
      report: analyze(sources, metrics, config),
    );

    test('the console line ends with the cycle note', () {
      final out = renderConsole(result);
      expect(
        out,
        contains(
          'lib/a.dart:1:1 • fail • library package:x/a.dart • coupling 2 '
          '[warn ≥ 1, fail ≥ 2] • import ×2 • cycle of 2\n',
        ),
      );
      expect(
        out,
        contains(
          'lib/b.dart:1:1 • warn • library package:x/b.dart • coupling 1 '
          '[warn ≥ 1, fail ≥ 2] • import ×1 • cycle of 2\n',
        ),
      );
      expect(renderConsole(result, all: true), contains('coupling 0 [warn'));
    });

    test('the JSON detail carries the graph', () {
      final json = jsonReport(result);
      final a = ((json['files'] as List).first['scopes'] as List).first as Map;
      expect(a['kind'], 'library');
      final r = (a['results'] as Map)['coupling'] as Map;
      expect(r['value'], 2);
      expect(r['detail'], {
        'dependencies': ['package:x/b.dart', 'package:x/c.dart'],
        'missing': <String>[],
        'exports': <String>[],
        'external': <String>[],
        'dependents': ['package:x/b.dart'],
        'cycle': ['package:x/a.dart', 'package:x/b.dart'],
      });
    });
  });

  group('acceptance: the shipped metrics run unmodified beside coupling', () {
    final fixtures = [
      for (final e in Directory('test/fixtures').listSync(recursive: true))
        if (e is File && e.path.endsWith('.dart')) e,
    ]..sort((a, b) => a.path.compareTo(b.path));

    test('${fixtures.length} fixtures give identical results', () {
      final sources = [
        for (final f in fixtures)
          SourceFile(
            path: f.path,
            content: f.readAsStringSync(),
            configRoot: '.',
            packageUri: Uri.parse('package:fixtures/${f.path}'),
          ),
      ];
      List<Metric> shipped() => [CyclomaticMetric(), CognitiveMetric()];
      List<String> rows(Report r) => [
        for (final f in r.files)
          for (final s in f.scopes)
            if (s.scope.kind != ScopeKind.library)
              for (final e in s.results.entries)
                '${s.scope.id}|${s.scope.qualifiedName}|${s.scope.fingerprint}|'
                    '${e.key}=${e.value.value}/${e.value.verdict.name}|'
                    '${e.value.measurement.contributorSummary}',
      ];
      const config = AnalysisConfig();
      final alone = rows(analyze(sources, shipped(), config));
      final beside = rows(
        analyze(sources, [...shipped(), CouplingMetric()], config),
      );
      expect(beside, alone);
      expect(alone.length, greaterThan(100));
    });
  });
}
