/// The commands that talk to an LLM agent rather than measure code:
/// `agent` prints the guide, `init` installs a pointer to it in a project.
///
/// `init` writes a short block into the project's instructions file
/// (`CLAUDE.md` or `AGENTS.md`, whichever exists) between
/// `<!-- dmetrics:start -->` and `<!-- dmetrics:end -->` markers, so a re-run
/// replaces the block and never touches the text around it. The block is
/// deliberately short: an instructions file is loaded on every turn, so it
/// carries only what makes the agent run the tool and read the guide; the
/// guide itself is fetched on demand with `dmetrics agent`. `--skill`
/// additionally writes the guide as a skill, for projects that prefer it
/// loaded without the extra command. Claude Code and Codex read the same
/// SKILL.md format (the Agent Skills spec) from different directories, so
/// one rendering serves both and only the path differs.
library;

import 'dart:io';

import 'package:args/args.dart';
import 'package:path/path.dart' as p;

import '../io/analyze_paths.dart' show UsageError;
import '../version.dart';
import 'agent_guide.dart';

export 'agent_guide.dart' show agentGuide;

const blockStart = '<!-- $toolName:start -->';
const blockEnd = '<!-- $toolName:end -->';

/// Instructions files in the order `init` looks for them when `--file` is
/// not given; the first is created when none exists.
const instructionsFiles = ['CLAUDE.md', 'AGENTS.md'];

/// Where each agent discovers repository skills.
const skillPaths = {
  'claude': '.claude/skills/$toolName/SKILL.md',
  'codex': '.agents/skills/$toolName/SKILL.md',
};

ArgParser buildAgentParser() =>
    ArgParser()
      ..addFlag('help', abbr: 'h', negatable: false, help: 'Show this help.');

ArgParser buildInitParser() => ArgParser()
  ..addMultiOption(
    'file',
    splitCommas: false,
    valueHelp: 'path',
    help:
        'Instructions file to write the block into, relative to the working '
        'directory. Repeatable. Default: the first of '
        '${instructionsFiles.join(', ')} that exists, else '
        '${instructionsFiles.first}.',
  )
  ..addMultiOption(
    'skill',
    allowed: skillPaths.keys.toList(),
    valueHelp: 'agent',
    help:
        'Also write the guide as a skill for that agent. Repeatable. '
        '${skillPaths.entries.map((e) => '${e.key}: ${e.value}').join('; ')}.',
  )
  ..addFlag('help', abbr: 'h', negatable: false, help: 'Show this help.');

/// Writes the block (and the skill when asked) under [runRoot] and returns
/// the report of what was done, one line per file. Throws [UsageError] on
/// a target argument: `init` has none, and a stray path most likely meant
/// `analyze`.
String runInit(ArgResults parsed, {required String runRoot}) {
  if (parsed.rest.isNotEmpty) {
    throw UsageError('`init` takes no targets, got `${parsed.rest.join(' ')}`');
  }
  final skills = parsed.multiOption('skill');
  final files = parsed.multiOption('file');
  final block = _block(runRoot, skills.isNotEmpty);
  final lines = [
    for (final file
        in files.isEmpty ? [_defaultInstructionsFile(runRoot)] : files)
      (file, _writeBlock(File(p.join(runRoot, file)), block)),
    for (final skill in skills)
      (
        skillPaths[skill]!,
        _writeSkill(File(p.join(runRoot, skillPaths[skill]!))),
      ),
  ];
  final width = lines.map((l) => l.$1.length).reduce((a, b) => a > b ? a : b);
  return lines.map((l) => '${l.$1.padRight(width)}  ${l.$2}\n').join();
}

String _defaultInstructionsFile(String runRoot) => instructionsFiles.firstWhere(
  (f) => File(p.join(runRoot, f)).existsSync(),
  orElse: () => instructionsFiles.first,
);

/// Replaces the block between the markers when present, appends it after
/// the existing text otherwise, creates the file when missing.
String _writeBlock(File file, String block) {
  if (!file.existsSync()) {
    file.parent.createSync(recursive: true);
    file.writeAsStringSync('$block\n');
    return 'written';
  }
  final content = file.readAsStringSync();
  final start = content.indexOf(blockStart);
  final end = content.indexOf(blockEnd, start < 0 ? 0 : start);
  if (start >= 0 && end > start) {
    file.writeAsStringSync(
      content.substring(0, start) +
          block +
          content.substring(end + blockEnd.length),
    );
    return 'updated';
  }
  final gap = content.isEmpty || content.endsWith('\n\n')
      ? ''
      : content.endsWith('\n')
      ? '\n'
      : '\n\n';
  file.writeAsStringSync('$content$gap$block\n');
  return 'appended';
}

String _writeSkill(File file) {
  final existed = file.existsSync();
  file.parent.createSync(recursive: true);
  file.writeAsStringSync(_skill);
  return existed ? 'updated' : 'written';
}

/// The command the block tells the agent to run: the package's source roots
/// that exist, so the line works as written in that project.
String _analyzeCommand(String runRoot) {
  final roots = [
    'lib',
    'bin',
  ].where((d) => Directory(p.join(runRoot, d)).existsSync());
  return [toolName, 'analyze', ...roots].join(' ');
}

String _block(String runRoot, bool withSkill) =>
    '''
$blockStart
## Code metrics — $toolName

This project measures code with **$toolName** (cyclomatic and cognitive
complexity per function, import coupling per library) against thresholds in
`analysis_options.yaml`. Run it once per task, after your edits, not after
every edit:

    ${_analyzeCommand(runRoot)}

Exit 0 is clean, 1 means violations, 2 means the analysis did not complete
(fix that first). Before interpreting a report, run `$toolName agent`: it
explains the report line, what each metric measures and what to do about a
warning.${withSkill ? ' The same guide is loaded as the `$toolName` skill.' : ''}
Warnings are evidence to weigh, not orders to obey. Never lower a threshold
or add an override to make a run pass; propose the change instead.
$blockEnd''';

const _skill =
    '''
---
name: $toolName
description: How to run $toolName and read its reports. Use when running $toolName, reading a $toolName report, or deciding what to do about a cyclomatic, cognitive or coupling warning.
---

<!-- Generated by `$toolName init`; a re-run overwrites this file. -->

$agentGuide''';
