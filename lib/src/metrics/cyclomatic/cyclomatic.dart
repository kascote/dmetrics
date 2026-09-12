/// Cyclomatic complexity (SPEC §6).
///
/// Base score 1 per measured scope, plus one per construct in the §6.1
/// decision table. The null-aware convention: count a construct when the
/// author wrote both paths (`??` has a right operand; `?.` short-circuits to
/// nothing). Irrefutability is decided syntactically: a pattern is
/// irrefutable iff it is a bare `_`, an untyped `var x` / `final x`, or a
/// parenthesized irrefutable pattern.
library;

import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/syntactic_entity.dart';
import 'package:analyzer/dart/ast/token.dart';

import '../../config/threshold.dart';
import '../../engine/measurement.dart';
import '../../engine/metric.dart';
import '../../engine/scope.dart';

class CyclomaticMetric extends Metric {
  static const metricId = 'cyclomatic';

  /// Knob: count `??` and `??=` (Lizard does, SonarQube does not).
  static const knobNullCoalescing = 'cyclomatic.count_null_coalescing';

  /// Knob: count each refutable `case` arm (`true`) or one per switch
  /// (`false`, the "modified" McCabe convention). `when` guards and
  /// logical-or patterns count under either setting.
  static const knobCaseArms = 'cyclomatic.count_case_arms';

  bool _countNullCoalescing = true;
  bool _countCaseArms = true;

  final _open = <ScopeId, List<Contributor>>{};

  @override
  String get id => metricId;

  @override
  MetricRequirements get requirements => MetricRequirements.syntactic;

  @override
  Set<ScopeKind> get measures => ScopeKind.measuredInV1;

  @override
  Map<String, Object?> get settingDefaults => const {
    knobNullCoalescing: true,
    knobCaseArms: true,
  };

  /// Decided at M4 with data: across eleven trial codebases `warn` at 10
  /// sat near the 90th–95th percentile and `fail` at 20 was precise.
  @override
  Threshold? get defaultThreshold => const Threshold(warn: 10, fail: 20);

  @override
  void onStartRun(RunContext ctx) {
    final settings = ctx.config.run.settings;
    _countNullCoalescing = _bool(settings, knobNullCoalescing, true);
    _countCaseArms = _bool(settings, knobCaseArms, true);
  }

  static bool _bool(Map<String, Object?> settings, String key, bool fallback) {
    final v = settings[key];
    if (v == null) return fallback;
    if (v is bool) return v;
    throw ArgumentError.value(v, key, 'expected true or false');
  }

  @override
  void onEnterScope(ScopeContext ctx) => _open[ctx.id] = [];

  @override
  Measurement onExitScope(ScopeContext ctx) {
    // Node events are pre-order, so an operator inside a condition arrives
    // after the construct that contains it; report in source order.
    final contributors = _open.remove(ctx.id)!
      ..sort((a, b) => a.span.start.offset.compareTo(b.span.start.offset));
    return Measurement(
      metricId: id,
      scope: ctx.id,
      value: contributors.fold<num>(1, (acc, c) => acc + c.increment),
      contributors: contributors,
    );
  }

  @override
  void onEnterNode(AstNode node, ScopeContext ctx) {
    // Nodes under a structural context (field and top-level initializers
    // outside any closure) have nowhere to count: ignored in v1 (§6.1).
    final contributors = _open[ctx.id];
    if (contributors == null) return;
    final c = _contributorFor(node, ctx);
    if (c != null) contributors.add(c);
  }

  @override
  void onExitNode(AstNode node, ScopeContext ctx) {}

