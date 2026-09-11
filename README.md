# metra

A Dart-native static code metrics engine. It measures every function-shaped
scope in your code (functions, methods, getters, setters, operators,
constructors, local functions, closures), compares each value against
thresholds you configure, and prints one consolidated report as console text
or JSON.

The one metric shipped today is **cyclomatic complexity**. The engine is
built so that more metrics register without touching it.

## Quick start

```sh
# Analyze the current directory
dart run bin/metra.dart analyze

# Analyze specific files or directories, print every scope (not only problems)
dart run bin/metra.dart analyze lib/src/config --all

# JSON report to stdout
dart run bin/metra.dart analyze lib --json
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
| `table-shaped: case`     | One kind supplies ≥ 80% of the score (and ≥ 8 in total): a dispatch table, a field-wise `==`, a `copyWith`. Its size is the table's, not a tangle's. |

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

Config lives under a `metra:` key in `analysis_options.yaml`, next to the
analyzer's own settings. Everything is optional. A bare `metra:` with nothing
under it is valid and just marks that directory as a config root with
defaults.

```yaml
metra:
  fail_on: fail # run-global: warn | fail
  closure_rollup: separate # run-global: separate | include_in_parent
  include: ["lib/**", "bin/**"] # per-root discovery globs; default: every .dart file
  exclude: ["**.g.dart"] # per-root; default: ['**.g.dart', '**.freezed.dart']
  metrics:
    cyclomatic:
      enabled: true
      thresholds: { warn: 10, fail: 20 }
      count_case_arms: true # run-global knob
      count_null_coalescing: true # run-global knob
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
| `metrics`        | per-root   | all enabled, no thresholds         | Per-metric settings keyed by metric id. See below.                                                     |
| `overrides`      | per-root   | none                               | Path-glob blocks that change `thresholds` and `enabled` for matching files. Last matching block wins.  |

Globs use `package:glob` semantics and match the file path **relative to the
config root**, not to the working directory.

### Per-metric keys

Under `metrics.<id>:`:

| Key          | Default  | Meaning                                                                                                 |
| ------------ | -------- | ------------------------------------------------------------------------------------------------------- |
| `enabled`    | `true`   | Whether the metric runs and reports for files in this root.                                             |
| `thresholds` | none     | `{ warn: N, fail: M }` with `N <= M`. A value `>= fail` is `fail`, `>= warn` is `warn`, otherwise `ok`. |
| knobs        | per knob | Counting knobs the metric declares. Run-global. Listed under each metric below.                         |

### Cyclomatic knobs

| Knob                    | Default | Meaning                                                                                                                                                             |
| ----------------------- | ------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `count_null_coalescing` | `true`  | Count `??` and `??=` as branches. Lizard does, SonarQube's cyclomatic does not.                                                                                     |
| `count_case_arms`       | `true`  | `true`: +1 per refutable `case` arm. `false`: +1 per `switch` and 0 per arm (the "modified" McCabe convention). `when` guards and `\|\|` patterns count either way. |

### Per-root vs. run-global

Each analyzed file has a **config root**: the nearest ancestor directory whose
`analysis_options.yaml` has a `metra:` section, otherwise the nearest
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
4. Built-in defaults: every metric enabled, no thresholds.

`overrides` may change only `thresholds` and `enabled`. A run-global key inside
an override is a config error.

### Config errors

All of these are reported with a file position and exit 2: unknown keys,
unknown metric ids, unknown or mistyped knobs, `warn > fail`, malformed YAML,
run-global keys inside `overrides`, and run-global values that differ between
roots.

## Command line

```
metra analyze [<file>|<dir> ...] [options]
```

No targets means the current directory. Files and directories mix freely.
Files named explicitly are analyzed even if `include`/`exclude` would skip
them, the same way `dart analyze` behaves.

