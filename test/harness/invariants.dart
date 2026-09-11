import 'package:dmetrics/dmetrics.dart';

/// Per-metric invariants the harness asserts on every result (SPEC §6.1, §6.3).
class ResultInvariants {
  /// Score of an empty scope: `measured == base + Σ contributors.increment`.
  /// Null skips the check for metrics whose value is not a sum (e.g. max).
  final num? base;

  /// Expected aggregated value under `include_in_parent`, given the parent's
  /// own measured value and the direct children's aggregated values.
  final num Function(num measured, List<num> childValues) rollUp;

  const ResultInvariants({required this.base, required this.rollUp});

  /// Base 1 and `measured + Σ(child.value − 1)`: the cyclomatic definition.
  static const cyclomaticStyle = ResultInvariants(
    base: 1,
    rollUp: _cyclomaticRollUp,
  );

  static num _cyclomaticRollUp(num measured, List<num> childValues) =>
      childValues.fold<num>(measured, (acc, v) => acc + (v - 1));
}

/// Checks one result against the structural and metric invariants. Returns
/// human-readable violations; empty means the result is sound.
List<String> checkResultInvariants({
  required FileReport file,
  required ScopeResult scope,
  required String metricId,
  required MetricResult result,
  required Set<ScopeKind> measures,
  required ClosureRollup policy,
  required ResultInvariants invariants,
}) {
  final out = <String>[];
  final m = result.measurement;
  final where = '${scope.scope.qualifiedName} [$metricId]';

  if (m.metricId != metricId) {
    out.add('$where: measurement.metricId is `${m.metricId}`');
  }
  if (m.scope != scope.id) {
    out.add(
      '$where: measurement.scope is `${m.scope}`, expected `${scope.id}`',
    );
  }
  if (scope.scope.partial != file.partial) {
    out.add(
      '$where: scope.partial=${scope.scope.partial} but '
      'file.partial=${file.partial}',
    );
  }

  final base = invariants.base;
  if (base != null) {
    final sum = m.contributors.fold<num>(0, (acc, c) => acc + c.increment);
    if (m.value != base + sum) {
      out.add(
        '$where: measured=${m.value} but base $base + '
        'Σ contributors $sum = ${base + sum} (${m.contributorSummary})',
      );
    }
  }

  final span = scope.scope.span;
  for (final c in m.contributors) {
    if (c.span.file.url != span.file.url ||
        c.span.start.offset < span.start.offset ||
        c.span.end.offset > span.end.offset) {
      out.add(
        '$where: contributor $c at ${c.span.start.offset}..'
        '${c.span.end.offset} lies outside the scope span '
        '${span.start.offset}..${span.end.offset}',
      );
    }
  }

  // Direct measured children: scopes whose nearest measured ancestor is this
  // scope and which carry a result for this metric.
  final directChildren = <ScopeResult>[
    for (final other in file.scopes)
      if (other.results.containsKey(metricId) &&
          other.scope.nearestAncestor(measures)?.id == scope.id)
        other,
  ];

  switch (policy) {
    case ClosureRollup.separate:
      if (result.value != m.value) {
        out.add(
          '$where: policy separate but value=${result.value} != '
          'measured=${m.value}',
        );
      }
      if (result.includes.isNotEmpty) {
        out.add('$where: policy separate but includes=${result.includes}');
      }
    case ClosureRollup.includeInParent:
      final childValues = <num>[];
      for (final id in result.includes) {
        final child = file.scopeById(id);
        if (child == null) {
          out.add('$where: includes unknown scope `$id`');
          continue;
        }
        if (child.scope.nearestAncestor(measures)?.id != scope.id) {
          out.add(
            '$where: includes `$id`, which is not a direct measured child',
          );
          continue;
        }
        final childResult = child.results[metricId];
        if (childResult == null) {
          out.add('$where: includes `$id`, which has no `$metricId` result');
          continue;
        }
        childValues.add(childResult.value);
      }
      for (final child in directChildren) {
        if (!result.includes.contains(child.id)) {
          out.add('$where: direct child `${child.id}` missing from includes');
        }
      }
      final expected = invariants.rollUp(m.value, childValues);
      if (result.value != expected) {
        out.add(
          '$where: value=${result.value} but rollUp(measured=${m.value}, '
          'children=$childValues) = $expected',
        );
      }
  }

  return out;
}
