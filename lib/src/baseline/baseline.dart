/// The baseline file: a snapshot of a run that `analyze` compares against.
///
/// One per config root. Values only, no verdicts and no thresholds, so the
/// comparison applies the current thresholds to both sides and tightening
/// a threshold grows the baselined count instead of failing CI on legacy
/// code. Paths are relative to the file's own directory and scope ids are
/// stored without their path, so the file moves with the code it describes.
/// One scope per line, sorted, so the file's git diff is the debt ledger's
/// history. This library is pure: reading and writing files is the I/O
/// layer's job.
library;

import 'dart:convert';

import 'package:path/path.dart' as p;

import '../version.dart';

const baselineSchemaVersion = 1;

/// The key under which an entry keeps its fingerprint; every other key of
/// an entry is a metric id.
const _fingerprintKey = 'fingerprint';

/// One scope as recorded: its fingerprint and rolled-up value per metric.
class BaselineEntry {
  final String fingerprint;

  /// Keyed by metric id. A metric the scope was not measured with is absent.
  final Map<String, num> values;

  const BaselineEntry({required this.fingerprint, required this.values});

  @override
  bool operator ==(Object other) =>
      other is BaselineEntry &&
      other.fingerprint == fingerprint &&
      _sameValues(other.values, values);

  @override
  int get hashCode => Object.hash(fingerprint, values.length);

  @override
  String toString() => 'BaselineEntry($fingerprint, $values)';
}

bool _sameValues(Map<String, num> a, Map<String, num> b) {
  if (a.length != b.length) return false;
  for (final e in a.entries) {
    if (b[e.key] != e.value) return false;
  }
  return true;
}

/// A baseline as stored, before any path is rebased.
class BaselineFile {
  /// The run-global knobs the values were counted under (`closure_rollup`
  /// and every metric's settings), without `fail_on`, which changes no
  /// value. Compared whole against the run's; a difference means the
  /// values are not comparable.
  final Map<String, Object?> run;

  /// The metric ids the file covers, sorted. A metric absent here is
  /// compared as if there were no baseline for it.
  final List<String> metrics;

  /// File path relative to the baseline's directory, then the scope id
  /// without its path, to the entry.
  final Map<String, Map<String, BaselineEntry>> files;

  const BaselineFile({
    required this.run,
    required this.metrics,
    required this.files,
  });

  int get scopeCount => files.values.fold(0, (n, f) => n + f.length);
}

/// Serializes [file] with one scope per line, files and scopes sorted by
/// key, so a diff reads scope by scope.
String encodeBaseline(BaselineFile file) {
  final out = StringBuffer()
    ..writeln('{')
    ..writeln('  "schemaVersion": $baselineSchemaVersion,')
    ..writeln(
      '  "tool": ${jsonEncode({'name': toolName, 'version': toolVersion})},',
    )
    ..writeln('  "run": ${jsonEncode(file.run)},')
    ..writeln('  "metrics": ${jsonEncode(file.metrics)},')
    ..writeln('  "files": {');
  final paths = file.files.keys.toList()..sort();
  for (final (i, path) in paths.indexed) {
    final scopes = file.files[path]!;
    final ids = scopes.keys.toList()..sort();
    out.writeln('    ${jsonEncode(path)}: {');
    for (final (j, id) in ids.indexed) {
      final e = scopes[id]!;
      final metricIds = e.values.keys.toList()..sort();
      final body = jsonEncode({
        _fingerprintKey: e.fingerprint,
        for (final m in metricIds) m: e.values[m],
      });
      out.writeln(
        '      ${jsonEncode(id)}: $body${j == ids.length - 1 ? '' : ','}',
      );
    }
    out.writeln('    }${i == paths.length - 1 ? '' : ','}');
  }
  out
    ..writeln('  }')
    ..writeln('}');
  return out.toString();
}

