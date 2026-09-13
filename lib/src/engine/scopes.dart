/// Scope classification, naming and identity (§5.0.1, §6.1 "Scopes
/// measured", §7.3 "Scope identity").
library;

import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/token.dart';
import 'package:source_span/source_span.dart' as ss;

import 'scope.dart';

/// The measured scope kind [node] opens, or null when it opens none.
///
/// Abstract, external and redirecting-factory declarations have no body and
/// open no scope. A constructor with a `;` body is still measured: its
/// initializer list belongs to it.
ScopeKind? measuredKindOf(AstNode node) {
  switch (node) {
    case MethodDeclaration():
      if (node.body is EmptyFunctionBody) return null;
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

/// The display name of a class-like declaration that opens a `class_`
/// context, or null when [node] opens none.
String? classContextNameOf(AstNode node) => switch (node) {
  ClassDeclaration() => node.namePart.typeName.lexeme,
  MixinDeclaration() => node.name.lexeme,
  EnumDeclaration() => node.namePart.typeName.lexeme,
  ExtensionTypeDeclaration() => node.namePart.typeName.lexeme,
  ExtensionDeclaration() => node.name?.lexeme ?? '<extension>',
  _ => null,
};

/// The declared name of a named measured scope.
String declaredNameOf(AstNode node) => switch (node) {
  MethodDeclaration(:final name, :final parameters)
      when node.isOperator &&
          name.lexeme == '-' &&
          (parameters?.parameters.isEmpty ?? true) =>
    'unary-',
  MethodDeclaration(:final name) => name.lexeme,
  FunctionDeclaration(:final name) => name.lexeme,
  ConstructorDeclaration(:final name) => name?.lexeme ?? 'new',
  _ => throw ArgumentError('not a named scope node: ${node.runtimeType}'),
};

/// The first token of a declaration: metadata through body, doc comments
/// excluded.
Token declarationBeginToken(AstNode node) => switch (node) {
  AnnotatedNode(:final metadata) when metadata.isNotEmpty =>
    metadata.beginToken!,
  AnnotatedNode() => node.firstTokenAfterCommentAndMetadata,
  _ => node.beginToken,
};

/// The whole declaration, metadata through body. Doc comments are excluded.
ss.FileSpan declarationSpan(ss.SourceFile file, AstNode node) =>
    file.span(declarationBeginToken(node).offset, node.end);

/// FNV-1a (32-bit) over the declaration's token lexemes, NUL-separated, as
/// eight hex digits. Comments and whitespace do not participate, and the
/// declaration's own name tokens hash as a placeholder, so a rename that
/// leaves the body alone keeps the fingerprint and a baseline can follow
/// it. Frozen: every baseline file depends on it.
String fingerprintOf(AstNode node) {
  var hash = 0x811c9dc5;
  void mix(int byte) {
    hash = ((hash ^ byte) * 0x01000193) & 0xffffffff;
  }

  final masked = _ownNameTokens(node);
  final end = node.end;
  for (
    Token? t = declarationBeginToken(node);
    t != null && t.offset < end && t.type != TokenType.EOF;
    t = t.next
  ) {
    final lexeme = masked.contains(t) ? _namePlaceholder : t.lexeme;
    for (final unit in lexeme.codeUnits) {
      mix(unit & 0xff);
      mix(unit >> 8);
    }
    mix(0);
  }
  return hash.toRadixString(16).padLeft(8, '0');
}

const _namePlaceholder = '\u0001name';

/// The tokens that spell the declaration's own name: a method's or
/// function's name; a constructor's class name and name. Identity, not
/// lexeme: a body that mentions the name still hashes it.
Set<Token> _ownNameTokens(AstNode node) => switch (node) {
  MethodDeclaration(:final name) => {name},
  FunctionDeclaration(:final name) => {name},
  ConstructorDeclaration(:final typeName, :final name) => {
    ?typeName?.token,
    ?name,
  },
  _ => const {},
};

/// Allocates ids that are unique within one file's report (§7.3).
///
/// Named scopes get `path::kind:qualifiedName`; when recovered source makes
/// two declarations share an id, later ones get `#2`, `#3`, … in source
/// order. Closures get `parentId::closure#N`, N being the source-order
/// ordinal among the parent context's direct closures.
class ScopeIdAllocator {
  final String path;
  final _used = <String>{};
  final _closureOrdinals = <ScopeId, int>{};

  ScopeIdAllocator(this.path);

  ScopeId file() => _claim(path);

  /// The one library a file can define.
  ScopeId library() => _claim('$path::library');

  ScopeId named(ScopeKind kind, String qualifiedName) =>
      _claim('$path::${kind.label}:$qualifiedName');

  /// Returns the id and the ordinal used for display.
  (ScopeId, int) closure(ScopeContext parent) {
    final n = (_closureOrdinals[parent.id] ?? 0) + 1;
    _closureOrdinals[parent.id] = n;
    return (_claim('${parent.id}::closure#$n'), n);
  }

  ScopeId _claim(String base) {
    var id = base;
    for (var n = 2; !_used.add(id); n++) {
      id = '$base#$n';
    }
    return ScopeId(id);
  }
}
