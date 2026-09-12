/// `dmetrics deps`: the dependency graph of a run as a whole, derived from
/// the `coupling` results of a finished [RunResult] and nothing else. Per
/// library `analyze` says "13 dependencies" and lists them; this view says
/// what the run's libraries form together: how many edges, which cycles
/// exist and which imports hold each one together, which libraries are hubs
/// by fan-out and fan-in, and how the package's directories depend on each
/// other, with the edges against the dominant direction marked.
///
/// The graph is read from every library scope's coupling `detail`
/// (`dependencies` and `exports` name the targets), never from the metric's
/// internals, so a report loaded from JSON could feed the same view. The
/// picture is complete only when the whole package is in the run: a target
/// outside the run has no scope and so no edges of its own, and fan-in
/// counts only libraries that were measured.
///
/// Cycle membership is not a verdict. Most libraries of a mature package sit
/// in one strongly connected component, so a member list says little; what
/// the view names instead is the component's back edges, a small set of
/// imports whose removal would leave it acyclic.
library;

import 'dart:convert';

import '../config/threshold.dart';
import '../engine/graph.dart';
import '../engine/result.dart';
import '../engine/scope.dart';
import '../version.dart';
import 'ansi.dart';
import 'format.dart';
import 'run_result.dart';

const depsSchemaVersion = 1;

/// The metric whose `detail` carries the graph.
const _couplingId = 'coupling';

class DepsReport {
  final int files;
  final int filesWithErrors;
  final List<RunDiagnostic> diagnostics;

  /// The run's libraries with coupling data, sorted by name.
  final List<LibraryNode> libraries;

  /// Import edges over the whole run, targets outside the run included.
  final int imports;

  /// Export edges over the whole run.
  final int exports;

  /// Distinct targets of the run's packages that are not run sources.
  final int outside;

  /// Components of two or more libraries, largest first.
  final List<Cycle> cycles;
  final DirectoryGraph directories;

  const DepsReport({
    required this.files,
    required this.filesWithErrors,
    required this.diagnostics,
    required this.libraries,
    required this.imports,
    required this.exports,
    required this.outside,
    required this.cycles,
    required this.directories,
  });

  Map<String, String> get pathOf => {for (final l in libraries) l.name: l.path};
}

class LibraryNode {
  final String name;
  final String path;

  /// Libraries of the run's packages this one imports: the coupling value.
  final int fanOut;

  /// Run libraries that import or export this one.
  final int fanIn;

  /// Libraries this one re-exports.
  final int exports;

  /// Martin's `I = Ce / (Ca + Ce)` with `Ce` = [fanOut] and `Ca` = [fanIn]:
  /// 0 is depended upon and depends on nothing, 1 the reverse. Null when
  /// the library is isolated.
  final double? instability;

  /// Index into [DepsReport.cycles], null when the library is in none.
  final int? cycle;

  /// The coupling verdict, for the console to color the fan-out column.
  final Verdict verdict;

  const LibraryNode({
    required this.name,
    required this.path,
    required this.fanOut,
    required this.fanIn,
    required this.exports,
    required this.instability,
    required this.cycle,
    required this.verdict,
  });
}

/// A strongly connected component of two or more libraries over import and
/// export edges, the same graph the coupling metric's `cycle` detail
/// describes.
class Cycle {
  /// Sorted library names.
  final List<String> members;

  /// Edges against a [feedbackOrder] of the graph: remove them and the
  /// component falls apart into a hierarchy. Sorted by source, then target.
  final List<Edge> backEdges;

  const Cycle({required this.members, required this.backEdges});
}

class Edge {
  final String from;
  final String to;

  const Edge(this.from, this.to);
}

/// The library graph folded onto directories: the shape of the package.
/// Import edges only: a barrel's re-exports say what the package publishes,
/// not what its top level needs, and folded in they would make `lib` depend
/// on every directory it exports from.
class DirectoryGraph {
  /// Directory levels kept under `lib/src` (or `lib`).
  final int depth;

  /// Every directory a run library folds into, in [feedbackOrder]: the
  /// layering the edges mostly follow, dependents first.
  final List<String> order;

  /// Between distinct directories only; most edges first.
  final List<DirectoryEdge> edges;

  const DirectoryGraph({
    required this.depth,
    required this.order,
    required this.edges,
  });

  int get backEdges => edges.where((e) => e.back).length;
}

class DirectoryEdge {
  final String from;
  final String to;

  /// Library edges folded into this one.
  final int count;

  /// True when the edge goes against [DirectoryGraph.order]: the minority
  /// direction between two directories that depend on each other.
  final bool back;

  const DirectoryEdge({
    required this.from,
    required this.to,
    required this.count,
    required this.back,
  });
}

