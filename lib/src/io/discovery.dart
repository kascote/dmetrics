/// Target expansion, config-root lookup and file reading (SPEC §5.2, §8).
/// The only code that touches the file system.
library;

import 'dart:io';

import 'package:path/path.dart' as p;

import '../config/config.dart';
import '../config/loader.dart';
import '../engine/metric.dart';
import '../engine/report.dart' show Severity;
import '../engine/source.dart';
import '../report/run_result.dart';

const analysisOptionsFile = 'analysis_options.yaml';

class DiscoveredSources {
  /// Readable sources, unique by path, in path order.
  final List<SourceFile> sources;

  /// Every config root seen, keyed run-root-relative; null means built-in
  /// defaults (no `dmetrics:` section above the file).
  final Map<String, LoadedConfig?> roots;

  /// Unreadable files and other I/O problems.
  final List<RunDiagnostic> diagnostics;

  /// Targets that do not exist: a usage error (exit 3).
  final List<String> missingTargets;

  const DiscoveredSources({
    required this.sources,
    required this.roots,
    required this.diagnostics,
    required this.missingTargets,
  });
}

class Discovery {
  /// Absolute run root: paths in the report are relative to it.
  final String runRoot;
  final List<Metric> metrics;

  /// `--config`: forces one root (the file's directory) for the whole run.
  final String? configPath;

  final _dirRoots = <String, _Root>{};
  final _parsedFiles = <String, LoadedConfig?>{};

  Discovery({required String runRoot, required this.metrics, this.configPath})
    : runRoot = p.normalize(p.absolute(runRoot));

  /// Expands [targets] (files and directories, mixed; none means the run
  /// root). Explicitly named files are always analyzed; files found under a
  /// directory pass their root's include/exclude globs first.
  DiscoveredSources expand(List<String> targets) {
    final diagnostics = <RunDiagnostic>[];
    final missing = <String>[];
    final roots = <String, LoadedConfig?>{};
    final explicit = <String>{};
    final found = <String>{};

    _Root? forced;
    if (configPath != null) {
      final abs = _absolute(configPath!);
      if (!File(abs).existsSync()) {
        missing.add(configPath!);
      } else {
        forced = _Root(p.dirname(abs), _parseFile(abs));
      }
    }

    for (final target in targets.isEmpty ? const ['.'] : targets) {
      final abs = _absolute(target);
      if (File(abs).existsSync()) {
        explicit.add(abs);
        found.add(abs);
      } else if (Directory(abs).existsSync()) {
        _walk(Directory(abs), found);
      } else {
        missing.add(target);
      }
    }

    final sources = <SourceFile>[];
    for (final abs in found.toList()..sort()) {
      final root = forced ?? _rootFor(p.dirname(abs));
      final rootRel = _relative(root.dir);
      roots[rootRel] = root.config;
      final rel = _relative(abs);
      if (!explicit.contains(abs)) {
        final config = root.config?.root ?? RootConfig.defaults;
        if (!config.selects(pathRelativeToRoot(rel, rootRel))) continue;
      }
      try {
        sources.add(
          SourceFile(
            path: rel,
            content: File(abs).readAsStringSync(),
            configRoot: rootRel,
          ),
        );
      } on FileSystemException catch (e) {
        diagnostics.add(
          RunDiagnostic(
            path: rel,
            message: 'could not read file: ${e.osError?.message ?? e.message}',
            severity: Severity.error,
          ),
        );
      }
    }
    return DiscoveredSources(
      sources: sources,
      roots: roots,
      diagnostics: diagnostics,
      missingTargets: missing,
    );
  }

  /// Recursively collects `*.dart` files, skipping dot-directories
  /// (`.dart_tool`, `.git`, …) like `dart analyze` does.
  void _walk(Directory dir, Set<String> found) {
    for (final entry in dir.listSync(followLinks: false)) {
      final name = p.basename(entry.path);
      if (entry is Directory) {
        if (!name.startsWith('.')) _walk(entry, found);
      } else if (entry is File && name.endsWith('.dart')) {
        found.add(p.normalize(entry.absolute.path));
      }
    }
  }

  /// The nearest ancestor of [dir] whose `analysis_options.yaml` has a
  /// `dmetrics:` section; otherwise the package root (nearest `pubspec.yaml`),
  /// with defaults; otherwise the run root, with defaults.
  _Root _rootFor(String dir) {
    final cached = _dirRoots[dir];
    if (cached != null) return cached;
    final chain = <String>[];
    _Root? root;
    for (var d = dir; ; d = p.dirname(d)) {
      final known = _dirRoots[d];
      if (known != null) {
        root = known;
        break;
      }
      chain.add(d);
      final options = p.join(d, analysisOptionsFile);
      if (File(options).existsSync()) {
        final config = _parseFile(options);
        if (config != null) {
          root = _Root(d, config);
          break;
        }
      }
      if (File(p.join(d, 'pubspec.yaml')).existsSync()) {
        root = _Root(d, null);
        break;
      }
      if (p.dirname(d) == d) {
        root = _Root(runRoot, null);
        break;
      }
    }
    for (final d in chain) {
      _dirRoots[d] = root;
    }
    return root;
  }

  LoadedConfig? _parseFile(String abs) => _parsedFiles.putIfAbsent(
    abs,
    () => parseDmetricsConfig(
      File(abs).readAsStringSync(),
      source: _relative(abs),
      metrics: metrics,
    ),
  );

  String _absolute(String target) =>
      p.normalize(p.isAbsolute(target) ? target : p.join(runRoot, target));

  /// Run-root-relative with forward slashes; `.` for the root itself.
  String _relative(String abs) {
    final rel = p.relative(abs, from: runRoot);
    return rel == '.' ? '.' : p.split(rel).join('/');
  }
}

class _Root {
  final String dir;
  final LoadedConfig? config;

  const _Root(this.dir, this.config);
}
