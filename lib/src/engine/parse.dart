import 'package:analyzer/dart/analysis/features.dart';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/diagnostic/diagnostic.dart' as an;
import 'package:source_span/source_span.dart' as ss;

import 'report.dart';
import 'source.dart';
import 'suppress.dart';

class ParsedSource {
  final SourceFile source;
  final CompilationUnit unit;
  final ss.SourceFile file;
  final List<Diagnostic> diagnostics;
  final Suppressions suppressions;

  const ParsedSource({
    required this.source,
    required this.unit,
    required this.file,
    required this.diagnostics,
    required this.suppressions,
  });

  bool get partial => diagnostics.any((d) => d.severity == Severity.error);
}

/// Parses with error recovery at the file's language version.
///
/// The version matters: the latest one rejects syntax older packages still
/// use (Dart 3.13 made `final` on a parameter a parse error), so a file is
/// parsed the way `dart` would parse it, with its package's version. A
/// `// @dart=` comment can still lower the version for one file; the scanner
/// applies it on top of the feature set given here.
ParsedSource parseSource(SourceFile source) {
  final version = source.languageVersion;
  final result = parseString(
    content: source.content,
    path: source.path,
    featureSet: version == null
        ? null
        : FeatureSet.fromEnableFlags2(
            sdkLanguageVersion: version.asVersion,
            flags: const [],
          ),
    throwIfDiagnostics: false,
  );
  final file = ss.SourceFile.fromString(source.content, url: source.path);
  return ParsedSource(
    source: source,
    unit: result.unit,
    file: file,
    suppressions: Suppressions.scan(result.unit.beginToken, file),
    diagnostics: [
      for (final e in result.errors)
        Diagnostic(
          message: e.message,
          // Recovery diagnostics at EOF can extend past the content.
          span: file.span(
            e.offset.clamp(0, file.length),
            (e.offset + e.length).clamp(0, file.length),
          ),
          severity: switch (e.severity) {
            an.Severity.error => Severity.error,
            an.Severity.warning => Severity.warning,
            an.Severity.info => Severity.info,
          },
        ),
    ],
  );
}
