import 'package:dmetrics/dmetrics.dart';
import 'package:test/test.dart';

/// The `deps` view over an in-memory package: the graph read back from the
/// coupling detail, cycles with their back edges, hubs with instability,
/// the directory fold and its back edges, and the two renderings.
void main() {
  SourceFile pkg(String path, String content) => SourceFile(
    path: path,
    content: content,
    configRoot: '.',
    packageUri: path.startsWith('lib/')
        ? Uri.parse('package:x/${path.substring(4)}')
        : null,
  );

  RunResult run(List<SourceFile> sources, {List<Metric>? metrics}) {
    final ms = metrics ?? [CouplingMetric()];
    const config = AnalysisConfig();
    return RunResult(
      metrics: ms,
      config: config,
      report: analyze(sources, ms, config),
    );
  }

  // engine/a → engine/b → config/c → engine/a is the cycle; engine/e also
  // imports config, so engine → config outweighs config → engine; the
  // barrel exports everything but e; util/d is a leaf; bin imports a and a
  // missing target.
  final sources = [
    pkg('lib/x.dart', '''
export 'src/engine/a.dart';
export 'src/engine/b.dart';
export 'src/config/c.dart';
export 'src/util/d.dart';
'''),
    pkg(
      'lib/src/engine/a.dart',
      "import 'b.dart';\nimport '../util/d.dart';\n",
    ),
    pkg('lib/src/engine/b.dart', "import '../config/c.dart';\n"),
    pkg('lib/src/config/c.dart', "import '../engine/a.dart';\n"),
    pkg('lib/src/engine/e.dart', "import '../config/c.dart';\n"),
    pkg('lib/src/util/d.dart', "import 'dart:async';\n"),
    pkg(
      'bin/main.dart',
      "import 'package:x/src/engine/a.dart';\nimport 'package:x/gone.dart';\n",
    ),
  ];
  final deps = computeDeps(run(sources));

  group('computeDeps', () {
    test('libraries, edges and targets outside the run', () {
      expect(deps.libraries.map((l) => l.path), [
        'bin/main.dart',
        'lib/src/config/c.dart',
        'lib/src/engine/a.dart',
        'lib/src/engine/b.dart',
        'lib/src/engine/e.dart',
        'lib/src/util/d.dart',
        'lib/x.dart',
      ]);
      expect(deps.imports, 7);
      expect(deps.exports, 4);
      expect(deps.outside, 1);
    });

    test('fan-out, fan-in over imports and exports, instability', () {
      final byPath = {for (final l in deps.libraries) l.path: l};
      final a = byPath['lib/src/engine/a.dart']!;
      expect(a.fanOut, 2);
      // c, bin and the barrel.
      expect(a.fanIn, 3);
      expect(a.instability, closeTo(0.4, 1e-9));
      expect(a.verdict, Verdict.ok);
      final barrel = byPath['lib/x.dart']!;
      expect(barrel.fanOut, 0);
      expect(barrel.exports, 4);
      expect(barrel.fanIn, 0);
      expect(barrel.instability, isNull);
      final bin = byPath['bin/main.dart']!;
      expect(bin.fanOut, 2, reason: 'the missing target still counts');
      expect(bin.instability, 1.0);
    });

    test('cycles list members and one back edge for a three-cycle', () {
      final c = deps.cycles.single;
      expect(c.members, [
        'package:x/src/config/c.dart',
        'package:x/src/engine/a.dart',
        'package:x/src/engine/b.dart',
      ]);
      expect(c.backEdges, hasLength(1));
      final byPath = {for (final l in deps.libraries) l.path: l};
      expect(byPath['lib/src/engine/a.dart']!.cycle, 0);
      expect(byPath['lib/src/util/d.dart']!.cycle, isNull);
    });

    test('directories fold imports only; the lighter direction is back', () {
      final g = deps.directories;
      expect(g.depth, 1);
      expect(g.order, ['bin', 'engine', 'config', 'lib', 'util']);
      expect(
        [
          for (final e in g.edges)
            '${e.from}→${e.to} ${e.count}${e.back ? ' back' : ''}',
        ],
        [
          'engine→config 2',
          'bin→engine 1',
          'config→engine 1 back',
          'engine→util 1',
        ],
      );
      expect(g.backEdges, 1);
      // A barrel's exports are not directory edges: `lib` has none.
      expect(g.edges.where((e) => e.from == 'lib'), isEmpty);
    });

    test('--depth keeps more levels', () {
      final g = computeDeps(run(sources), depth: 2).directories;
      expect(g.order, contains('engine'));
      expect(g.order.length, 5);
    });

    test('a run without coupling has no libraries', () {
      final d = computeDeps(run(sources, metrics: [CyclomaticMetric()]));
      expect(d.libraries, isEmpty);
      expect(d.files, 7);
    });
  });

  group('directoryOf', () {
    test('strips lib/src and keeps depth levels', () {
      expect(directoryOf('lib/src/engine/x.dart', depth: 1), 'engine');
      expect(directoryOf('lib/src/a/b/x.dart', depth: 1), 'a');
      expect(directoryOf('lib/src/a/b/x.dart', depth: 2), 'a/b');
      expect(directoryOf('lib/src/a/b/x.dart', depth: 9), 'a/b');
      expect(directoryOf('lib/src/x.dart', depth: 1), 'lib');
      expect(directoryOf('lib/x.dart', depth: 1), 'lib');
      expect(directoryOf('lib/a/x.dart', depth: 1), 'a');
    });

    test('keeps what precedes lib and folds paths without lib', () {
      expect(
        directoryOf('packages/foo/lib/src/a/x.dart', depth: 1),
        'packages/foo/a',
      );
      expect(
        directoryOf('packages/foo/lib/foo.dart', depth: 1),
        'packages/foo/lib',
      );
      expect(directoryOf('bin/x.dart', depth: 1), 'bin');
      expect(directoryOf('test/report/x.dart', depth: 1), 'test');
      expect(directoryOf('test/report/x.dart', depth: 2), 'test/report');
      expect(directoryOf('x.dart', depth: 1), '.');
    });
  });

  group('renderDepsConsole', () {
    test('sections, tables and markers', () {
      final out = renderDepsConsole(deps, top: 2);
      expect(
        out,
        startsWith(
          'Dependencies • 7 libraries • 11 edges (7 imports, 4 exports) • '
          '1 target outside the run\n'
          'Cycles • 1 component • largest 3 of 7 libraries (42.9%) • '
          '1 back edge\n'
          '  #1 • 3 libraries • 1 back edge\n'
          '    lib/src/engine/b.dart → lib/src/config/c.dart\n',
        ),
      );
      expect(out, contains('Fan-out • top 2 • I = instability'));
      expect(out, contains('    out    in     I  library\n'));
      expect(
        out,
        contains('      2     3  0.40  lib/src/engine/a.dart  cycle #1\n'),
      );
      expect(out, contains('      2     0  1.00  bin/main.dart\n'));
      expect(out, contains('Fan-in • top 2\n'));
      expect(
        out,
        endsWith(
          'Directories • depth 1 • 5 directories • 4 edges • 1 back edge\n'
          '  layering bin › engine › config › lib › util\n'
          '      2  engine → config\n'
          '      1  bin    → engine\n'
          '      1  config → engine  back\n'
          '      1  engine → util\n',
        ),
      );
    });

    test('colors the fan-out count by verdict and dims markers', () {
      final config = AnalysisConfig(
        roots: {
          '.': RootConfig(
            metrics: {
              'coupling': MetricConfig(threshold: Threshold(warn: 1, fail: 2)),
            },
          ),
        },
      );
      final metrics = [CouplingMetric()];
      final d = computeDeps(
        RunResult(
          metrics: metrics,
          config: config,
          report: analyze(sources, metrics, config),
        ),
      );
      final out = renderDepsConsole(d, palette: Palette.ansi);
      expect(out, contains('\x1B[1mDependencies\x1B[0m'));
      expect(
        out,
        contains('\x1B[31m    2\x1B[0m     3  0.40  lib/src/engine/a.dart'),
      );
      expect(out, contains('\x1B[33m    1\x1B[0m'));
      expect(out, contains('\x1B[2mback\x1B[0m'));
    });

    test('empty runs and runs without coupling say so', () {
      expect(renderDepsConsole(computeDeps(run([]))), 'No files analyzed.\n');
      expect(
        renderDepsConsole(
          computeDeps(run(sources, metrics: [CyclomaticMetric()])),
        ),
        'No dependency data: the coupling metric measured no library in this '
        'run.\n',
      );
      final noCycles = computeDeps(run(sources.sublist(1, 2)));
      expect(renderDepsConsole(noCycles), contains('Cycles • none\n'));
    });
  });

  group('jsonDeps', () {
    test('document shape', () {
      final json = jsonDeps(deps, status: RunStatus.ok);
      expect(json['schemaVersion'], depsSchemaVersion);
      expect(json['status'], 'ok');
      expect(json['summary'], {
        'files': 7,
        'filesWithErrors': 0,
        'libraries': 7,
        'edges': {'imports': 7, 'exports': 4},
        'outside': 1,
        'cycles': {'count': 1, 'largest': 3},
      });
      final libraries = json['libraries'] as List;
      expect(libraries, hasLength(7));
      expect(libraries[2], {
        'name': 'package:x/src/engine/a.dart',
        'path': 'lib/src/engine/a.dart',
        'fanOut': 2,
        'fanIn': 3,
        'exports': 0,
        'instability': 0.4,
        'cycle': 0,
        'verdict': 'ok',
      });
      final cycles = json['cycles'] as List;
      expect((cycles.single as Map)['members'], hasLength(3));
      expect((cycles.single as Map)['backEdges'], hasLength(1));
      final dirs = json['directories'] as Map;
      expect(dirs['depth'], 1);
      expect(dirs['order'], ['bin', 'engine', 'config', 'lib', 'util']);
      expect((dirs['edges'] as List)[2], {
        'from': 'config',
        'to': 'engine',
        'count': 1,
        'back': true,
      });
      expect(jsonDeps(deps, status: RunStatus.errors)['status'], 'errors');
    });
  });
}
