import 'dart:io';

import 'package:dmetrics/src/cli/agent.dart';
import 'package:dmetrics/src/cli/cli.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('dmetrics_init_'));
  tearDown(() => tmp.deleteSync(recursive: true));

  ({int code, String out, String err}) run(List<String> args) {
    final out = StringBuffer();
    final err = StringBuffer();
    final code = runCli(args, out: out, err: err, runRoot: tmp.path);
    return (code: code, out: out.toString(), err: err.toString());
  }

  String read(String rel) => File(p.join(tmp.path, rel)).readAsStringSync();

  test('creates CLAUDE.md with one marked block', () {
    final r = run(['init']);
    expect(r.code, 0);
    expect(r.err, isEmpty);
    expect(r.out, 'CLAUDE.md  written\n');
    final text = read('CLAUDE.md');
    expect(text, startsWith('$blockStart\n'));
    expect(text, endsWith('$blockEnd\n'));
    expect(blockStart.allMatches(text).length, 1);
    // No lib or bin here, so the command carries no targets.
    expect(text, contains('\n    dmetrics analyze\n'));
    expect(text, contains('`dmetrics agent`'));
    expect(text, isNot(contains('skill')));
  });

  test('names the source roots that exist', () {
    Directory(p.join(tmp.path, 'lib')).createSync();
    Directory(p.join(tmp.path, 'bin')).createSync();
    run(['init']);
    expect(read('CLAUDE.md'), contains('\n    dmetrics analyze lib bin\n'));
  });

  test('appends after existing text and replaces its own block on re-run', () {
    final file = File(p.join(tmp.path, 'CLAUDE.md'))
      ..writeAsStringSync('# Project\n\nKeep me.\n');
    expect(run(['init']).out, 'CLAUDE.md  appended\n');
    final first = read('CLAUDE.md');
    expect(first, startsWith('# Project\n\nKeep me.\n\n$blockStart'));

    // Text after the block survives too, and nothing is duplicated.
    file.writeAsStringSync('$first\nTrailing note.\n');
    expect(run(['init']).out, 'CLAUDE.md  updated\n');
    final second = read('CLAUDE.md');
    expect(second, '$first\nTrailing note.\n');
    expect(blockStart.allMatches(second).length, 1);
    expect(blockEnd.allMatches(second).length, 1);
  });

  test('--file picks the instructions files, repeatable', () {
    final r = run(['init', '--file', 'AGENTS.md']);
    expect(r.out, 'AGENTS.md  written\n');
    expect(read('AGENTS.md'), contains(blockStart));
    expect(File(p.join(tmp.path, 'CLAUDE.md')).existsSync(), isFalse);

    final both = run(['init', '--file', 'CLAUDE.md', '--file', 'AGENTS.md']);
    expect(both.out, 'CLAUDE.md  written\nAGENTS.md  updated\n');
  });

  test('without --file the first existing instructions file is used', () {
    File(p.join(tmp.path, 'AGENTS.md')).writeAsStringSync('# Agents\n');
    expect(run(['init']).out, 'AGENTS.md  appended\n');
    expect(File(p.join(tmp.path, 'CLAUDE.md')).existsSync(), isFalse);

    // CLAUDE.md wins once it exists, so a project that has both and points
    // one at the other gets the block once.
    File(p.join(tmp.path, 'CLAUDE.md')).writeAsStringSync('@AGENTS.md\n');
    expect(run(['init']).out, 'CLAUDE.md  appended\n');
  });

  test(
    '--skill writes the guide where that agent looks; the block says so',
    () {
      final r = run(['init', '--skill', 'claude', '--skill', 'codex']);
      expect(r.code, 0, reason: r.err);
      final claude = skillPaths['claude']!;
      final codex = skillPaths['codex']!;
      expect(
        r.out,
        'CLAUDE.md                         written\n'
        '$claude  written\n'
        '$codex  written\n',
      );
      expect(claude, '.claude/skills/dmetrics/SKILL.md');
      expect(codex, '.agents/skills/dmetrics/SKILL.md');
      // One rendering serves both: same Agent Skills frontmatter, same body.
      final skill = read(claude);
      expect(read(codex), skill);
      expect(skill, startsWith('---\nname: dmetrics\ndescription: '));
      expect(skill, contains('\n---\n'));
      expect(skill, contains(agentGuide));
      expect(read('CLAUDE.md'), contains('`dmetrics` skill'));

      // The skill is generated, so a re-run overwrites it.
      File(p.join(tmp.path, codex)).writeAsStringSync('stale');
      expect(
        run(['init', '--skill', 'codex']).out,
        endsWith('$codex  updated\n'),
      );
      expect(read(codex), skill);
    },
  );

  test('usage: targets and unknown flags are exit 3, -h prints usage', () {
    for (final args in [
      ['init', 'lib'],
      ['init', '--bogus'],
      ['init', '--json'],
      ['init', '--skill'],
      ['init', '--skill', 'cursor'],
    ]) {
      final r = run(args);
      expect(r.code, exitUsage, reason: '$args');
      expect(r.err, contains('Usage: dmetrics init'), reason: '$args');
      expect(r.out, isEmpty, reason: '$args');
    }
    expect(File(p.join(tmp.path, 'CLAUDE.md')).existsSync(), isFalse);
    final h = run(['init', '-h']);
    expect(h.code, 0);
    expect(h.out, startsWith('Usage: dmetrics init'));
  });

  test('an unwritable target is exit 2 with the path', () {
    Directory(p.join(tmp.path, 'CLAUDE.md')).createSync();
    final r = run(['init']);
    expect(r.code, 2);
    expect(r.err, startsWith('could not write '));
    expect(r.err, contains('CLAUDE.md'));
    expect(r.out, isEmpty);
  });
}
