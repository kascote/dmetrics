/// The single traversal: one context stack, node and scope events broadcast
/// to every metric in source order (§5.0.1).
library;

import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:source_span/source_span.dart' as ss;

import 'measurement.dart';
import 'metric.dart';
import 'scope.dart';
import 'scopes.dart';

/// A measured scope and what each metric produced for it, keyed by metric id.
class ScopeMeasurements {
  final ScopeContext scope;
  final Map<String, Measurement> measurements;

  const ScopeMeasurements(this.scope, this.measurements);
}

class Driver extends GeneralizingAstVisitor<void> {
  final ss.SourceFile file;
  final String path;

  /// What the file's `library` scope is called: its `package:` URI or its
  /// path. Also the identity a directive metric resolves edges against.
  final String libraryName;
  final List<Metric> metrics;
  final bool partial;

  final List<ScopeMeasurements> measured = [];
  final ScopeIdAllocator _ids;

  /// Whether any metric asked for `library` scopes. When none did, the unit
  /// is traversed under the file context exactly as before, so a
  /// function-shaped run never reports a scope no metric measured.
  final bool _opensLibrary;

  /// Display ordinals for closures, keyed by the owner display name so that
  /// `C.a.<closure#1>` and `C.b.<closure#1>` both read naturally.
  final _displayOrdinals = <String, int>{};
  late ScopeContext _ctx;

  Driver({
    required this.file,
    required this.path,
    required this.metrics,
    required this.partial,
    String? libraryName,
  }) : libraryName = libraryName ?? path,
       _ids = ScopeIdAllocator(path),
       _opensLibrary = metrics.any(
         (m) => m.measures.contains(ScopeKind.library),
       );

  /// Traverses [unit]; results accumulate in [measured] in completion order.
  void run(CompilationUnit unit) {
    _ctx = ScopeContext(
      id: _ids.file(),
      kind: ScopeKind.file,
      parent: null,
      span: file.span(0, file.length),
      qualifiedName: path,
      partial: partial,
      fingerprint: fingerprintOf(unit),
    );
    unit.accept(this);
  }

  @override
  void visitNode(AstNode node) {
    final className = classContextNameOf(node);
    if (className != null) {
      _enterNode(node);
      final saved = _ctx;
      _ctx = ScopeContext(
        id: _ids.named(ScopeKind.class_, className),
        kind: ScopeKind.class_,
        parent: saved,
        span: declarationSpan(file, node),
        qualifiedName: className,
        partial: partial,
        fingerprint: fingerprintOf(node),
      );
      node.visitChildren(this);
      _ctx = saved;
      _exitNode(node);
      return;
    }

    final kind = node is CompilationUnit
        ? _libraryKindOf(node)
        : measuredKindOf(node);
    if (kind == null) {
      _enterNode(node);
      node.visitChildren(this);
      _exitNode(node);
      return;
    }

    // The opening node belongs to the enclosing context; all of its children
    // belong to the new scope. While the scope is open the enclosing context
    // receives nothing.
    _enterNode(node);
    final saved = _ctx;
    final scope = _open(node, kind, saved);
    _ctx = scope;
    final measuring = [
      for (final m in metrics)
        if (m.measures.contains(kind)) m,
    ];
    for (final m in measuring) {
      m.onEnterScope(scope);
    }
    node.visitChildren(this);
    final measurements = <String, Measurement>{
      for (final m in measuring) m.id: m.onExitScope(scope),
    };
    _ctx = saved;
    _exitNode(node);
    measured.add(ScopeMeasurements(scope, measurements));
  }

  /// A unit opens a `library` scope when a metric measures libraries and the
  /// unit is not a part: a part's declarations belong to the library that
  /// includes it, and which one that is only the whole run knows.
  ScopeKind? _libraryKindOf(CompilationUnit unit) =>
      _opensLibrary && !unit.directives.any((d) => d is PartOfDirective)
      ? ScopeKind.library
      : null;

  ScopeContext _open(AstNode node, ScopeKind kind, ScopeContext parent) {
    final ScopeId id;
    final String qualifiedName;
    if (kind == ScopeKind.library) {
      // From the first token to the end of the file: leading comments are
      // excluded like a declaration's doc comment, so a license header does
      // not become the library's location and an `// ignore:` on the line
      // before the first directive reaches it.
      return ScopeContext(
        id: _ids.library(),
        kind: kind,
        parent: parent,
        span: file.span(node.beginToken.offset, file.length),
        qualifiedName: libraryName,
        partial: partial,
        fingerprint: fingerprintOf(node),
      );
    }
    if (kind == ScopeKind.closure) {
      final owner = _closureOwnerName(node, parent);
      final display = (_displayOrdinals[owner] ?? 0) + 1;
      _displayOrdinals[owner] = display;
      // Ids are allocated under the file, not the library, so a top-level
      // closure keeps the same id whether or not a library metric is in the
      // run: ids are baseline keys and must not depend on the metric set.
      final (allocated, _) = _ids.closure(
        parent.kind == ScopeKind.library ? parent.parent! : parent,
      );
      id = allocated;
      qualifiedName = _join(owner, '<closure#$display>');
    } else {
      qualifiedName = _join(_displayPrefix(parent), declaredNameOf(node));
      id = _ids.named(kind, qualifiedName);
    }
    return ScopeContext(
      id: id,
      kind: kind,
      parent: parent,
      span: declarationSpan(file, node),
      qualifiedName: qualifiedName,
      partial: partial,
      fingerprint: fingerprintOf(node),
    );
  }

  /// `C.m` for a closure in a method; `C.field` / `field` for a closure in a
  /// variable initializer under a structural context; `C` / `` otherwise.
  String _closureOwnerName(AstNode node, ScopeContext parent) {
    final prefix = _displayPrefix(parent);
    if (!parent.kind.isDeclarationContainer) return prefix;
    for (var n = node.parent; n != null; n = n.parent) {
      if (n is VariableDeclaration) return _join(prefix, n.name.lexeme);
      if (measuredKindOf(n) != null || classContextNameOf(n) != null) break;
    }
    return prefix;
  }

  /// Top-level declarations are unqualified whether the unit is traversed
  /// under the file context or under a `library` scope.
  static String _displayPrefix(ScopeContext ctx) =>
      ctx.kind == ScopeKind.file || ctx.kind == ScopeKind.library
      ? ''
      : ctx.qualifiedName;

  static String _join(String prefix, String name) =>
      prefix.isEmpty ? name : '$prefix.$name';

  void _enterNode(AstNode node) {
    for (final m in metrics) {
      m.onEnterNode(node, _ctx);
    }
  }

  void _exitNode(AstNode node) {
    for (final m in metrics) {
      m.onExitNode(node, _ctx);
    }
  }
}