  /// `parent.measured + Σ(child.value − 1)`: each child's base score is
  /// excluded (§6.3).
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
        detail: parent.detail,
      );

  /// Kinds pooled for the table-shaped marker. A `switch` arm is one
  /// increment for its pattern, one more per `||` in it and one for its
  /// `when` guard; all three are that arm, so a table of guarded arms is
  /// still one table.
  static const _families = {'pattern-or': 'case', 'when': 'case'};

  /// The whole decision table as one `switch`: 37 by its own measure and
  /// marked table-shaped, but the marker never changes a verdict.
  // ignore: dmetrics_cyclomatic
  Contributor? _contributorFor(AstNode node, ScopeContext ctx) {
    Contributor c(String kind, SyntacticEntity start, [SyntacticEntity? end]) =>
        Contributor(
          kind: kind,
          family: _families[kind],
          increment: 1,
          span: ctx.spanOfRange(start.offset, (end ?? start).end),
        );

    switch (node) {
      // if / if-case, as statements and as collection elements.
      case IfStatement():
        return c(
          node.caseClause == null ? 'if' : 'if-case',
          node.ifKeyword,
          node.rightParenthesis,
        );
      case IfElement():
        return c(
          node.caseClause == null ? 'if' : 'if-case',
          node.ifKeyword,
          node.rightParenthesis,
        );

      // Loops, as statements and as collection elements.
      case ForStatement():
        return c(
          'loop',
          node.awaitKeyword ?? node.forKeyword,
          node.rightParenthesis,
        );
      // A null-aware element inserts or omits one element, which is what
      // `if (x != null) x` does and counts as an `if`; the lint that
      // rewrites one into the other must not move the score. `?.` stays 0:
      // it passes null through an expression written once, and counting it
      // buys boilerplate hits (`lerp`, `copyWith`), not tangles.
      case NullAwareElement():
        return c('if', node.question, node.value);
      case MapLiteralEntry(:final keyQuestion, :final valueQuestion)
          when keyQuestion != null || valueQuestion != null:
        return c('if', keyQuestion ?? node.key, node.value);
      case ForElement():
        return c(
          'loop',
          node.awaitKeyword ?? node.forKeyword,
          node.rightParenthesis,
        );
      case WhileStatement():
        return c('loop', node.whileKeyword, node.rightParenthesis);
      case DoStatement():
        return c('loop', node.doKeyword);

      // switch: arms by default, one per switch under the knob.
      case SwitchStatement() when !_countCaseArms:
        return c('switch', node.switchKeyword, node.rightParenthesis);
      case SwitchExpression() when !_countCaseArms:
        return c('switch', node.switchKeyword, node.rightParenthesis);
      case SwitchPatternCase(:final guardedPattern)
          when _countCaseArms && !_isIrrefutable(guardedPattern.pattern):
        return c('case', guardedPattern.pattern);
      case SwitchExpressionCase(:final guardedPattern)
          when _countCaseArms && !_isIrrefutable(guardedPattern.pattern):
        return c('case', guardedPattern.pattern);
      case SwitchCase() when _countCaseArms:
        // Pre-pattern language versions: a constant expression, refutable.
        return c('case', node.expression);

      // Guards and patterns.
      case WhenClause():
        return c('when', node);
      case LogicalOrPattern():
        return c('pattern-or', node.operator);

      case CatchClause():
        final start = node.onKeyword ?? node.catchKeyword!;
        final end = node.rightParenthesis ?? node.exceptionType!;
        return c('catch', start, end);

      case ConditionalExpression():
        return c('ternary', node.question);
      case BinaryExpression(:final operator):
        return switch (operator.type) {
          TokenType.AMPERSAND_AMPERSAND => c('&&', operator),
          TokenType.BAR_BAR => c('||', operator),
          TokenType.QUESTION_QUESTION when _countNullCoalescing => c(
            '??',
            operator,
          ),
          _ => null,
        };
      case AssignmentExpression(:final operator)
          when operator.type == TokenType.QUESTION_QUESTION_EQ &&
              _countNullCoalescing:
        return c('??=', operator);

      default:
        return null;
    }
  }

  /// Syntactic irrefutability (§6): bare `_`, untyped binding, or a
  /// parenthesized irrefutable pattern. Everything else is a test.
  static bool _isIrrefutable(DartPattern pattern) => switch (pattern) {
    WildcardPattern(:final type) => type == null,
    DeclaredVariablePattern(:final type) => type == null,
    ParenthesizedPattern(:final pattern) => _isIrrefutable(pattern),
    _ => false,
  };
}
