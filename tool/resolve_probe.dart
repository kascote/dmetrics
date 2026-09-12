// Cost probe for the resolved-pipeline spike. Not part of the product.
//
// Measures, per package and in a fresh process each, what dmetrics pays today
// (parse) against the three ways a dependency metric could be fed:
//
//   parse       parseString over every analyzed file (today's pipeline)
//   directives  parse + import/export URIs resolved via package_config.json
//               (a library graph with no resolution at all)
//   elements    AnalysisContextCollection + getLibraryByUri per library
//               (element model only, no resolved ASTs)
//   units       AnalysisContextCollection + getResolvedUnit per file
//               (the full resolved pipeline every metric would consume)
//
// Usage:
//   dart run tool/resolve_probe.dart [--modes a,b,c] [--out rows.jsonl]
//       [--sdk <dart-sdk-dir>] name=path/to/lib ...
//
// Each package/mode pair runs in a child process so peak RSS is per run.
// The numbers in the spec were taken from an AOT build (`dart compile exe`),
// which needs `--sdk` because the analyzer cannot infer the SDK from a
// compiled executable; under `dart run` the default is right.
//
// The 2026-09-12 run over 13 packages found that the directive-level graph
// costs the same as parsing and produced the same edge counts as the
// element model everywhere, and that resolution cost is a fixed cost of
// linking the package's transitive dependency closure (0.2-2 s, 115-815 MB
// peak), not a function of the package's own size.

import 'dart:convert';
import 'dart:io';

import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:package_config/package_config.dart';
import 'package:path/path.dart' as p;

const allModes = ['parse', 'directives', 'elements', 'units'];

Future<void> main(List<String> args) async {
  if (args.isNotEmpty && args.first == '--worker') {
    final row = await _work(args[1], args[2], args[3], args[4]);
    stdout.writeln(jsonEncode(row));
    return;
  }

  var modes = allModes;
  String? out;
  // The AOT-compiled probe cannot infer the SDK from its own executable.
  var sdk =
      Platform.environment['DART_SDK'] ??
      p.dirname(p.dirname(Platform.resolvedExecutable));
  final packages = <(String, String)>[];
  for (var i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--modes':
        modes = args[++i].split(',');
      case '--out':
        out = args[++i];
      case '--sdk':
        sdk = args[++i];
      default:
        final eq = args[i].indexOf('=');
        packages.add((args[i].substring(0, eq), args[i].substring(eq + 1)));
    }
  }

  final rows = <Map<String, Object?>>[];
  final sink = out == null ? null : File(out).openWrite();
  for (final (name, lib) in packages) {
    for (final mode in modes) {
      final row = await _spawn(name, p.normalize(p.absolute(lib)), mode, sdk);
      rows.add(row);
      sink?.writeln(jsonEncode(row));
      stderr.writeln(_progress(row));
    }
  }
  await sink?.close();
  stdout.writeln(_table(rows));
}

Future<Map<String, Object?>> _spawn(
  String name,
  String lib,
  String mode,
  String sdk,
) async {
  final exe = Platform.resolvedExecutable;
  final script = Platform.script.toFilePath();
  final cmd = script.endsWith('.dart')
      ? [exe, 'run', script, '--worker', name, lib, mode, sdk]
      : [exe, '--worker', name, lib, mode, sdk];
  final r = await Process.run(cmd.first, cmd.sublist(1));
  if (r.exitCode != 0) {
    return {
      'name': name,
      'mode': mode,
      'error':
          'exit ${r.exitCode}: ${(r.stderr as String).trim().split('\n').take(3).join(' | ')}',
    };
  }
  return jsonDecode((r.stdout as String).trim().split('\n').last)
      as Map<String, Object?>;
}

String _progress(Map<String, Object?> r) {
  if (r['error'] != null) {
    return '${r['name']} ${r['mode']}: ERROR ${r['error']}';
  }
  return '${r['name']} ${r['mode']}: ${r['totalMs']} ms, ${r['maxRssMb']} MB';
}

// ---------------------------------------------------------------- worker

Future<Map<String, Object?>> _work(
  String name,
  String lib,
  String mode,
  String sdk,
) async {
  final listing = Stopwatch()..start();
  final files = _dartFiles(lib);
  listing.stop();
  var loc = 0;
  for (final f in files) {
    loc += File(f).readAsLinesSync().length;
  }
  final row = <String, Object?>{
    'name': name,
    'mode': mode,
    'files': files.length,
    'loc': loc,
    'listMs': listing.elapsedMilliseconds,
  };
  final total = Stopwatch()..start();
  switch (mode) {
    case 'parse':
      row.addAll(_parse(files));
    case 'directives':
      row.addAll(await _directives(lib, files));
    case 'elements':
      row.addAll(await _elements(lib, files, sdk));
    case 'units':
      row.addAll(await _units(lib, files, sdk));
    default:
      throw ArgumentError('unknown mode $mode');
  }
  total.stop();
  row['totalMs'] = total.elapsedMilliseconds;
  row['maxRssMb'] = ProcessInfo.maxRss ~/ (1024 * 1024);
  row['currentRssMb'] = ProcessInfo.currentRss ~/ (1024 * 1024);
  return row;
}

