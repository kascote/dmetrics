import 'dart:convert';
import 'dart:io';

import 'package:dmetrics/dmetrics.dart';
import 'package:dmetrics/src/cli/cli.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('dmetrics_cli_'));
  tearDown(() => tmp.deleteSync(recursive: true));

  void write(String rel, String content) {
    final f = File(p.join(tmp.path, rel));
    f.parent.createSync(recursive: true);
    f.writeAsStringSync(content);
  }

  const fn = 'int f(int x) => x > 0 ? (x > 1 ? 2 : 1) : 0;\n';

  ({int code, String out, String err}) run(List<String> args) {
    final out = StringBuffer();
    final err = StringBuffer();
    final code = runCli(args, out: out, err: err, runRoot: tmp.path);
    return (code: code, out: out.toString(), err: err.toString());
  }

  group('usage', () {
    test('no args, unknown command, bad flag: exit 3 with usage on stderr', () {
      for (final args in [
        <String>[],
        ['frobnicate'],
        ['analyze', '--bogus'],
        ['analyze', '--fail-on', 'never'],
        ['analyze', '--set', 'novalue'],
        ['analyze', '--threshold', 'cyclomatic=8'],
        ['analyze', '--threshold', 'cyclomatic=warn:9,fail:8'],
        ['stats', '--all'],
        ['stats', '--fail-on', 'warn'],
        ['stats', '--set', 'novalue'],
        ['deps', '--all'],
        ['deps', '--fail-on', 'warn'],
        ['deps', '--top', '0'],
        ['deps', '--depth', 'two'],
        ['agent', 'lib'],
        ['agent', '--json'],
      ]) {
        final r = run(args);
        expect(r.code, exitUsage, reason: '$args');
        expect(r.err, contains('Usage:'), reason: '$args');
        expect(r.out, isEmpty, reason: '$args');
      }
    });

    test('--help and --version', () {
      final top = run(['--help']);
      expect(top.code, 0);
      expect(top.out, contains('$toolName analyze'));
      expect(top.out, contains('$toolName stats'));
      expect(top.out, contains('$toolName deps'));
      expect(top.out, contains('$toolName agent'));
      expect(top.out, contains('$toolName init'));
      expect(
        run(['analyze', '-h']).out,
        startsWith('Usage: $toolName analyze'),
      );
      expect(run(['stats', '-h']).out, startsWith('Usage: $toolName stats'));
      expect(run(['deps', '-h']).out, startsWith('Usage: $toolName deps'));
      expect(run(['agent', '-h']).out, startsWith('Usage: $toolName agent'));
      expect(run(['--version']).out, '$toolName $toolVersion\n');
    });

    test('agent prints the guide and touches no files', () {
      final r = run(['agent']);
      expect(r.code, 0);
      expect(r.err, isEmpty);
      expect(r.out, startsWith('$toolName — how to use and read it\n'));
      // The sections a reader navigates by, and the traps the guide exists
      // to explain: the same suppression syntax the engine accepts, and the
      // exit codes the CLI actually returns.
      for (final needle in [
        'When to run',
        'Reading a report line',
        'The metrics',
        'What to do about a warning',
        'Suppressing',
        'Other commands',
        '// ignore: dmetrics_cognitive',
        '// ignore_for_file: dmetrics_coupling',
        'table-shaped',
        '<closure#2>',
        'Exit 0 clean • 1 violations • 2 analysis incomplete',
      ]) {
        expect(r.out, contains(needle), reason: needle);
      }
      expect(tmp.listSync(), isEmpty);
    });

    test('a missing target is exit 3 without usage noise', () {
      final r = run(['analyze', 'nope.dart']);
      expect(r.code, exitUsage);
      expect(r.err, 'no such file or directory: nope.dart\n');
    });
  });

  group('analyze', () {
    test('clean run: exit 0, console summary', () {
      write('lib/a.dart', 'int f() => 0;\n');
      final r = run(['analyze']);
      expect(r.code, 0);
      expect(r.err, isEmpty);
      // The function and the library it sits in; one `ok` per metric result.
      expect(
        r.out,
        '2 scopes in 1 file • 0 fail, 0 warn, ${defaultMetrics().length} ok, '
        '0 suppressed • status: ok\n',
      );
    });

    test('--color: never by default off a tty, always forces, auto follows the tty', () {
      write('lib/a.dart', fn);
      const flags = [
        'analyze',
        'lib',
        '--threshold',
        'cyclomatic=warn:1,fail:2',
      ];
      expect(run(flags).out, isNot(contains('\x1B[')));
      expect(
        run([...flags, '--color', 'always']).out,
        contains('\x1B[31mfail'),
      );
      final out = StringBuffer();
      runCli(
        [...flags, '--color', 'auto'],
        out: out,
        err: StringBuffer(),
        runRoot: tmp.path,
        stdoutIsTerminal: true,
      );
      expect(out.toString(), contains('\x1B[31mfail'));
      expect(run([...flags, '--color', 'plaid']).code, exitUsage);
    });

    test('--threshold and --fail-on drive exit 1', () {
      write('lib/a.dart', fn);
      expect(run(['analyze', 'lib']).code, 0);
      expect(
        run(['analyze', 'lib', '--threshold', 'cyclomatic=warn:3,fail:10'])
            .code,
        0,
      );
      expect(
        run([
          'analyze',
          'lib',
          '--threshold',
          'cyclomatic=warn:3,fail:10',
          '--fail-on',
          'warn',
        ]).code,
        1,
      );
      expect(
        run(['analyze', 'lib', '--threshold', 'cyclomatic=fail:3,warn:1']).code,
        1,
      );
    });

    test('--json writes only the report to stdout', () {
      write('lib/a.dart', fn);
      write('lib/bad.dart', 'int g() => 0\n');
      final r = run([
        'analyze',
        'lib',
        '--json',
        '--json-contributors',
        'summary',
      ]);
      expect(r.code, 2);
      expect(r.err, isEmpty);
      final json = jsonDecode(r.out) as Map;
      expect(json['status'], 'errors');
      expect(json['schemaVersion'], schemaVersion);
      expect((json['files'] as List).map((f) => (f as Map)['status']), [
        'ok',
        'errors',
      ]);
      final scopes = (json['files'] as List).first['scopes'] as List;
      final scope = scopes.cast<Map<String, Object?>>().singleWhere(
        (s) => s['kind'] == 'function',
      );
      expect(
        (scope['results'] as Map)['cyclomatic'],
        isNot(contains('contributors')),
      );
    });

    test('--set and --config flow into the run section', () {
      write('lib/a.dart', fn);
      write(
        'conf/analysis_options.yaml',
        'dmetrics:\n  metrics:\n    cyclomatic: {count_null_coalescing: false}\n',
      );
      final r = run([
        'analyze',
        'lib',
        '--json',
        '--config',
        'conf/analysis_options.yaml',
        '--set',
        'cyclomatic.count_case_arms=false',
        '--set',
        'closure_rollup=include_in_parent',
      ]);
      expect(r.code, 0, reason: r.err);
      final json = jsonDecode(r.out) as Map;
      expect(json['run'], {
        'cyclomatic': {
          'count_null_coalescing': false,
          'count_case_arms': false,
        },
        'closure_rollup': 'include_in_parent',
        'fail_on': 'fail',
      });
      expect((json['configs'] as List).single['root'], 'conf');
    });

    test('invalid config: exit 2, diagnostic on stderr-free console', () {
      write('pubspec.yaml', 'name: x\n');
      write('analysis_options.yaml', 'dmetrics:\n  nope: 1\n');
      write('lib/a.dart', fn);
      final r = run(['analyze']);
      expect(r.code, 2);
      expect(
        r.out,
        startsWith('analysis_options.yaml:2:3 • error • unknown key `nope`'),
      );
    });
  });

  group('stats', () {
    test('console output, exit 0 even with violations', () {
      write('lib/a.dart', fn);
      write('lib/b.dart', fn.replaceFirst('f(', 'g('));
      final r = run([
        'stats',
        'lib',
        '--threshold',
        'cyclomatic=warn:1,fail:2',
      ]);
      expect(r.code, 0);
      expect(r.err, isEmpty);
      expect(r.out, contains('cyclomatic • 2 scopes in 2 files\n'));
      expect(r.out, contains('Thresholds • warn ≥ 1, fail ≥ 2\n'));
      expect(r.out, contains('  ≥ fail     2 100.0%\n'));
      expect(r.out, contains('    lib/a.dart:1 function f\n'));
      expect(r.out, contains('    lib/b.dart:1 function g\n'));
      expect(
        run([
          'stats',
          'lib',
          '--threshold',
          'cyclomatic=warn:1,fail:2',
          '--color',
          'always',
        ]).out,
        contains('\x1B[1mcyclomatic\x1B[0m'),
      );
    });

    test('--json writes only the stats document; parse errors exit 2', () {
      write('lib/a.dart', fn);
      write('lib/bad.dart', 'int g() => 0\n');
      final r = run([
        'stats',
        'lib',
        '--json',
        '--set',
        'closure_rollup=include_in_parent',
      ]);
      expect(r.code, 2);
      expect(r.err, isEmpty);
      final json = jsonDecode(r.out) as Map;
      expect(json['schemaVersion'], statsSchemaVersion);
      expect(json['status'], 'errors');
      expect(json['summary'], {'files': 2, 'filesWithErrors': 1});
      expect(((json['metrics'] as Map)['cyclomatic'] as Map)['scopes'], 2);
      expect(json, isNot(contains('files')));
    });

    test('built-in 10/20 applies; `thresholds: none` opts out', () {
      write('lib/a.dart', fn);
      expect(run(['stats']).out, contains('Thresholds • warn ≥ 10, fail ≥ 20'));
      write('pubspec.yaml', 'name: x\n');
      write(
        'analysis_options.yaml',
        'dmetrics:\n  metrics:\n    cyclomatic: {thresholds: none}\n',
      );
      expect(run(['stats']).out, contains('Thresholds • none configured'));
      final json = jsonDecode(run(['analyze', '--json']).out) as Map;
      final configs = json['configs'] as List;
      expect(
        ((configs.single['metrics'] as Map)['cyclomatic'] as Map)['thresholds'],
        isNull,
      );
    });
  });

  group('deps', () {
    const a = "import 'b.dart';\nint f() => 0;\n";
    const b = "import 'a.dart';\n";

    test('console output, exit 0 even with violations', () {
      write('lib/a.dart', a);
      write('lib/b.dart', b);
      write('lib/src/c.dart', "import '../a.dart';\n");
      final r = run(['deps', 'lib', '--threshold', 'coupling=warn:1,fail:1']);
      expect(r.code, 0);
      expect(r.err, isEmpty);
      expect(
        r.out,
        startsWith(
          'Dependencies • 3 libraries • 3 edges (3 imports, 0 exports)\n'
          'Cycles • 1 component • largest 2 of 3 libraries (66.7%) • '
          '1 back edge\n'
          '  #1 • 2 libraries • 1 back edge\n'
          '    lib/b.dart → lib/a.dart\n',
        ),
      );
      expect(r.out, contains('      1     2  0.33  lib/a.dart  cycle #1\n'));
      expect(r.out, contains('Directories • depth 1 • 1 directory • 0 edges'));
      expect(
        run(['deps', 'lib', '--top', '1', '--color', 'always']).out,
        contains('\x1B[1mFan-out\x1B[0m • top 1'),
      );
    });

    test('--json writes only the deps document; parse errors exit 2', () {
      write('lib/a.dart', a);
      write('lib/b.dart', b);
      write('lib/bad.dart', 'int g() => 0\n');
      final r = run(['deps', 'lib', '--json', '--depth', '2']);
      expect(r.code, 2);
      expect(r.err, isEmpty);
      final json = jsonDecode(r.out) as Map;
      expect(json['schemaVersion'], depsSchemaVersion);
      expect(json['status'], 'errors');
      expect((json['summary'] as Map)['libraries'], 3);
      expect((json['directories'] as Map)['depth'], 2);
      expect(json, isNot(contains('files')));
    });
  });

  test('bin/dmetrics.dart end to end', () {
    write('lib/a.dart', fn);
    final result = Process.runSync(Platform.resolvedExecutable, [
      'run',
      p.absolute('bin/dmetrics.dart'),
      'analyze',
      'lib',
      '--json',
      '--threshold',
      'cyclomatic=warn:1,fail:2',
    ], workingDirectory: tmp.path);
    expect(result.exitCode, 1, reason: '${result.stderr}');
    final json = jsonDecode(result.stdout as String) as Map;
    expect(json['status'], 'violations');
    expect((json['files'] as List).single['path'], 'lib/a.dart');
  }, timeout: const Timeout(Duration(minutes: 2)));
}
