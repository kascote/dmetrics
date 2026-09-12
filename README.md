# dmetrics

A Dart-native static code metrics engine. It measures every function-shaped
scope in your code (functions, methods, getters, setters, operators,
constructors, local functions, closures), compares each value against
thresholds you configure, and prints one consolidated report as console text
or JSON.

Three metrics ship today: **cyclomatic complexity** and **cognitive
complexity** per function-shaped scope, and **import coupling** per library.
The engine is built so that more metrics register without touching it; the
second one proved it, and the third added a scope kind and a detail payload
without changing the first two.

## Quick start

```sh
# Analyze the current directory
dart run bin/dmetrics.dart analyze

# Analyze specific files or directories, print every scope (not only problems)
dart run bin/dmetrics.dart analyze lib/src/config --all

# JSON report to stdout
dart run bin/dmetrics.dart analyze lib --json
```

Without any configuration every scope reports `ok`: **there are no built-in
thresholds**. Values are measured and printed, but never judged until you set
`thresholds` in `analysis_options.yaml` or pass `--threshold` on the command
line. See [Configuration](#configuration).

## Reading the console output

One line per scope:

```
lib/src/config/loader.dart:372:1 • fail • function resolveRun • cyclomatic 22 [warn ≥ 10, fail ≥ 20] • loop ×8, if ×7, || ×1, && ×2, case ×2, ?? ×1
```

| Part                     | Meaning                                                                     |
| ------------------------ | --------------------------------------------------------------------------- |
| `path:line:col`          | Where the declaration starts, relative to the working directory.            |
| `fail`                   | Verdict: `ok`, `warn`, `fail`, or `suppressed`.                             |
| `function resolveRun`    | Scope kind and qualified name (`Class.method`, `Class.method.<closure#1>`). |
| `cyclomatic 22`          | Metric id and the value the verdict was computed on.                        |
| `[warn ≥ 10, fail ≥ 20]` | The thresholds that applied. Absent when none is configured.                |
| `loop ×8, if ×7, ...`    | Contributor summary: which constructs produced the score.                   |
| `table-shaped: case`     | One kind supplies ≥ 70% of the score (and ≥ 8 in total): a dispatch table, a field-wise `==`, a `copyWith`. Its size is the table's, not a tangle's. `case` pools `pattern-or` and `when`: a guarded arm is still one arm. For cognitive the family is a kind at a nesting level: `table-shaped: if@1` means the score is mostly `if`s one level down (a `switch` whose arms each hold a run of `if`s), `if` alone means `if`s at the top of the body. See below. |
| `cycle of 3`             | On a `library` line: the library is in an import cycle of that many libraries of the run. The members are in the JSON `detail`. |

By default only `warn`, `fail` and `suppressed` scopes are printed, followed
by a one-line summary. `--all` prints every scope. The summary ends with the
run status (`ok`, `violations`, `errors`), which maps to the exit code.

## Exit codes

| Exit | Status       | Meaning                                                                                    |
| ---- | ------------ | ------------------------------------------------------------------------------------------ |
| 0    | `ok`         | Analysis complete, no verdict at or above `fail_on`.                                       |
| 1    | `violations` | Analysis complete, at least one non-suppressed verdict at or above `fail_on`.              |
| 2    | `errors`     | Analysis incomplete: parse errors, unreadable files, invalid config, conflicting settings. |
| 3    | —            | Usage error: bad flags, nonexistent target or `--config` file.                             |

Errors win over violations. Files with syntax errors are still measured from
the recovered AST and marked `partial`, but the run is never clean. Config
problems abort analysis entirely rather than measuring under a config you did
not ask for.

## Configuration

Config lives under a `dmetrics:` key in `analysis_options.yaml`, next to the
analyzer's own settings. Everything is optional. A bare `dmetrics:` with nothing
under it is valid and just marks that directory as a config root with
defaults.

```yaml
dmetrics:
  fail_on: fail # run-global: warn | fail
  closure_rollup: separate # run-global: separate | include_in_parent
  include: ["lib/**", "bin/**"] # per-root discovery globs; default: every .dart file
  exclude: ["**.g.dart"] # per-root; default: ['**.g.dart', '**.freezed.dart']
  metrics:
    cyclomatic:
      enabled: true
      thresholds: { warn: 10, fail: 20 } # the built-in default; `none` turns them off
      count_case_arms: true # run-global knob
      count_null_coalescing: true # run-global knob
    cognitive:
      thresholds: { warn: 15, fail: 25 } # the built-in default
    coupling:
      thresholds: { warn: 15, fail: 30 } # the built-in default
  overrides: # thresholds and enablement only; last match wins
    - paths: ["test/**"]
      metrics:
        cyclomatic: { thresholds: { warn: 15, fail: 25 } }
    - paths: ["lib/src/generated/**"]
      metrics:
        cyclomatic: { enabled: false }
```

### Top-level keys

| Key              | Scope      | Default                            | Meaning                                                                                                |
| ---------------- | ---------- | ---------------------------------- | ------------------------------------------------------------------------------------------------------ |
| `fail_on`        | run-global | `fail`                             | Lowest verdict that counts as a violation (exit 1). `warn` makes warnings fail the run too.            |
| `closure_rollup` | run-global | `separate`                         | How closures and local functions aggregate into their parent. See [Closure roll-up](#closure-roll-up). |
| `include`        | per-root   | every `.dart` file                 | Globs selecting files when a directory is analyzed. Explicitly named files are always analyzed.        |
| `exclude`        | per-root   | `['**.g.dart', '**.freezed.dart']` | Globs removed from discovery. Setting this replaces the default list.                                  |
| `metrics`        | per-root   | all enabled, default thresholds    | Per-metric settings keyed by metric id. See below.                                                     |
| `overrides`      | per-root   | none                               | Path-glob blocks that change `thresholds` and `enabled` for matching files. Last matching block wins.  |

Globs use `package:glob` semantics and match the file path **relative to the
config root**, not to the working directory.

### Per-metric keys

Under `metrics.<id>:`:

| Key          | Default  | Meaning                                                                                                 |
| ------------ | -------- | ------------------------------------------------------------------------------------------------------- |
| `enabled`    | `true`   | Whether the metric runs and reports for files in this root.                                             |
| `thresholds` | metric's | `{ warn: N, fail: M }` with `N <= M`, or `none`. `>= fail` is `fail`, `>= warn` is `warn`, else `ok`.   |
| knobs        | per knob | Counting knobs the metric declares. Run-global. Listed under each metric below.                         |

Cyclomatic ships with `warn: 10, fail: 20` built in, chosen from a field
trial over eleven codebases where 10 sat near the 90th–95th percentile of
scope scores and 20 flagged only real tangles. Cognitive ships with
`warn: 15, fail: 25`, calibrated over the same corpus to the same prevalence
(SonarSource's own default is 15). Coupling ships with `warn: 15, fail: 30`:
15 is about the 95th percentile of libraries in fourteen packages, and 30
flagged only hubs (`theme_data.dart`, `router.dart`, a composition root).
`thresholds: none` turns thresholds off
for a metric in that root; `dmetrics stats` shows where your own codebase sits
before you tune them.

### Cyclomatic knobs

| Knob                    | Default | Meaning                                                                                                                                                             |
| ----------------------- | ------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `count_null_coalescing` | `true`  | Count `??` and `??=` as branches. Lizard does, SonarQube's cyclomatic does not.                                                                                     |
| `count_case_arms`       | `true`  | `true`: +1 per refutable `case` arm. `false`: +1 per `switch` and 0 per arm (the "modified" McCabe convention). `when` guards and `\|\|` patterns count either way. |

### Per-root vs. run-global

Each analyzed file has a **config root**: the nearest ancestor directory whose
`analysis_options.yaml` has a `dmetrics:` section, otherwise the nearest
`pubspec.yaml` directory with built-in defaults, otherwise the working
directory. A monorepo run naturally has several roots, and this lookup is the
same whether a file was named explicitly or found under a directory.

- **Per-root** settings (`thresholds`, `enabled`, `overrides`, `include`,
  `exclude`) may differ between roots.
- **Run-global** settings (`fail_on`, `closure_rollup`, and every counting
  knob) must agree across all roots in a run. If two roots disagree the run
  is a config error (exit 2) naming both files, unless `--set` fixes the
  value for the whole run.

`--config <path>` forces one file as the single root for every analyzed file.

### Precedence

Within a root, highest first:

1. CLI flags: `--threshold`, `--set`, `--fail-on`.
2. The last matching `overrides` block in that root's config.
3. That root's top-level `metrics` config.
4. Built-in defaults: every metric enabled, the metric's own thresholds.

`overrides` may change only `thresholds` and `enabled`. A run-global key inside
an override is a config error.

### Config errors

All of these are reported with a file position and exit 2: unknown keys,
unknown metric ids, unknown or mistyped knobs, `warn > fail`, malformed YAML,
run-global keys inside `overrides`, and run-global values that differ between
roots.

## Command line

```
dmetrics analyze [<file>|<dir> ...] [options]
dmetrics stats   [<file>|<dir> ...] [options]
dmetrics deps    [<file>|<dir> ...] [options]
dmetrics agent
dmetrics init    [--file <path>]... [--skill claude|codex]...
```

`dmetrics agent` prints a guide for an LLM coding agent working in a project
that uses dmetrics: when to run it, how to read a report line, what each
metric measures and what to do about a warning. It ships inside the binary so
it never drifts from the output it explains.

`dmetrics init` points a project at that guide: it writes a short block into
the project's instructions file between `<!-- dmetrics:start -->` and
`<!-- dmetrics:end -->` markers, so a re-run replaces the block and leaves the
rest of the file alone. Without `--file` it uses the first of `CLAUDE.md` and
`AGENTS.md` that exists, creating `CLAUDE.md` when neither does; `--file` names
the file explicitly and repeats. The block tells the agent to run `dmetrics
analyze` on the package's source roots once per task and to read `dmetrics
agent` before interpreting a report. `--skill claude` also writes the guide as a skill at
`.claude/skills/dmetrics/SKILL.md`, and `--skill codex` at
`.agents/skills/dmetrics/SKILL.md`, for projects that want it loaded without
the extra command. Both agents read the same SKILL.md format, so the two files
are identical; they are generated, and a re-run overwrites them.

No targets means the current directory. Files and directories mix freely.
Files named explicitly are analyzed even if `include`/`exclude` would skip
them, the same way `dart analyze` behaves.

| Flag                                 | Meaning                                                                                                       |
| ------------------------------------ | ------------------------------------------------------------------------------------------------------------- |
| `--json`                             | Write the JSON document to stdout. Nothing else goes to stdout in this mode.                                  |
| `--json-contributors full\|summary`  | `analyze` only. `summary` drops the per-contributor span list from the JSON report. Default `full`.           |
| `--all`                              | `analyze` only, console mode: print every scope, not only `warn`/`fail`/`suppressed`.                         |
| `--color auto\|always\|never`        | Console mode. `auto` colors when stdout is a terminal, `NO_COLOR` is unset and `TERM` is not `dumb`.          |
| `--config <path>`                    | Use one `analysis_options.yaml` as the config root for every file.                                            |
| `--fail-on warn\|fail`               | `analyze` only. Shorthand for `--set fail_on=...`.                                                            |
| `--set <key>=<value>`                | Fix a run-global setting for the whole run. Repeatable. Keys: `fail_on`, `closure_rollup`, `<metric>.<knob>`. |
| `--threshold <metric>=warn:N,fail:M` | Force a metric's thresholds in every root, above any `overrides`. Repeatable. Order of `warn`/`fail` is free. |
| `--top N`                            | `deps` only, console mode. Rows per hub table and back edges listed per cycle. Default 10.                     |
| `--depth N`                          | `deps` only. Directory levels kept under `lib/src` (or `lib`) when folding the graph. Default 1.              |
| `--help`, `-h`                       | Usage.                                                                                                        |
| `--version`                          | Tool name and version.                                                                                        |

Examples:

```sh
# Try thresholds without touching the config file
dart run bin/dmetrics.dart analyze lib --threshold cyclomatic=warn:8,fail:12

# Treat warnings as failures for this run
dart run bin/dmetrics.dart analyze lib --fail-on warn

# Modified McCabe counting, and fold closures into their parent
dart run bin/dmetrics.dart analyze lib \
  --set cyclomatic.count_case_arms=false \
  --set closure_rollup=include_in_parent
```

### Calibrating thresholds: `dmetrics stats`

`dmetrics stats` measures exactly like `analyze` (same targets, config, `--set`,
`--threshold`) and then, instead of listing findings, prints per metric the
numbers a threshold decision needs:

```
cyclomatic • 258 scopes in 26 files
Distribution
  1–5      220  85.3%  ████████████████████
  6–9       22   8.5%  ██
  10–14     11   4.3%  █
  15–19      2   0.8%
  20+        3   1.2%
  p50 1 • p90 7 • p95 11 • p99 22 • max 37
Thresholds • warn ≥ 10, fail ≥ 20
  ≥ warn    16   6.2%
  ≥ fail     3   1.2%
Sweep • scopes at or above each candidate
  ≥ 5       49  19.0%  1 table-shaped
  ≥ 8       23   8.9%  1 table-shaped
  ≥ 10      16   6.2%
  ...
Contributor mix • share of summed increments
  if 28.0% • loop 23.8% • case 14.7% • ternary 11.8% • ?? 8.6% • ...
Sibling clusters • same value and contributor mix, ≥ warn
  cyclomatic 12 • case ×11 • 3 scopes
    lib/widgets/a.dart:40 method A.build
    ...
```

- **Distribution**: value bands and nearest-rank percentiles. A healthy
  codebase puts `warn` around the 90th–95th percentile.
- **Thresholds**: scopes at or above `warn` and `fail`, each counted against
  its own applied threshold (per-root overrides honored), with how many of
  those are table-shaped, the built-in false-positive estimate.
- **Sweep**: the same count for a fixed set of candidates (5, 8, 10, 12, 15,
  20, 25, 30): "at 15 you would have 5 warns, 2 of them tables".
- **Contributor mix**: summed increments per contributor kind over the whole
  run, as a share.
- **Sibling clusters**: two or more scopes with the same value and the same
  contributor summary, at or above `warn` (top decile when no threshold is
  configured). Identical scores with identical breakdowns are usually copies.

Suppressions are ignored: stats describe the code, not the verdicts. Exit
codes are 0 or 2 (analysis incomplete); violations never make `stats` exit 1.
`--json` writes a separate document (`schemaVersion`, `tool`, `status`,
`summary`, `diagnostics`, `metrics.<id>` with `bands`, `percentiles`,
`thresholds`, `sweep`, `contributorMix`, `siblingClusters`; shares are
fractions in `[0, 1]`), not the `analyze` report.

### Seeing the graph: `dmetrics deps`

`analyze` says "coupling 13" on a library's line and lists its dependencies
in the JSON detail; that resolves nothing on its own. `dmetrics deps` reads
the same data for the whole run and prints the structure:

```
Dependencies • 33 libraries • 145 edges (121 imports, 24 exports)
Cycles • none
Fan-out • top 10 • I = instability, out / (in + out)
    out    in     I  library
     14     1  0.93  lib/src/cli/cli.dart
     10     2  0.83  lib/src/engine/engine.dart
     ...
Fan-in • top 10
    out    in     I  library
      2    16  0.11  lib/src/engine/result.dart
      5    14  0.26  lib/src/engine/metric.dart
     ...
Directories • depth 1 • 8 directories • 16 edges • 1 back edge
  layering bin › cli › io › metrics › report › engine › config › lib
     16  report  → engine
     14  metrics → engine
      6  cli     → report
      5  engine  → config
      3  config  → engine   back
     ...
```

- **Cycles**: every strongly connected component of two or more libraries,
  largest first, each with its **back edges**: the imports a greedy
  feedback-arc-set order points against. Remove them and the component is
  acyclic. A 114-library component (pub) is described by its ~100 back
  edges rather than by a member list. Membership is not judged.
- **Fan-out / Fan-in**: the hub libraries, with Martin's instability
  `I = out / (in + out)` (0: depended upon, depends on nothing; 1: the
  reverse). Fan-out is colored by the coupling verdict; `cycle #n` points
  at the component above.
- **Directories**: the graph folded onto the first `--depth` levels under
  `lib/src` (or `lib`; `bin`, `test` and a monorepo's `packages/foo` stay
  apart), as a layering with per-edge library counts. Edges against the
  layering are marked `back`: the minority direction between directories
  that depend on each other. Import edges only; a barrel's re-exports are
  not what its directory needs.

The picture is complete only when the whole package is in the run. Exit
codes and `--json` behave as for `stats`: the document has `summary`,
`libraries[]` (`fanOut`, `fanIn`, `exports`, `instability`, `cycle`,
`verdict`), `cycles[]` (`members`, `backEdges`) and `directories` (`order`,
`edges` with `back`).

## Suppressions

Analyzer-style ignore comments, taken from the token stream so text inside
string literals never matches:

```dart
// ignore: dmetrics_cyclomatic
void bigButJustified() { ... }

void alsoFine() { // ignore: dmetrics_cyclomatic
  ...
}

// ignore_for_file: dmetrics_cyclomatic
```

- `// ignore: dmetrics_<metric>` on the line immediately before the declaration
  (before its metadata, if any) or as a trailing comment on the declaration's
  first line. A doc comment between the ignore and the declaration breaks
  the adjacency.
- `// ignore: dmetrics` suppresses every metric for that scope.
- `// ignore_for_file: dmetrics_<metric>` or `// ignore_for_file: dmetrics`
  anywhere in the file suppresses the whole file.
- Other names in the same comment (`// ignore: unused_element, dmetrics_cyclomatic`)
  are ignored, as the analyzer does. Metric names are the ids: `dmetrics_cyclomatic`,
  `dmetrics_cognitive`.
- A line ignore applies only to the **outermost** scopes starting on that
  line. Suppressing a method does not suppress its closures. To suppress a
  closure, put the ignore on the closure's own line.

Suppressed scopes are still measured and reported, with verdict `suppressed`.
They never count as violations.

## Closure roll-up

Closures and local functions are always their own scope with their own
score. `closure_rollup` decides whether they also fold into the enclosing
scope's value:

- `separate` (default): each scope stands alone. `value == measured`.
- `include_in_parent`: the parent's value becomes
  `parent.measured + Σ (child.value − 1)` over its direct children, so each
  child's base score of 1 is excluded. A method of 2 containing a closure of
  3 reports 4. The children are still emitted with their own verdicts and
  still count toward the summary and the exit code. In JSON the parent lists
  its folded children under `includes`.

Verdicts are always computed on the rolled-up value, so a printed number can
never disagree with its verdict.

## Cyclomatic complexity rules

Base score 1 per scope, plus one per construct below. Contributor kinds are
what the console summary and JSON report show.

| Construct                                                                                                                | Δ                                      | Kind         |
| ------------------------------------------------------------------------------------------------------------------------ | -------------------------------------- | ------------ |
| `if`, `else if`, collection `if` element                                                                                 | +1                                     | `if`         |
| `if (x case P)` statement or element                                                                                     | +1                                     | `if-case`    |
| `for`, `for-in`, `await for`, `while`, `do-while`, collection `for` element                                              | +1                                     | `loop`       |
| `case` arm with a refutable pattern (incl. constants, typed `int _`, typed bindings, object/record/list/map, relational) | +1 each                                | `case`       |
| `default`, bare `_`, untyped `var x` / `final x` arm                                                                     | 0                                      | —            |
| `switch` with `count_case_arms: false`                                                                                   | +1 per switch, arms 0                  | `switch`     |
| `when` guard                                                                                                             | +1                                     | `when`       |
| Logical-or pattern `P1 \|\| P2`                                                                                          | +1 per extra alternative, at any depth | `pattern-or` |
| Logical-and pattern `P1 && P2`                                                                                           | 0                                      | —            |
| `catch`, `on T catch`, `on T`                                                                                            | +1 per clause                          | `catch`      |
| `c ? a : b`                                                                                                              | +1                                     | `ternary`    |
| `&&`, `\|\|`                                                                                                             | +1 each                                | `&&`, `\|\|` |
| `??`, `??=` (with `count_null_coalescing`)                                                                               | +1 each                                | `??`, `??=`  |
| Null-aware element `?x`, `?k: v`, `k: ?v`                                                                                | +1 each                                | `if`         |
| `?.`, `?..`, `?[]`, `!`, `...`, `...?`                                                                                   | 0                                      | —            |
| `assert`, `return`, `break`, `continue`, `throw`, `yield`, `await`, labels, cascades, `try`, `finally`, `rethrow`        | 0                                      | —            |
| Closure / local function                                                                                                 | own scope                              | —            |

The guiding rule: count a construct that chooses between authored outcomes.
`??` chooses a right operand; `?x` chooses whether an element is present, like
the `if (x != null) x` it replaces. `?.` passes null through an expression
written once and counts 0. Irrefutability is decided syntactically, never
from static types.

Not measured: abstract, external and redirecting-factory declarations (no
body, no scope). Branch constructs directly inside field or top-level
variable initializers, outside any closure, are ignored in v1.

## Cognitive complexity rules

Base score 0 per scope. After SonarSource's cognitive complexity: every break
in the linear flow counts, nesting makes it cost more, and shorthand is free.
A structure counts 1 plus the number of nesting bodies it sits in (branches,
loop and `catch` bodies, `switch` arms); a link in a chain and a labeled jump
count 1 flat; a run of the same boolean operator counts 1.

| Construct                                                                    | Δ            | Kind                |
| ---------------------------------------------------------------------------- | ------------ | ------------------- |
| `if`, `if-case`, collection `if` element                                     | +1 + nesting | `if`                |
| `else if`                                                                    | +1           | `else-if`           |
| `else`                                                                       | +1           | `else`              |
| `for`, `for-in`, `await for`, `while`, `do-while`, collection `for` element  | +1 + nesting | `loop`              |
| `switch` statement or expression                                             | +1 + nesting | `switch`            |
| `case` arms, `default`, patterns, `when` guards, `\|\|` and `&&` patterns    | 0            | —                   |
| `catch`, `on T catch`, `on T`                                                | +1 + nesting | `catch`             |
| `c ? a : b`                                                                  | +1 + nesting | `ternary`           |
| Run of `&&`, run of `\|\|` (operator change starts a new run)               | +1 per run   | `&&`, `\|\|`        |
| Labeled `break`, labeled `continue`                                          | +1           | `break`, `continue` |
| `??`, `??=`, `?.`, `?..`, `?[]`, `!`, `?x`, `...`, `...?`                    | 0            | —                   |
| `assert`, `return`, `throw`, `yield`, `await`, unlabeled jumps, cascades     | 0            | —                   |
| Recursion                                                                    | 0            | —                   |
| Closure / local function                                                     | own scope    | —                   |

A condition is read at its statement's level; the branch is one deeper. An
`if / else if / else` chain reads flat: the links cost 1 each and every
branch is one level deeper than the chain. A `switch` costs 1 however many
arms it has, `&&`/`||` runs and null-aware shorthand cost nothing extra, so
the case tables, `==` and `copyWith` methods that cyclomatic flags score
near 0 here, and a ladder of nested `if`s scores 1 + 2 + 3.

A closure or local function is its own scope whose body starts one level
deeper than the point where it is written, so its own score says how hard
it is to read where it sits. Under `include_in_parent` the parent's value
is `measured + Σ child.value`, which is the number SonarSource reports for
the whole method. A closure in a field or top-level initializer starts at
level 0, like a function. Same scopes as cyclomatic; no knobs.

**Reading `table-shaped: if@1`.** The marker names the contributor family
that supplies at least 70% of the score. For cognitive, a family is a kind
at a nesting level: `if` is `if`s at the top of the body, `if@1` is `if`s
one level down, `if@2` two levels down. `else if` and `else` count toward
the `if` family of their chain; `&&`, `||`, `break` and `continue` never
nest and keep their plain kind. So:

- `table-shaped: if` — a flat run of top-level `if`s, e.g. a `toString`
  that appends one line per non-null field, or a validator of early returns.
- `table-shaped: if@1` — a flat run of `if`s all one level in: a `switch`
  whose arms each check a few conditions, or a widget's `children: [if (a)
  X, if (b) Y, …]` inside a `builder:` closure. Still a table, just indented.
- No marker on a scope full of `if`s — the `if`s sit at different levels,
  which is a ladder. A ladder of `1 + 2 + 3 + 4` is the tangle this metric
  exists to find, and pooling by kind alone would have called it a table.

The score is unchanged either way; the marker is a reading hint.

## Import coupling rules

Per library, the number of distinct libraries **of your own packages** that
the library's code imports. Base 0. The scope is the whole file (kind
`library`, named by its `package:` URI); a `part` file has no scope of its
own. The rule: count what the library's code can break on.

| Directive                                                        | Δ                            | Kind     |
| ---------------------------------------------------------------- | ---------------------------- | -------- |
| `import` of a library of one of the analyzed packages            | +1 per distinct target       | `import` |
| A second `import` of the same library (`show`, `hide`, a prefix) | 0                            | —        |
| `export`                                                         | 0 (an edge, listed in detail) | —        |
| `import 'dart:…'`, `import 'package:other/…'`                    | 0 (external, listed in detail) | —      |
| `import 'a.dart' if (dart.library.io) 'b.dart'`                  | +1 for the default URI       | `import` |
| `part 'p.dart'` whose part has its own imports                   | +1 per library the part adds | `part`   |

A target counts whether or not it is in the run: `dmetrics analyze
lib/src/a.dart` gives `a.dart` the same number as `dmetrics analyze lib`.
Re-exports are not counted because a barrel file has a package's API surface,
not its coupling; they still are edges, so a barrel takes part in cycles and
appears among its targets' dependents.

The JSON `detail` of a library result is the graph: `dependencies` (counted),
`missing` (counted but not in the run: excluded, generated, absent),
`exports`, `external`, `dependents` (which run libraries import or export
this one), and `cycle` when the library is in an import cycle (the members,
itself included). Cycles are reported, not judged: most of every mature
package sits in one, so a verdict on membership would flag everything. The
console prints `cycle of N` on the library's line; `dmetrics deps` shows the
run-level picture (see [above](#seeing-the-graph-dmetrics-deps)).

No knobs. The table-shaped marker never fires for this metric: an import
list is what it counts.

## JSON report

`--json` writes a single document with `schemaVersion`, `tool`, `status`,
the effective `configs` per root and `run`-global settings, a `summary`
(files, scopes, verdict counts, suppressed count), run-level `diagnostics`,
and `files[]`. Each file carries its `configRoot`, its own `status` and parse
`diagnostics`, and `scopes[]` with the scope's id, kind, qualified name, span,
measured value, rolled-up value, applied threshold, verdict, suppression, and
every contributor with its span. A `library` scope's coupling result also
carries `detail` (the import graph, see above). Ordering is deterministic:
configs by root, files by path, scopes by start offset, contributors by start
offset.

The full specimen and its guarantees are in `SPEC.md` §7.3, and
`test/golden/report.json` is the golden rendering of it.

## Install

```sh
make install          # dart compile exe → ~/.local/bin/dmetrics
dmetrics analyze lib  # from any Dart project
```

`make help` lists every target: `build`, `test`, `lint`, `format`, `doc`, `clean`,
and `testf`, `lintf`, `formatf` which take `FILE=<path>`.

## Development

```sh
dart test                                             # everything
UPDATE_GOLDENS=1 dart test test/report/json_golden_test.dart   # regenerate the JSON golden
```

Metric behaviour is specified by annotated fixtures under `test/fixtures`:
each scope carries `// expect: cyclomatic=N` (and `rolled=M` where roll-up
differs) and the harness asserts every scope plus each metric's invariant
(`measured == base + Σ contributors`). What a single file cannot show
(import edges between files, cycles, parts) is covered by in-memory graph
tests under `test/metrics`.

The design document is `SPEC.md`. Section numbers referenced in source
comments (§6.1, §7.2, §8) point there.
