/// Hardcoded dummy metrics for exercising the harness (M0). Not shipped.
library;

import 'package:analyzer/dart/ast/ast.dart';
import 'package:metra/metra.dart';

/// `1 + number of if statements` per measured scope, with one `if`
/// contributor per statement. Shaped like cyclomatic so the same invariants
/// apply, including the cyclomatic-style roll-up.
class IfCountMetric extends Metric {
  @override
  String get id => 'ifcount';

  @override
  MetricRequirements get requirements => MetricRequirements.syntactic;

  @override
  Set<ScopeKind> get measures => ScopeKind.measuredInV1;

  final _stack = <List<Contributor>>[];

  @override
  void onEnterScope(ScopeContext ctx) => _stack.add([]);

  @override
  Measurement onExitScope(ScopeContext ctx) {
    final contributors = _stack.removeLast();
    return Measurement(
      metricId: id,
      scope: ctx.id,
      value: 1 + contributors.length,
      contributors: contributors,
    );
  }

  @override
  void onEnterNode(AstNode node, ScopeContext ctx) {
    if (node is IfStatement && _stack.isNotEmpty) {
      _stack.last.add(
        Contributor(
          kind: 'if',
          increment: 1,
          span: ctx.spanOfRange(
            node.ifKeyword.offset,
            node.rightParenthesis.end,
          ),
        ),
      );
    }
  }

  @override
  void onExitNode(AstNode node, ScopeContext ctx) {}

  @override
  Measurement rollUp(Measurement parent, List<Measurement> children) =>
      Measurement(
        metricId: parent.metricId,
        scope: parent.scope,
        value: children.fold<num>(
          parent.value,
          (acc, c) => acc + (c.value - 1),
        ),
        contributors: parent.contributors,
      );
}

/// Always 1, no contributors. A second metric for multi-metric annotations.
class ConstantMetric extends Metric {
  @override
  String get id => 'one';

  @override
  MetricRequirements get requirements => MetricRequirements.syntactic;

  @override
  Set<ScopeKind> get measures => ScopeKind.measuredInV1;

  @override
  void onEnterScope(ScopeContext ctx) {}

  @override
  Measurement onExitScope(ScopeContext ctx) => Measurement(
    metricId: id,
    scope: ctx.id,
    value: 1,
    contributors: const [],
  );

  @override
  void onEnterNode(AstNode node, ScopeContext ctx) {}

  @override
  void onExitNode(AstNode node, ScopeContext ctx) {}
}
