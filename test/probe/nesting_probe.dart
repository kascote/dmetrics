/// Throwaway nesting-depth probe (SPEC §8, M1). Never ships.
///
/// It proves the traversal contract before cyclomatic is built on it:
/// depth goes up on node enter and DOWN ON NODE EXIT, and state is kept per
/// scope keyed by the context delivered with each event, never on a stack.
/// So a missing exit event leaves depth inflated for later siblings, and a
/// node delivered with the wrong context inflates the wrong scope.
library;

import 'dart:math' as math;

import 'package:analyzer/dart/ast/ast.dart';
import 'package:dmetrics/dmetrics.dart';

class NestingProbe extends Metric {
  @override
  String get id => 'nesting';

  @override
  MetricRequirements get requirements => MetricRequirements.syntactic;

  @override
  Set<ScopeKind> get measures => ScopeKind.measuredInV1;

  final _state = <ScopeId, _Depth>{};

  @override
  void onEnterScope(ScopeContext ctx) {
    if (_state.containsKey(ctx.id)) {
      throw StateError('scope ${ctx.id} entered twice');
    }
    _state[ctx.id] = _Depth();
  }

  @override
  Measurement onExitScope(ScopeContext ctx) {
    final d = _state.remove(ctx.id);
    if (d == null) throw StateError('scope ${ctx.id} exited without enter');
    if (d.current != 0) {
      throw StateError('scope ${ctx.id} exited at depth ${d.current}');
    }
    return Measurement(
      metricId: id,
      scope: ctx.id,
      value: d.max,
      contributors: const [],
    );
  }

  @override
  void onEnterNode(AstNode node, ScopeContext ctx) {
    if (!_nests(node)) return;
    final d = _state[ctx.id];
    if (d == null) return; // structural context: nothing to measure
    d.current++;
    d.max = math.max(d.max, d.current);
  }

  @override
  void onExitNode(AstNode node, ScopeContext ctx) {
    if (!_nests(node)) return;
    _state[ctx.id]?.current--;
  }

  /// Nesting is the max over the scope and its rolled-up children.
  @override
  Measurement rollUp(Measurement parent, List<Measurement> children) =>
      Measurement(
        metricId: parent.metricId,
        scope: parent.scope,
        value: children.fold<num>(parent.value, (m, c) => math.max(m, c.value)),
        contributors: parent.contributors,
      );

  static bool _nests(AstNode node) =>
      node is IfStatement ||
      node is ForStatement ||
      node is WhileStatement ||
      node is DoStatement ||
      node is SwitchStatement ||
      node is TryStatement;
}

class _Depth {
  int current = 0;
  int max = 0;
}
