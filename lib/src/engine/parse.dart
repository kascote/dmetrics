import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/diagnostic/diagnostic.dart' as an;
import 'package:source_span/source_span.dart' as ss;

import 'report.dart';
import 'source.dart';

class ParsedSource {
  final SourceFile source;
  final CompilationUnit unit;
  final ss.SourceFile file;
  final List<Diagnostic> diagnostics;

  const ParsedSource({
    required this.source,
    required this.unit,
    required this.file,
    required this.diagnostics,
  });

  bool get partial => diagnostics.any((d) => d.severity == Severity.error);
}

/// Parses with error recovery and the latest language version; `// @dart=`
/// override comments are honored by the parser (§7.2).
ParsedSource parseSource(SourceFile source) {
  final result = parseString(
    content: source.content,
    path: source.path,
    throwIfDiagnostics: false,
  );
  final file = ss.SourceFile.fromString(source.content, url: source.path);
  return ParsedSource(
    source: source,
    unit: result.unit,
    file: file,
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
