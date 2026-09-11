import '../config/config.dart';
import 'driver.dart';
import 'metric.dart';
import 'parse.dart';
import 'pipeline.dart';
import 'report.dart';
import 'source.dart';

/// Pure entry point: in-memory sources in, report out. Never touches the
/// file system.
///
/// One instance per metric per run: `onStartRun` fires once before the first
/// file, `finish` once after the last. Files are reported in path order.
/// Throws [ArgumentError] when two sources share a path, since ids would
/// collide across files.
Report analyze(
  List<SourceFile> sources,
  List<Metric> metrics,
  AnalysisConfig config,
) {
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

  final runCtx = RunContext(config);
  for (final m in metrics) {
    m.onStartRun(runCtx);
  }

  final ordered = [...sources]..sort((a, b) => a.path.compareTo(b.path));
  final files = [for (final s in ordered) _analyzeFile(s, metrics, config)];

  final finish = [for (final m in metrics) ...m.finish(runCtx)];
  return Report(config: config, files: files, runMeasurements: finish);
}

FileReport _analyzeFile(
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
    metrics: active,
    partial: parsed.partial,
  )..run(parsed.unit);
  return FileReport(
    source: source,
    diagnostics: parsed.diagnostics,
    scopes: buildResults(
      measured: driver.measured,
      metrics: active,
      effective: effective,
      run: config.run,
      suppressions: parsed.suppressions,
    ),
  );
}