/// The directory a library's [path] folds into. `lib/src/` (or `lib/`) is
/// stripped and [depth] levels under it are kept, so `lib/src/engine/x.dart`
/// is `engine` and `lib/x.dart` is `lib`; whatever precedes `lib` stays, so
/// a monorepo's `packages/foo/lib/src/a/x.dart` is `packages/foo/a`. Paths
/// without a `lib` segment (`bin`, `test`) keep their first [depth] levels.
String directoryOf(String path, {required int depth}) {
  final dirs = path.split('/')..removeLast();
  final lib = dirs.indexOf('lib');
  if (lib < 0) return dirs.isEmpty ? '.' : dirs.take(depth).join('/');
  final prefix = dirs.sublist(0, lib);
  var rest = dirs.sublist(lib + 1);
  if (rest.isNotEmpty && rest.first == 'src') rest = rest.sublist(1);
  final kept = rest.isEmpty ? const ['lib'] : rest.take(depth);
  return [...prefix, ...kept].join('/');
}

DepsReport computeDeps(RunResult result, {int depth = 1}) {
  final summary = result.summary;
  final paths = <String, String>{};
  final results = <String, MetricResult>{};
  for (final f in result.files) {
    for (final s in f.scopes) {
      if (s.scope.kind != ScopeKind.library) continue;
      final r = s.results[_couplingId];
      if (r == null) continue;
      paths[s.scope.qualifiedName] = f.path;
      results[s.scope.qualifiedName] = r;
    }
  }
  final names = paths.keys.toList()..sort();
  final imports = {
    for (final n in names) n: _targets(results[n]!, 'dependencies'),
  };
  final exports = {for (final n in names) n: _targets(results[n]!, 'exports')};

  final fanIn = <String, int>{};
  final outside = <String>{};
  for (final n in names) {
    for (final t in imports[n]!.followedBy(exports[n]!)) {
      if (paths.containsKey(t)) {
        fanIn[t] = (fanIn[t] ?? 0) + 1;
      } else {
        outside.add(t);
      }
    }
  }

  List<String> inRun(Iterable<String> targets) => [
    for (final t in targets)
      if (paths.containsKey(t)) t,
  ];
  final edgesOf = {
    for (final n in names) n: inRun(imports[n]!.followedBy(exports[n]!)),
  };
  final cycles = _cycles(names, edgesOf);
  final cycleOf = <String, int>{};
  for (var i = 0; i < cycles.length; i++) {
    for (final m in cycles[i].members) {
      cycleOf[m] = i;
    }
  }

  return DepsReport(
    files: summary.files,
    filesWithErrors: summary.filesWithErrors,
    diagnostics: result.diagnostics,
    libraries: [
      for (final n in names)
        LibraryNode(
          name: n,
          path: paths[n]!,
          fanOut: imports[n]!.length,
          fanIn: fanIn[n] ?? 0,
          exports: exports[n]!.length,
          instability: _instability(
            fanOut: imports[n]!.length,
            fanIn: fanIn[n] ?? 0,
          ),
          cycle: cycleOf[n],
          verdict: results[n]!.verdict,
        ),
    ],
    imports: imports.values.fold(0, (sum, l) => sum + l.length),
    exports: exports.values.fold(0, (sum, l) => sum + l.length),
    outside: outside.length,
    cycles: cycles,
    directories: _directories(paths, {
      for (final n in names) n: inRun(imports[n]!),
    }, depth),
  );
}

/// The string list under [key] of the result's `detail`, empty when the
/// detail has no such list (another metric's shape, or none).
List<String> _targets(MetricResult r, String key) {
  final detail = r.measurement.detail;
  if (detail is! Map) return const [];
  final list = detail[key];
  if (list is! List) return const [];
  return [for (final t in list) t.toString()];
}

double? _instability({required int fanOut, required int fanIn}) =>
    fanOut + fanIn == 0 ? null : fanOut / (fanOut + fanIn);

/// Components of two or more, largest first, each with the back edges of
/// one feedback order over the whole graph (a back edge always joins two
/// members of the same component).
List<Cycle> _cycles(List<String> names, Map<String, List<String>> edgesOf) {
  final order = feedbackOrder(names, [
    for (final e in edgesOf.entries)
      for (final t in e.value) (e.key, t, 1),
  ]);
  final position = {for (var i = 0; i < order.length; i++) order[i]: i};
  final components = stronglyConnectedComponents(names, (n) => edgesOf[n]!);
  return [
    for (final c in components)
      if (c.length >= 2)
        Cycle(
          members: c..sort(),
          backEdges: [
            for (final from in c)
              for (final to in edgesOf[from]!)
                if (isBackEdge(position, from, to)) Edge(from, to),
          ]..sort(_bySourceThenTarget),
        ),
  ]..sort(_largestFirst);
}

