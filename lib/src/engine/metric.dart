import 'package:analyzer/dart/ast/ast.dart';

import '../config/config.dart';
import 'measurement.dart';
import 'result.dart';
import 'scope.dart';

enum MetricRequirements { syntactic, resolved }

/// Run-level context handed to [Metric.finish]. Gains a resolved-context
/// accessor when the resolved pipeline lands.
class RunContext {
  final AnalysisConfig config;

  const RunContext(this.config);
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
  Iterable<Measurement> finish(RunContext ctx) => const [];
}