| Flag                                 | Meaning                                                                                                       |
| ------------------------------------ | ------------------------------------------------------------------------------------------------------------- |
| `--json`                             | Write the JSON report to stdout. Nothing else goes to stdout in this mode.                                    |
| `--json-contributors full\|summary`  | `summary` drops the per-contributor span list from the JSON report. Default `full`.                           |
| `--all`                              | Console mode: print every scope, not only `warn`/`fail`/`suppressed`.                                         |
| `--color auto\|always\|never`        | Console mode. `auto` colors when stdout is a terminal, `NO_COLOR` is unset and `TERM` is not `dumb`.          |
| `--config <path>`                    | Use one `analysis_options.yaml` as the config root for every file.                                            |
| `--fail-on warn\|fail`               | Shorthand for `--set fail_on=...`.                                                                            |
| `--set <key>=<value>`                | Fix a run-global setting for the whole run. Repeatable. Keys: `fail_on`, `closure_rollup`, `<metric>.<knob>`. |
| `--threshold <metric>=warn:N,fail:M` | Force a metric's thresholds in every root, above any `overrides`. Repeatable. Order of `warn`/`fail` is free. |
| `--help`, `-h`                       | Usage.                                                                                                        |
| `--version`                          | Tool name and version.                                                                                        |

Examples:

```sh
# Try thresholds without touching the config file
dart run bin/metra.dart analyze lib --threshold cyclomatic=warn:8,fail:12

# Treat warnings as failures for this run
dart run bin/metra.dart analyze lib --fail-on warn

# Modified McCabe counting, and fold closures into their parent
dart run bin/metra.dart analyze lib \
  --set cyclomatic.count_case_arms=false \
  --set closure_rollup=include_in_parent
```

## Suppressions

Analyzer-style ignore comments, taken from the token stream so text inside
string literals never matches:

```dart
// ignore: metra_cyclomatic
void bigButJustified() { ... }

void alsoFine() { // ignore: metra_cyclomatic
  ...
}

// ignore_for_file: metra_cyclomatic
```

- `// ignore: metra_<metric>` on the line immediately before the declaration
  (before its metadata, if any) or as a trailing comment on the declaration's
  first line. A doc comment between the ignore and the declaration breaks
  the adjacency.
- `// ignore: metra` suppresses every metric for that scope.
- `// ignore_for_file: metra_<metric>` or `// ignore_for_file: metra`
  anywhere in the file suppresses the whole file.
- Other names in the same comment (`// ignore: unused_element, metra_cyclomatic`)
  are ignored, as the analyzer does.
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
| `?.`, `?..`, `?[]`, `!`, `...`, `...?`, `?x` elements                                                                    | 0                                      | —            |
| `assert`, `return`, `break`, `continue`, `throw`, `yield`, `await`, labels, cascades, `try`, `finally`, `rethrow`        | 0                                      | —            |
| Closure / local function                                                                                                 | own scope                              | —            |

The guiding rule for the null-aware family: count a construct when the author
wrote both paths. `??` has a right operand, `?.` short-circuits to nothing.
Irrefutability is decided syntactically, never from static types.

Not measured: abstract, external and redirecting-factory declarations (no
body, no scope). Branch constructs directly inside field or top-level
variable initializers, outside any closure, are ignored in v1.

## JSON report

`--json` writes a single document with `schemaVersion`, `tool`, `status`,
the effective `configs` per root and `run`-global settings, a `summary`
(files, scopes, verdict counts, suppressed count), run-level `diagnostics`,
and `files[]`. Each file carries its `configRoot`, its own `status` and parse
`diagnostics`, and `scopes[]` with the scope's id, kind, qualified name, span,
measured value, rolled-up value, applied threshold, verdict, suppression, and
every contributor with its span. Ordering is deterministic: configs by root,
files by path, scopes by start offset, contributors by start offset.

The full specimen and its guarantees are in `SPEC.md` §7.3, and
`test/golden/report.json` is the golden rendering of it.

## Development

```sh
dart test                                             # everything
UPDATE_GOLDENS=1 dart test test/report/json_golden_test.dart   # regenerate the JSON golden
```

Metric behaviour is specified by annotated fixtures under `test/fixtures`:
each scope carries `// expect: cyclomatic=N` (and `rolled=M` where roll-up
differs) and the harness asserts every scope plus the invariant
`measured == 1 + Σ contributors`.

The design document is `SPEC.md`. Section numbers referenced in source
comments (§6.1, §7.2, §8) point there.
