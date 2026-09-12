import 'dart:io';

import 'package:dmetrics/dmetrics.dart';
import 'package:test/test.dart';

import 'import_count_metric.dart';
import 'recording_metric.dart';

/// The engine seam for dependency metrics: pipeline selection by
/// requirement level, the `library` scope, directive resolution, and finish
/// measurements that replace a scope's traversal measurement.
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

  group('pipeline selection', () {
    test('a syntactic run never builds the library index', () {
      final m = RecordingMetric();
      analyze([src('void f() {}')], [m], const AnalysisConfig());
      expect(m.runContext, isNotNull);
      expect(m.runContext!.libraries, isNull);
    });

    test('one directive metric lifts the whole run to the directive level', () {
      final syntactic = RecordingMetric();
      final directive = RecordingMetric(
        id: 'directive',
        requirements: MetricRequirements.directive,
      );
      analyze(
        [src('void f() {}')],
        [syntactic, directive],
        const AnalysisConfig(),
      );
      expect(syntactic.runContext!.libraries, isNotNull);
      expect(identical(syntactic.runContext, directive.runContext), isTrue);
    });

    test('the resolved level is refused, naming the metric', () {
      final m = RecordingMetric(
        id: 'needs_elements',
        requirements: MetricRequirements.resolved,
      );
      expect(
        () => analyze([src('void f() {}')], [m], const AnalysisConfig()),
        throwsA(
          isA<UnsupportedError>().having(
            (e) => e.message,
            'message',
            contains('needs_elements'),
          ),
        ),
      );
    });
  });

  group('library scope', () {
    const source = '''
import 'dart:async';
import 'b.dart';

final onTap = () { if (a) b(); };

class C {
  void m() {}
}
''';

    test('brackets the unit, under the file context, only when measured', () {
      final m = RecordingMetric(
        measures: {ScopeKind.library, ScopeKind.method},
        nodeTypes: {'CompilationUnit', 'ImportDirective', 'ClassDeclaration'},
      );
      analyze([pkg('lib/a.dart', source)], [m], const AnalysisConfig());
      expect(m.events, [
        'enterNode CompilationUnit ctx=lib/a.dart',
        'enterScope package:x/a.dart',
        'enterNode ImportDirective ctx=package:x/a.dart',
        'exitNode ImportDirective ctx=package:x/a.dart',
        'enterNode ImportDirective ctx=package:x/a.dart',
        'exitNode ImportDirective ctx=package:x/a.dart',
        'enterNode ClassDeclaration ctx=package:x/a.dart',
        'enterScope C.m',
        'exitScope C.m',
        'exitNode ClassDeclaration ctx=package:x/a.dart',
        'exitScope package:x/a.dart',
        'exitNode CompilationUnit ctx=lib/a.dart',
      ]);
      final lib = m.scopes.first;
      expect(lib.kind, ScopeKind.library);
      expect(lib.id.value, 'lib/a.dart::library');
      expect(lib.name, 'package:x/a.dart');
      expect(lib.parent!.kind, ScopeKind.file);
      expect(lib.span.start.offset, 0);
      expect(lib.span.end.offset, source.length);
      expect(m.scopes.last.parent!.parent, same(lib));
    });

    test('a file outside lib/ is named by its path', () {
      final m = RecordingMetric(measures: {ScopeKind.library});
      analyze(
        [src('void f() {}', path: 'bin/t.dart')],
        [m],
        const AnalysisConfig(),
      );
      expect(m.scopes.single.qualifiedName, 'bin/t.dart');
    });

    test('a part opens no library scope', () {
      final m = RecordingMetric(measures: {ScopeKind.library});
      analyze(
        [
          pkg('lib/a.dart', "part 'p.dart';\nvoid f() {}\n"),
          pkg('lib/p.dart', "part of 'a.dart';\nvoid g() {}\n"),
        ],
        [m],
        const AnalysisConfig(),
      );
      expect(m.scopes.map((s) => s.qualifiedName), ['package:x/a.dart']);
    });

    test('no metric measuring it means no library scope in the report', () {
      final m = RecordingMetric();
      final report = analyze(
        [pkg('lib/a.dart', source)],
        [m],
        const AnalysisConfig(),
      );
      expect(
        report.files.single.scopes.map((s) => s.scope.kind),
        isNot(contains(ScopeKind.library)),
      );
    });

    test('ids, names and values of other metrics do not change', () {
      List<Metric> cyclomatic() => [CyclomaticMetric(), CognitiveMetric()];
      List<String> rows(Report r) => [
        for (final f in r.files)
          for (final s in f.scopes)
            if (s.scope.kind != ScopeKind.library)
              for (final e in s.results.entries)
                '${s.scope.id} ${s.scope.qualifiedName} ${s.scope.kind.name} '
                    '${e.key}=${e.value.value} ${e.value.measurement.contributorSummary}',
      ];
      final sources = [
        pkg('lib/a.dart', source),
        pkg('lib/b.dart', 'int x = 1;'),
      ];
      final alone = analyze(sources, cyclomatic(), const AnalysisConfig());
      final withLibrary = analyze(sources, [
        ...cyclomatic(),
        RecordingMetric(measures: {ScopeKind.library}),
      ], const AnalysisConfig());
      expect(rows(withLibrary), rows(alone));
      expect(
        rows(alone),
        contains(startsWith('lib/a.dart::closure#1 onTap.<closure#1> closure')),
      );
    });
  });

  group('LibraryIndex', () {
    final index = LibraryIndex([
      pkg('lib/a.dart', ''),
      pkg('lib/src/b.dart', ''),
      pkg('lib/y.dart', '', package: 'y'),
      src('', path: 'bin/t.dart'),
      src('', path: 'test/t_test.dart'),
    ]);

    test('package URIs resolve to run sources by identity', () {
      final r = index.resolve('package:x/src/b.dart', from: 'package:x/a.dart');
      expect(r.kind, LibraryRefKind.source);
      expect(r.target, 'package:x/src/b.dart');
      expect(r.source!.path, 'lib/src/b.dart');
    });

    test('relative URIs under lib/ resolve through the package URI', () {
      expect(
        index.resolve('../a.dart', from: 'package:x/src/b.dart').target,
        'package:x/a.dart',
      );
      expect(
        index.resolve('src/b.dart', from: 'package:x/a.dart').kind,
        LibraryRefKind.source,
      );
    });

    test('relative URIs outside lib/ resolve by path', () {
      final r = index.resolve('../test/t_test.dart', from: 'bin/t.dart');
      expect(r.kind, LibraryRefKind.source);
      expect(r.target, 'test/t_test.dart');
      expect(
        index.resolve('other.dart', from: 'bin/t.dart').kind,
        LibraryRefKind.missing,
      );
    });

    test('a run package without that file is missing; others are external', () {
      expect(
        index.resolve('package:x/gen.g.dart', from: 'package:x/a.dart').kind,
        LibraryRefKind.missing,
      );
      expect(
        index.resolve('package:y/y.dart', from: 'package:x/a.dart').kind,
        LibraryRefKind.source,
      );
      expect(
        index.resolve('package:meta/meta.dart', from: 'package:x/a.dart').kind,
        LibraryRefKind.external,
      );
    });

    test('dart:, malformed and foreign schemes', () {
      expect(
        index.resolve('dart:async', from: 'package:x/a.dart').kind,
        LibraryRefKind.sdk,
      );
      expect(
        index.resolve('package:', from: 'package:x/a.dart').kind,
        LibraryRefKind.invalid,
      );
      expect(
        index.resolve('http://x/y.dart', from: 'package:x/a.dart').kind,
        LibraryRefKind.invalid,
      );
      expect(
        index.resolve(':::', from: 'package:x/a.dart').kind,
        LibraryRefKind.invalid,
      );
    });

    test('an unknown origin is a programming error', () {
      expect(
        () => index.resolve('a.dart', from: 'lib/nope.dart'),
        throwsArgumentError,
      );
    });
  });

  group('a directive metric end to end', () {
    final sources = [
      pkg('lib/a.dart', '''
import 'b.dart';
import 'package:x/c.dart';
export 'src/e.dart';

void f() {}
'''),
      pkg('lib/b.dart', "import 'c.dart';\n"),
      pkg('lib/c.dart', '''
import 'dart:async';
import 'package:meta/meta.dart';
import 'gen.g.dart';
'''),
    ];
    const config = AnalysisConfig(
      roots: {
        '.': RootConfig(
          metrics: {
            ImportCountMetric.metricId: MetricConfig(
              threshold: Threshold(warn: 2, fail: 3),
            ),
          },
        ),
      },
    );
    final metrics = [CyclomaticMetric(), ImportCountMetric()];
    final report = analyze(sources, metrics, config);
    final result = RunResult(metrics: metrics, config: config, report: report);

    Map<String, MetricResult> imports() => {
      for (final f in report.files)
        for (final s in f.scopes)
          s.scope.qualifiedName: ?s.results[ImportCountMetric.metricId],
    };

    test('every library has a measurement, finalized from finish', () {
      final r = imports();
      expect(r.keys, [
        'package:x/a.dart',
        'package:x/b.dart',
        'package:x/c.dart',
      ]);
      expect(r['package:x/a.dart']!.value, 3);
      expect(r['package:x/a.dart']!.measurement.detail, {
        'imports': ['package:x/b.dart', 'package:x/c.dart'],
        'external': <String>[],
        'missing': ['package:x/src/e.dart'],
        'importedBy': <String>[],
      });
      expect(r['package:x/c.dart']!.measurement.detail, {
        'imports': <String>[],
        'external': ['package:meta/meta.dart'],
        'missing': ['package:x/gen.g.dart'],
        'importedBy': ['package:x/a.dart', 'package:x/b.dart'],
      });
      expect(report.runMeasurements, isEmpty);
    });

    test('a library result carries thresholds, verdict and contributors', () {
      final a = imports()['package:x/a.dart']!;
      expect(a.verdict, Verdict.fail);
      expect(a.threshold, const Threshold(warn: 2, fail: 3));
      expect(a.measurement.contributorSummary, {'import': 2, 'export': 1});
      expect(imports()['package:x/b.dart']!.verdict, Verdict.ok);
      expect(result.status, RunStatus.violations);
      expect(result.summary.scopes, 4);
    });

    test('the console renders it with the generic line', () {
      final out = renderConsole(result);
      expect(
        out,
        contains(
          'lib/a.dart:1:1 • fail • library package:x/a.dart • imports 3 '
          '[warn ≥ 2, fail ≥ 3] • import ×2, export ×1',
        ),
      );
      expect(out, contains('4 scopes in 3 files • 1 fail, 1 warn, 2 ok'));
    });

    test('the JSON report carries kind, detail and parent links', () {
      final json = jsonReport(result);
      final scopes = (json['files'] as List).first['scopes'] as List;
      final library = scopes.first as Map;
      expect(library['kind'], 'library');
      expect(library['name'], 'package:x/a.dart');
      expect(library['parent'], isNull);
      final detail = (library['results'] as Map)['imports']['detail'] as Map;
      expect(detail['importedBy'], isEmpty);
      final f = scopes[1] as Map;
      expect(f['qualifiedName'], 'f');
      expect(f['parent'], 'lib/a.dart::library');
      expect((f['results'] as Map).keys, ['cyclomatic']);
    });

    test('an ignore_for_file suppresses the library like any scope', () {
      final r = analyze(
        [
          pkg(
            'lib/a.dart',
            "// ignore_for_file: dmetrics_imports\nimport 'b.dart';\nimport 'c.dart';\nimport 'd.dart';\n",
          ),
        ],
        [ImportCountMetric()],
        config,
      );
      final lib =
          r.files.single.scopes.single.results[ImportCountMetric.metricId]!;
      expect(lib.suppressed, isNotNull);
      expect(lib.verdict, Verdict.ok);
    });

    test('a finish measurement for another metric id is refused', () {
      final m = _Impostor();
      expect(
        () => analyze([src('void f() {}')], [m], const AnalysisConfig()),
        throwsArgumentError,
      );
    });

    test('a finish measurement for an untraversed scope is run-level', () {
      final m = _Stray();
      final r = analyze([src('void f() {}')], [m], const AnalysisConfig());
      expect(r.runMeasurements.single.scope.value, 'nowhere');
    });
  });

  group('acceptance: the shipped metrics run unmodified beside a directive metric', () {
    final fixtures = [
      for (final e in Directory('test/fixtures').listSync(recursive: true))
        if (e is File && e.path.endsWith('.dart')) e,
    ]..sort((a, b) => a.path.compareTo(b.path));

    test('${fixtures.length} fixtures give identical results', () {
      expect(fixtures, isNotEmpty);
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
        analyze(sources, [...shipped(), ImportCountMetric()], config),
      );
      expect(beside, alone);
      expect(alone.length, greaterThan(100));
    });
  });
}

/// Emits a finish measurement under another metric's id.
class _Impostor extends RecordingMetric {
  _Impostor() : super(id: 'impostor');

  @override
  Iterable<Measurement> finish(RunContext ctx) => [
    Measurement(
      metricId: 'cyclomatic',
      scope: scopes.first.id,
      value: 0,
      contributors: const [],
    ),
  ];
}

/// Emits a finish measurement for a scope no file produced.
class _Stray extends RecordingMetric {
  _Stray() : super(id: 'stray');

  @override
  Iterable<Measurement> finish(RunContext ctx) => [
    Measurement(
      metricId: id,
      scope: const ScopeId('nowhere'),
      value: 0,
      contributors: const [],
    ),
  ];
}