DirectoryGraph _directories(
  Map<String, String> paths,
  Map<String, List<String>> importsOf,
  int depth,
) {
  final dirOf = {
    for (final e in paths.entries) e.key: directoryOf(e.value, depth: depth),
  };
  final counts = <(String, String), int>{};
  for (final e in importsOf.entries) {
    for (final t in e.value) {
      final edge = (dirOf[e.key]!, dirOf[t]!);
      if (edge.$1 == edge.$2) continue;
      counts[edge] = (counts[edge] ?? 0) + 1;
    }
  }
  final order = feedbackOrder(dirOf.values.toSet(), [
    for (final e in counts.entries) (e.key.$1, e.key.$2, e.value),
  ]);
  final position = {for (var i = 0; i < order.length; i++) order[i]: i};
  final edges = [
    for (final e in counts.entries)
      DirectoryEdge(
        from: e.key.$1,
        to: e.key.$2,
        count: e.value,
        back: isBackEdge(position, e.key.$1, e.key.$2),
      ),
  ]..sort(_mostFirst);
  return DirectoryGraph(depth: depth, order: order, edges: edges);
}

int _largestFirst(Cycle a, Cycle b) {
  final bySize = b.members.length.compareTo(a.members.length);
  return bySize != 0 ? bySize : a.members.first.compareTo(b.members.first);
}

int _bySourceThenTarget(Edge a, Edge b) {
  final byFrom = a.from.compareTo(b.from);
  return byFrom != 0 ? byFrom : a.to.compareTo(b.to);
}

int _mostFirst(DirectoryEdge a, DirectoryEdge b) {
  final byCount = b.count.compareTo(a.count);
  if (byCount != 0) return byCount;
  final byFrom = a.from.compareTo(b.from);
  return byFrom != 0 ? byFrom : a.to.compareTo(b.to);
}

// --- Console ---------------------------------------------------------------

/// [top] caps the hub tables and the back edges listed per cycle.
String renderDepsConsole(
  DepsReport deps, {
  int top = 10,
  Palette palette = Palette.plain,
}) {
  final out = StringBuffer();
  for (final d in deps.diagnostics) {
    out.writeln(d.toString());
  }
  if (deps.files == 0 && deps.diagnostics.isEmpty) {
    out.writeln('No files analyzed.');
    return out.toString();
  }
  if (deps.libraries.isEmpty) {
    out.writeln(
      'No dependency data: the coupling metric measured no library in this '
      'run.',
    );
    return out.toString();
  }
  out.writeln(
    [
      palette.bold('Dependencies'),
      _libraries(deps.libraries.length),
      '${plural(deps.imports + deps.exports, 'edge')} '
          '(${deps.imports} imports, ${deps.exports} exports)',
      if (deps.outside > 0) '${plural(deps.outside, 'target')} outside the run',
      if (deps.filesWithErrors > 0)
        '${plural(deps.filesWithErrors, 'file')} with parse errors',
    ].join(' • '),
  );
  _renderCycles(out, deps, top, palette);
  _renderHubs(out, deps, top, palette);
  _renderDirectories(out, deps.directories, palette);
  return out.toString();
}

void _renderCycles(StringBuffer out, DepsReport deps, int top, Palette p) {
  if (deps.cycles.isEmpty) {
    out.writeln('${p.bold('Cycles')} • none');
    return;
  }
  final largest = deps.cycles.first.members.length;
  final back = deps.cycles.fold(0, (n, c) => n + c.backEdges.length);
  out.writeln(
    '${p.bold('Cycles')} • ${plural(deps.cycles.length, 'component')} • '
    'largest $largest of ${_libraries(deps.libraries.length)} '
    '(${pct(largest / deps.libraries.length).trim()}) • '
    '${plural(back, 'back edge')}',
  );
  final pathOf = deps.pathOf;
  for (var i = 0; i < deps.cycles.length; i++) {
    final c = deps.cycles[i];
    out.writeln(
      '  #${i + 1} • ${_libraries(c.members.length)} • '
      '${plural(c.backEdges.length, 'back edge')}',
    );
    for (final e in c.backEdges.take(top)) {
      out.writeln('    ${pathOf[e.from]} → ${pathOf[e.to]}');
    }
    if (c.backEdges.length > top) {
      out.writeln('    ${p.dim('… and ${c.backEdges.length - top} more')}');
    }
  }
}

