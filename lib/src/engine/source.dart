/// Engine input. The engine never touches the file system.
class SourceFile {
  /// Run-root-relative path with forward slashes. Report-wide file identity;
  /// embedded in scope ids.
  final String path;

  final String content;

  /// Run-root-relative directory of this file's config group. Path globs in
  /// that config match [path] relative to [configRoot], never [path] itself.
  final String configRoot;

  const SourceFile({
    required this.path,
    required this.content,
    required this.configRoot,
  });

  @override
  String toString() => 'SourceFile($path)';
}
