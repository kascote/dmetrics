import 'package:analyzer/dart/ast/ast.dart';
import 'package:dmetrics/dmetrics.dart';

/// Records the event stream as readable lines for lifecycle assertions.
///
/// Node events are recorded only for [nodeTypes] (by runtime type name
/// without the `Impl` suffix) to keep sequences short.
class RecordingMetric extends Metric {
  final Set<ScopeKind> _measures;
  final Set<String> nodeTypes;
  final events = <String>[];
  final scopes = <ScopeContext>[];
  int startRuns = 0;
  int finishes = 0;

  /// The context handed to [onStartRun], for pipeline-selection assertions.
  RunContext? runContext;

  @override
  final String id;

  @override
  final MetricRequirements requirements;

  RecordingMetric({
    Set<ScopeKind> measures = ScopeKind.measuredInV1,
    this.nodeTypes = const {},
    this.id = 'recording',
    this.requirements = MetricRequirements.syntactic,
  }) : _measures = measures; // ignore: prefer_initializing_formals

  @override
  Set<ScopeKind> get measures => _measures;

  @override
  void onStartRun(RunContext ctx) {
    startRuns++;
    runContext = ctx;
  }

  @override
  void onEnterScope(ScopeContext ctx) {
    scopes.add(ctx);
    events.add('enterScope ${ctx.qualifiedName}');
  }

  @override
  Measurement onExitScope(ScopeContext ctx) {
    events.add('exitScope ${ctx.qualifiedName}');
    return Measurement(
      metricId: id,
      scope: ctx.id,
      value: 1,
      contributors: const [],
    );
  }

  @override
  void onEnterNode(AstNode node, ScopeContext ctx) =>
      _node('enterNode', node, ctx);

  @override
  void onExitNode(AstNode node, ScopeContext ctx) =>
      _node('exitNode', node, ctx);

  @override
  Iterable<Measurement> finish(RunContext ctx) {
    finishes++;
    return const [];
  }

  void _node(String event, AstNode node, ScopeContext ctx) {
    final type = typeName(node);
    if (nodeTypes.contains(type)) {
      events.add('$event $type ctx=${ctx.qualifiedName}');
    }
  }

  static String typeName(AstNode node) =>
      node.runtimeType.toString().replaceFirst(RegExp(r'Impl$'), '');
}

const testSource = SourceFile(path: 'lib/c.dart', content: '', configRoot: '.');

SourceFile src(String content, {String path = 'lib/c.dart'}) =>
    SourceFile(path: path, content: content, configRoot: '.');
