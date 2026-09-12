import 'package:analyzer/dart/ast/ast.dart';

import '../config/config.dart';
import 'directives.dart';
import 'measurement.dart';
import 'result.dart';
import 'scope.dart';

/// What a metric needs from the engine, cheapest first. A run has exactly
/// one pipeline: the most demanding level any of its metrics asks for. Every
/// metric then consumes that pipeline's ASTs, so a syntactic metric must
/// produce the same numbers whatever level the run ended up at.
enum MetricRequirements {
  /// Parsed ASTs.
  syntactic,

  /// Parsed ASTs plus a [LibraryIndex] over the run's sources, so directive
  /// URIs resolve to libraries. Costs a map over the source list, nothing
  /// more; enough for import graphs.
  directive,

  /// Resolved ASTs and the element model. Not implemented: the engine
  /// refuses a run that asks for it.
  resolved,
}

/// Run-level context handed to [Metric.onStartRun] and [Metric.finish].
class RunContext {
  final AnalysisConfig config;

  /// Directive resolution over the run's sources. Non-null only when the
  /// run's pipeline is at least [MetricRequirements.directive]; a syntactic
  /// run never builds it, so it never pays for it.
  final LibraryIndex? libraries;

  const RunContext(this.config, {this.libraries});
}

/// A passive consumer of the engine's single traversal.
///
/// One instance per metric per run. Scope events are properly nested and
/// bracketed; node events fire for every node in the file. Metrics keep
/// per-scope state keyed by [ScopeId] (or a stack) and no cross-file state
/// unless they emit from [finish].
abstract class Metric {
  /// e.g. `cyclomatic`.
  String get id;

  MetricRequirements get requirements;

  /// Scope kinds this metric measures. The engine emits scope events ONLY for
  /// these kinds, so adding `class_` or `library` measurements later cannot
  /// change this metric's output.
  Set<ScopeKind> get measures;

  /// Run-global knobs this metric reads, keyed `<id>.<knob>`, with their
  /// documented defaults. The config loader validates values against the
  /// default's type and reports every knob in the JSON `run` section.
  Map<String, Object?> get settingDefaults => const {};

  /// Thresholds that apply when no config root sets any. Null means every
  /// verdict is `ok` until a threshold is configured; `thresholds: none` in
  /// a config opts out of a non-null default.
  Threshold? get defaultThreshold => null;

  /// Fires once per run before the first file. Metrics read their run-global
  /// knobs from `ctx.config.run.settings` here.
  void onStartRun(RunContext ctx) {}

  void onEnterScope(ScopeContext ctx);

  Measurement onExitScope(ScopeContext ctx);

  /// Pre-order node enter. [ctx] is the innermost open context of any kind,
  /// structural or measured, and is never null.
  void onEnterNode(AstNode node, ScopeContext ctx);

  /// Post-order node exit.
  void onExitNode(AstNode node, ScopeContext ctx);

  /// Roll-up hook (§6.3), called only when the run's policy asks for
  /// aggregation. [children] are the direct measured children with their
  /// already-aggregated values. Default: [parent] unchanged.
  Measurement rollUp(Measurement parent, List<Measurement> children) => parent;

  /// Run-level finalization after every file has been traversed. Syntactic
  /// metrics return nothing.
  ///
  /// A measurement whose scope is one this metric measured during traversal
  /// replaces what [onExitScope] returned for it, so a graph metric can
  /// return a provisional value per library and finalize it once the whole
  /// graph is known; the replacement then flows through aggregation,
  /// suppression and thresholds like any other. A measurement for a scope
  /// the run did not traverse is reported at run level. Every measurement
  /// must carry this metric's [id].
  Iterable<Measurement> finish(RunContext ctx) => const [];
}
