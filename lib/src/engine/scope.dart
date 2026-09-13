import 'package:analyzer/dart/ast/syntactic_entity.dart';
import 'package:source_span/source_span.dart' show FileSpan;

enum ScopeKind {
  // Structural contexts: always present, never measured in v1.
  file,
  class_,
  // Measured scopes.
  function,
  method,
  getter,
  setter,
  operator,
  constructor,
  localFunction,
  closure,
  // The whole compilation unit of a library (not a part): the scope of
  // per-library metrics such as import coupling. Opened only when a metric
  // measures it, so function-shaped runs never grow an extra scope per file.
  library;

  /// The scope kinds a function-shaped metric measures in v1.
  static const Set<ScopeKind> measuredInV1 = {
    function,
    method,
    getter,
    setter,
    operator,
    constructor,
    localFunction,
    closure,
  };

  /// Structural contexts never receive scope events in v1.
  bool get isStructural => this == file || this == class_;

  /// Contexts whose direct children are declarations rather than code. A
  /// closure written in a variable initializer under one of these is named
  /// after the variable it initializes.
  bool get isDeclarationContainer => isStructural || this == library;

  /// The name used in ids and reports (`method`, `closure`, ...).
  String get label => this == class_ ? 'class' : name;
}

/// Opaque scope identity: deterministic and unique within a report.
///
/// Reporters must not parse it. Its shape (`path::kind:qualifiedName`,
/// `parentId::closure#N`, `#2` collision suffix) is an engine detail.
class ScopeId {
  final String value;

  const ScopeId(this.value);

  /// Rebuilds an id from [localIn]'s output under [path]. The baseline
  /// stores ids without their path so a file can move with the baseline;
  /// only these two helpers know how a path sits inside an id.
  ScopeId.inFile(String path, String local) : value = '$path::$local';

  /// The id with its file path stripped: `method:C.m`, `library`,
  /// `method:C.m::closure#1`. [path] must be the file's own path.
  String localIn(String path) {
    final prefix = '$path::';
    if (!value.startsWith(prefix)) {
      throw ArgumentError('$value is not a scope of $path');
    }
    return value.substring(prefix.length);
  }

  @override
  bool operator ==(Object other) => other is ScopeId && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => value;
}

/// The innermost open context delivered with every event.
///
/// Structural contexts (`file`, `class_`) and measured scopes share this type;
/// [kind] tells them apart.
class ScopeContext {
  final ScopeId id;
  final ScopeKind kind;

  /// Nearest enclosing context of any kind; null only for `file`.
  final ScopeContext? parent;

  /// The whole declaration: metadata through body.
  final FileSpan span;

  /// Display only: `C.m`, `C.m.<closure#1>`, `C.field.<closure#1>`.
  final String qualifiedName;

  /// True when the enclosing file had parse errors.
  final bool partial;

  /// Short hash of the declaration's token stream, comments and whitespace
  /// excluded. Deterministic; recorded as evidence for a future baseline
  /// matcher (§7.3) and promised nothing more.
  final String fingerprint;

  const ScopeContext({
    required this.id,
    required this.kind,
    required this.parent,
    required this.span,
    required this.qualifiedName,
    required this.partial,
    this.fingerprint = '',
  });

  /// The last segment of [qualifiedName]. A library's name is a URI or a
  /// path whose dots are not qualification, so it is returned whole.
  String get name {
    if (kind == ScopeKind.library) return qualifiedName;
    final i = qualifiedName.lastIndexOf('.');
    return i < 0 ? qualifiedName : qualifiedName.substring(i + 1);
  }

  /// A span in this scope's file for a node or token.
  FileSpan spanOf(SyntacticEntity entity) =>
      spanOfRange(entity.offset, entity.end);

  /// A span in this scope's file for a `[start, end)` offset range.
  FileSpan spanOfRange(int start, int end) => span.file.span(start, end);

  /// Nearest enclosing context whose kind is in [kinds], excluding this one.
  ScopeContext? nearestAncestor(Set<ScopeKind> kinds) {
    for (var p = parent; p != null; p = p.parent) {
      if (kinds.contains(p.kind)) return p;
    }
    return null;
  }

  @override
  String toString() => '$kind $qualifiedName';
}