/// The files dmetrics analyzes: every `.dart` under [lib], generated files
/// excluded as by its default config.
List<String> _dartFiles(String lib) {
  final out = <String>[];
  for (final e in Directory(
    lib,
  ).listSync(recursive: true, followLinks: false)) {
    if (e is! File) continue;
    final path = e.path;
    if (!path.endsWith('.dart')) continue;
    if (path.endsWith('.g.dart') || path.endsWith('.freezed.dart')) continue;
    if (p.split(p.relative(path, from: lib)).any((s) => s.startsWith('.'))) {
      continue;
    }
    out.add(path);
  }
  return out..sort();
}

Map<String, Object?> _parse(List<String> files) {
  var errors = 0;
  var nodes = 0;
  for (final f in files) {
    final r = parseString(
      content: File(f).readAsStringSync(),
      path: f,
      throwIfDiagnostics: false,
    );
    if (r.errors.isNotEmpty) errors++;
    nodes += r.unit.declarations.length;
  }
  return {'filesWithErrors': errors, 'topLevelDecls': nodes};
}

/// Directive-level graph: import/export URIs, `package:` resolved through
/// the nearest package_config.json, relative ones against the file. Counts
/// edges into the same package (what a coupling metric would keep) and
/// edges out of it, `dart:` excluded; parts are folded into their library
/// by counting every file's directives.
Future<Map<String, Object?>> _directives(String lib, List<String> files) async {
  final configFile = _findPackageConfig(lib);
  final config = configFile == null
      ? null
      : await loadPackageConfig(File(configFile));
  final own = config?.packageOf(Uri.file(p.join(lib, 'x.dart')));
  var inPackage = 0, outPackage = 0, unresolved = 0, parts = 0, partOf = 0;
  for (final f in files) {
    final r = parseString(
      content: File(f).readAsStringSync(),
      path: f,
      throwIfDiagnostics: false,
    );
    for (final d in r.unit.directives) {
      final String? uriText;
      switch (d) {
        case ImportDirective():
          uriText = d.uri.stringValue;
        case ExportDirective():
          uriText = d.uri.stringValue;
        case PartDirective():
          parts++;
          continue;
        case PartOfDirective():
          partOf++;
          continue;
        default:
          continue;
      }
      if (uriText == null) {
        unresolved++;
        continue;
      }
      final uri = Uri.tryParse(uriText);
      if (uri == null || uri.scheme == 'dart') continue;
      final Uri? resolved;
      if (uri.scheme == 'package') {
        resolved = config?.resolve(uri);
      } else if (uri.scheme.isEmpty) {
        resolved = Uri.file(f).resolveUri(uri);
      } else {
        resolved = null;
      }
      if (resolved == null) {
        unresolved++;
      } else if (own != null && config!.packageOf(resolved) == own) {
        inPackage++;
      } else {
        outPackage++;
      }
    }
  }
  return {
    'packageConfig': configFile,
    'package': own?.name,
    'edgesIn': inPackage,
    'edgesOut': outPackage,
    'unresolved': unresolved,
    'partDirectives': parts,
    'partOfFiles': partOf,
  };
}

String? _findPackageConfig(String dir) {
  for (var d = dir; ; d = p.dirname(d)) {
    final f = p.join(d, '.dart_tool', 'package_config.json');
    if (File(f).existsSync()) return f;
    if (p.dirname(d) == d) return null;
  }
}

