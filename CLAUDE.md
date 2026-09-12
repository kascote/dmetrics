# dmetrics

Dart-native static code metrics engine. `SPEC.md` is the design document.

## Final pass

Before reporting a task done, run `make check` and fix what it reports. It
runs the analyzer, verifies formatting, runs the tests, and measures the code
with dmetrics itself (`dmetrics analyze lib bin`). Do not run dmetrics after
every edit; once per task is the intended cadence.

## Conventions

- Format only touched directories (`make formatf FILE=...` or `make format`).
  A tree-wide `dart format .` fails on the deliberately unparseable fixtures.
- Fixture files under `test/**/fixtures` are metric inputs, not code to lint.
- Do not reference `SPEC.md` or its section numbers in code comments. The
  spec can change or go stale; the code is the truth. Say why something is
  the way it is, in the comment itself.
- Ask before committing.

<!-- dmetrics:start -->
## Code metrics — dmetrics

This project measures code with **dmetrics** (cyclomatic and cognitive
complexity per function, import coupling per library) against thresholds in
`analysis_options.yaml`. Run it once per task, after your edits, not after
every edit:

    dmetrics analyze [<file>|<dir> ...]

Pass the package's source roots: `lib`, plus `bin` when it has one. With no
targets it measures the current directory, tests and fixtures included, which
is usually more than you want.

Exit 0 is clean, 1 means violations, 2 means the analysis did not complete
(fix that first). Before interpreting a report, run `dmetrics agent`: it
explains the report line, what each metric measures and what to do about a
warning. The same guide is loaded as the `dmetrics` skill.
Warnings are evidence to weigh, not orders to obey. Never lower a threshold
or add an override to make a run pass; propose the change instead.
<!-- dmetrics:end -->
