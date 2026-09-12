/// JSON report (SPEC §7.3). The schema is the tool's public interface; the
/// golden test pins it. Ordering is deterministic: configs by root, files by
/// path, scopes by start then end offset, contributors by start offset,
/// includes by the child's start offset.
library;

import 'dart:convert';

import 'package:source_span/source_span.dart' show FileSpan, SourceLocation;

import '../config/config.dart';
import '../engine/measurement.dart';
import '../engine/metric.dart';
import '../engine/pipeline.dart';
import '../config/threshold.dart';
import '../engine/report.dart';
import '../engine/result.dart';
import '../engine/scope.dart';
import '../version.dart';
import 'run_result.dart';

const schemaVersion = 1;

/// `full` emits every contributor; `summary` keeps only `contributorSummary`.
enum ContributorDetail { full, summary }

String renderJson(
  RunResult result, {
  ContributorDetail contributors = ContributorDetail.full,
}) =>
    const JsonEncoder.withIndent('  ')
        .convert(jsonReport(result, contributors: contributors));

Map<String, Object?> jsonReport(
  RunResult result, {
  ContributorDetail contributors = ContributorDetail.full,
}) {
  final config = result.config;
  final summary = result.summary;
  final roots = config.roots.keys.toList()..sort();
  return {
    'schemaVersion': schemaVersion,
    'tool': {'name': toolName, 'version': toolVersion},
    'status': result.status.name,
    'configs': [
      for (final root in roots) _config(root, config.roots[root]!, result),
    ],
    'run': {
      for (final m in result.metrics)
        if (m.settingDefaults.isNotEmpty)
          m.id: {
            for (final key in m.settingDefaults.keys)
              key.substring(m.id.length + 1):
                  config.run.settings[key] ?? m.settingDefaults[key],
          },
      RunConfig.keyClosureRollup: config.run.closureRollup.label,
      RunConfig.keyFailOn: config.run.failOn.name,
    },
    'summary': {
      'files': summary.files,
      'filesWithErrors': summary.filesWithErrors,
      'scopes': summary.scopes,
      'verdicts': {for (final v in Verdict.values) v.name: summary.verdicts[v]},
      'suppressed': summary.suppressed,
    },
    'diagnostics': [for (final d in result.diagnostics) _runDiagnostic(d)],
    'files': [for (final f in result.files) _file(f, contributors)],
    if (result.report case Report(:final runMeasurements)
        when runMeasurements.isNotEmpty)
      'runMeasurements': [
        for (final m in runMeasurements) _measurement(m, contributors),
      ],
  };
}

Map<String, Object?> _config(String root, RootConfig c, RunResult result) => {
  'root': root,
  'source': c.source,
  'metrics': {
    for (final m in result.metrics)
      m.id: _metricConfig(c.metrics[m.id], metric: m),
  },
  if (c.overrides.isNotEmpty)
    'overrides': [
      for (final o in c.overrides)
        {
          'paths': o.paths,
          'metrics': {
            for (final e in o.metrics.entries) e.key: _metricConfig(e.value),
          },
        },
    ],
};

/// With [metric], the effective thresholds (built-in default included);
/// without it (override blocks), what the block itself says.
Map<String, Object?> _metricConfig(MetricConfig? m, {Metric? metric}) => {
  'enabled': m?.isEnabled ?? true,
  'thresholds': _threshold(
    metric == null ? m?.threshold : effectiveThreshold(m, metric),
  ),
};

Map<String, Object?>? _threshold(Threshold? t) =>
    t == null || t == Threshold.none ? null : {'warn': t.warn, 'fail': t.fail};

Map<String, Object?> _runDiagnostic(RunDiagnostic d) => {
  'path': d.path,
  'severity': d.severity.name,
  'message': d.message,
  'line': d.line,
  'column': d.column,
};

Map<String, Object?> _file(FileReport f, ContributorDetail detail) {
  final emitted = {for (final s in f.scopes) s.id};
  return {
    'path': f.path,
    'configRoot': f.source.configRoot,
    'status': f.partial ? 'errors' : 'ok',
    'diagnostics': [
      for (final d in f.diagnostics)
        {
          'severity': d.severity.name,
          'message': d.message,
          'span': _span(d.span),
        },
    ],
    'scopes': [for (final s in f.scopes) _scope(s, emitted, detail)],
  };
}

Map<String, Object?> _scope(
  ScopeResult s,
  Set<ScopeId> emitted,
  ContributorDetail detail,
) {
  final ctx = s.scope;
  // The nearest enclosing scope that is itself in the report; structural
  // contexts are not serialized, so a method's parent is null.
  ScopeContext? parent = ctx.parent;
  while (parent != null && !emitted.contains(parent.id)) {
    parent = parent.parent;
  }
  final metricIds = s.results.keys.toList()..sort();
  return {
    'id': ctx.id.value,
    'kind': ctx.kind.label,
    'name': ctx.name,
    'qualifiedName': ctx.qualifiedName,
    'parent': parent?.id.value,
    'fingerprint': ctx.fingerprint,
    'span': _span(ctx.span),
    'partial': ctx.partial,
    'results': {
      for (final id in metricIds) id: _result(s.results[id]!, detail),
    },
  };
}

Map<String, Object?> _result(MetricResult r, ContributorDetail detail) {
  final m = r.measurement;
  final suppressed = r.suppressed;
  return {
    'measured': m.value,
    'value': r.value,
    'includes': [for (final id in r.includes) id.value],
    'threshold': _threshold(r.threshold),
    'verdict': r.verdict.name,
    'suppressed': suppressed == null
        ? null
        : {
            'kind': suppressed.kind == SuppressionKind.ignore
                ? 'ignore'
                : 'ignore_for_file',
            'span': _span(suppressed.span),
          },
    ..._contributors(m, detail),
    if (m.detail != null) 'detail': m.detail,
  };
}

Map<String, Object?> _measurement(Measurement m, ContributorDetail detail) => {
  'metric': m.metricId,
  'scope': m.scope.value,
  'value': m.value,
  ..._contributors(m, detail),
  if (m.detail != null) 'detail': m.detail,
};

Map<String, Object?> _contributors(Measurement m, ContributorDetail detail) {
  final sorted = [...m.contributors]
    ..sort((a, b) => a.span.start.offset.compareTo(b.span.start.offset));
  final summary = <String, int>{};
  for (final c in sorted) {
    summary[c.kind] = (summary[c.kind] ?? 0) + 1;
  }
  return {
    if (detail == ContributorDetail.full)
      'contributors': [
        for (final c in sorted)
          {'kind': c.kind, 'increment': c.increment, 'span': _span(c.span)},
      ],
    'contributorSummary': {for (final c in sorted) c.kind: 0}
      ..updateAll((kind, _) => sorted.where((c) => c.kind == kind).length),
    if (m.tableShape case final t?)
      'tableShaped': {'kind': t.kind, 'share': t.share},
  };
}

/// 1-based line/column, end-exclusive, 0-based UTF-16 offsets.
Map<String, Object?> _span(FileSpan span) => {
  'start': _location(span.start),
  'end': _location(span.end),
};

Map<String, Object?> _location(SourceLocation l) => {
  'line': l.line + 1,
  'column': l.column + 1,
  'offset': l.offset,
};
