/// The comparison of a finished run against its config roots' baselines:
/// which scope is which, and what each result's status is.
///
/// Matching is three passes, deterministic and explainable: named scopes by
/// exact id, which survives every body edit; then, among what is still
/// unmatched on both sides, by fingerprint when it is unique on both sides,
/// which follows a move between files and a rename; then closures by exact
/// id, the ordinal under their parent. Closures take the fingerprint pass
/// before the ordinal pass because inserting a closure shifts the ordinals
/// after it. No similarity heuristic: an edited closure whose ordinal also
/// moved reads as new, and so does a renamed scope whose body changed.
///
/// The baseline side is every entry under the run's targets, whether or
/// not its file still exists: an entry whose file was deleted or renamed
/// takes the fingerprint pass like any other, so a moved file is followed,
/// and what stays unmatched counts as gone. Entries outside the targets
/// are ignored, so a single-file run does not report the rest as gone.
///
/// A pure function of the run and the loaded files; the engine is not
/// involved beyond the id helpers that strip and restore a path.
library;

import '../config/config.dart';
import '../config/threshold.dart';
import '../engine/metric.dart';
import '../engine/report.dart';
import '../engine/result.dart';
import '../engine/scope.dart';
import 'baseline.dart';

/// Where a result stands against the baseline. Only [added] and [worse] can
/// be violations, and [added] only at or above the `fail_on` floor.
enum BaselineStatus {
  /// No entry matched the scope, or the entry had no value for the metric.
  added('new'),

  /// At or above the floor and above the baseline value.
  worse('worse'),

  /// At or above the floor, at or below the baseline value: accepted debt.
  baselined('baselined'),

  /// Below the floor, value differs from the baseline: drift, either way.
  changed('changed'),

  /// Below the floor, same value.
  unchanged('unchanged');

  /// The word the reports use.
  final String label;

  const BaselineStatus(this.label);
}

class BaselineMatch {
  final BaselineStatus status;

  /// The baseline's value, null for [BaselineStatus.added].
  final num? value;

  const BaselineMatch(this.status, this.value);

  @override
  String toString() => 'BaselineMatch(${status.label}, was $value)';
}

/// Run-level counts. Results for all but [gone], which counts entries.
class BaselineCounts {
  /// Violations that were in the baseline and did not get worse.
  final int baselined;

  /// `new` results at or above the floor: unmatched scopes that violate.
  final int added;
  final int worse;

  /// Matched entries at or above the floor by their baseline value under
  /// the current threshold, now below it by their current value.
  final int fixed;

  /// Drift: results below the floor whose value differs, either direction.
  final int changed;

  /// Entries in files of the run that matched nothing.
  final int gone;

  const BaselineCounts({
    this.baselined = 0,
    this.added = 0,
    this.worse = 0,
    this.fixed = 0,
    this.changed = 0,
    this.gone = 0,
  });

  bool get isEmpty =>
      baselined == 0 &&
      added == 0 &&
      worse == 0 &&
      fixed == 0 &&
      changed == 0 &&
      gone == 0;

  /// Entries that no longer describe the code: a refresh would drop them.
  int get stale => fixed + gone;
}

/// What `analyze` knows after comparing. Present on a [RunResult] only when
/// at least one root had a baseline; [of] is null for a scope whose root
/// had none, or whose metric the root's file does not cover.
class BaselineComparison {
  /// Config root to the run-root-relative path of its baseline, null for a
  /// root that had none.
  final Map<String, String?> byRoot;

  /// Scope id to metric id to match, for every compared result.
  final Map<ScopeId, Map<String, BaselineMatch>> matches;
  final BaselineCounts counts;

  const BaselineComparison({
    required this.byRoot,
    required this.matches,
    required this.counts,
  });

  BaselineMatch? of(ScopeId id, String metricId) => matches[id]?[metricId];

  /// Whether the status keeps the result from being a violation: only
  /// baselined debt does, a new or worse result counts as always.
  bool accepts(ScopeId id, String metricId) =>
      of(id, metricId)?.status == BaselineStatus.baselined;
}

/// A baseline that could not be used: the file is skipped and the run is
/// incomplete, since the values it holds cannot be compared with the run's.
class BaselineProblem {
  /// Run-root-relative path of the file.
  final String path;
  final String message;

  const BaselineProblem({required this.path, required this.message});

  @override
  String toString() => '$path: $message';
}