/// Parses what [encodeBaseline] wrote. Throws [FormatException] on anything
/// that is not a baseline of this schema, with a message that names what
/// was wrong.
BaselineFile decodeBaseline(String text) {
  final Object? doc;
  try {
    doc = jsonDecode(text);
  } on FormatException catch (e) {
    throw FormatException('invalid JSON: ${e.message}');
  }
  if (doc is! Map<String, Object?>) {
    throw const FormatException('expected a JSON object');
  }
  final schema = doc['schemaVersion'];
  if (schema != baselineSchemaVersion) {
    throw FormatException(
      'schemaVersion $schema is not $baselineSchemaVersion',
    );
  }
  final run = doc['run'];
  if (run is! Map<String, Object?>) {
    throw const FormatException('`run` must be an object');
  }
  final metrics = doc['metrics'];
  if (metrics is! List || metrics.any((m) => m is! String)) {
    throw const FormatException('`metrics` must be a list of metric ids');
  }
  final files = doc['files'];
  if (files is! Map<String, Object?>) {
    throw const FormatException('`files` must be an object keyed by path');
  }
  return BaselineFile(
    run: run,
    metrics: metrics.cast<String>().toList()..sort(),
    files: {for (final f in files.entries) f.key: _scopes(f.key, f.value)},
  );
}

Map<String, BaselineEntry> _scopes(String path, Object? node) {
  if (node is! Map<String, Object?>) {
    throw FormatException('`files.$path` must be an object keyed by scope');
  }
  return {for (final s in node.entries) s.key: _entry(path, s.key, s.value)};
}

BaselineEntry _entry(String path, String id, Object? node) {
  if (node is! Map<String, Object?> || node[_fingerprintKey] is! String) {
    throw FormatException(
      '`files.$path.$id` must be an object with a fingerprint',
    );
  }
  final values = <String, num>{};
  for (final e in node.entries) {
    if (e.key == _fingerprintKey) continue;
    final v = e.value;
    if (v is! num) {
      throw FormatException('`files.$path.$id.${e.key}` must be a number');
    }
    values[e.key] = v;
  }
  return BaselineEntry(
    fingerprint: node[_fingerprintKey] as String,
    values: values,
  );
}

/// Where a baseline file sits, so stored paths can be rebased to the run
/// root and back. [path] is the file's run-root-relative path.
class BaselineLocation {
  final String path;

  const BaselineLocation(this.path);

  String get _dir => p.posix.dirname(path);

  /// A stored path as a run-root-relative one.
  String toRunRoot(String stored) =>
      p.posix.normalize(p.posix.join(_dir, stored));

  /// A run-root-relative path as the file stores it.
  String fromRunRoot(String runRelative) {
    final rel = p.posix.relative(runRelative, from: _dir);
    return p.posix.normalize(rel);
  }
}

/// A file read from disk with the place it was read from.
class LoadedBaseline {
  final BaselineLocation location;
  final BaselineFile file;

  const LoadedBaseline({required this.location, required this.file});

  String get path => location.path;
}

/// The next content of a baseline: [recorded] (run-root-relative path to
/// scopes) replaces whatever [existing] held for every path [inRun] says
/// the run covered; entries for other paths are kept. An [existing] file
/// recorded under different knobs is dropped whole, since its values would
/// not be comparable with the new ones.
BaselineFile updateBaseline({
  required BaselineFile? existing,
  required BaselineLocation location,
  required Map<String, Object?> run,
  required List<String> metrics,
  required Map<String, Map<String, BaselineEntry>> recorded,
  required bool Function(String runRelativePath) inRun,
}) {
  final files = <String, Map<String, BaselineEntry>>{};
  if (existing != null && sameRun(existing.run, run)) {
    for (final e in existing.files.entries) {
      if (!inRun(location.toRunRoot(e.key))) files[e.key] = e.value;
    }
  }
  for (final e in recorded.entries) {
    files[location.fromRunRoot(e.key)] = e.value;
  }
  return BaselineFile(run: run, metrics: metrics..sort(), files: files);
}

/// Deep equality over two `run` blocks as JSON values.
bool sameRun(Object? a, Object? b) {
  if (a is Map && b is Map) {
    if (a.length != b.length) return false;
    for (final k in a.keys) {
      if (!b.containsKey(k) || !sameRun(a[k], b[k])) return false;
    }
    return true;
  }
  if (a is List && b is List) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!sameRun(a[i], b[i])) return false;
    }
    return true;
  }
  return a == b;
}
