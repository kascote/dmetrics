import '../engine/result.dart';

/// Aggregation policy for closures and local functions (§6.3).
enum ClosureRollup { separate, includeInParent }

enum FailOn { warn, fail }

/// Run-global settings: identical across every config root in a run.
class RunConfig {
  final ClosureRollup closureRollup;
  final FailOn failOn;

  /// Counting knobs keyed `<metric>.<knob>`, e.g. `cyclomatic.count_case_arms`.
  /// Metrics read their own keys and apply documented defaults.
  final Map<String, Object?> settings;

  const RunConfig({
    this.closureRollup = ClosureRollup.separate,
    this.failOn = FailOn.fail,
    this.settings = const {},
  });

  RunConfig copyWith({
    ClosureRollup? closureRollup,
    FailOn? failOn,
    Map<String, Object?>? settings,
  }) => RunConfig(
    closureRollup: closureRollup ?? this.closureRollup,
    failOn: failOn ?? this.failOn,
    settings: settings ?? this.settings,
  );
}

/// Per-metric settings within one config root.
class MetricConfig {
  final bool enabled;
  final Threshold? threshold;

  const MetricConfig({this.enabled = true, this.threshold});
}

/// Per-root settings: may differ between config roots.
class RootConfig {
  /// Keyed by metric id. Metrics absent here are enabled with no threshold.
  final Map<String, MetricConfig> metrics;

  const RootConfig({this.metrics = const {}});

  static const RootConfig defaults = RootConfig();

  MetricConfig metric(String id) => metrics[id] ?? const MetricConfig();
}

/// Everything the engine needs besides sources and metrics.
class AnalysisConfig {
  final RunConfig run;

  /// Keyed by run-root-relative config root, matching `SourceFile.configRoot`.
  final Map<String, RootConfig> roots;

  const AnalysisConfig({
    this.run = const RunConfig(),
    this.roots = const {'.': RootConfig.defaults},
  });

  RootConfig root(String configRoot) =>
      roots[configRoot] ?? RootConfig.defaults;

  AnalysisConfig copyWith({RunConfig? run, Map<String, RootConfig>? roots}) =>
      AnalysisConfig(run: run ?? this.run, roots: roots ?? this.roots);
}
