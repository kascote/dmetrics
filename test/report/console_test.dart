import 'package:metra/metra.dart';
import 'package:test/test.dart';

void main() {
  final metrics = [CyclomaticMetric()];
  const content = '''
int low() => 0;
// ignore: metra_cyclomatic
int hidden(int x) => x > 0 ? (x > 1 ? 2 : 1) : 0;
int high(int x) => x > 0 ? (x > 1 ? 2 : 1) : 0;
String name(int x) => switch (x) {
  1 => 'one',
  2 => 'two',
  3 => 'three',
  4 => 'four',
  5 => 'five',
  6 => 'six',
  7 => 'seven',
  8 => 'eight',
  _ => 'many',
};
''';
  const config = AnalysisConfig(
    roots: {
      '.': RootConfig(
        metrics: {
          'cyclomatic': MetricConfig(threshold: Threshold(warn: 2, fail: 3)),
        },
      ),
    },
  );
  final result = RunResult(
    metrics: metrics,
    config: config,
    report: analyze(
      [const SourceFile(path: 'lib/a.dart', content: content, configRoot: '.')],
      metrics,
      config,
    ),
  );

  test('prints findings, suppressions and a summary; ok scopes only with --all', () {
    final lines = renderConsole(result).trimRight().split('\n');
    expect(lines, [
      'lib/a.dart:3:1 • suppressed (ignore) • function hidden • cyclomatic 3 [warn ≥ 2, fail ≥ 3] • ternary ×2',
      'lib/a.dart:4:1 • fail • function high • cyclomatic 3 [warn ≥ 2, fail ≥ 3] • ternary ×2',
      'lib/a.dart:5:1 • fail • function name • cyclomatic 9 [warn ≥ 2, fail ≥ 3] • case ×8 • table-shaped: case',
      '4 scopes in 1 file • 2 fail, 0 warn, 2 ok, 1 suppressed • status: violations',
    ]);
    final all = renderConsole(result, all: true).trimRight().split('\n');
    expect(all, hasLength(5));
    expect(
      all.first,
      'lib/a.dart:1:1 • ok • function low • cyclomatic 1 [warn ≥ 2, fail ≥ 3]',
    );
  });

  test('a palette colors the verdict tag, marker and status only', () {
    final lines = renderConsole(
      result,
      palette: Palette.ansi,
    ).trimRight().split('\n');
    expect(
      lines[1],
      'lib/a.dart:4:1 • \x1B[31mfail\x1B[0m • function high • cyclomatic 3 [warn ≥ 2, fail ≥ 3] • ternary ×2',
    );
    expect(lines[0], contains('\x1B[2msuppressed (ignore)\x1B[0m'));
    expect(lines[2], endsWith('case ×8 • \x1B[2mtable-shaped: case\x1B[0m'));
    expect(
      lines.last,
      '4 scopes in 1 file • \x1B[31m2\x1B[0m fail, 0 warn, \x1B[32m2\x1B[0m ok, '
      '\x1B[2m1\x1B[0m suppressed • status: \x1B[33mviolations\x1B[0m',
    );
    expect(
      renderConsole(result, palette: Palette.plain),
      renderConsole(result),
    );
  });

  test('resolveColor: auto needs a tty, no NO_COLOR, TERM != dumb', () {
    Palette auto({bool tty = true, Map<String, String> env = const {}}) =>
        resolveColor(ColorMode.auto, stdoutIsTerminal: tty, environment: env);
    expect(auto().enabled, isTrue);
    expect(auto(tty: false).enabled, isFalse);
    expect(auto(env: {'NO_COLOR': '1'}).enabled, isFalse);
    expect(auto(env: {'NO_COLOR': ''}).enabled, isTrue);
    expect(auto(env: {'TERM': 'dumb'}).enabled, isFalse);
    expect(
      resolveColor(
        ColorMode.always,
        stdoutIsTerminal: false,
        environment: {},
      ).enabled,
      isTrue,
    );
    expect(
      resolveColor(
        ColorMode.never,
        stdoutIsTerminal: true,
        environment: {},
      ).enabled,
      isFalse,
    );
  });

  test('diagnostics come first, with positions', () {
    final r = RunResult(
      metrics: metrics,
      config: config,
      report: analyze(
        [
          const SourceFile(
            path: 'lib/b.dart',
            content: 'int f() => 0\n',
            configRoot: '.',
          ),
        ],
        metrics,
        config,
      ),
      diagnostics: const [
        RunDiagnostic(path: 'x.dart', message: 'could not read file'),
      ],
    );
    final lines = renderConsole(r).trimRight().split('\n');
    expect(lines.first, 'x.dart • error • could not read file');
    expect(lines[1], startsWith('lib/b.dart:1:12 • error • '));
    expect(lines.last, contains('1 file with parse errors'));
    expect(lines.last, endsWith('status: errors'));
  });

  test('nothing analyzed says so', () {
    final r = RunResult(
      metrics: metrics,
      config: config,
      report: analyze(const [], metrics, config),
    );
    expect(
      renderConsole(r),
      'No files analyzed.\n0 scopes in 0 files • 0 fail, 0 warn, 0 ok, 0 suppressed • status: ok\n',
    );
  });
}
