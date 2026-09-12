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

  /// The one contributor family that supplies nearly the whole score, or
  /// null.
  ///
  /// A scope is table-shaped when a single family accounts for at least
  /// [TableShape.minShare] of the summed increments and the scope has at
  /// least [TableShape.minIncrements] of increment in total: a `switch`
  /// dispatch, a field-wise `==`, a `copyWith` of `??`s. Its score is the
  /// size of a table, not the tangle of a control flow, which is a reading
  /// hint for consumers, not a change in how anything is counted.
  ///
  /// Pooling by [Contributor.family] rather than kind is what keeps a
  /// guarded switch table-shaped: its `when` guards and or-patterns are arms
  /// of the same table, and counting them as separate kinds split the share
  /// below the cut on every real one the field trial found.
  TableShape? get tableShape {
    final byFamily = <String, num>{};
    num total = 0;
    for (final c in contributors) {
      byFamily[c.family] = (byFamily[c.family] ?? 0) + c.increment;
      total += c.increment;
    }
    if (total < TableShape.minIncrements) return null;
    for (final e in byFamily.entries) {
      final share = e.value / total;
      if (share >= TableShape.minShare) {
        return TableShape(kind: e.key, share: share);
      }
    }
    return null;
  }

  @override
  String toString() =>
      'Measurement($metricId, $scope, value=$value, contributors=$contributorSummary)';
}

/// See [Measurement.tableShape].
class TableShape {
  static const minShare = 0.7;
  static const minIncrements = 8;

  /// The dominant [Contributor.family]; the kind itself for kinds that are
  /// not pooled.
  final String kind;

  /// Fraction of the summed increments [kind] supplies, in `[minShare, 1]`.
  final double share;

  const TableShape({required this.kind, required this.share});

  @override
  String toString() => 'TableShape($kind, ${(share * 100).round()}%)';
}

/// One construct that produced part of a score.
class Contributor {
  /// Stable vocabulary defined by the metric; what reporters show.
  final String kind;

  /// The group [tableShape] pools this kind with. Defaults to [kind]; a
  /// metric names a family when several of its kinds are one construct
  /// written in pieces, so that a scope built from all of them is still
  /// read as a table, or when one kind is several things (`if`s at
  /// different nesting levels), so that a ladder of them is not.
  final String family;
  final num increment;
  final FileSpan span;

  const Contributor({
    required this.kind,
    required this.increment,
    required this.span,
    String? family,
  }) : family = family ?? kind;

  @override
  String toString() => '$kind(+$increment @${span.start.offset})';
}
