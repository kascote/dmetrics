import 'package:pub_semver/pub_semver.dart';

/// Engine input. The engine never touches the file system.
class SourceFile {
  /// Run-root-relative path with forward slashes. Report-wide file identity;
  /// embedded in scope ids.
  final String path;

  final String content;

  /// Run-root-relative directory of this file's config group. Path globs in
  /// that config match [path] relative to [configRoot], never [path] itself.
  final String configRoot;

  /// The language version the file is parsed with. Null means the latest
  /// version the bundled analyzer knows, which is what a file outside any
  /// package gets.
  final LanguageVersion? languageVersion;

  const SourceFile({
    required this.path,
    required this.content,
    required this.configRoot,
    this.languageVersion,
  });

  @override
  String toString() => 'SourceFile($path)';
}

/// The Dart language version a file is parsed with: the lower bound of its
/// package's `environment: sdk:` constraint, which is how `dart` itself picks
/// it. Only major and minor matter; patch and pre-release tags never change
/// syntax.
class LanguageVersion {
  final int major;
  final int minor;

  const LanguageVersion(this.major, this.minor);

  /// Reads the lower bound of a pubspec `sdk:` constraint (`^3.12.0`,
  /// `>=3.0.0 <4.0.0`, `3.13.2`). Null when there is no lower bound (`any`)
  /// or the text is not a constraint; the caller then uses the latest
  /// version rather than refusing to analyze.
  static LanguageVersion? fromSdkConstraint(String constraint) {
    try {
      final parsed = VersionConstraint.parse(constraint.trim());
      final min = parsed is VersionRange ? parsed.min : null;
      if (min == null) return null;
      return LanguageVersion(min.major, min.minor);
    } on FormatException {
      return null;
    }
  }

  Version get asVersion => Version(major, minor, 0);

  @override
  bool operator ==(Object other) =>
      other is LanguageVersion && other.major == major && other.minor == minor;

  @override
  int get hashCode => Object.hash(major, minor);

  @override
  String toString() => '$major.$minor';
}
