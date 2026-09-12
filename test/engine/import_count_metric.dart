import 'package:analyzer/dart/ast/ast.dart';
import 'package:dmetrics/dmetrics.dart';
import 'package:source_span/source_span.dart' show FileSpan;

/// Dummy directive metric that proves the engine seam. Never ships.
///
/// Per library: the number of `import` and `export` directives that name a
/// library other than `dart:` ones, one contributor each. Every edge is
/// classified through the run's [LibraryIndex] into `detail`, and the
/// libraries that import this one (fan-in) are filled in from [finish],
/// which can only know them once every file has been traversed. So it
/// exercises the directive pipeline, the `library` scope, `detail`, and a
/// finish measurement replacing a traversal one.
class ImportCountMetric extends Metric {
  static const metricId = 'imports';

  late LibraryIndex _index;
  final _libraries = <ScopeId, _Library>{};
  _Library? _open;

  @override
  String get id => metricId;

  @override
  MetricRequirements get requirements => MetricRequirements.directive;

  @override
  Set<ScopeKind> get measures => const {ScopeKind.library};

  @override
  void onStartRun(RunContext ctx) {
    _index = ctx.libraries!;
    _libraries.clear();
  }

  @override
  void onEnterScope(ScopeContext ctx) {
    _open = _Library(ctx);
  }

  @override
  Measurement onExitScope(ScopeContext ctx) {
    final lib = _open!;
    _open = null;
    _libraries[ctx.id] = lib;
    return lib.measurement(id, importedBy: null);
  }

  @override
  void onEnterNode(AstNode node, ScopeContext ctx) {
    final lib = _open;
    if (lib == null || node is! NamespaceDirective) return;
    final text = node.uri.stringValue;
    final ref = text == null
        ? null
        : _index.resolve(text, from: lib.scope.qualifiedName);
    if (ref == null || ref.kind == LibraryRefKind.sdk) return;
    lib.edges.add((
      kind: node is ImportDirective ? 'import' : 'export',
      ref: ref,
      span: ctx.spanOf(node),
    ));
  }

  @override
  void onExitNode(AstNode node, ScopeContext ctx) {}

  @override
  Iterable<Measurement> finish(RunContext ctx) {
    final importedBy = <String, List<String>>{};
    for (final lib in _libraries.values) {
      for (final e in lib.edges) {
        if (e.ref.kind == LibraryRefKind.source) {
          importedBy.putIfAbsent(e.ref.target, () => []).add(lib.name);
        }
      }
    }
    return [
      for (final lib in _libraries.values)
        lib.measurement(id, importedBy: importedBy[lib.name] ?? const []),
    ];
  }
}

typedef _Edge = ({String kind, LibraryRef ref, FileSpan span});

class _Library {
  final ScopeContext scope;
  final edges = <_Edge>[];

  _Library(this.scope);

  String get name => scope.qualifiedName;

  Measurement measurement(
    String metricId, {
    required List<String>? importedBy,
  }) {
    List<String> targets(LibraryRefKind kind) => [
      for (final e in edges)
        if (e.ref.kind == kind) e.ref.target,
    ]..sort();
    return Measurement(
      metricId: metricId,
      scope: scope.id,
      value: edges.length,
      contributors: [
        for (final e in edges)
          Contributor(kind: e.kind, increment: 1, span: e.span),
      ],
      detail: {
        'imports': targets(LibraryRefKind.source),
        'external': targets(LibraryRefKind.external),
        'missing': targets(LibraryRefKind.missing),
        if (importedBy != null) 'importedBy': [...importedBy]..sort(),
      },
    );
  }
}
