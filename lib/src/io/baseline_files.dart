/// Reading and writing baseline files: where each config root's file is,
/// what to do when it is missing, and the partial-refresh rule of
/// `dmetrics baseline`. The format and the comparison are pure (`src/baseline`);
/// this is the file system side.
library;

import 'dart:io';

import 'package:path/path.dart' as p;

import '../baseline/baseline.dart';
import '../baseline/compare.dart';
import '../config/config.dart';
import '../config/threshold.dart';
import '../engine/report.dart' show FileReport, Severity;
import '../report/run_result.dart';

/// The baselines of a run, keyed by config root, with the files that could
/// not be read.
class ReadBaselines {
  final Map<String, LoadedBaseline?> byRoot;
  final List<RunDiagnostic> diagnostics;

  const ReadBaselines(this.byRoot, this.diagnostics);
}

/// Resolves and reads each root's baseline. [forcedPath] (`--baseline`)
/// names one file for every root; [disabled] (`--no-baseline`) reads none.
/// A configured file that is missing is an error; the default name is used
/// only when it exists.
ReadBaselines readBaselines(
  AnalysisConfig config, {
  required String runRoot,
  String? forcedPath,
  bool disabled = false,
}) {
  final byRoot = <String, LoadedBaseline?>{};
  final diagnostics = <RunDiagnostic>[];
  if (disabled) {
    return ReadBaselines({for (final r in config.roots.keys) r: null}, []);
  }
  final cache = <String, LoadedBaseline?>{};
  for (final root in config.roots.keys) {
    final located = forcedPath == null
        ? baselinePathOf(root, config.roots[root]!)
        : _relative(runRoot, forcedPath);
    if (located == null) {
      byRoot[root] = null;
      continue;
    }
    final required = forcedPath != null || config.roots[root]!.baselineRequired;
    byRoot[root] = cache.putIfAbsent(
      located,
      () => _read(runRoot, located, required: required, diagnostics),
    );
  }
  return ReadBaselines(byRoot, diagnostics);
}

/// The run-root-relative path of [root]'s baseline, or null when the root
/// opted out.
String? baselinePathOf(String root, RootConfig config) {
  final rel = config.baselinePath;
  if (rel == null) return null;
  return p.posix.normalize(p.posix.join(root == '.' ? '' : root, rel));
}

LoadedBaseline? _read(
  String runRoot,
  String path,
  List<RunDiagnostic> diagnostics, {
  required bool required,
}) {
  final file = File(p.join(runRoot, p.fromUri(path)));
  if (!file.existsSync()) {
    if (required) {
      diagnostics.add(
        RunDiagnostic(
          path: path,
          message:
              'baseline file not found; run `dmetrics baseline` to '
              'create it, or set `baseline: none`',
          severity: Severity.error,
        ),
      );
    }
    return null;
  }
  try {
    return LoadedBaseline(
      location: BaselineLocation(path),
      file: decodeBaseline(file.readAsStringSync()),
    );
  } on FormatException catch (e) {
    diagnostics.add(
      RunDiagnostic(
        path: path,
        message: 'not a baseline file: ${e.message}',
        severity: Severity.error,
      ),
    );
  } on FileSystemException catch (e) {
    diagnostics.add(
      RunDiagnostic(
        path: path,
        message: 'could not read baseline: ${e.osError?.message ?? e.message}',
        severity: Severity.error,
      ),
    );
  }
  return null;
}

/// What `dmetrics baseline` wrote for one root.
class WrittenBaseline {
  /// Run-root-relative path of the file.
  final String path;
  final int files;
  final int scopes;

  /// Results at or above `warn` under the current thresholds: the debt the
  /// file accepts.
  final int violations;

  const WrittenBaseline({
    required this.path,
    required this.files,
    required this.scopes,
    required this.violations,
  });
}

/// Records [result] into each root's baseline: entries of the run's files
/// replace what the file held for every path under [targets] (run-root-
/// relative files and directories; none means everything), entries for
/// other paths are kept. [outputPath] (`--output`) names the file for a
/// single-root run. Throws [FileSystemException] when a file cannot be
/// written.
List<WrittenBaseline> writeBaselines(
  RunResult result, {
  required String runRoot,
  required List<String> targets,
  String? outputPath,
}) {
  final report = result.report!;
  final run = runKnobs(result.metrics, result.config.run);
  final metrics = [for (final m in result.metrics) m.id];
  final recorded = recordRun(report);
  final covered = _Targets(runRoot, targets);
  final written = <WrittenBaseline>[];
  for (final root in result.config.roots.keys.toList()..sort()) {
    final path = outputPath == null
        ? baselinePathOf(root, result.config.roots[root]!)
        : _relative(runRoot, outputPath);
    if (path == null) continue;
    final files = [
      for (final f in report.files)
        if (f.source.configRoot == root) f,
    ];
    if (files.isEmpty) continue;
    final location = BaselineLocation(path);
    final file = File(p.join(runRoot, p.fromUri(path)));
    final existing = file.existsSync() ? _existing(file) : null;
    final next = updateBaseline(
      existing: existing,
      location: location,
      run: run,
      metrics: metrics,
      recorded: {for (final f in files) f.path: recorded[f.path]!},
      inRun: covered.contains,
    );
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(encodeBaseline(next));
    written.add(
      WrittenBaseline(
        path: path,
        files: files.length,
        scopes: files.fold(0, (n, f) => n + f.scopes.length),
        violations: _violations(files),
      ),
    );
  }
  return written;
}

/// An unreadable or foreign existing file is replaced, not merged: the
/// command's job is to leave a valid baseline behind.
BaselineFile? _existing(File file) {
  try {
    return decodeBaseline(file.readAsStringSync());
  } on FormatException {
    return null;
  }
}

int _violations(List<FileReport> files) {
  var n = 0;
  for (final f in files) {
    for (final s in f.scopes) {
      for (final r in s.results.values) {
        if (r.threshold != null &&
            r.threshold!.evaluate(r.value) != Verdict.ok) {
          n++;
        }
      }
    }
  }
  return n;
}

/// The run's targets as run-root-relative paths: a file covers itself, a
/// directory everything under it.
class _Targets {
  final List<String> paths;

  _Targets(String runRoot, List<String> targets)
    : paths = [
        for (final t in targets.isEmpty ? const ['.'] : targets)
          _relative(runRoot, t),
      ];

  bool contains(String runRelative) => paths.any(
    (t) =>
        t == '.' ||
        t == runRelative ||
        runRelative.startsWith(t.endsWith('/') ? t : '$t/'),
  );
}

/// Run-root-relative with forward slashes; `.` for the root itself.
String _relative(String runRoot, String target) {
  final abs = p.normalize(
    p.isAbsolute(target) ? target : p.join(runRoot, target),
  );
  final rel = p.relative(abs, from: p.normalize(p.absolute(runRoot)));
  return rel == '.' ? '.' : p.split(rel).join('/');
}