/// Element-model graph: one getLibraryByUri per defining unit, imports and
/// exports read off every fragment (so parts are folded in). No resolved
/// ASTs are requested.
Future<Map<String, Object?>> _elements(
  String lib,
  List<String> files,
  String sdk,
) async {
  final build = Stopwatch()..start();
  final collection = AnalysisContextCollection(
    includedPaths: [lib],
    sdkPath: sdk,
  );
  final context = collection.contextFor(lib);
  final session = context.currentSession;
  build.stop();

  final first = Stopwatch();
  var libraries = 0, parts = 0, failed = 0, inPackage = 0, outPackage = 0;
  final ownName = _directivesPackageName(
    session.uriConverter.pathToUri(files.first),
  );
  for (final f in files) {
    final uri = session.uriConverter.pathToUri(f);
    if (uri == null) {
      failed++;
      continue;
    }
    if (libraries == 0) first.start();
    final r = await session.getLibraryByUri(uri.toString());
    if (libraries == 0 && first.isRunning) first.stop();
    if (r is! LibraryElementResult) {
      if (r is NotLibraryButPartResult) {
        parts++;
      } else {
        failed++;
      }
      continue;
    }
    libraries++;
    for (final frag in r.element.fragments) {
      for (final target in [
        for (final i in frag.libraryImports) i.importedLibrary?.uri,
        for (final e in frag.libraryExports) e.exportedLibrary?.uri,
      ]) {
        if (target == null || target.scheme == 'dart') continue;
        if (_directivesPackageName(target) == ownName) {
          inPackage++;
        } else {
          outPackage++;
        }
      }
    }
  }
  await collection.dispose();
  return {
    'buildMs': build.elapsedMilliseconds,
    'firstMs': first.elapsedMilliseconds,
    'package': ownName,
    'libraries': libraries,
    'partFiles': parts,
    'failed': failed,
    'edgesIn': inPackage,
    'edgesOut': outPackage,
  };
}

String? _directivesPackageName(Uri? uri) =>
    uri != null && uri.scheme == 'package' && uri.pathSegments.isNotEmpty
    ? uri.pathSegments.first
    : null;

/// The full resolved pipeline: a resolved AST for every analyzed file, in the
/// same order dmetrics traverses them.
Future<Map<String, Object?>> _units(
  String lib,
  List<String> files,
  String sdk,
) async {
  final build = Stopwatch()..start();
  final collection = AnalysisContextCollection(
    includedPaths: [lib],
    sdkPath: sdk,
  );
  final session = collection.contextFor(lib).currentSession;
  build.stop();

  final first = Stopwatch()..start();
  var resolved = 0, failed = 0, withErrors = 0, decls = 0;
  for (final f in files) {
    final r = await session.getResolvedUnit(f);
    if (resolved == 0 && failed == 0) first.stop();
    if (r is! ResolvedUnitResult) {
      failed++;
      continue;
    }
    resolved++;
    if (r.diagnostics.isNotEmpty) withErrors++;
    decls += r.unit.declarations.length;
  }
  await collection.dispose();
  return {
    'buildMs': build.elapsedMilliseconds,
    'firstMs': first.elapsedMilliseconds,
    'resolved': resolved,
    'failed': failed,
    'filesWithDiagnostics': withErrors,
    'topLevelDecls': decls,
  };
}

// ---------------------------------------------------------------- table

String _table(List<Map<String, Object?>> rows) {
  final names = <String>[];
  for (final r in rows) {
    final n = r['name'] as String;
    if (!names.contains(n)) names.add(n);
  }
  Map<String, Object?>? find(String name, String mode) {
    for (final r in rows) {
      if (r['name'] == name && r['mode'] == mode) return r;
    }
    return null;
  }

  String ms(Map<String, Object?>? r) => r == null
      ? ''
      : r['error'] != null
      ? 'ERR'
      : '${r['totalMs']}';
  String mb(Map<String, Object?>? r) =>
      r == null || r['error'] != null ? '' : '${r['maxRssMb']}';
  String edges(Map<String, Object?>? r) =>
      r == null || r['error'] != null ? '' : '${r['edgesIn']}/${r['edgesOut']}';

  final b = StringBuffer();
  b.writeln(
    '| package | files | kLOC | parse ms | directives ms | dir edges in/out | elements ms | elem edges in/out | units build ms | units first ms | units total ms | RSS parse MB | RSS elements MB | RSS units MB |',
  );
  b.writeln('|---|--:|--:|--:|--:|--:|--:|--:|--:|--:|--:|--:|--:|--:|');
  for (final n in names) {
    final any = rows.firstWhere((r) => r['name'] == n);
    final pr = find(n, 'parse'), di = find(n, 'directives');
    final el = find(n, 'elements'), un = find(n, 'units');
    final kloc = any['loc'] == null
        ? ''
        : ((any['loc'] as int) / 1000).toStringAsFixed(1);
    b.writeln(
      '| $n | ${any['files'] ?? ''} | $kloc | ${ms(pr)} | ${ms(di)} | ${edges(di)} | ${ms(el)} | ${edges(el)} | ${un?['buildMs'] ?? ''} | ${un?['firstMs'] ?? ''} | ${ms(un)} | ${mb(pr)} | ${mb(el)} | ${mb(un)} |',
    );
  }
  for (final r in rows) {
    if (r['error'] != null) {
      b.writeln('\n${r['name']} ${r['mode']}: ${r['error']}');
    }
  }
  return b.toString();
}
