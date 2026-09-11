/// Throwaway stand-in for the engine so the harness can run end to end in M0.
///
/// It parses with `parseString`, opens a scope for every function-shaped
/// declaration and closure, and broadcasts node events. It deliberately does
/// NOT implement roll-up, ordering guarantees beyond start offset, id
/// collision fallback, or thresholds. It is replaced by the real engine in M1
/// and must not be extended.
library;

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/diagnostic/diagnostic.dart' as an;
import 'package:metra/metra.dart';
import 'package:source_span/source_span.dart' as ss;

Report stubAnalyze(
  List<SourceFile> sources,
  List<Metric> metrics,
  AnalysisConfig config,
) => Report(
  config: config,
  files: [for (final s in sources) _analyzeFile(s, metrics)],
);

FileReport _analyzeFile(SourceFile source, List<Metric> metrics) {
  final parsed = parseString(
    content: source.content,
    path: source.path,
    throwIfDiagnostics: false,
  );
  final file = ss.SourceFile.fromString(source.content, url: source.path);
  final diagnostics = [
    for (final e in parsed.errors)
      Diagnostic(
        message: e.message,
        span: file.span(e.offset, e.offset + e.length),
        severity: switch (e.severity) {
          an.Severity.error => Severity.error,
          an.Severity.warning => Severity.warning,
          an.Severity.info => Severity.info,
        },
      ),
  ];
  final partial = diagnostics.any((d) => d.severity == Severity.error);
  final root = ScopeContext(
    id: ScopeId(source.path),
    kind: ScopeKind.file,
    parent: null,
    span: file.span(0, source.content.length),
    qualifiedName: source.path,
    partial: partial,
  );
  final visitor = _StubVisitor(file, metrics, root, source.path);
  parsed.unit.accept(visitor);
  final scopes = visitor.results
    ..sort((a, b) {
      final c = a.scope.span.start.offset.compareTo(b.scope.span.start.offset);
      return c != 0
          ? c
          : a.scope.span.end.offset.compareTo(b.scope.span.end.offset);
    });
  return FileReport(source: source, diagnostics: diagnostics, scopes: scopes);
}

class _StubVisitor extends GeneralizingAstVisitor<void> {
  final ss.SourceFile file;
  final List<Metric> metrics;
  final String path;
  final results = <ScopeResult>[];
  final _closureOrdinals = <ScopeId, int>{};
  ScopeContext ctx;

  _StubVisitor(this.file, this.metrics, this.ctx, this.path);

  @override
  void visitNode(AstNode node) {
    if (node is ClassDeclaration) {
      _enterNode(node);
      final saved = ctx;
      ctx = ScopeContext(
        id: ScopeId('$path::class:${node.namePart.typeName.lexeme}'),
        kind: ScopeKind.class_,
        parent: saved,
        span: file.span(node.offset, node.end),
        qualifiedName: node.namePart.typeName.lexeme,
        partial: saved.partial,
      );
      node.visitChildren(this);
      ctx = saved;
      _exitNode(node);
      return;
    }

    final kind = _scopeKindOf(node);
    if (kind == null) {
      _enterNode(node);
      node.visitChildren(this);
      _exitNode(node);
      return;
    }

    // The opening node belongs to the enclosing context.
    _enterNode(node);
    final saved = ctx;
    final scope = _open(node, kind, saved);
    ctx = scope;
    final measuring = metrics.where((m) => m.measures.contains(kind)).toList();
    for (final m in measuring) {
      m.onEnterScope(scope);
    }
    node.visitChildren(this);
    final measurements = {
      for (final m in measuring) m.id: m.onExitScope(scope),
    };
    ctx = saved;
    _exitNode(node);

    results.add(
      ScopeResult(
        scope: scope,
        results: {
          for (final e in measurements.entries)
            e.key: MetricResult(
              measurement: e.value,
              value: e.value.value,
              includes: const [],
              threshold: null,
              verdict: Verdict.ok,
              suppressed: null,
            ),
        },
      ),
    );
  }

  ScopeContext _open(AstNode node, ScopeKind kind, ScopeContext parent) {
    final String qualifiedName;
    final ScopeId id;
    if (kind == ScopeKind.closure) {
      final ownerScope = ScopeKind.measuredInV1.contains(parent.kind)
          ? parent
          : parent.nearestAncestor(ScopeKind.measuredInV1) ?? parent;
      final n = (_closureOrdinals[ownerScope.id] ?? 0) + 1;
      _closureOrdinals[ownerScope.id] = n;
      qualifiedName = '${ownerScope.qualifiedName}.<closure#$n>';
      id = ScopeId('${ownerScope.id}::closure#$n');
    } else {
      final name = _nameOf(node);
      final enclosing = parent.kind == ScopeKind.file
          ? null
          : parent.qualifiedName;
      qualifiedName = enclosing == null ? name : '$enclosing.$name';
      id = ScopeId('$path::${kind.label}:$qualifiedName');
    }
    return ScopeContext(
      id: id,
      kind: kind,
      parent: parent,
      span: file.span(node.offset, node.end),
      qualifiedName: qualifiedName,
      partial: parent.partial,
    );
  }

  static String _nameOf(AstNode node) => switch (node) {
    MethodDeclaration(:final name) => name.lexeme,
    FunctionDeclaration(:final name) => name.lexeme,
    ConstructorDeclaration(:final name) => name?.lexeme ?? '',
    _ => throw StateError('unnamed scope node ${node.runtimeType}'),
  };

  static ScopeKind? _scopeKindOf(AstNode node) {
    switch (node) {
      case MethodDeclaration():
        if (node.body is EmptyFunctionBody) return null; // abstract / external
        if (node.isGetter) return ScopeKind.getter;
        if (node.isSetter) return ScopeKind.setter;
        if (node.isOperator) return ScopeKind.operator;
        return ScopeKind.method;
      case FunctionDeclaration():
        if (node.functionExpression.body is EmptyFunctionBody) return null;
        if (node.parent is FunctionDeclarationStatement) {
          return ScopeKind.localFunction;
        }
        if (node.isGetter) return ScopeKind.getter;
        if (node.isSetter) return ScopeKind.setter;
        return ScopeKind.function;
      case ConstructorDeclaration():
        if (node.externalKeyword != null) return null;
        if (node.redirectedConstructor != null) return null;
        return ScopeKind.constructor;
      case FunctionExpression():
        return node.parent is FunctionDeclaration ? null : ScopeKind.closure;
      default:
        return null;
    }
  }

  void _enterNode(AstNode node) {
    for (final m in metrics) {
      m.onEnterNode(node, ctx);
    }
  }

  void _exitNode(AstNode node) {
    for (final m in metrics) {
      m.onExitNode(node, ctx);
    }
  }
}
