/// Target expansion, config-root lookup and file reading (SPEC §5.2, §8).
/// The only code that touches the file system.
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import '../config/config.dart';
import '../config/loader.dart';
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
  final List<MetricSpec> metrics;

  /// `--config`: forces one root (the file's directory) for the whole run.
  final String? configPath;

  final _dirRoots = <String, _Root>{};
  final _parsedFiles = <String, LoadedConfig?>{};
  final _dirPackages = <String, _Package?>{};
  final _pubspecs = <String, _Package>{};

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
        final package = _packageFor(p.dirname(abs));
        sources.add(
          SourceFile(
            path: rel,
            content: File(abs).readAsStringSync(),
            configRoot: rootRel,
            languageVersion: package?.languageVersion,
            packageUri: package?.uriOf(abs),
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

  /// The package containing [dir]: the nearest `pubspec.yaml` up the tree,
  /// independent of the config root (a `dmetrics:` section may sit above or
  /// below the package). Null outside any package.
  _Package? _packageFor(String dir) {
    if (_dirPackages.containsKey(dir)) return _dirPackages[dir];
    final chain = <String>[];
    _Package? package;
    for (var d = dir; ; d = p.dirname(d)) {
      if (_dirPackages.containsKey(d)) {
        package = _dirPackages[d];
        break;
      }
      chain.add(d);
      final pubspec = p.join(d, 'pubspec.yaml');
      if (File(pubspec).existsSync()) {
        package = _pubspecs.putIfAbsent(pubspec, () => _Package.read(d));
        break;
      }
      if (p.dirname(d) == d) break;
    }
    for (final d in chain) {
      _dirPackages[d] = package;
    }
    return package;
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

/// What a pubspec tells the engine about the files under it.
class _Package {
  final String dir;

  /// Null when the pubspec has no usable `name`; files then get no
  /// `package:` URI and are reachable only by relative import.
  final String? name;

  /// The `sdk` lower bound, or null when there is no usable constraint.
  final LanguageVersion? languageVersion;

  const _Package(this.dir, this.name, this.languageVersion);

  /// Reads `name` and `environment: sdk:` from `<dir>/pubspec.yaml`.
  /// Anything unreadable or malformed yields nulls: a broken pubspec is
  /// `dart pub`'s problem to report, and parsing at the latest version with
  /// no package identity is still a useful answer.
  factory _Package.read(String dir) {
    try {
      final doc = loadYaml(
        File(p.join(dir, 'pubspec.yaml')).readAsStringSync(),
      );
      if (doc is! YamlMap) return _Package(dir, null, null);
      final name = doc['name'];
      final env = doc['environment'];
      final sdk = env is YamlMap ? env['sdk'] : null;
      return _Package(
        dir,
        name is String && name.isNotEmpty ? name : null,
        sdk is String ? LanguageVersion.fromSdkConstraint(sdk) : null,
      );
    } on FileSystemException {
      return _Package(dir, null, null);
    } on YamlException {
      return _Package(dir, null, null);
    }
  }

  /// `package:<name>/<path under lib>` for a file under this package's
  /// `lib/`; null for anything else (`bin/`, `test/`, a nameless package).
  Uri? uriOf(String abs) {
    final lib = p.join(dir, 'lib');
    if (name == null || !p.isWithin(lib, abs)) return null;
    return Uri.parse(
      'package:$name/${p.split(p.relative(abs, from: lib)).join('/')}',
    );
  }
}
