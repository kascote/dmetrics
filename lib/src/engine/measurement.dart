import 'package:source_span/source_span.dart' show FileSpan;

import 'scope.dart';

/// What a metric produces for one scope.
class Measurement {
  final String metricId;
  final ScopeId scope;
  final num value;

  /// Complete list; reporters may truncate for display.
  final List<Contributor> contributors;

  /// Reserved for structured payloads (edges, cycles). Must be JSON-encodable.
  final Object? detail;

  const Measurement({
    required this.metricId,
    required this.scope,
    required this.value,
    required this.contributors,
    this.detail,
  });

  /// `{kind: count}` over [contributors], insertion-ordered by first sighting.
  Map<String, int> get contributorSummary {
    final out = <String, int>{};
    for (final c in contributors) {
      out[c.kind] = (out[c.kind] ?? 0) + 1;
    }
    return out;
  }

  @override
  String toString() =>
      'Measurement($metricId, $scope, value=$value, contributors=$contributorSummary)';
}

/// One construct that produced part of a score.
class Contributor {
  /// Stable vocabulary defined by the metric (for cyclomatic: §6.1).
  final String kind;
  final num increment;
  final FileSpan span;

  const Contributor({
    required this.kind,
    required this.increment,
    required this.span,
  });

  @override
  String toString() => '$kind(+$increment @${span.start.offset})';
}