void _renderHubs(StringBuffer out, DepsReport deps, int top, Palette p) {
  final byOut = deps.libraries.where((l) => l.fanOut > 0).toList()
    ..sort((a, b) {
      final by = b.fanOut.compareTo(a.fanOut);
      return by != 0 ? by : a.name.compareTo(b.name);
    });
  final byIn = deps.libraries.where((l) => l.fanIn > 0).toList()
    ..sort((a, b) {
      final by = b.fanIn.compareTo(a.fanIn);
      return by != 0 ? by : a.name.compareTo(b.name);
    });
  out.writeln(
    '${p.bold('Fan-out')} • top $top • I = instability, out / (in + out)',
  );
  _renderHubTable(out, byOut.take(top), p);
  out.writeln('${p.bold('Fan-in')} • top $top');
  _renderHubTable(out, byIn.take(top), p);
}

void _renderHubTable(StringBuffer out, Iterable<LibraryNode> rows, Palette p) {
  if (rows.isEmpty) {
    out.writeln('  none');
    return;
  }
  out.writeln('  ${p.dim('  out    in     I  library')}');
  for (final l in rows) {
    final paint = switch (l.verdict) {
      Verdict.fail => p.red,
      Verdict.warn => p.yellow,
      Verdict.ok => (String s) => s,
    };
    final i = l.instability == null
        ? '-'.padLeft(5)
        : l.instability!.toStringAsFixed(2).padLeft(5);
    out.writeln(
      '  ${paint(countCol(l.fanOut))} ${countCol(l.fanIn)} $i  ${l.path}'
      '${l.cycle == null ? '' : '  ${p.dim('cycle #${l.cycle! + 1}')}'}',
    );
  }
}

void _renderDirectories(StringBuffer out, DirectoryGraph g, Palette p) {
  out.writeln(
    [
      p.bold('Directories'),
      'depth ${g.depth}',
      _dirs(g.order.length),
      plural(g.edges.length, 'edge'),
      plural(g.backEdges, 'back edge'),
    ].join(' • '),
  );
  out.writeln('  ${p.dim('layering')} ${g.order.join(' › ')}');
  if (g.edges.isEmpty) out.writeln('  none');
  int widest(String Function(DirectoryEdge) of) =>
      g.edges.fold(0, (w, e) => of(e).length > w ? of(e).length : w);
  final from = widest((e) => e.from);
  final to = widest((e) => e.to);
  for (final e in g.edges) {
    out.writeln(
      '  ${countCol(e.count)}  ${e.from.padRight(from)} → '
      '${e.back ? '${e.to.padRight(to)}  ${p.dim('back')}' : e.to}',
    );
  }
}

String _libraries(int n) => plural(n, 'library', 'libraries');

String _dirs(int n) => plural(n, 'directory', 'directories');

// --- JSON ------------------------------------------------------------------

String renderDepsJson(DepsReport deps, {RunStatus? status}) =>
    const JsonEncoder.withIndent('  ').convert(jsonDeps(deps, status: status));

/// A document of its own, not the analyze report. `libraries` lists every
/// run library (hubs are a sort away); `cycles` are largest first with
/// member names and back edges, and each library's `cycle` indexes into
/// them.
Map<String, Object?> jsonDeps(DepsReport deps, {RunStatus? status}) => {
  'schemaVersion': depsSchemaVersion,
  'tool': {'name': toolName, 'version': toolVersion},
  'status': status == RunStatus.errors ? 'errors' : 'ok',
  'summary': {
    'files': deps.files,
    'filesWithErrors': deps.filesWithErrors,
    'libraries': deps.libraries.length,
    'edges': {'imports': deps.imports, 'exports': deps.exports},
    'outside': deps.outside,
    'cycles': {
      'count': deps.cycles.length,
      'largest': deps.cycles.isEmpty ? 0 : deps.cycles.first.members.length,
    },
  },
  'diagnostics': [
    for (final d in deps.diagnostics)
      {
        'path': d.path,
        'severity': d.severity.name,
        'message': d.message,
        'line': d.line,
        'column': d.column,
      },
  ],
  'libraries': [
    for (final l in deps.libraries)
      {
        'name': l.name,
        'path': l.path,
        'fanOut': l.fanOut,
        'fanIn': l.fanIn,
        'exports': l.exports,
        'instability': l.instability,
        'cycle': l.cycle,
        'verdict': l.verdict.name,
      },
  ],
  'cycles': [
    for (final c in deps.cycles)
      {
        'members': c.members,
        'backEdges': [
          for (final e in c.backEdges) {'from': e.from, 'to': e.to},
        ],
      },
  ],
  'directories': {
    'depth': deps.directories.depth,
    'order': deps.directories.order,
    'edges': [
      for (final e in deps.directories.edges)
        {'from': e.from, 'to': e.to, 'count': e.count, 'back': e.back},
    ],
  },
};
