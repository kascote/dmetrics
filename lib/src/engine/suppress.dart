/// `// ignore:` suppressions (SPEC §8).
///
/// `// ignore: metra_cyclomatic` on the line immediately before a scope's
/// declaration or on the declaration's first line; `// ignore_for_file:
/// metra_cyclomatic` anywhere in the file; `metra` alone names every metric.
/// A suppression on a method does not suppress its closures: a line ignore
/// applies only to the outermost measured scopes starting on that line.
library;

import 'package:analyzer/dart/ast/token.dart';
import 'package:source_span/source_span.dart' as ss;

import 'result.dart';

class IgnoreComment {
  static const prefix = 'metra';

  final SuppressionKind kind;
  final Set<String> names;
  final ss.FileSpan span;

  const IgnoreComment({
    required this.kind,
    required this.names,
    required this.span,
  });

  /// 0-based line of the comment.
  int get line => span.start.line;

  bool covers(String metricId) =>
      names.contains(prefix) || names.contains('${prefix}_$metricId');

  @override
  String toString() => '${kind.name} $names @${line + 1}';
}

/// The ignore comments of one file, indexed for the pipeline.
class Suppressions {
  static const none = Suppressions([]);

  final List<IgnoreComment> comments;

  const Suppressions(this.comments);

  /// Scans every comment token reachable from [begin].
  factory Suppressions.scan(Token begin, ss.SourceFile file) {
    final out = <IgnoreComment>[];
    for (Token? t = begin; t != null; t = t.next) {
      for (Token? c = t.precedingComments; c != null; c = c.next) {
        final m = _pattern.firstMatch(c.lexeme);
        if (m == null) continue;
        out.add(
          IgnoreComment(
            kind: m.group(1) == 'ignore'
                ? SuppressionKind.ignore
                : SuppressionKind.ignoreForFile,
            names: {
              for (final n in m.group(2)!.split(','))
                if (n.trim().isNotEmpty) n.trim(),
            },
            span: file.span(c.offset, c.end),
          ),
        );
      }
      if (t.type == TokenType.EOF) break;
    }
    return Suppressions(out);
  }

  /// The first `ignore_for_file` naming [metricId], if any.
  Suppression? forFile(String metricId) {
    for (final c in comments) {
      if (c.kind == SuppressionKind.ignoreForFile && c.covers(metricId)) {
        return Suppression(kind: c.kind, span: c.span);
      }
    }
    return null;
  }

  /// An `ignore` naming [metricId] on [line] (0-based) or the line before.
  Suppression? forLine(int line, String metricId) {
    for (final c in comments) {
      if (c.kind == SuppressionKind.ignore &&
          (c.line == line || c.line == line - 1) &&
          c.covers(metricId)) {
        return Suppression(kind: c.kind, span: c.span);
      }
    }
    return null;
  }

  static final _pattern = RegExp(r'^//\s*(ignore|ignore_for_file):\s*(.*)$');
}
