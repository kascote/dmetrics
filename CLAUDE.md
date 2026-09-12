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
