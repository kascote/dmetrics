/// Import coupling per library: how many other libraries of the codebase
/// under analysis a library's code depends on.
///
/// Efferent coupling at library granularity. The value is the number of
/// distinct libraries of the run's own packages that a library imports.
/// `dart:` libraries and dependencies from other packages are not counted
/// (they are listed in `detail`) because a library's coupling to the code it
/// ships with is the number a refactoring can change. Re-exports are not
/// counted either: an `export` brings no code that can break, so a barrel
/// file has the API surface of a package but the coupling of an empty file;
/// it still is an edge of the graph, so it takes part in fan-in and cycles
/// and is listed in `detail`. A target that belongs to one of the run's
/// packages counts whether or not it is among the run's sources, so
/// measuring a single file gives the same number as measuring its package.
///
/// Directives are collected per file during traversal. A part opens no
/// library scope, so its directives are collected under the file and folded
/// into the including library in [finish], attributed to that library's own
/// `part` directive. [finish] also has the whole graph: fan-in and cycle
/// membership (strongly connected components over the edges between run
/// libraries) go into `detail`, and the finish measurement replaces the
/// provisional one from traversal.
library;

import 'package:analyzer/dart/ast/ast.dart';
import 'package:source_span/source_span.dart' show FileSpan;

import '../../engine/directives.dart';
import '../../engine/measurement.dart';
import '../../engine/metric.dart';
import '../../engine/result.dart';
import '../../engine/graph.dart';
import '../../engine/scope.dart';

class CouplingMetric extends Metric {
  static const metricId = 'coupling';

  late LibraryIndex _index;

  /// Every traversed unit by run path: libraries and parts alike.
  final _units = <String, _Unit>{};
  _Unit? _current;

  @override
  String get id => metricId;

  @override
  MetricRequirements get requirements => MetricRequirements.directive;

  @override
  Set<ScopeKind> get measures => const {ScopeKind.library};

  /// Calibrated over the field-trial corpus: 15 is about the 95th percentile
  /// of libraries in library and app code alike, 30 catches the hubs (a
  /// package's god-file, its composition root) and nothing else. See the
  /// spec for the numbers.
  @override
  Threshold? get defaultThreshold => const Threshold(warn: 15, fail: 30);

  @override
  void onStartRun(RunContext ctx) {
    _index = ctx.libraries!;
    _units.clear();
    _current = null;
  }

  @override
  void onEnterScope(ScopeContext ctx) {
    _current!.scope = ctx;
  }

  @override
  Measurement onExitScope(ScopeContext ctx) =>
      _Graph.provisional(_current!).measure(id, _current!);

  @override
  void onEnterNode(AstNode node, ScopeContext ctx) {
    switch (node) {
      case CompilationUnit():
        // The unit's node arrives under the file context, before any
        // library scope opens; the file's path is that context's name.
        _current = _units[ctx.qualifiedName] = _Unit(ctx.qualifiedName);
      case UriBasedDirective():
        _collect(node);
      default:
        break;
    }
  }

  @override
  void onExitNode(AstNode node, ScopeContext ctx) {}

  /// A configurable import (`import 'a.dart' if (dart.library.io) 'b.dart'`)
  /// contributes its default URI: that is the one the element model binds
  /// when no platform is chosen, and the probe matched the element model.
  void _collect(UriBasedDirective node) {
    final unit = _current!;
    final text = node.uri.stringValue;
    if (text == null) return;
    final kind = switch (node) {
      ImportDirective() => _DirectiveKind.import,
      ExportDirective() => _DirectiveKind.export,
      PartDirective() => _DirectiveKind.part,
    };
    unit.directives.add((
      kind: kind,
      ref: _index.resolve(text, from: unit.path),
      span: unit.scope?.spanOf(node),
    ));
  }

  @override
  Iterable<Measurement> finish(RunContext ctx) {
    final graph = _Graph.complete(_units);
    return [
      for (final unit in _units.values)
        if (unit.scope != null) graph.measure(id, unit),
    ];
  }
}

enum _DirectiveKind { import, export, part }

/// One directive as written, resolved against the run. [span] is null in a
/// part, whose directives are attributed to the including library's `part`.
typedef _Directive = ({_DirectiveKind kind, LibraryRef ref, FileSpan? span});

/// A traversed compilation unit: its directives, and its `library` scope
/// when it is not a part.
class _Unit {
  final String path;
  final directives = <_Directive>[];
  ScopeContext? scope;

  _Unit(this.path);

  String get name => scope!.qualifiedName;
}

/// One edge of a library to a library of the run's packages: the first
/// directive that named the target. Imported targets count and carry a
/// contributor; targets that are only re-exported do not.
class _Dependency {
  final LibraryRef ref;
  final Contributor? contributor;

  const _Dependency(this.ref, this.contributor);

  bool get isSource => ref.kind == LibraryRefKind.source;
  bool get counted => contributor != null;
}

/// The dependencies of every library, with fan-in and cycles once complete.
class _Graph {
  final Map<String, List<_Dependency>> _deps;
  final Map<String, Set<String>> _external;
  final _dependents = <String, List<String>>{};
  final _cycles = <String, List<String>>{};