/// The outcome of [compareBaselines]: the comparison, or null when no root
/// had a usable baseline, plus the files that could not be used.
class ComparisonOutcome {
  final BaselineComparison? comparison;
  final List<BaselineProblem> problems;

  const ComparisonOutcome(this.comparison, this.problems);
}

/// Compares [report] against [baselines], keyed by config root. [run] is
/// the knob block the run counted under, as `runKnobs` renders it; [inRun]
/// says whether a run-root-relative path lies under the run's targets.
ComparisonOutcome compareBaselines({
  required Report report,
  required Map<String, LoadedBaseline?> baselines,
  required Map<String, Object?> run,
  required RunConfig config,
  required bool Function(String runRelativePath) inRun,
}) {
  final problems = <BaselineProblem>[];
  final byRoot = <String, String?>{};
  final usable = <String, LoadedBaseline>{};
  for (final e in baselines.entries) {
    final b = e.value;
    if (b == null) {
      byRoot[e.key] = null;
      continue;
    }
    if (!sameRun(b.file.run, run)) {
      problems.add(
        BaselineProblem(
          path: b.path,
          message:
              'baseline was recorded under different settings '
              '(${_describeRun(b.file.run)} vs ${_describeRun(run)}); '
              'run `dmetrics baseline` to refresh it',
        ),
      );
      byRoot[e.key] = null;
      continue;
    }
    byRoot[e.key] = b.path;
    usable[e.key] = b;
  }
  if (usable.isEmpty) return ComparisonOutcome(null, problems);

  final matches = <ScopeId, Map<String, BaselineMatch>>{};
  var counts = const BaselineCounts();
  final present = {for (final f in report.files) f.path};
  for (final e in usable.entries) {
    final files = [
      for (final f in report.files)
        if (f.source.configRoot == e.key) f,
    ];
    final absent = _absentFiles(e.value, e.key, usable.keys, present, inRun);
    final root = _Root(e.value, files, absent, config.violationFloor);
    counts = root.run(matches, counts);
  }
  return ComparisonOutcome(
    BaselineComparison(byRoot: byRoot, matches: matches, counts: counts),
    problems,
  );
}

/// The stored files of [baseline] that are not in the tree any more and
/// that [root] answers for: under the targets, and nearer to [root] than to
/// any other of [roots], so a file shared by several roots (`--baseline`)
/// counts each absent file once.
List<String> _absentFiles(
  LoadedBaseline baseline,
  String root,
  Iterable<String> roots,
  Set<String> present,
  bool Function(String) inRun,
) => [
  for (final stored in baseline.file.files.keys)
    if (baseline.location.toRunRoot(stored) case final path
        when !present.contains(path) &&
            inRun(path) &&
            _nearestRoot(path, roots) == root)
      path,
];

/// The deepest of [roots] that contains [path]; `.` contains everything.
String? _nearestRoot(String path, Iterable<String> roots) {
  String? best;
  for (final r in roots) {
    final under = r == '.' || path == r || path.startsWith('$r/');
    if (under && (best == null || r.length > best.length)) best = r;
  }
  return best;
}

String _describeRun(Map<String, Object?> run) {
  final parts = <String>[];
  for (final e in run.entries) {
    if (e.value is Map) {
      for (final k in (e.value as Map).entries) {
        parts.add('${e.key}.${k.key}=${k.value}');
      }
    } else {
      parts.add('${e.key}=${e.value}');
    }
  }
  return parts.join(', ');
}

/// Matching and classification within one root.
class _Root {
  final LoadedBaseline baseline;
  final List<FileReport> files;
  final Verdict floor;

  /// Entries of the run's files, present or [absent], keyed by their id
  /// under the run root.
  final entries = <ScopeId, BaselineEntry>{};
  final matched = <ScopeId, ScopeId>{};
  final taken = <ScopeId>{};

  _Root(this.baseline, this.files, List<String> absent, this.floor) {
    for (final path in [for (final f in files) f.path, ...absent]) {
      final scopes = baseline.file.files[baseline.location.fromRunRoot(path)];
      if (scopes == null) continue;
      for (final s in scopes.entries) {
        entries[ScopeId.inFile(path, s.key)] = s.value;
      }
    }
  }

  BaselineCounts run(
    Map<ScopeId, Map<String, BaselineMatch>> matches,
    BaselineCounts counts,
  ) {
    final scopes = [
      for (final f in files)
        for (final s in f.scopes) s,
    ];
    _byId(scopes, closures: false);
    _byFingerprint(scopes);
    _byId(scopes, closures: true);
    return _classify(scopes, matches, counts);
  }

