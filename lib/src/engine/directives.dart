/// Directive-level library resolution: which library an `import`, `export`
/// or `part` URI names, and whether that library is one of the run's
/// sources. This is all a dependency metric needs for an import graph; the
/// cost probe found it produces the same graph as the analyzer's element
/// model at parse cost, so it is its own pipeline level below resolution.
///
/// Built once per run from the source list. Never touches the file system:
/// `package:` URIs resolve through each source's [SourceFile.packageUri],
/// which the I/O layer derives from the nearest pubspec.
library;

import 'package:path/path.dart' as p;

import 'source.dart';

/// The display name and graph identity of a library: its `package:` URI when
/// it lives under a package's `lib/`, otherwise its run-root-relative path.
/// The driver names `library` scopes with it, so an edge's target compares
/// equal to the target's scope name.
String libraryNameOf(SourceFile source) =>
    source.packageUri?.toString() ?? source.path;

enum LibraryRefKind {
  /// One of the run's sources.
  source,

  /// Inside a package the run analyzes, but not among its sources: excluded
  /// by config (generated files), not yet written, or a typo.
  missing,

  /// A package the run does not analyze: a dependency.
  external,

  /// `dart:` libraries.
  sdk,

  /// Not a URI the resolver understands: interpolated, malformed, or an
  /// unsupported scheme.
  invalid,
}

/// Where a directive URI points.
class LibraryRef {
  final LibraryRefKind kind;

  /// The target's identity: the source's library name for [kind] `source`,
  /// otherwise the resolved URI or path as text.
  final String target;

  /// Non-null only for [kind] `source`.
  final SourceFile? source;

  const LibraryRef._(this.kind, this.target, [this.source]);

  @override
  String toString() => 'LibraryRef(${kind.name} $target)';
}

/// Resolves directive URIs against the run's sources.
class LibraryIndex {
  final _byName = <String, SourceFile>{};
  final _byPath = <String, SourceFile>{};
  final _packages = <String>{};

  LibraryIndex(Iterable<SourceFile> sources) {
    for (final s in sources) {
      _byName[libraryNameOf(s)] = s;
      _byPath[s.path] = s;
      if (s.packageUri case final uri?) {
        _byName[uri.toString()] = s;
        _packages.add(uri.pathSegments.first);
      }
    }
  }

  Iterable<SourceFile> get sources => _byPath.values;

  /// The source with this library name or run-root-relative path.
  SourceFile? operator [](String nameOrPath) =>
      _byName[nameOrPath] ?? _byPath[nameOrPath];

  /// Resolves [uriText] as written in a directive of the library named
  /// [from] (a source's library name or path). Relative URIs resolve against
  /// the importing file's `package:` URI when it has one, so a file under
  /// `lib/` reaches its siblings by package identity, and against its path
  /// otherwise. Throws [ArgumentError] when [from] is not a run source.
  LibraryRef resolve(String uriText, {required String from}) {
    final origin = this[from];
    if (origin == null) {
      throw ArgumentError.value(from, 'from', 'not a source of this run');
    }
    final Uri uri;
    try {
      uri = Uri.parse(uriText);
    } on FormatException {
      return LibraryRef._(LibraryRefKind.invalid, uriText);
    }
    switch (uri.scheme) {
      case 'dart':
        return LibraryRef._(LibraryRefKind.sdk, uriText);
      case 'package':
        return _package(uri);
      case '':
        if (origin.packageUri case final base?) {
          return _package(base.resolveUri(uri));
        }
        final path = p.posix.normalize(
          p.posix.join(p.posix.dirname(origin.path), uri.path),
        );
        final source = _byPath[path];
        return source != null
            ? LibraryRef._(LibraryRefKind.source, libraryNameOf(source), source)
            : LibraryRef._(LibraryRefKind.missing, path);
      default:
        return LibraryRef._(LibraryRefKind.invalid, uriText);
    }
  }

  LibraryRef _package(Uri uri) {
    final text = uri.toString();
    final source = _byName[text];
    if (source != null) {
      return LibraryRef._(LibraryRefKind.source, text, source);
    }
    final segments = uri.pathSegments;
    if (segments.length < 2 || segments.first.isEmpty) {
      return LibraryRef._(LibraryRefKind.invalid, text);
    }
    return LibraryRef._(
      _packages.contains(segments.first)
          ? LibraryRefKind.missing
          : LibraryRefKind.external,
      text,
    );
  }
}
