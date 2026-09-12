/// Cognitive complexity, after SonarSource's definition, adapted to Dart.
///
/// Base score 0. Every break in the linear flow of a scope counts 1 plus the
/// number of flow-breaking structures it is nested in, so a deeply nested
/// `if` costs more than the same `if` at the top of a body. `else if` and
/// `else` count 1 with no nesting increment: a chain reads flat. A `switch`
/// counts once however many arms it has: the arms are a table, and so are
/// their patterns and guards. A run of the same boolean operator counts once;
/// the operator changing starts a new run. A labeled `break` or `continue`
/// counts 1. Null-aware shorthand (`??`, `??=`, `?.`, `?x`, `...?`) counts 0:
/// it collapses statements the reader would otherwise have to follow, which
/// is why cyclomatic's boilerplate hits (`copyWith`, `==`, case tables) score
/// low here.
///
/// Nesting is tracked per scope from the node events: the body of a nesting
/// structure is one level deeper than the structure itself, its condition is
/// not. A closure or local function is its own scope whose body starts one
/// level deeper than the point where it is written, so folding it into its
/// parent under `include_in_parent` reproduces the whole-method number. A
/// closure in a field or top-level initializer has no enclosing body and
/// starts at level 0, like a function.
library;

import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/syntactic_entity.dart';
import 'package:analyzer/dart/ast/token.dart';

import '../../engine/measurement.dart';
import '../../engine/metric.dart';
import '../../engine/result.dart';
import '../../engine/scope.dart';

class CognitiveMetric extends Metric {
  static const metricId = 'cognitive';

  final _open = <ScopeId, _OpenScope>{};

  @override
  String get id => metricId;

  @override
  MetricRequirements get requirements => MetricRequirements.syntactic;

  @override
  Set<ScopeKind> get measures => ScopeKind.measuredInV1;

  /// Sonar's default is 15 per function. Calibrated at M5 over the field
  /// trial corpus: see the spec for the numbers.
  @override
  Threshold? get defaultThreshold => const Threshold(warn: 15, fail: 25);

  @override
  void onEnterScope(ScopeContext ctx) {
    // A scope nested in a measured scope starts one level deeper than the
    // point where it is written; one under a structural context (a field or
    // top-level initializer) starts at 0.
    final parent = _open[ctx.parent?.id];
    _open[ctx.id] = _OpenScope(parent == null ? 0 : parent.depth + 1);
  }

  @override
  Measurement onExitScope(ScopeContext ctx) {
    final scope = _open.remove(ctx.id)!;
    assert(
      scope.depth == scope.base,
      'scope ${ctx.id} exited at depth ${scope.depth}, entered at ${scope.base}',
    );
    // An `else` arrives after everything in the branch before it; report in
    // source order.
    final contributors = scope.contributors
      ..sort((a, b) => a.span.start.offset.compareTo(b.span.start.offset));
    return Measurement(
      metricId: id,
      scope: ctx.id,
      value: contributors.fold<num>(0, (acc, c) => acc + c.increment),
      contributors: contributors,
    );
  }

  @override
  void onEnterNode(AstNode node, ScopeContext ctx) {
    // Nodes under a structural context (field and top-level initializers
    // outside any closure) have nowhere to count: ignored, as cyclomatic
    // does.
    final scope = _open[ctx.id];
    if (scope == null) return;
    // The body of a structure is one level deeper than the structure, so
    // step in before scoring a node that is itself such a body.
    if (_isNestedBody(node)) scope.depth++;
    // A node in an `else` position is the chain link and, if it is itself a
    // structure (`else for`, `else switch`), that structure too.
    final link = _elseContributor(node, scope.depth, ctx);
    if (link != null) scope.contributors.add(link);
    final c = _contributorFor(node, scope.depth, ctx);
    if (c != null) scope.contributors.add(c);
  }

  @override
  void onExitNode(AstNode node, ScopeContext ctx) {
    if (_isNestedBody(node)) _open[ctx.id]?.depth--;
  }

  /// `parent.measured + Σ child.value`: a child's score already includes the
  /// nesting of the point where it is written, so the sum is the number the
  /// whole method would score as one body.
  @override
  Measurement rollUp(Measurement parent, List<Measurement> children) =>
      Measurement(
        metricId: parent.metricId,
        scope: parent.scope,
        value: children.fold<num>(parent.value, (acc, c) => acc + c.value),
        contributors: parent.contributors,
        detail: parent.detail,
      );

  /// True when [node] is read one level deeper than its parent: the body of
  /// a loop or `catch`, either branch of an `if` or a ternary, an arm of a
  /// `switch`. Conditions and scrutinees stay at the parent's level. An
  /// `else if` is not a body: the chain reads flat, and its own branches
  /// step in from the chain's level.
  static bool _isNestedBody(AstNode node) {
    final parent = node.parent;
    return switch (parent) {
      IfStatement() =>
        identical(parent.thenStatement, node) ||
            (identical(parent.elseStatement, node) && node is! IfStatement),
      IfElement() =>
        identical(parent.thenElement, node) ||
            (identical(parent.elseElement, node) && node is! IfElement),
      ForStatement() => identical(parent.body, node),
      ForElement() => identical(parent.body, node),
      WhileStatement() => identical(parent.body, node),
      DoStatement() => identical(parent.body, node),
      CatchClause() => identical(parent.body, node),
      ConditionalExpression() =>
        identical(parent.thenExpression, node) ||
            identical(parent.elseExpression, node),
      SwitchStatement() => node is SwitchMember,
      SwitchExpression() => node is SwitchExpressionCase,
      _ => false,
    };
  }