  void _byId(List<ScopeResult> scopes, {required bool closures}) {
    for (final s in scopes) {
      if ((s.scope.kind == ScopeKind.closure) != closures) continue;
      if (matched.containsKey(s.id)) continue;
      if (entries.containsKey(s.id) && taken.add(s.id)) matched[s.id] = s.id;
    }
  }

  void _byFingerprint(List<ScopeResult> scopes) {
    final current = <String, List<ScopeResult>>{};
    for (final s in scopes) {
      if (matched.containsKey(s.id)) continue;
      current.putIfAbsent(s.scope.fingerprint, () => []).add(s);
    }
    final stored = <String, List<ScopeId>>{};
    for (final e in entries.entries) {
      if (taken.contains(e.key)) continue;
      stored.putIfAbsent(e.value.fingerprint, () => []).add(e.key);
    }
    for (final e in current.entries) {
      final candidates = stored[e.key];
      if (e.value.length != 1 || candidates == null || candidates.length != 1) {
        continue;
      }
      matched[e.value.single.id] = candidates.single;
      taken.add(candidates.single);
    }
  }

  BaselineCounts _classify(
    List<ScopeResult> scopes,
    Map<ScopeId, Map<String, BaselineMatch>> matches,
    BaselineCounts counts,
  ) {
    var baselined = counts.baselined;
    var added = counts.added;
    var worse = counts.worse;
    var fixed = counts.fixed;
    var changed = counts.changed;
    final covered = baseline.file.metrics.toSet();
    for (final s in scopes) {
      final entry = matched[s.id] == null ? null : entries[matched[s.id]!];
      for (final r in s.results.entries) {
        if (!covered.contains(r.key)) continue;
        final result = r.value;
        final was = entry?.values[r.key];
        final match = _matchFor(result, was);
        (matches[s.id] ??= {})[r.key] = match;
        switch (match.status) {
          case BaselineStatus.added:
            if (result.verdict.index >= floor.index) added++;
          case BaselineStatus.worse:
            worse++;
          case BaselineStatus.baselined:
            baselined++;
          case BaselineStatus.changed:
            changed++;
          case BaselineStatus.unchanged:
            break;
        }
        if (was != null && _isFixed(result, was)) fixed++;
      }
    }
    return BaselineCounts(
      baselined: baselined,
      added: added,
      worse: worse,
      fixed: fixed,
      changed: changed,
      gone: counts.gone + (entries.length - taken.length),
    );
  }

  BaselineMatch _matchFor(MetricResult r, num? was) {
    if (was == null) return const BaselineMatch(BaselineStatus.added, null);
    final violates = r.verdict.index >= floor.index;
    final status = violates
        ? (r.value > was ? BaselineStatus.worse : BaselineStatus.baselined)
        : (r.value != was ? BaselineStatus.changed : BaselineStatus.unchanged);
    return BaselineMatch(status, was);
  }

  /// Judged on values under the current threshold, not on verdicts, so a
  /// suppression added since the baseline is not a fix.
  bool _isFixed(MetricResult r, num was) {
    final t = r.threshold;
    if (t == null) return false;
    return t.evaluate(was).index >= floor.index &&
        t.evaluate(r.value).index < floor.index;
  }
}

/// What a run records: every scope of every file, keyed by run-root-relative
/// path then local id, values only.
Map<String, Map<String, BaselineEntry>> recordRun(Report report) => {
  for (final f in report.files)
    f.path: {
      for (final s in f.scopes)
        s.id.localIn(f.path): BaselineEntry(
          fingerprint: s.scope.fingerprint,
          values: {for (final r in s.results.entries) r.key: r.value.value},
        ),
    },
};

/// The run-global knobs a baseline records and a comparison checks: every
/// metric's settings with their effective values, plus `closure_rollup`.
/// `fail_on` is left out: it changes no value.
Map<String, Object?> runKnobs(List<Metric> metrics, RunConfig run) => {
  for (final m in metrics)
    if (m.settingDefaults.isNotEmpty)
      m.id: {
        for (final key in m.settingDefaults.keys)
          key.substring(m.id.length + 1):
              run.settings[key] ?? m.settingDefaults[key],
      },
  RunConfig.keyClosureRollup: run.closureRollup.label,
};
