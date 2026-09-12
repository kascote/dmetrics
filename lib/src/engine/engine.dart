import '../config/config.dart';
import 'directives.dart';
import 'driver.dart';
import 'measurement.dart';
import 'metric.dart';
import 'parse.dart';
import 'pipeline.dart';
import 'report.dart';
import 'scope.dart';
import 'source.dart';

/// Pure entry point: in-memory sources in, report out. Never touches the
/// file system.
///
/// One instance per metric per run: `onStartRun` fires once before the first
/// file, `finish` once after the last. Files are reported in path order.
/// Throws [ArgumentError] when two sources share a path, since ids would
/// collide across files, and [UnsupportedError] when a metric requires the
/// resolved pipeline, which does not exist yet.
Report analyze(
  List<SourceFile> sources,
  List<Metric> metrics,
  AnalysisConfig config,
) {
  _checkUnique(sources, metrics);
  final level = _pipelineLevel(metrics);
  final runCtx = RunContext(
    config,
    libraries: level == MetricRequirements.directive
        ? LibraryIndex(sources)
        : null,
  );
  for (final m in metrics) {
    m.onStartRun(runCtx);
  }

  final ordered = [...sources]..sort((a, b) => a.path.compareTo(b.path));
  final traversed = [for (final s in ordered) _traverse(s, metrics, config)];
  final runLevel = _applyFinish(metrics, runCtx, traversed);

  return Report(
    config: config,
    files: [
      for (final t in traversed)
        FileReport(
          source: t.parsed.source,
          diagnostics: t.parsed.diagnostics,
          scopes: buildResults(
            measured: t.measured,
            metrics: t.active,
            effective: t.effective,
            run: config.run,
            suppressions: t.parsed.suppressions,
          ),
        ),
    ],
    runMeasurements: runLevel,
  );
}

void _checkUnique(List<SourceFile> sources, List<Metric> metrics) {
  final seen = <String>{};
  for (final s in sources) {
    if (!seen.add(s.path)) {
      throw ArgumentError.value(s.path, 'sources', 'duplicate source path');
    }
  }
  final ids = <String>{};
  for (final m in metrics) {
    if (!ids.add(m.id)) {
      throw ArgumentError.value(m.id, 'metrics', 'duplicate metric id');
    }
  }
}

/// One pipeline per run: the most demanding level any metric asks for.
/// Levels are ordered by cost, so the maximum is the run's level.
MetricRequirements _pipelineLevel(List<Metric> metrics) {
  var level = MetricRequirements.syntactic;
  for (final m in metrics) {
    if (m.requirements.index > level.index) level = m.requirements;
  }
  if (level == MetricRequirements.resolved) {
    throw UnsupportedError(
      'the resolved pipeline is not implemented; required by '
      '${[for (final m in metrics)
        if (m.requirements == level) m.id]}',
    );
  }
  return level;
}

/// Collects every metric's finish measurements. One that names a traversed
/// scope replaces that scope's measurement for the metric; the rest are
/// returned as run-level. A metric disabled for a file by config has no say
/// over that file's scopes.
List<Measurement> _applyFinish(
  List<Metric> metrics,
  RunContext runCtx,
  List<_Traversal> traversed,
) {
  final byScope = <ScopeId, (_Traversal, ScopeMeasurements)>{};
  for (final t in traversed) {
    for (final m in t.measured) {
      byScope[m.scope.id] = (t, m);
    }
  }
  final runLevel = <Measurement>[];
  for (final m in metrics) {
    for (final fm in m.finish(runCtx)) {
      if (fm.metricId != m.id) {
        throw ArgumentError.value(
          fm.metricId,
          'finish',
          'metric ${m.id} emitted a measurement for another metric',
        );
      }
      switch (byScope[fm.scope]) {
        case null:
          runLevel.add(fm);
        case (final t, final scope) when t.active.contains(m):
          scope.measurements[m.id] = fm;
        case _:
          break;
      }
    }
  }
  return runLevel;
}

/// One file after traversal, before the result pipeline.
class _Traversal {
  final ParsedSource parsed;
  final List<Metric> active;
  final Map<String, MetricConfig> effective;
  final List<ScopeMeasurements> measured;

  const _Traversal({
    required this.parsed,
    required this.active,
    required this.effective,
    required this.measured,
  });
}

_Traversal _traverse(
  SourceFile source,
  List<Metric> metrics,
  AnalysisConfig config,
) {
  final parsed = parseSource(source);
  final root = config.root(source.configRoot);
  final relative = pathRelativeToRoot(source.path, source.configRoot);
  final effective = {
    for (final m in metrics) m.id: root.metric(m.id, relativePath: relative),
  };
  final active = [
    for (final m in metrics)
      if (effective[m.id]!.isEnabled) m,
  ];
  final driver = Driver(
    file: parsed.file,
    path: source.path,
    libraryName: libraryNameOf(source),
    metrics: active,
    partial: parsed.partial,
  )..run(parsed.unit);
  return _Traversal(
    parsed: parsed,
    active: active,
    effective: effective,
    measured: driver.measured,
  );
}