  /// The `else` keyword before [node] when [node] is the else branch of an
  /// `if` statement or element and not an `else if`: +1 with no nesting
  /// increment, the chain reads flat.
  static Contributor? _elseContributor(
    AstNode node,
    int depth,
    ScopeContext ctx,
  ) {
    final parent = node.parent;
    final Token? keyword = switch (parent) {
      IfStatement()
          when identical(parent.elseStatement, node) && node is! IfStatement =>
        parent.elseKeyword,
      IfElement()
          when identical(parent.elseElement, node) && node is! IfElement =>
        parent.elseKeyword,
      _ => null,
    };
    if (keyword == null) return null;
    // The link sits one level out from the branch it opens, which was
    // stepped into just above.
    return Contributor(
      kind: 'else',
      family: _family('if', depth - 1),
      increment: 1,
      span: ctx.spanOf(keyword),
    );
  }

  /// What the table-shaped marker pools: a kind at a nesting level. A run of
  /// `if`s at one level is a table; a ladder of `if`s each inside the last
  /// is a tangle, and pooling by kind alone would mark it a table. `else if`
  /// and `else` are links in an `if` chain and pool with it. Reads `if` at
  /// the top of a body, `if@2` two levels down.
  static String _family(String kind, int depth) =>
      depth == 0 ? kind : '$kind@$depth';

  /// The whole decision table as one `switch`; cyclomatic counts its arms.
  // ignore: dmetrics_cyclomatic
  Contributor? _contributorFor(AstNode node, int depth, ScopeContext ctx) {
    Contributor c(
      String kind,
      String family,
      int increment,
      SyntacticEntity start, [
      SyntacticEntity? end,
    ]) => Contributor(
      kind: kind,
      family: family,
      increment: increment,
      span: ctx.spanOfRange(start.offset, (end ?? start).end),
    );
    // A structure pays for its nesting; a chain link or a jump does not.
    Contributor nested(String kind, SyntacticEntity s, [SyntacticEntity? e]) =>
        c(kind, _family(kind, depth), 1 + depth, s, e);
    Contributor flat(String kind, SyntacticEntity s, [SyntacticEntity? e]) =>
        c(kind, kind, 1, s, e);
    Contributor elseIf(SyntacticEntity s, SyntacticEntity e) =>
        c('else-if', _family('if', depth), 1, s, e);

    final parent = node.parent;
    switch (node) {
      // if / else if / else, as statements and as collection elements.
      // `if-case` is an `if`: one test, its pattern and guard are the test.
      case IfStatement()
          when parent is IfStatement && identical(parent.elseStatement, node):
        return elseIf(parent.elseKeyword!, node.rightParenthesis);
      case IfStatement():
        return nested('if', node.ifKeyword, node.rightParenthesis);
      case IfElement()
          when parent is IfElement && identical(parent.elseElement, node):
        return elseIf(parent.elseKeyword!, node.rightParenthesis);
      case IfElement():
        return nested('if', node.ifKeyword, node.rightParenthesis);

      // Loops, as statements and as collection elements.
      case ForStatement():
        return nested(
          'loop',
          node.awaitKeyword ?? node.forKeyword,
          node.rightParenthesis,
        );
      case ForElement():
        return nested(
          'loop',
          node.awaitKeyword ?? node.forKeyword,
          node.rightParenthesis,
        );
      case WhileStatement():
        return nested('loop', node.whileKeyword, node.rightParenthesis);
      case DoStatement():
        return nested('loop', node.doKeyword);

      // One per switch; arms, patterns, `when` guards and `||` patterns are
      // the table, not flow.
      case SwitchStatement():
        return nested('switch', node.switchKeyword, node.rightParenthesis);
      case SwitchExpression():
        return nested('switch', node.switchKeyword, node.rightParenthesis);

      case CatchClause():
        final start = node.onKeyword ?? node.catchKeyword!;
        final end = node.rightParenthesis ?? node.exceptionType!;
        return nested('catch', start, end);

      case ConditionalExpression():
        return nested('ternary', node.question);

      // One per run of the same operator: `a && b && c` is one decision to
      // read, `a && b || c` is two. `!` is 0.
      case BinaryExpression(:final operator)
          when _isBooleanOperator(operator) && !_continuesRun(node):
        return flat(operator.lexeme, _runStart(node).operator);

      // A labeled jump is a `goto` the reader has to chase.
      case BreakStatement(:final label?):
        return flat('break', node.breakKeyword, label);
      case ContinueStatement(:final label?):
        return flat('continue', node.continueKeyword, label);

      default:
        return null;
    }
  }

  static bool _isBooleanOperator(Token operator) =>
      operator.type == TokenType.AMPERSAND_AMPERSAND ||
      operator.type == TokenType.BAR_BAR;

  /// True when the enclosing expression, through parentheses, is the same
  /// operator: the reader is still in the same run.
  static bool _continuesRun(BinaryExpression node) {
    var p = node.parent;
    while (p is ParenthesizedExpression) {
      p = p.parent;
    }
    return p is BinaryExpression && p.operator.type == node.operator.type;
  }

  /// The leftmost operator of the run [node] ends, so the contributor points
  /// at where the run starts in the source.
  static BinaryExpression _runStart(BinaryExpression node) {
    var start = node;
    while (true) {
      Expression left = start.leftOperand;
      while (left is ParenthesizedExpression) {
        left = left.expression;
      }
      if (left is BinaryExpression &&
          left.operator.type == node.operator.type) {
        start = left;
      } else {
        return start;
      }
    }
  }
}

class _OpenScope {
  /// Nesting level of the scope's body.
  final int base;
  int depth;
  final contributors = <Contributor>[];

  _OpenScope(this.base) : depth = base;
}