  _Graph._(this._deps, this._external);

  /// Own directives only: what traversal knows before the run ends.
  factory _Graph.provisional(_Unit unit) {
    final deps = <_Dependency>[];
    final external = <String>{};
    _collect(unit, unit.name, deps, external, span: null);
    return _Graph._({unit.name: deps}, {unit.name: external});
  }

  /// Every library with its parts folded in, then fan-in and strongly
  /// connected components over the edges between run libraries.
  factory _Graph.complete(Map<String, _Unit> units) {
    final deps = <String, List<_Dependency>>{};
    final external = <String, Set<String>>{};
    for (final unit in units.values) {
      if (unit.scope == null) continue;
      final own = deps[unit.name] = [];
      final ext = external[unit.name] = {};
      _collect(unit, unit.name, own, ext, span: null);
      _foldParts(unit, unit.name, units, own, ext, visited: {unit.path});
    }
    return _Graph._(deps, external)
      .._computeDependents()
      .._computeCycles();
  }

  /// Adds [unit]'s import and export edges to [deps], one contributor per
  /// new imported target. Inside a part, [span] is the library's `part`
  /// directive, which then carries one increment per import the part adds.
  static void _collect(
    _Unit unit,
    String library,
    List<_Dependency> deps,
    Set<String> external, {
    required FileSpan? span,
  }) {
    for (final d in unit.directives) {
      if (d.kind == _DirectiveKind.part) continue;
      switch (d.ref.kind) {
        case LibraryRefKind.external:
          external.add(d.ref.target);
        case LibraryRefKind.source || LibraryRefKind.missing:
          if (d.ref.target == library) continue;
          _addEdge(deps, d, span);
        case LibraryRefKind.sdk || LibraryRefKind.invalid:
          break;
      }
    }
  }

  /// A target imported after being re-exported becomes counted; the reverse
  /// changes nothing.
  static void _addEdge(List<_Dependency> deps, _Directive d, FileSpan? span) {
    final i = deps.indexWhere((e) => e.ref.target == d.ref.target);
    if (d.kind == _DirectiveKind.export) {
      if (i < 0) deps.add(_Dependency(d.ref, null));
      return;
    }
    if (i >= 0 && deps[i].counted) return;
    final kind = span == null ? 'import' : 'part';
    final edge = _Dependency(
      d.ref,
      Contributor(
        kind: kind,
        // One family per target, so no library is ever "table-shaped:
        // import": an import list is what this metric counts, and the
        // marker would say nothing.
        family: '$kind:${d.ref.target}',
        increment: 1,
        span: span ?? d.span!,
      ),
    );
    if (i < 0) {
      deps.add(edge);
    } else {
      deps[i] = edge;
    }
  }

  /// Parts, and parts of parts, that are run sources contribute their
  /// directives to the library that includes them.
  static void _foldParts(
    _Unit unit,
    String library,
    Map<String, _Unit> units,
    List<_Dependency> deps,
    Set<String> external, {
    required Set<String> visited,
    FileSpan? span,
  }) {
    for (final d in unit.directives) {
      if (d.kind != _DirectiveKind.part) continue;
      final part = d.ref.source == null ? null : units[d.ref.source!.path];
      if (part == null || part.scope != null || !visited.add(part.path)) {
        continue;
      }
      final at = span ?? d.span!;
      _collect(part, library, deps, external, span: at);
      _foldParts(
        part,
        library,
        units,
        deps,
        external,
        visited: visited,
        span: at,
      );
    }
  }

  void _computeDependents() {
    for (final e in _deps.entries) {
      for (final d in e.value) {
        if (d.isSource && _deps.containsKey(d.ref.target)) {
          _dependents.putIfAbsent(d.ref.target, () => []).add(e.key);
        }
      }
    }
  }

  /// A component of two or more libraries is a cycle.
  void _computeCycles() {
    final components = stronglyConnectedComponents(
      _deps.keys,
      (name) => [
        for (final d in _deps[name]!)
          if (d.isSource && _deps.containsKey(d.ref.target)) d.ref.target,
      ],
    );
    for (final component in components) {
      if (component.length < 2) continue;
      final members = component..sort();
      for (final m in members) {
        _cycles[m] = members;
      }
    }
  }

  Measurement measure(String metricId, _Unit unit) {
    final edges = _deps[unit.name]!;
    final counted = edges.where((d) => d.counted);
    final contributors = [for (final d in counted) d.contributor!]
      ..sort((a, b) => a.span.start.offset.compareTo(b.span.start.offset));
    List<String> names(Iterable<_Dependency> from) =>
        [for (final d in from) d.ref.target]..sort();
    return Measurement(
      metricId: metricId,
      scope: unit.scope!.id,
      value: contributors.length,
      contributors: contributors,
      detail: {
        'dependencies': names(counted),
        'missing': names(counted.where((d) => !d.isSource)),
        'exports': names(edges.where((d) => !d.counted)),
        'external': _external[unit.name]!.toList()..sort(),
        'dependents': (_dependents[unit.name] ?? const <String>[]).toList()
          ..sort(),
        'cycle': ?_cycles[unit.name],
      },
    );
  }
}
