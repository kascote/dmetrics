# Dart Code Metrics Engine — High-Level Spec

**Status:** Draft 0.11 · **Owner:** Nelson · **Date:** 2026-09-12
**Name:** `dmetrics`

**Changes in 0.11 (M7, `dmetrics deps`: the aggregate graph view):** `dmetrics deps [targets]`, the run-level view of the graph `coupling` reports per library, built like `stats` on the finished run and reading only each library scope's `detail` (§7.1). Motivation: "13 dependencies" on a file's line resolves nothing by itself, and a per-file `dependencies` list is not a structure; the reader needs the graph. The view prints library and edge counts; every strongly connected component largest first with its **back edges**, the imports a greedy feedback-arc-set order (Eades, Lin and Smyth; `feedbackOrder` in `src/engine/graph.dart`, next to the Tarjan the metric already used) points against, so pub's 114-library component is described by the 101 imports whose removal would leave it acyclic instead of by its member list; the libraries with the highest fan-out and fan-in with Martin's instability `I = Ce / (Ca + Ce)` per library, meaningful only here where the whole package is in the run and therefore not added to `analyze`'s `detail`; and the graph folded onto directories (`--depth` levels under `lib/src`, default 1) as a layering with the edges against it marked `back`. The fold uses import edges only: with exports folded in, a barrel made `lib` depend on every directory it exported from and every directory pair read as a cycle. On dmetrics itself the one back edge is `config → engine`; on pub they are the top-level files depending on `command`, `source` and `validator`; on dart-sass, 25 of 76 directory edges. `--json` is a document of its own, exit codes as `stats`. No engine change beyond lifting Tarjan into the shared graph file; the console helpers `stats` and `deps` share moved to `src/report/format.dart`. Radar updated in §8. First change the view prompted: its one back edge on dmetrics itself was `config → engine`, three imports; `Threshold` and `Verdict` moved from the engine's result model to `src/config/threshold.dart` (they are the numbers a user writes plus the rule that reads them), and the loader now validates against a `MetricSpec` (id and setting defaults, built by `Metric.spec`) instead of the metric itself. Config is a leaf under the engine again and the directory layering has no back edge.

**Changes in 0.10 (M6, metric #3: import coupling):** `coupling`, the first dependency metric, shipped on the directive pipeline with its own counting table (§6.5). Per library, the number of distinct libraries of the run's own packages that the library's code imports: `dart:` and other packages' libraries are listed in `detail`, not counted; a target of one of the run's packages counts whether or not it is among the run's sources, so a single file measures as it does inside its package. Re-exports are edges, not coupling: they take part in fan-in and cycles and are listed in `detail.exports`, but an `export` brings no code that can break, and before that decision the top scorer of 8 of the 14 calibration packages was its barrel file (Flutter's `material.dart` at 182). Parts fold into the library that includes them, attributed to its `part` directive. `detail` carries the graph: `dependencies`, `missing`, `exports`, `external`, `dependents` (fan-in) and, for a member of a strongly connected component of two or more run libraries, `cycle` with the members; the console prints `cycle of N` for the one `detail` shape it knows, its first specialized block (§5.1). Cycle membership is informational: 60–85% of the libraries of every mature package in the corpus sit in one component. Built-in thresholds `warn: 15, fail: 30`, calibrated over 14 packages: 15 is about the 95th percentile of libraries in library and app code alike and 30 catches only the hubs a package has by name (`theme_data.dart`, `evaluate.dart`, `router.dart`). No knobs; the marker never fires, since an import list is what the metric counts. One seam change from building it: a `library` scope now starts at the unit's first token, leading comments excluded like a declaration's doc comment, so a license header is not the library's location and an `// ignore:` on the line before the first directive reaches it. Everything else held: zero engine, config or reporter changes beyond registration, the export, the span and the console note; the shipped metrics produce identical results over every fixture with `coupling` registered. Radar updated in §8.

**Changes in 0.9 (resolved-pipeline spike: cost probe and engine seam):** the cost probe (`tool/resolve_probe.dart`, 13 packages) closed two open questions in §9: a directive-level import graph costs the same as parsing and matches the analyzer's element model edge for edge, while cold resolution is a fixed cost of the dependency closure (0.2–2 s, 115–815 MB), seconds not minutes. So `MetricRequirements` gains a middle level, `directive`, and the engine now selects the pipeline: the most demanding level any metric in the run asks for, `resolved` refused until it exists (§5.0, §5.1). A directive run hands metrics a `LibraryIndex` on `RunContext` that resolves `import`/`export`/`part` URIs to the run's sources; `SourceFile` gains `packageUri`, derived by the I/O layer from the nearest pubspec's `name`, so `package:` URIs resolve without a package config. The `library` scope exists: the whole compilation unit of a non-part file, opened only when a metric lists it in `measures`, named by the file's `package:` URI or path, parent of the file's top-level declarations for event and reporting purposes while ids stay allocated under the file so a top-level closure's id does not depend on the metric set. `finish` can address scopes: a measurement whose scope was traversed replaces that scope's measurement for the metric and flows through aggregation, suppression and thresholds; only measurements for untraversed scopes stay run-level. Proven with a throwaway import-count metric in the tests (not shipped): the shipped metrics produce identical ids, names, fingerprints, values and verdicts over every fixture with it registered, and both reporters render library results with no changes.

**Changes in 0.8 (M5 cognitive complexity):** metric #2, `cognitive`, after SonarSource's definition adapted to Dart, with its own counting table (§6.4): base 0, every break in linear flow +1 plus one per enclosing nesting level, `else if`/`else` and labeled jumps +1 flat, one `switch` increment however many arms, one per run of the same boolean operator, null-aware shorthand 0, no knobs. Closures and local functions stay their own scopes; a closure's body starts one level deeper than where it is written, so `include_in_parent` (`value = measured + Σ child.value`) reproduces the whole-method number. Built-in thresholds `warn: 15, fail: 25`, calibrated over the M4 corpus: 15 has the prevalence cyclomatic 10 had and 25 that of cyclomatic 20, and on the M4-labeled scopes every table and boilerplate false positive scores ≤ 13 while every real tangle scores ≥ 18. The architecture proof held: zero engine changes beyond registration and an export; reporters, config, suppressions, `stats` and the JSON schema rendered the new metric unmodified. One seam finding: the table-shaped marker pools contributor families, and for a nesting-weighted metric a kind alone is the wrong family (dart_style's deepest `if` ladders were marked tables); cognitive names its families per kind and nesting level (`if`, `if@1`, `if@2`, §6.4), inside the metric. Two CLI tests that assumed a single registered metric were loosened. dmetrics' own config parser scored 25 and was split (`_Parser.parse` → `_topLevelEntry`), the same shape as M4's `resolveRun`.

**Changes in 0.7 (M4 field trial):** `--color auto|always|never` for the console reporter (verdict tag, table-shaped marker, diagnostic severity and the status word only; `auto` follows the tty, `NO_COLOR` and `TERM=dumb`; `--json` never colors). `table-shaped: <kind>` marker on console lines and `tableShaped: { kind, share }` in JSON results when one contributor kind supplies ≥ 70% of a scope's increments (≥ 8 in total). Motivation: across eleven trial codebases the false fails were `case` tables (opcode dispatch, `_contributorFor`, a text editor's `_executeAction`) and field-wise `==`/`copyWith`; the cut started at 80% and moved to 70% because tables whose arms carry `pattern-or` land at ~75% while the closest real tangle in the labeled set sits at 65%; the scalar cannot separate `case ×20` from `case ×12, if ×12`, the breakdown can. A reading hint for consumers, not a counting change (N6 intact). `dmetrics stats [targets]`: the calibration analysis the trial did by hand, per metric from a finished run (value bands and nearest-rank percentiles, share at or above the applied `warn`/`fail` with the table-shaped count among them, a sweep over fixed candidates, contributor mix by summed increment, sibling clusters of equal value and contributor summary at or above `warn`). Same targets and config handling as `analyze`, `--json` as a separate document, exit 0/2/3 only. Built-in cyclomatic thresholds `warn: 10, fail: 20` (`Metric.defaultThreshold`, `thresholds: none` opts out), closing the question §8 deferred to M4. Working name dropped: the tool, package, config key and suppression marker are `dmetrics`. Files are parsed at their package's language version (nearest `pubspec.yaml` `sdk` lower bound) instead of the latest, after the field trial found 3.13 rejecting `final` parameters across five community packages (§7.2). Table-shaped share pooled by contributor family (§7.3): every guarded `switch` table the trial found (`_contributorFor`, dart_style `blockFormatType`, dart-sass `_singleExpression` and `_visitQuotedString`) split its share across `case`, `pattern-or` and `when` and escaped the marker. G7 benchmark measured and recorded in the goal itself: the hypothesis holds with a ~20× margin. Null-aware collection elements count +1 as `if` (they are the `if (x != null) x` the lint rewrites); `?.` stays 0 after measuring the cost of counting it; initializer-level branches stay ignored on the data (§6.1).

**Changes in 0.6 (M3 as built):** config file shape specified (§8); metrics declare their run-global knobs with defaults (`settingDefaults`) so the loader can type-check them and the JSON `run` block always lists every knob; `fingerprint` added to `ScopeContext`; JSON gains a top-level `diagnostics[]` for problems with no parsed file to hang off (config errors, unreadable files), `configs[].overrides` when non-empty, `detail` only when non-null; CLI gains `--threshold`, `--json-contributors`, `--all`; a missing `--config` file is a usage error; suppression placement pinned down (trailing on the first line, before metadata, outermost scope on the line only); no built-in thresholds — without config every verdict is `ok`; `yaml` and `path` added to the dependency list; §5.2 gains the `RunResult` type that wraps the engine report for reporters.

**Changes in 0.5:** nested roll-up invariant corrected to use children's aggregated values (`value = measured + Σ(child.value − 1)`, cyclomatic-specific) with a three-level fixture; file identity made report-wide (run-root-relative) and separated from the config-root-relative path used for glob matching; deterministic collision fallback for duplicate named declarations in recovered source; JSON `parent` defined as the nearest enclosing scope emitted in the report; cyclomatic counting made explicitly independent of pipeline selection.

**Changes in 0.4:** structural file/class contexts introduced so every node has a context and scope-opening nodes have a home; metrics declare which scope kinds they measure; scope span now covers the whole declaration (metadata, parameters, initializers, body); multiple config roots reconciled with run-global counting knobs; scope identity narrowed to "deterministic and unique within a report" with declaration kind included, baseline matching deferred; JSON specimen made internally consistent with a stated invariant and deterministic ordering; aggregated results link to the child results they include; hide-children knob removed; counting-table holes closed (`on T` without `catch`, untyped binding arms, syntactic irrefutability rule, `switch` contributor kind); consumer 3 reworded to editor integration.

**Changes in 0.3:** consumption model reframed from "real-time checker" to "post-edit analysis, invoked like `dart analyze`"; traversal contract made explicit; roll-up moved from reporter policy to engine aggregation; counting rules expanded into a decision table; invalid-source contract and exit codes defined; JSON specimen added; I/O seam separated from the engine; config precedence and suppression matching specified; nesting probe added to M1.

---

## 1. Idea

A Dart-native static metrics engine that parses a codebase once, traverses each file's AST once, and feeds a set of pluggable metrics consuming that single traversal synchronously. The first two metrics are cyclomatic and cognitive complexity; the architecture is designed so that further metrics (nesting depth, LOC, parameter counts, …) slot in without new traversal passes or duplicated scope logic.

Library-first: the core exposes `analyze(sources, metrics, config) → report` as a pure Dart API over in-memory sources, with no file-system opinions. A thin I/O layer (discovery, reading, config lookup) and a CLI sit on top. This keeps the door open for an analyzer-plugin frontend and for embedding the engine in other tooling later.

Two framing decisions shape the roadmap:

1. **The primary consumer is a coding agent, and it runs the tool the way it runs `dart analyze`: after a unit of work is done, over a file or a directory, to get one consolidated report.** This is _not_ a real-time checker. An LLM acts on a complete report at a decision point; a stream of interim results over half-edited code is noise it cannot use and invites "fix the number" churn mid-edit. So: no watch mode, no daemon, no LSP in the critical path. The latency target is "a routine step in the agent's workflow", comparable to `dart analyze`, not "interactive". Editor integration for humans is demoted to reviewer tooling, later.
2. **Syntactic metrics are the beginning, not the end.** Per-file complexity metrics are job-level checks; project-maintainability metrics (coupling, dependency structure, instability) require _resolved_ analysis and are an explicit roadmap destination. v1 does not implement resolution, but every interface is designed so the resolved pipeline is additive, not a rewrite (see §5).

## 2. Goals

- **G1 — Correct cyclomatic complexity for modern Dart.** Full coverage of Dart 3 constructs: switch expressions, patterns (incl. logical-or/and, relational, object, typed wildcards, untyped bindings), `when` guards, `if-case`, collection `if`/`for` elements, null-aware operators, and null-aware collection elements (`?x`, Dart 3.8+). Every construct has an explicit counted/not-counted decision in §6; "not mentioned" is never a valid state.
- **G2 — Single-pass, multi-metric engine.** One driver visitor broadcasting node and scope events to N passive metric consumers, synchronously, in traversal order. Adding a metric must not add an AST traversal. (Post-traversal finalization over collected data, e.g. graph algorithms for dependency metrics, is explicitly permitted; see §5.1.)
- **G3 — Engine-owned scope model.** The engine alone decides what a scope is and maintains the context stack: structural contexts (file, class) and measured scopes (methods, getters/setters, constructors, closures, local functions). Metrics receive `ScopeContext` and declare which kinds they measure. Closure roll-up is an engine aggregation policy applied _before_ thresholds, not per-metric logic and not a reporter concern (see §6.3).
- **G4 — Uniform result model.** Every metric emits a per-scope `Measurement` (value + contributors); the engine turns it into a `MetricResult` (value, verdict, suppression, threshold, included children) so reporters are metric-agnostic.
- **G5 — Opinionated defaults, minimal knobs.** Counting semantics are uniform across a run. The two knobs in §6.2 exist because respected tools disagree; a disagreement alone does not create a knob (see §4). Thresholds and enablement can vary by path glob, by config root, and via `// ignore:` suppressions; measurement semantics cannot.
- **G6 — Executable spec via annotated fixtures.** Every row of the counting tables in §6.1, §6.4 and §6.5 has at least one annotated Dart fixture (`// expect: cyclomatic=4`, `// expect: cognitive=3`, `// expect: coupling=2`), doubling as regression test and documentation.
- **G7 — Fast on syntactic metrics.** Use `parseFile()`-level parsing (no resolution) whenever the requested metric set allows it. Benchmark hypothesis was a single 2k-LOC file in well under one second and a ~50k-LOC package in low single-digit seconds. Measured at M4 (2026-09-11, `dart compile exe` binary, Apple M4 Pro, warm file cache, median of three; each run is a cold process and includes config discovery, parsing, analysis and JSON serialization to stdout): a 2.3k-LOC file in 0.01 s, a 5k-LOC file in 0.02 s, pub's `lib` (36k LOC) in 0.08 s, dart-sass's `lib` (63k LOC, 4.2k scopes) in 0.16 s, and Flutter's `packages/flutter/lib` (570k LOC, 25k scopes, 44 MB of JSON) in 0.95 s. Process start dominates below ~5k LOC; above that the cost is linear at roughly 600k LOC/s on one core. The hypothesis holds with a margin of about 20×, so parallelism across isolates stays unneeded for syntactic metrics.
- **G8 — Agent-first ergonomics.** One command, `dmetrics analyze [targets…] --json`, over any mix of files and directories, mirroring `dart analyze`. JSON output includes a _contributor breakdown_ (which constructs produced the score, with spans) so an LLM gets an actionable refactor hint, not just a verdict. Analysis failures (parse errors, unreadable files, bad config) are never confusable with a clean report: distinct exit code, distinct status field (see §7.2).
- **G9 — Resolved-ready interfaces.** Coupling/dependency metrics are a committed future, so the interfaces already carry: `MetricRequirements { syntactic | directive | resolved }`, structural class/file contexts and a `library` scope opened only when measured, per-metric `measures` so new scope kinds never leak into old metrics, a structured `detail` slot, a run-level `finish` hook, and engine-side pipeline selection. Adding the resolved pipeline must not change any existing metric, and existing reporters must keep producing a useful generic rendering of new result types.

## 3. Non-goals

- **N1 — Not a linter.** No style rules, no auto-fixes. Metrics only.
- **N2 — No resolved-AST _implementation_ in v1 — but it is on the radar, not dropped.** Coupling, inheritance depth, dependency/instability metrics, dead-code detection all need `AnalysisContextCollection` and are the higher-value maintainability play long-term. v1 ships syntactic-only, but the interface commitments in §5.1 are binding now precisely so this lands later without rework.
- **N3 — No third-party plugin system.** Metrics are compiled in. Revisit only if the tool goes public.
- **N4 — Not a real-time checker; no watch mode, no daemon, no editor/LSP integration in v1.** The consumer is an agent invoking a batch command at a decision point (§7). Humans use the same console output. Editor integration (CodeLens `CC 12` as _reviewer_ tooling) is a v3+ item; the library seam exists so it can be an adapter rather than a rewrite.
- **N5 — No historical tracking / dashboards.** JSON output is the interchange point; trend analysis is someone else's job. (The v2 baseline file is a diff against a snapshot, not a history.)
- **N6 — No per-scope semantic overrides.** A given construct either counts as a branch everywhere in a run or nowhere. Non-negotiable for score comparability.

## 4. Prior art

| Tool / source                                     | What to take from it                                                                                                                                                          |
| ------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **dart_code_metrics** (pre-DCM OSS)               | The reference Dart implementation. Mine its construct list, visitor structure, and edge-case handling for cyclomatic complexity. Note where its counting differs from others. |
| **SonarSource — Cognitive Complexity whitepaper** | The spec for metric #2 (§6.4). Also a model of how to _document_ counting rules precisely.                                                                                    |
| **Lizard**                                        | Multi-language CC tool; useful as a cross-check oracle on shared constructs and for its pragmatic "count what induces branches" stance.                                       |
| **ESLint `complexity` rule**                      | Decades of issue-tracker pressure shaped its config surface; shows which knobs users actually demanded in a C-family language.                                                |
| **Dart SDK analyzer & linter**                    | `RecursiveAstVisitor` API, `// ignore:` suppression conventions, `analysis_options.yaml` config shape, and the annotated-fixture testing pattern used by the analyzer team.   |
| **McCabe (1976)**                                 | The original edges−nodes+2 definition; grounding for why branch-counting is an equivalent shortcut on structured code.                                                        |

Research task before M2: build a comparison table of counting decisions across dart_code_metrics, SonarQube, Lizard, and ESLint. The table _informs_ the decisions in §6.1; it does not generate knobs. A disagreement becomes a knob only if the M4 field trial shows real codebases need both conventions (M4 rule: bug-first, knob-second). Until then, §6.2 is the complete knob list.

## 5. Architecture outline

```
┌─────────────────────────────────────────────────────┐
│ Consumers    agent (post-edit) │ CI │ human console │
├─────────────────────────────────────────────────────┤
│ CLI (thin)   dmetrics analyze [files|dirs] [--json]    │
├─────────────────────────────────────────────────────┤
│ I/O layer    discovery (globs, excludes, *.g.dart)  │
│              config-root lookup, file reading       │
├─────────────────────────────────────────────────────┤
│ Reporters    console │ json (w/ contributor detail) │
├─────────────────────────────────────────────────────┤
│ Engine (pure, in-memory sources in → report out)    │
│  · pipeline select: syntactic (v1) │ resolved (vN)  │
│  · driver visitor → event broadcast                 │
│  · context stack (file, class, scopes)              │
│  · aggregation (roll-up) → suppression → thresholds │
│  · run-level finish (graph metrics, later)          │
├─────────────────────────────────────────────────────┤
│ Metrics (passive consumers)                         │
│  · cyclomatic (v1) · cognitive (v1) · coupling (vN) │
├─────────────────────────────────────────────────────┤
│ package:analyzer                                    │
│  · parseString/parseFile (v1) · AnalysisContext (vN)│
└─────────────────────────────────────────────────────┘
```

### 5.0 Core interfaces

```dart
/// Engine input: the engine never touches the file system.
class SourceFile {
  final String path;       // run-root-relative, forward slashes; report-wide file identity, used in ids
  final String content;
  final String configRoot; // run-root-relative directory of this file's config group (§8);
                           // globs match `path` relative to `configRoot`, never `path` itself
  final Uri? packageUri;   // package:<name>/<path under lib> when the file lives under a package's
                           // lib/, from the nearest pubspec's `name`; how `package:` imports resolve
}

enum ScopeKind {
  // Structural contexts: always present, never measured in v1.
  file, class_,
  // Measured scopes.
  function, method, getter, setter, operator, constructor, localFunction, closure,
  // The compilation unit of a non-part file, from its first token to the end of the file.
  // Opened only when a metric lists it in `measures`; named by the file's package: URI, else
  // its path.
  library,
}

/// What a metric needs from the engine, cheapest first. One pipeline per run: the most
/// demanding level any metric asks for. `directive` adds a LibraryIndex over the sources;
/// `resolved` is not implemented and the engine refuses a run that asks for it.
enum MetricRequirements { syntactic, directive, resolved }

class RunContext {
  final AnalysisConfig config;
  final LibraryIndex? libraries;   // non-null from `directive` up; a syntactic run never builds it
}

/// Directive resolution over the run's sources: `resolve(uriText, from: libraryName)` gives a
/// LibraryRef of kind source (one of the run's files), missing (a run package's file that is not
/// in the run: excluded, generated, absent), external (a dependency), sdk, or invalid.
class LibraryIndex { … }

abstract class Metric {
  String get id;                          // e.g. 'cyclomatic'
  MetricRequirements get requirements;    // syntactic | directive | resolved
  Set<ScopeKind> get measures;            // cyclomatic: the eight measured kinds above

  // Run-global knobs this metric reads, keyed `<id>.<knob>`, with their
  // documented defaults. The config loader rejects unknown knobs and values
  // of the wrong type; the JSON `run` block lists every knob with its
  // effective value. Read in onStartRun from `ctx.config.run.settings`.
  Map<String, Object?> get settingDefaults;   // cyclomatic: the two §6.2 knobs
  void onStartRun(RunContext ctx);

  // Scope lifecycle. The engine emits these ONLY for kinds in `measures`, so a
  // metric never sees a scope kind it did not opt into — adding `class_` or
  // `library` measurements later cannot change this metric's output.
  // Bracketed: every onEnterScope has exactly one onExitScope.
  void onEnterScope(ScopeContext ctx);
  Measurement onExitScope(ScopeContext ctx);

  // Node events, pre-order enter / post-order exit, source order, for EVERY
  // node in the file. `ctx` is the innermost open context of any kind
  // (structural or measured) and is never null.
  void onEnterNode(AstNode node, ScopeContext ctx);
  void onExitNode(AstNode node, ScopeContext ctx);

  // Roll-up hook (see §6.3). Called only when the run's policy asks for
  // aggregation. Default implementation: return `parent` unchanged.
  Measurement rollUp(Measurement parent, List<Measurement> children);

  // Run-level finalization, after every file has been traversed. Syntactic
  // metrics return nothing; graph-based metrics emit here. A measurement for
  // a scope the run traversed replaces that scope's measurement for this
  // metric; one for an unknown scope is reported at run level.
  Iterable<Measurement> finish(RunContext ctx);
}

class ScopeContext {
  final ScopeId id;             // opaque; deterministic and unique within a report (§7.3)
  final ScopeKind kind;
  final ScopeContext? parent;   // nearest enclosing context; null only for `file`
  final SourceSpan span;        // the whole declaration: metadata through body
  final String qualifiedName;   // display only: C.m / C.m.<closure#1> / C.field.<closure#1>
  final bool partial;           // true if the enclosing file had parse errors
  final String fingerprint;     // 8 hex digits, FNV-1a over the declaration's token
                                // lexemes (comments/whitespace excluded); see §7.3
}

/// What a metric produces for one scope.
class Measurement {
  final String metricId;
  final ScopeId scope;
  final num value;
  final List<Contributor> contributors;   // complete list; reporters may truncate
  final Object? detail;                   // reserved: structured payloads (edges, cycles)
}

class Contributor {
  final String kind;         // stable vocabulary from §6.1
  final num increment;
  final SourceSpan span;
}

/// What the engine emits after aggregation, suppression and thresholds.
class MetricResult {
  final Measurement measurement;      // as measured, always preserved
  final num value;                    // the value verdicts apply to (after roll-up)
  final List<ScopeId> includes;       // child results folded into `value`; empty unless rolled up
  final Threshold? threshold;         // the one that applied, after overrides
  final Verdict verdict;              // ok | warn | fail
  final Suppression? suppressed;      // non-null when an ignore applies
}
```

**Metric lifetime.** One instance per metric per run. The engine guarantees scope events are properly nested and bracketed, so a metric keeps per-scope state in a stack or a map keyed by `ScopeId`, created on `onEnterScope` and consumed on `onExitScope`. Node events that arrive while no measured scope is open (e.g. a `?:` in a field initializer, delivered with a `class_` context) are simply ignored by a metric that does not measure that kind. Metrics must not keep cross-file state unless they are resolved/run-level metrics that emit from `finish`; this is what makes isolate-parallelism a later drop-in.

### 5.0.1 Traversal lifecycle example

For this source:

```dart
class C {
  void m(int a) {
    if (a > 0) {
      list.forEach((x) { if (x) f(); });
    }
  }
}
```

a metric with `measures = {method, closure, …}` observes, in order:

```
[file context lib/c.dart]                              structural: no scope events
  onEnterNode  CompilationUnit        ctx=file
  onEnterNode  ClassDeclaration       ctx=file
  [class context C]                                    structural: no scope events
    onEnterNode  MethodDeclaration    ctx=C            ← the opening node belongs to the enclosing context
    onEnterScope C.m                                   ← method ∈ measures
      onEnterNode  FormalParameterList ctx=C.m         ← parameters, metadata, initializers: inside the scope
      onEnterNode  BlockFunctionBody   ctx=C.m
      onEnterNode  IfStatement         ctx=C.m
        onEnterNode  FunctionExpression ctx=C.m        ← closure node itself: parent scope
        onEnterScope C.m.<closure#1>
          onEnterNode  IfStatement     ctx=C.m.<closure#1>
          onExitNode   IfStatement     ctx=C.m.<closure#1>
        onExitScope  C.m.<closure#1>   → Measurement(cyclomatic=2)
        onExitNode   FunctionExpression ctx=C.m
      onExitNode   IfStatement         ctx=C.m
      …
    onExitScope  C.m                   → Measurement(cyclomatic=2)
    onExitNode   MethodDeclaration     ctx=C
  onExitNode   ClassDeclaration       ctx=file
  onExitNode   CompilationUnit        ctx=file
```

Rules this fixes:

- **Every node has a non-null context.** The file context is the root; class bodies open a `class_` context. Structural contexts never receive scope events and never produce measurements in v1; they exist so that scope-opening nodes, imports, field declarations and their initializers all have a home. A field-initializer closure's parent chain is `closure → class_ → file`.
- **The node that _opens_ a scope** (`MethodDeclaration`, `FunctionExpression`, `FunctionDeclaration`, `ConstructorDeclaration`, …) is delivered to the **enclosing** context on enter and exit. **All of its children** — metadata, name, type parameters, formal parameters, constructor initializer list, redirect, body — are delivered to the new scope. A parameter-count metric therefore sees parameters inside the scope it measures; constructor initializer-list branches belong to the constructor.
- While a child scope is open, the enclosing context receives **no** node events. Parent state is untouched until the child exits.
- `onExitScope` returns the child's measurement before the parent continues. Roll-up (if any) is applied by the engine after the parent's own `onExitScope`, via `rollUp(parent, children)`, where `children` are the measured scopes whose nearest measured ancestor is this scope.
- Traversal order is the analyzer's `visitChildren` order, which is source order. Both `onEnterNode` and `onExitNode` fire for every node; metrics ignore what they don't need.
- `ScopeKind.class_` and `file` become measurable (for future class/library metrics) purely by a new metric listing them in `measures`. Existing metrics are unaffected by construction.

### 5.1 Resolved pipeline — binding interface commitments

The resolved pipeline is not implemented in v1, but these decisions are made _now_ so that coupling/dependency metrics arrive as additions, not amendments:

- **Pipeline selection is engine-internal, and there is exactly one pipeline per run.** Callers pass a metric set; the engine runs the most demanding level any metric asks for and _all_ metrics consume its ASTs — syntactic metrics run unchanged over a directive or resolved run (that's the compatibility test). Never parse twice. Three levels, cheapest first: `syntactic` parses; `directive` parses and builds a `LibraryIndex` over the source list, which the cost probe showed is enough for import graphs at parse cost; `resolved` (element model) is refused until it exists. **Built 2026-09-12** for `syntactic` and `directive`.
- **One AST traversal per file; post-traversal finalization is allowed.** Dependency cycles and instability are properties of a graph collected across files. Resolved metrics accumulate during traversal and compute in `finish(RunContext)`. "No additional traversal" constrains AST walks, not algorithms over collected data.
- **Scope granularity widens, the result model doesn't.** Coupling/instability are per-class and per-library. `class_` is already a context; `library` is a scope: the unit of a non-part file, from its first token (leading comments excluded, like a declaration's doc comment, so a license header is not where the library starts and an `// ignore:` on the line before the first directive reaches it) to the end of the file, opened only when a metric lists it in `measures`, so function-shaped runs never report a scope nothing measured. While open it is the context of the file's top-level declarations (their JSON `parent`), but ids keep being allocated under the file: a top-level closure's id must not depend on which metrics are in the run. A part opens no library scope; its declarations belong to a library only the whole run can name. No reporter may assume scopes are function-shaped.
- **`finish` addresses scopes.** A graph metric returns a provisional measurement per library from `onExitScope` and replaces it from `finish` once the graph is complete; the replacement goes through aggregation, suppression and thresholds like any traversal measurement, so a library result has a verdict, counts toward status and exit code, and renders on the generic console line. Only a measurement for a scope the run did not traverse stays a bare run-level measurement.
- **The event model gains, never mutates.** Resolved metrics receive the same events plus a `ResolvedContext` accessor on `RunContext`/`ScopeContext` (element model, library graph).
- **`detail` carries structure; reporters degrade gracefully.** Dependency metrics report edges and cycles in `detail` (§6.5). The v1 JSON reporter serializes `detail` generically (any JSON-encodable value). The console reporter renders `value` + verdict for any metric and a specialized block only for detail types it knows: today one, a `cycle` list, printed as `cycle of N`. Adding a metric with a new `detail` shape must not break either reporter; making it _pretty_ in the console is that metric's job.
- **Cost honesty.** Resolution is slower and memory-hungry. A single-file target with syntactic metrics must never pay resolution cost. Resolved metrics are a repo-mode / CI concern — which fits, since that's where maintainability questions get asked.

### 5.2 I/O seam

`analyze()` takes `List<SourceFile>` and the resolved per-root `Config`s. Everything that touches the disk lives in `src/io/`: target expansion (files and directories; dot-directories such as `.dart_tool` skipped; `**.g.dart` and `**.freezed.dart` excluded by default), reading, and config-root lookup (§8). A convenience `analyzePaths(targets, …)` composes the two and returns a `RunResult`: the engine `Report` (null when config problems aborted the run) plus run-level diagnostics that belong to no parsed file (config errors, unreadable files), from which status, exit code and summary derive (§7.2). Reporters consume `RunResult`, never the bare `Report`. Tests drive the engine with in-memory sources; the I/O layer has its own small tests on temp directories.

## 6. v1 counting rules

§6.1–6.3 define cyclomatic complexity, metric #1; §6.4 defines cognitive complexity, metric #2; §6.5 defines import coupling, metric #3.

Base score 1 per measured scope. The table below is the complete decision list; every row has a fixture. The guiding convention: **count a construct that chooses between authored outcomes.** `??` chooses a right operand; a null-aware collection element chooses whether an element is present, exactly like the `if` element it desugars to. Null propagation (`?.`, `?..`, `?[]`, `...?`, `!`) passes null through an expression written once and counts 0. That line is pragmatic, and M4 checked it: `?.` is a runtime branch too, but counting it adds 7–19% to app-code scores, nearly all in field-wise boilerplate (`lerp`, `copyWith`), and flags no tangle the count misses. This is a documented cyclomatic variant, not McCabe over the full runtime CFG.

**Irrefutability is decided syntactically in v1.** A pattern is _irrefutable_ iff it is a bare wildcard `_`, an untyped variable pattern (`var x`, `final x`), or a parenthesized irrefutable pattern. Every other pattern — constants, typed wildcards `int _`, typed bindings `int x`, object, record, list, map, relational, null-check, null-assert — is treated as a test that can fail, regardless of what the scrutinee's static type would say. This convention is a property of the cyclomatic metric, **not of the pipeline**: the resolved pipeline must produce identical cyclomatic scores for identical source. Adding a resolved metric to a run must never change an existing metric's numbers. Any future change to counting is an explicit, versioned metric-policy decision (bumping `schemaVersion` and the metric's documented policy), never a side effect of resolution being available.

### 6.1 Decision table

| Construct                                                     | Δ                   | Contributor kind | Notes                                                                                        |
| ------------------------------------------------------------- | ------------------- | ---------------- | -------------------------------------------------------------------------------------------- |
| `if` statement                                                | +1                  | `if`             | `else if` is an `if`: +1. Bare `else`: 0.                                                    |
| `if-case` statement (`if (x case P)`)                         | +1                  | `if-case`        | Counts once, not `if` + pattern. Its `when` guard counts separately.                         |
| `for`, `for-in`, `await for`, `while`, `do-while`             | +1 each             | `loop`           | `for (;;)` with no condition still +1: uniformity over CFG purity.                           |
| `switch` statement / expression                               | 0 (default)         | `switch`         | Arms count; see next rows. With `count_case_arms=false`: +1 per switch (kind `switch`), arms 0. |
| `case` arm with a refutable pattern                           | +1 each             | `case`           | Constants, typed wildcards (`int _`), typed bindings, object/record/list/map, relational.    |
| `default` arm, bare `_` arm, untyped binding arm (`case var x`) | 0                 | —                | Irrefutable. Exhaustive switches without a wildcard get no adjustment.                       |
| Grouped labels (`case 1: case 2:` sharing a body)             | +1 per label        | `case`           | Same as separate arms.                                                                       |
| `when` guard (switch arm or `if-case`)                        | +1 each             | `when`           |                                                                                              |
| Logical-or pattern `P1 \|\| P2 \|\| P3`                       | +1 per extra alt.   | `pattern-or`     | At any nesting depth (`Foo(x: 1 \|\| 2)` counts). The arm itself still counts once.          |
| Logical-and pattern `P1 && P2`                                | 0                   | —                | Both must match; failure goes to the same place. Part of the arm's single test.              |
| `catch (e)`, `on T catch (e)`, `on T` without `catch`         | +1 each             | `catch`          | One per clause, binding or not. `try`, `finally`, `rethrow`: 0.                              |
| Conditional expression `c ? a : b`                            | +1                  | `ternary`        |                                                                                              |
| `&&`, `\|\|`                                                  | +1 each             | `&&`, `\|\|`     |                                                                                              |
| `??`, `??=`                                                   | +1 each             | `??`, `??=`      | Knob `count_null_coalescing`.                                                                |
| `?.`, `?..`, `?[]`, `!`                                       | 0                   | —                | Null propagation, not a decision; see the convention above.                                  |
| Collection `if` element (incl. `if-case` element)             | +1                  | `if`/`if-case`   | `else` element: 0.                                                                           |
| Collection `for` element                                      | +1                  | `loop`           |                                                                                              |
| Null-aware collection element `?x`, `?k: v`, `k: ?v` (3.8+)   | +1 per element      | `if`             | Sugar for `if (x != null) x`, which counts; the `use_null_aware_elements` rewrite is score-neutral. Decided at M4. |
| Spread `...`, null-aware spread `...?`                        | 0                   | —                |                                                                                              |
| `assert`                                                      | 0                   | —                | Not production control flow.                                                                 |
| `return`, `break`, `continue`, `throw`, `yield`, `await`      | 0                   | —                |                                                                                              |
| Labels, cascades `..`, recursion                              | 0                   | —                |                                                                                              |
| Closure / local function inside a scope                       | own scope           | —                | Never contributes to the parent's measurement; roll-up is an aggregation step (§6.3).        |

**Invariant, asserted by the harness for every measured scope:** `measured == 1 + Σ contributors.increment`.

**Scopes measured.** Methods, getters, setters, operators, constructors (the whole declaration including initializer list; a constructor with a `;` body but an initializer list is still measured), top-level functions, local functions, closures (function expressions, wherever they appear — including in field and top-level variable initializers, named `C.field.<closure#1>` under the `class_` or `file` context).

**Not measured.** Abstract, external, and redirecting-factory declarations (no body: no scope emitted, not score 1). Branch constructs directly inside field / top-level variable initializers (outside any closure) are delivered with a structural context and therefore **ignored** — a documented gap. M4 measured it over 21 packages (~1.9M LOC): 106 branch nodes in 88 initializers, three initializers with three or more, the largest six `if` elements; nothing within reach of a threshold. Kept ignored; dedicated initializer scopes remain the extension if that ever changes.

### 6.2 Knobs (complete list)

- `count_null_coalescing` (default: `true`) — Lizard counts `??`, SonarQube's cyclomatic does not.
- `count_case_arms` (default: `true`; `false` = +1 per switch) — the classic McCabe-vs-modified disagreement.

Both are **run-global** (§8). `closure_rollup` is not a counting knob; it is an aggregation policy (§6.3).

### 6.3 Aggregation, suppression, thresholds — in that order

The engine pipeline per file is: **measure scopes → aggregate → suppress → evaluate thresholds → report**. Verdicts are always computed on the value the aggregation policy produced, so a reported number can never disagree with its verdict.

- `closure_rollup: separate` (default) — each scope is its own result; `value == measurement.value`; `includes` is empty.
- `closure_rollup: include_in_parent` — the engine calls `metric.rollUp(parent, children)` bottom-up, where `children` are the **direct** measured children and each child's `value` is already its own aggregate. Cyclomatic defines it as `parent.measured + Σ(child.value − 1)`: each child's base score is excluded, so a method of 2 with a closure of 3 reports 4, and a method of 2 containing a closure of 2 that itself contains a closure of 2 reports 2 → 3 → 4 at the three levels. The parent result lists its direct folded children in `includes`; the children are **always emitted** with their own results and verdicts, and they count toward the summary and the exit code like any other result. There is no option to hide them: the JSON is the record, and the console reporter decides how much of it to print.

**Aggregated evidence invariant (cyclomatic-specific):** under `include_in_parent`, `value == measured + Σ over includes of (child.value − 1)`, with `includes` holding direct children only. A parent's own `contributors` explain `measured`; following `includes` recursively explains the rest without double-counting descendants. Other metrics define their own `rollUp` and their own invariant. Nothing in a report is a number without a breakdown that reaches it.

Every `MetricResult` preserves the raw `Measurement`, so the JSON carries both the measured and the aggregated value and the policy in effect. Aggregation is per metric (`rollUp` is a metric method): there is no engine-generic "sum"; a future nesting-depth metric defines `max`, a parameter-count metric defines identity.

Class- and file-level aggregates (max, sum, p90) are **not** produced in v1. They will become first-class when class/library metrics exist (§5.1).

### 6.4 Cognitive complexity (metric #2, `cognitive`)

Base score 0 per measured scope. After SonarSource's Cognitive Complexity (§4), adapted to Dart. The guiding convention: **count every break in the linear flow, and charge nesting for it.** A structure counts 1 plus the number of nesting bodies it sits in; a link in a chain (`else if`, `else`) and a labeled jump count 1 flat; a run of the same boolean operator counts 1; shorthand that collapses statements (`??`, `?.`, `?x`) and the arms of a `switch` count 0. Where cyclomatic scores a table by its size, cognitive scores it as one decision, which is why the two ship together: on the M4-labeled scopes every table and boilerplate false positive scores ≤ 13 here and every real tangle ≥ 18.

| Construct                                                                        | Δ             | Contributor kind      | Notes                                                                                                                                                       |
| -------------------------------------------------------------------------------- | ------------- | --------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `if` statement, `if-case` statement, collection `if` / `if-case` element         | +1 + nesting  | `if`                  | The condition is read at the statement's level; the branch is one deeper. `if-case` is one test: its pattern and guard are 0.                                |
| `else if` (statement or element)                                                 | +1            | `else-if`             | No nesting increment: a chain reads flat. Its own branches are one level deeper than the chain, like the first `if`'s.                                       |
| `else` (statement or element)                                                    | +1            | `else`                | Same. A structure directly in the `else` position (`else for`, `else switch`) is the link plus that structure one level deeper.                             |
| `for`, `for-in`, `await for`, `while`, `do-while`, collection `for` element      | +1 + nesting  | `loop`                | The header (init, condition, update, iterable) is at the loop's level; the body is one deeper.                                                              |
| `switch` statement / expression                                                  | +1 + nesting  | `switch`              | Once per switch, however many arms. The arms are one level deeper.                                                                                          |
| `case` arms, `default`, patterns, `when` guards, `\|\|` and `&&` patterns        | 0             | —                     | The table. A boolean run inside a guard is still a run.                                                                                                     |
| `catch (e)`, `on T catch (e)`, `on T`                                            | +1 + nesting  | `catch`               | Body one deeper. The `try` body is not nested; `try`, `finally`, `rethrow`: 0.                                                                              |
| Conditional expression `c ? a : b`                                               | +1 + nesting  | `ternary`             | Both branches one deeper, the condition not. A chain in the else branch nests: there is no `else if` shorthand for ternaries.                               |
| Run of `&&`, run of `\|\|`                                                       | +1 per run    | `&&`, `\|\|`          | Never charged nesting. The operator changing starts a new run; parentheses do not break a run of the same operator. `!` is 0.                               |
| Labeled `break`, labeled `continue`                                              | +1            | `break`, `continue`   | Flat. Unlabeled: 0.                                                                                                                                         |
| `??`, `??=`, `?.`, `?..`, `?[]`, `!`, `?x`, `?k: v`, `...`, `...?`               | 0             | —                     | Shorthand for a null check the reader would otherwise follow as statements. Cyclomatic counts `??` and `?x`; this metric is where that boilerplate scores low. |
| `assert`, `return`, `throw`, `yield`, `await`, labels, cascades                  | 0             | —                     |                                                                                                                                                             |
| Recursion                                                                        | 0             | —                     | Sonar adds 1 per method in a recursion cycle; naming a cycle needs resolution. A versioned decision for the resolved pipeline, never a side effect of it.   |
| Closure / local function inside a scope                                          | own scope     | —                     | Its body starts one level deeper than the point where it is written; see aggregation. A closure in a field or top-level initializer starts at level 0.       |

**Nesting.** A node's level is the number of nesting bodies between it and its scope's body: the branches of `if`, `else` and ternaries, the bodies of loops and `catch` clauses, the arms of a `switch`. A closure or local function written inside a measured scope starts at that point's level plus one, because its body is one more thing the reader is inside; under a structural context it starts at 0.

**Invariant, asserted by the harness for every measured scope:** `measured == Σ contributors.increment`, each increment `1 + level` for a structure and `1` otherwise.

**Aggregation.** Under `include_in_parent`, `value = measured + Σ child.value` over direct children, with the same `includes` rule as §6.3. A child's increments already carry the level of the point where it is written, so the aggregate is the number Sonar reports for the whole method, whose lambdas add a level and no increment. The three-level fixture asserts 6 / 5 / 3 for a method of 1 holding a closure of 2 holding a closure of 3.

**Scopes.** Measured and unmeasured exactly as §6.1; initializer-level branches outside closures are likewise ignored.

**Table-shaped marker.** Cognitive names its contributor families per kind and nesting level: `if` at the top of a body, `if@1` one level down, `if@2` two; `else if` and `else` pool with the `if` at their chain's level; runs and jumps pool by kind. A run of `if`s at one level is a table (Flutter's `InputDecoration.toString` is 54 property `if`s; `TextStyle.lerp` 96 field ternaries one level down); a ladder of `if`s each inside the last is the tangle this metric exists to find, and pooling by kind alone marked eleven of dart_style's thirty-eight scopes at or above 15 as tables, `RuleSet.tryBind` at 49 with increments five deep among them. With families per level none of those is marked and the flat tables still are.

**Thresholds.** Built in: `warn: 15, fail: 25`. Sonar's single default is 15. Calibrated 2026-09-11 over the M4 corpus (ten GitHub packages, ten own codebases, ~90k scopes): at or above 15 is 2.4–4.0% of scopes in library code (dart_style, dart-sass, pub; p95 = 10–12, p99 = 24–31) and 0.2–1.3% in app code (Flutter, Immich, AppFlowy, LocalSend, Spotube, getx; p95 = 4–6), the prevalence cyclomatic 10 has; at or above 25 is 0.8–1.4% and 0.1–0.5%, the prevalence of cyclomatic 20. On the scopes the M4 trial labeled: every real tangle scores 30–71 except three at 18–20 (a key handler, an eight-branch `else if` ladder, a seventeen-arm `&&` table), and every labeled false positive scores ≤ 13 (`TextAreaModel._executeAction` 1 against cyclomatic 21, `Theme.==` 2 against 19, `EngineConfig.copyWith` 0 against 23, dart-sass `_singleExpression` 1 against 24, dart_style `blockFormatType` 3 against 25, dart-sass `_visitQuotedString` 13 against 50).

**Knobs.** None. Sonar's definition has none and the trial gave no reason for one.

### 6.5 Import coupling (metric #3, `coupling`)

Per library, the number of distinct libraries of the run's own packages that the library's code imports: efferent coupling at library granularity, on the directive pipeline (§5.1). Base 0. The guiding convention: **count what the library's code can break on.** A library depends on what it imports from the codebase it ships with; the SDK and other packages are not that codebase, and a re-export is not code. Where cyclomatic and cognitive measure a scope's body, this measures its edges, which is why it is the first metric with a `library` scope, a `detail` payload and a `finish` step.

| Construct                                                                                     | Δ                        | Contributor kind | Notes                                                                                                                                                                                                                                                                                                                             |
| --------------------------------------------------------------------------------------------- | ------------------------ | ---------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `import 'x.dart'`, `import 'package:own/x.dart'` naming a library of one of the run's packages | +1 per distinct target   | `import`         | One contributor, at the first directive naming the target; a second `import` of the same library (`show`/`hide`, a prefix, `deferred`) is 0. The target counts whether or not it is among the run's sources (excluded, generated, absent: `missing` in `detail`), so a file measured alone scores as it does inside its package. |
| `export 'x.dart'`                                                                              | 0                        | —                | A re-export brings no code that can break: a barrel file is a package's API surface, not its coupling. Still an edge of the graph: the target's `dependents` name the exporting library and the edge takes part in cycles. Listed in `detail.exports` unless the same target is also imported.                                    |
| `import 'dart:…'`, `export 'dart:…'`                                                           | 0                        | —                | The SDK is not the codebase.                                                                                                                                                                                                                                                                                                      |
| `import 'package:other/…'` from a package the run does not analyze                             | 0                        | —                | A dependency, listed in `detail.external`. The run's packages are the package names of the run's `lib/` sources (§5.0 `packageUri`), so a run over a single `bin/` file has none and its `package:` imports of its own package are external; relative imports resolve by path and count either way.                                |
| Configurable import `import 'a.dart' if (dart.library.io) 'b.dart'`                            | +1 for the default URI   | `import`         | The alternatives are 0. The element model binds the default URI when no platform is chosen, and the cost probe matched the element model edge for edge.                                                                                                                                                                             |
| `part 'p.dart'`                                                                                | 0, plus the part's edges | `part`           | A part opens no scope of its own. Its `import`s (enhanced parts) fold into the including library: one `part` contributor per library the part adds, at the library's own `part` directive, so contributors stay inside the scope's file. Parts of parts likewise, through the same directive. A part not in the run adds nothing. |
| `part of`, `library`, an import of the library itself, a malformed or foreign-scheme URI       | 0                        | —                | A part measures nothing; the rest are not edges.                                                                                                                                                                                                                                                                                  |

**Detail.** `{ dependencies, missing, exports, external, dependents, cycle }`, every entry a sorted list of library names (`package:` URIs, or run-root-relative paths for files outside `lib/`). `dependencies` are the counted targets; `missing` the subset not among the run's sources; `exports` the re-exported targets that are not also imported; `external` the distinct libraries of other packages; `dependents` the run libraries that import or export this one (fan-in: only what the run saw, so a single-file run has none); `cycle`, present only when the library belongs to a strongly connected component of two or more run libraries, the component's members, this library included. Fan-in and fan-out being both present is deliberate: Martin's instability, `Ce / (Ca + Ce)`, is a derived number a later metric can compute from this graph without a new traversal.

**Cycles are informational.** Calibration found 60–85% of the libraries of every mature package inside one component (pub 114 of 134, dartdoc 64 of 89, dart-sass 217 of 373, the Flutter framework 283 and 103 in two). A verdict on membership would flag most of every real package; a verdict on component size, or on the edges whose removal breaks a cycle, is a later metric decided with data, never a side effect of this one. The console prints `cycle of N` after the contributor summary so a reader sees the tangle a hub sits in. The run-level picture (components with the back edges that hold them together, hubs with instability, the directory layering) is `dmetrics deps` (§7.1), a view over these `detail`s and nothing else.

**Invariant, asserted by the harness for every measured scope:** `measured == Σ contributors.increment`, each increment 1, base 0. A library has no measured children for this metric, so aggregation is the identity and `closure_rollup` does not apply.

**Table-shaped marker.** Never fires: each contributor is its own family. An import list is what this metric counts, and marking every library with eight or more imports as `table-shaped: import` would say nothing.

**Thresholds.** Built in: `warn: 15, fail: 30`. Calibrated 2026-09-12 over 14 packages: eight from the M4 corpus (dart-sass 373 libraries, pub 134, dart_style 82, dartdoc 89, drift 168, the Flutter framework 677, Immich's mobile app 633, LocalSend 184) and six own (universal_feed, kiko_core, kiko_widgets, plume, rope_lib, dmetrics; 18–75 each). Distribution: p50 = 1–4, p90 = 3–16, p95 = 5–19, p99 = 8–29. At or above 15 is 1.1–6.5% of libraries in both populations (pub the outlier at 10.4%, with 114 of its 134 libraries in one cycle) and 0–1.3% in the own packages, the prevalence cyclomatic 10 has. At or above 30 is 0–0.7%, and every hit is a hub by name: dart-sass `evaluate.dart` 41 and `async_evaluate.dart` 40, pub `validator.dart` 31, drift's `compiler.dart` 36, Flutter `theme_data.dart` 67, `editable_text.dart` 45 and `app.dart` 33, Immich `router.dart` 77 and `database.dart` 46, LocalSend `init.dart` 32. Between 25 and 30 sit registries and composition roots (pub `command_runner.dart` 29 and `entrypoint.dart` 28, Immich `main.dart` 29, LocalSend's `send_tab.dart` 29): hubs a package has one of on purpose, so `fail` stays above them and `warn` reads as "this file knows a lot of the package". Before exports were dropped from the value, the top scorer of 8 of the 14 packages was its barrel file (Flutter `material.dart` 182, dart-sass `ast/sass.dart` 86, kiko 47–52, universal_feed 45): that measurement decided the `export` row.

**Knobs.** None. The `export` decision was made on data rather than offered as a knob: no published tool disagrees with counting imports, and G5's bar for a knob is disagreement between respected tools.

## 7. Consumption model

Three consumers, in priority order:

1. **Agent, post-edit.** After finishing a task or a coherent batch of edits, the agent runs `dmetrics analyze <file|dir> --json`, exactly as it would run `dart analyze`, wired via a line in `CLAUDE.md` ("after editing, run `dmetrics analyze` on touched files; keep functions under 10"). The JSON contributor breakdown ("6 case arms, 4 nested ifs, 3 `??`", each with a span) turns a threshold failure into a refactor hint the model can act on. One report per decision point; no streaming, no per-keystroke feedback.
2. **CI backstop.** Whole-repo run, strict thresholds, exit codes, JSON artifact. The baseline file (recorded existing violations, fail only on new/worsened) is what lets CI be strict on agent-written code without a legacy cleanup crusade — a v2 commitment. Resolved metrics, when they land, live here.
3. **Editor integration (later).** Humans read the console output from v1. CodeLens-style "CC 14" in an editor, for judging what the agent produced, is nice, not necessary; see N4.

### 7.1 CLI shape

```
dmetrics analyze [<file>|<dir> ...] [--json] [--json-contributors full|summary] [--all]
              [--config <path>] [--fail-on warn|fail] [--set <key>=<value>]
              [--threshold <metric>=warn:N,fail:M]
```

- No targets: the current directory. Files and directories mix freely. A single-file target does no repo-wide discovery: it reads that file and looks up its config root (§8). Files that don't match the config's include/exclude are still analyzed when named explicitly (same as `dart analyze`).
- `--json` writes the report in §7.3 to stdout; console output otherwise. Diagnostics and progress never go to stdout in JSON mode; usage errors go to stderr.
- Console output is `dart analyze`-shaped: one line per finding (`path:line:col • verdict • kind qualifiedName • metric value [warn ≥ w, fail ≥ f] • contributor summary • table-shaped: kind` (last field only when one kind dominates; verdict, marker and status word colored under `--color`), only warn / fail / suppressed results and diagnostics by default, every scope with `--all`, then a one-line summary ending in the status.
- `--set cyclomatic.count_case_arms=false` overrides a run-global knob for the whole run (§8); `--fail-on` is shorthand for `--set fail_on=…`. `--threshold cyclomatic=warn:8,fail:12` forces a metric's thresholds in every root, above `overrides`.
- `--help` / `--version` as usual. A nonexistent target or `--config` file is a usage error (exit 3).

```
dmetrics stats [<file>|<dir> ...] [--json] [--config <path>] [--set <key>=<value>]
            [--threshold <metric>=warn:N,fail:M] [--color auto|always|never]
```

- Measures exactly as `analyze` does, then prints per metric: a distribution (bands `1–5, 6–9, 10–14, 15–19, 20+` and nearest-rank p50/p90/p95/p99/max over the rolled-up `value`), the count and share of scopes at or above `warn` and `fail` against each result's own applied threshold with how many of those are table-shaped, the same for a fixed candidate sweep (5, 8, 10, 12, 15, 20, 25, 30), the contributor mix (summed increments per kind as a share of the run's total), and sibling clusters (two or more scopes with equal `value` and equal contributor summary, at or above the result's `warn`, or the 90th percentile when no threshold applies). Suppressions are ignored: stats describe the code, not the verdicts. Metric-agnostic (G4): values, kinds and increments only.
- `--json` writes a stats document of its own (`schemaVersion`, `tool`, `status` of `ok`|`errors`, `summary`, `diagnostics`, `metrics.<id>`), never the §7.3 report. Exit codes: 0, 2 when analysis is incomplete, 3 on usage; violations are the subject of stats, not its outcome.

```
dmetrics deps [<file>|<dir> ...] [--json] [--top N] [--depth N] [--config <path>]
            [--set <key>=<value>] [--threshold <metric>=warn:N,fail:M] [--color auto|always|never]
```

- Measures exactly as `analyze` does, then prints the graph the `coupling` results describe, for the run as a whole: library and edge counts (imports and exports, targets outside the run); every strongly connected component of two or more libraries, largest first, with its back edges (the edges a greedy feedback-arc-set order points against: remove them and the component is acyclic; `--top` caps the listing); the libraries with the highest fan-out and fan-in (`--top` rows each) with Martin's instability `I = out / (in + out)`, the fan-out colored by the coupling verdict and cycle membership noted; and the graph folded onto directories (`--depth` levels under `lib/src` or `lib`, default 1; whatever precedes `lib` is kept, so a monorepo's packages stay apart) as a layering with per-edge library counts and the edges against the layering marked `back`. The fold uses import edges only: a barrel's re-exports say what the package publishes, not what its top level needs. Complete only when the whole package is in the run. Reads each library scope's `detail` by shape and nothing from the metric, so a run without `coupling` says it has no dependency data.
- `--json` writes a deps document of its own (`schemaVersion`, `tool`, `status`, `summary`, `diagnostics`, `libraries[]` with `fanOut`, `fanIn`, `exports`, `instability`, `cycle`, `verdict`; `cycles[]` with `members` and `backEdges`; `directories` with `depth`, `order` and `edges`). Exit codes as `stats`.

### 7.2 Invalid source and exit codes

Parsing uses error recovery (`throwIfDiagnostics: false`) at the file's language version: the lower bound of the nearest `pubspec.yaml` `sdk` constraint, the way `dart` resolves it, or the latest version for a file outside any package. The latest version is not a safe default: Dart 3.13 rejects `final` on parameters, which packages at 3.12 and below use freely. Per-file `// @dart=` override comments are honored by the parser on top of that. Files with syntax errors are still traversed: their scopes are measured from the recovered AST and marked `partial: true`, because a report on the 90% that parsed is still a useful hint. But the run is never clean:

| Exit | Meaning                                                                                    | JSON `status` |
| ---- | ------------------------------------------------------------------------------------------ | ------------- |
| 0    | Analysis complete, no verdict at or above `--fail-on`                                      | `ok`          |
| 1    | Analysis complete, threshold violations present                                            | `violations`  |
| 2    | Analysis incomplete: parse errors, unreadable files, invalid config, conflicting knobs (§8) | `errors`      |
| 3    | Usage error (bad flags, no such target)                                                    | —             |

Exit 2 wins over exit 1. Parse diagnostics are listed per file (`files[].diagnostics`: message, span, severity) and the file gets `status: "errors"`; problems with no parsed file to hang off — invalid config, conflicting knobs, unreadable files — go in the top-level `diagnostics[]` (message, severity, optional path/line/column). Either kind makes the run `errors`, so the agent can fix syntax or config first, then re-run. Config problems abort analysis (`files: []`) rather than measuring under a config the user did not ask for. `summary.filesWithErrors` counts files with parse errors; unreadable files never enter `files[]`. An empty target set (nothing matched) is exit 0 with zero files — reported explicitly in `summary`, never silent.

### 7.3 JSON report — specimen

The schema is the tool's real public interface; this specimen is a golden test. Coordinates are 1-based line/column, end-exclusive, plus 0-based UTF-16 offsets. All paths (`files[].path`, `configRoot`, `configs[].root`) are relative to the **run root** — the working directory of the invocation, as `dart analyze` reports them — with forward slashes, so a file path is unique within a report even when the run spans several packages.

**Ordering is deterministic:** `configs` by root path; `files` by path (byte order); `scopes` by start offset, then end offset; `contributors` by start offset; `includes` by the child's start offset.

```json
{
  "schemaVersion": 1,
  "tool": { "name": "dmetrics", "version": "0.1.0" },
  "status": "violations",
  "configs": [
    {
      "root": ".",
      "source": "analysis_options.yaml",
      "metrics": {
        "cyclomatic": {
          "enabled": true,
          "thresholds": { "warn": 8, "fail": 12 }
        }
      }
    }
  ],
  "run": {
    "cyclomatic": { "count_null_coalescing": true, "count_case_arms": true },
    "closure_rollup": "separate",
    "fail_on": "fail"
  },
  "summary": {
    "files": 1,
    "filesWithErrors": 0,
    "scopes": 2,
    "verdicts": { "ok": 1, "warn": 0, "fail": 1 },
    "suppressed": 0
  },
  "diagnostics": [],
  "files": [
    {
      "path": "lib/src/parser.dart",
      "configRoot": ".",
      "status": "ok",
      "diagnostics": [],
      "scopes": [
        {
          "id": "lib/src/parser.dart::method:Parser.parseExpr",
          "kind": "method",
          "name": "parseExpr",
          "qualifiedName": "Parser.parseExpr",
          "parent": null,
          "fingerprint": "b41e07d2",
          "span": {
            "start": { "line": 41, "column": 3, "offset": 1180 },
            "end": { "line": 88, "column": 4, "offset": 2731 }
          },
          "partial": false,
          "results": {
            "cyclomatic": {
              "measured": 13,
              "value": 13,
              "includes": [],
              "threshold": { "warn": 8, "fail": 12 },
              "verdict": "fail",
              "suppressed": null,
              "contributors": [
                { "kind": "case", "increment": 1, "span": { "start": { "line": 44, "column": 7,  "offset": 1240 }, "end": { "line": 44, "column": 18, "offset": 1251 } } },
                { "kind": "when", "increment": 1, "span": { "start": { "line": 44, "column": 19, "offset": 1252 }, "end": { "line": 44, "column": 31, "offset": 1264 } } },
                { "kind": "case", "increment": 1, "span": { "start": { "line": 47, "column": 7,  "offset": 1301 }, "end": { "line": 47, "column": 20, "offset": 1314 } } },
                { "kind": "case", "increment": 1, "span": { "start": { "line": 50, "column": 7,  "offset": 1366 }, "end": { "line": 50, "column": 22, "offset": 1381 } } },
                { "kind": "if",   "increment": 1, "span": { "start": { "line": 52, "column": 5,  "offset": 1402 }, "end": { "line": 52, "column": 22, "offset": 1419 } } },
                { "kind": "case", "increment": 1, "span": { "start": { "line": 55, "column": 7,  "offset": 1478 }, "end": { "line": 55, "column": 24, "offset": 1495 } } },
                { "kind": "when", "increment": 1, "span": { "start": { "line": 55, "column": 25, "offset": 1496 }, "end": { "line": 55, "column": 40, "offset": 1511 } } },
                { "kind": "if",   "increment": 1, "span": { "start": { "line": 58, "column": 5,  "offset": 1560 }, "end": { "line": 58, "column": 27, "offset": 1582 } } },
                { "kind": "case", "increment": 1, "span": { "start": { "line": 66, "column": 7,  "offset": 1760 }, "end": { "line": 66, "column": 19, "offset": 1772 } } },
                { "kind": "??",   "increment": 1, "span": { "start": { "line": 70, "column": 14, "offset": 1868 }, "end": { "line": 70, "column": 16, "offset": 1870 } } },
                { "kind": "case", "increment": 1, "span": { "start": { "line": 74, "column": 7,  "offset": 1951 }, "end": { "line": 74, "column": 21, "offset": 1965 } } },
                { "kind": "if",   "increment": 1, "span": { "start": { "line": 80, "column": 5,  "offset": 2140 }, "end": { "line": 80, "column": 30, "offset": 2165 } } }
              ],
              "contributorSummary": { "case": 6, "when": 2, "if": 3, "??": 1 }
            }
          }
        },
        {
          "id": "lib/src/parser.dart::method:Parser.parseExpr::closure#1",
          "kind": "closure",
          "name": "<closure#1>",
          "qualifiedName": "Parser.parseExpr.<closure#1>",
          "parent": "lib/src/parser.dart::method:Parser.parseExpr",
          "fingerprint": "3f9a1c8e",
          "span": {
            "start": { "line": 60, "column": 20, "offset": 1610 },
            "end": { "line": 63, "column": 6, "offset": 1702 }
          },
          "partial": false,
          "results": {
            "cyclomatic": {
              "measured": 2,
              "value": 2,
              "includes": [],
              "threshold": { "warn": 8, "fail": 12 },
              "verdict": "ok",
              "suppressed": null,
              "contributors": [
                { "kind": "if", "increment": 1, "span": { "start": { "line": 61, "column": 7, "offset": 1640 }, "end": { "line": 61, "column": 19, "offset": 1652 } } }
              ],
              "contributorSummary": { "if": 1 }
            }
          }
        }
      ]
    }
  ]
}
```

Contract notes:

- **Scope identity vs display name.** `qualifiedName` and `name` are for humans and may shift (`<closure#1>` becomes `<closure#2>` when an earlier closure is inserted). `id` is **deterministic and unique within a report**, nothing more: `path::kind:qualifiedName` for named scopes — `path` is the run-root-relative file path (report-wide unique, so two packages each holding `lib/src/parser.dart` do not collide), and the kind is part of the id because display names collide (constructor `C.foo` vs method `C.foo`; getter `C.x` vs setter `C.x`) — and `parentId::closure#N` for closures, where `N` is the source-order ordinal among the parent's direct closures. **Collision fallback:** recovered invalid source can contain duplicate named declarations; when two named scopes would share an id, the second and later ones get a `#2`, `#3`, … suffix in source order (`path::method:C.m#2`). `id` is opaque to reporters. **Cross-revision matching is a baseline (v2) responsibility, not an identity property**; `fingerprint` (a short hash of the scope's normalized token stream) is recorded as supporting evidence for that future matcher, and v1 promises nothing about it beyond determinism.
- **Contributors are complete.** The engine records every contributor with its span, and the JSON emits all of them (the specimen above lists all twelve of `parseExpr`'s). Reporters may truncate for display (console shows `contributorSummary` plus the top few); `--json-contributors=summary` drops the list from the JSON when a consumer only wants counts.
- **Table-shaped scopes are marked, not excused.** When one contributor kind supplies at least 70% of a scope's summed increments and the total is at least 8, the result carries `tableShaped: { kind, share }` (JSON, present only then) and the console line ends in `table-shaped: kind`. A `switch` over twenty messages, a seventeen-field `==`, a `copyWith` of `??`s: their score is the size of a table, and a consumer deciding whether to refactor should read the marker first. The share is computed over contributor _families_: a metric may pool kinds that are one construct written in pieces (cyclomatic pools `case`, `pattern-or` and `when`, because a guarded or-pattern arm is still one arm of the table); unpooled kinds are their own family and the marker names the family; a metric may also split a kind into families, as cognitive does per nesting level (`if@2`, §6.4), so that a ladder of nested `if`s is never a table. The verdict is unchanged; getting such a scope past CI is what a named override (§12) or a suppression is for. Metric-agnostic: computed from families and increments alone.
- **Suppressed results are still reported**, with `suppressed: { "kind": "ignore" | "ignore_for_file", "span": … }`, verdict forced to `ok`, and counted in `summary.suppressed`. Suppressions are visible, never silent.
- **`measured` vs `value` vs `includes`.** Identical values and empty `includes` under `closure_rollup: separate`. Under `include_in_parent`, `value` is the aggregate, `includes` lists the child ids folded in, `verdict` applies to `value`, and the children appear as their own scopes with their own results.
- **`parent` in JSON** is the id of the nearest enclosing scope **emitted in the report**, or `null`. Structural contexts (file, class) are not serialized, so a method's JSON `parent` is `null` even though its in-engine `ScopeContext.parent` is the class context. Reporters that need the class can read `qualifiedName`.
- **`configs` vs `run`.** Per-root settings (thresholds, enablement, overrides) live in `configs[]`; each file names its `configRoot`. `configs[].source` is the config file's run-root-relative path, or `null` for a defaults root; `configs[].overrides` (`[{ paths, metrics }]`) appears only when the root has any. Run-global settings (counting knobs, roll-up policy, `fail_on`) live once in `run`; every knob a metric declares in `settingDefaults` is listed with its effective value, config or not.
- **Optional keys.** `detail` appears on a result only when the metric set it; `runMeasurements[]` (from `finish`) only when non-empty. Everything else in the specimen is always present, `null` where it does not apply. `summary.verdicts` counts results, not scopes, so it sums to `scopes` only in a single-metric run.
- **`partial: true`** on a scope means the file had parse errors; the number is a best effort from a recovered AST.
- **Scopes are not all function-shaped.** `kind` is `library` for a per-library result (§6.5): its `name` and `qualifiedName` are the library's `package:` URI or path, its `parent` is `null`, and the file's top-level scopes name it as their `parent`. A library result's `detail` is the import graph as §6.5 lists it. Consumers must dispatch on `kind`, never assume a method.
- **`fingerprint`** is FNV-1a (32-bit) over the declaration's token lexemes, NUL-separated, comments and whitespace excluded, as eight hex digits. Identifiers are not normalized in v1; a rename changes it.

## 8. Initial setup

**Package layout** (single package to start; split only if the CLI grows):

```
dmetrics/
  lib/
    dmetrics.dart              # public API: analyze(), analyzePaths()
    src/engine/             # driver visitor, context stack, aggregation, thresholds, graph algorithms
    src/metrics/cyclomatic/
    src/metrics/cognitive/
    src/metrics/coupling/     # first dependency metric; directive pipeline, `library` scope, `finish`
    src/io/                 # discovery, reading, config-root lookup (the only fs code)
    src/config/
    src/report/             # console, json, and the run-level views: stats, deps
  bin/dmetrics.dart            # CLI entry
  test/
    fixtures/cyclomatic/    # annotated .dart fixture files, one per §6.1 row minimum
    engine/                 # context/scope lifecycle tests (in-memory sources)
    probe/                  # nesting-sensitive probe metric (M1, not shipped)
  analysis_options.yaml
```

**Dependencies:** `analyzer`, `args`, `glob`, `path`, `source_span`, `yaml`, `test`. Nothing else until it hurts (`path` and `yaml` are already transitive via `analyzer`).

**Config file.** The `dmetrics:` section of `analysis_options.yaml`:

```yaml
dmetrics:
  fail_on: fail                        # run-global: warn | fail
  closure_rollup: separate             # run-global: separate | include_in_parent
  include: ['lib/**', 'bin/**']        # per-root discovery globs; default: every .dart file
  exclude: ['**.g.dart']               # per-root; default: ['**.g.dart', '**.freezed.dart']
  metrics:
    cyclomatic:
      enabled: true
      thresholds: { warn: 8, fail: 12 }
      count_case_arms: true            # run-global knob, declared by the metric (settingDefaults)
      count_null_coalescing: true
  overrides:                           # thresholds and enablement only; last match wins
    - paths: ['test/**']
      metrics:
        cyclomatic: { thresholds: { warn: 15, fail: 25 } }
    - paths: ['lib/src/generated/**']
      metrics:
        cyclomatic: { enabled: false }
```

Unknown keys, unknown metric ids, unknown or mistyped knobs, `warn > fail`, malformed YAML, and a run-global key inside `overrides` are all config errors (exit 2) with a file position. A bare `dmetrics:` with nothing under it still makes its directory a root, with defaults. Built-in defaults are: every compiled-in metric enabled, each metric's own default thresholds (`Metric.defaultThreshold`; cyclomatic `warn: 10, fail: 20`, decided at M4 with data: across eleven trial codebases 10 sat near the 90th–95th percentile and 20 was precise), the default `exclude` list. `thresholds: none` under a metric opts out of its default for that root (every verdict `ok` until `--threshold` says otherwise); a metric with no default behaves as if `none` were set. `configs[].metrics.<id>.thresholds` in the JSON report is the effective pair, default included.

**Config roots.** Config is read from `analysis_options.yaml` under a `dmetrics:` key. Each analyzed file's **config root** is the nearest ancestor directory containing an `analysis_options.yaml` with that key (or the package root if none has it, using built-in defaults). This lookup is per file and identical whether the file was named explicitly or discovered under a directory, so both paths yield the same measurement and the same policy. `--config <path>` forces a single root for the whole run. A monorepo run therefore naturally has several roots.

Two classes of setting, with different scoping:

- **Per-root (may differ between roots):** thresholds, metric enablement, `overrides` path-glob blocks, include/exclude patterns.
- **Run-global (must be identical across roots):** counting knobs (§6.2), `closure_rollup`, `fail_on`. If two roots in one run disagree on a run-global setting, the run is a config error (exit 2, `status: errors`, diagnostic naming both files) unless `--set` fixes the value for the whole run, in which case the CLI value wins everywhere and is reported in `run`.

Precedence within a root, highest first:

1. CLI flags (`--fail-on`, `--threshold cyclomatic=warn:8,fail:12`, `--set …`)
2. Path-glob `overrides` blocks in that root's config — last matching override wins
3. That root's top-level config
4. Built-in defaults

Globs match the file's path **relative to its config root** with `package:glob` semantics; the run-root-relative `path` used for identity and reporting is never what a glob sees, so a package's config matches the same files regardless of where the run was started. `overrides` may change **thresholds and enablement only**; a run-global key inside `overrides` is a config error (exit 2).

**Suppressions.** `// ignore: dmetrics_cyclomatic` on the line immediately before a scope's declaration (the line before its metadata, if any; a doc comment in between breaks the adjacency), or as a trailing comment on the declaration's first line; `// ignore_for_file: dmetrics_cyclomatic` anywhere in the file. `// ignore: dmetrics` suppresses all metrics for that scope; other names in the same comment (`// ignore: unused_element, dmetrics_cyclomatic`) are ignored, as the analyzer does. Comments are taken from the token stream, so text inside string literals never matches. A line ignore applies only to the **outermost** measured scopes starting on that line, so a suppression on a method does not suppress its closures, not even a closure on the method's first line; to suppress a closure, put the ignore on the closure's own line. Suppressed results are reported as in §7.3. (Inline suppressions vs. agent-authored code is under review — see §9 — but ship as specced.)

**Golden.** `test/golden/report.json` is the rendering of `test/golden/src/lib/src/parser.dart` (a source built to reproduce the specimen's numbers: 13, six `case` arms, two `when`, three `if`, one `??`, one closure). The golden test also parses the §7.3 specimen straight out of this file and asserts that the rendered report has exactly its key structure, so editing the specimen without the reporter (or vice versa) fails the build. Regenerate with `UPDATE_GOLDENS=1 dart test test/report/json_golden_test.dart`.

**Testing.** The annotated-fixture harness is the _first_ thing built. Each fixture scope carries `// expect: cyclomatic=N` (and `// expect: cyclomatic=N rolled=M` where roll-up differs, including a three-level method → closure → closure fixture asserting 2/3/4); the harness parses annotations, runs the engine over in-memory sources, asserts per scope, and checks the §6.1 and §6.3 invariants on every result. A fixture with an `// expect: partial` header asserts the invalid-source behavior. Cognitive has its own fixture directory with one file per §6.4 row plus the whitepaper's worked examples transliterated to Dart at the numbers the paper gives, and a `both` directory measures cyclomatic and cognitive on one traversal (`// expect: cyclomatic=4 cognitive=7`), each checked against its own invariants. Coupling has a fixture directory for the per-file rows of §6.5 (a fixture is one file, so every relative target is a `missing` library of its package, which counts) and an in-memory graph test for what one file cannot show: edges between sources, fan-in, cycles through imports and exports, parts folded into their library, a file scoring the same alone as in its package, and the shipped metrics unchanged beside it. Engine tests include a display-name collision fixture (constructor `C.foo` next to method `foo`, getter/setter pair) asserting distinct ids, a recovered-source fixture with a duplicated method asserting the `#2` fallback, a two-package fixture with identical relative paths asserting distinct ids, and multi-root fixtures asserting per-root thresholds and the knob-conflict error. A small oracle script compares selected fixtures against Lizard for cross-validation of shared constructs.

**Milestones:**

1. **M0 — Harness.** Fixture format + test runner working against a hardcoded dummy metric, in-memory sources only.
2. **M1 — Engine skeleton.** Driver visitor with enter/exit node events, context stack (file, class, measured scopes), `ScopeContext`, `ScopeId`, `measures` filtering, result model, aggregation and threshold stages. Lifecycle tests green: closure-inside-`build`, closure in field initializer (parent chain `closure → class_ → file`), local function in constructor, parameters delivered inside the scope, opening node delivered to the enclosing context. **Includes the nesting probe:** a throwaway metric that tracks nesting depth via node exit and independent per-scope state, asserted on nested-closure fixtures. It never ships; it proves the traversal contract before cyclomatic is built on it.
3. **M2 — Cyclomatic.** Full §6.1 table, one fixture per row minimum, Dart 3.8 constructs included, invariant checked on every fixture.
4. **M3 — I/O layer, CLI, reporters.** Discovery, config roots and precedence, run-global conflict detection, suppressions, console + JSON output conforming to the §7.3 specimen (golden test), deterministic ordering, exit codes per §7.2, invalid-source handling.
5. **M4 — Field trial.** Run on 2–3 real codebases (a large pub package, work monorepo with several config roots); wire into a real Claude Code session via `CLAUDE.md` as a post-edit step; triage every surprising score as bug-first, knob-second; run the G7 benchmark under its stated conditions; revisit the null-aware-element and initializer decisions with data. **Done 2026-09-11.** 11 own codebases plus 14 GitHub packages in two populations (Dart-team libraries; community apps such as Immich, AppFlowy, LocalSend); thresholds 10/20 kept, precision at fail confirmed on both; two bugs fixed from the trial (parse at the package language version; table-shaped share pooled by family); G7 measured with a ~20× margin; `?x` and initializer decisions closed (§6.1). The `CLAUDE.md` wiring is `make check` ending in `dmetrics analyze lib bin`.
6. **M5 — Metric #2 (cognitive complexity)** as the architecture proof: it must require zero engine changes beyond registration. (M1's probe makes this a confirmation, not a discovery.) **Done 2026-09-11.** Confirmed: `CognitiveMetric` is registered in `defaultMetrics()` and exported, and nothing else in the engine, config, suppressions, reporters or `stats` changed. Two CLI tests had assumed one registered metric (verdict counts are per result; `stats` lists metrics alphabetically) and were loosened. One seam finding, solved inside the metric: the table-shaped marker pools by contributor family, and a nesting-weighted metric needs families per kind and level (§6.4). Thresholds calibrated over the M4 corpus (§6.4); dmetrics' own config parser was the one self-fail at 25 and was split.

7. **M6 — Resolved-pipeline spike and metric #3 (import coupling).** **Done 2026-09-12.** The cost probe settled the pipeline (directive-level, §9); the engine seam was built and proven with a throwaway import-count metric (§5.1: pipeline selection, `LibraryIndex`, `library` scope, `finish` addressing scopes); then `coupling` shipped on it with its own counting table, `detail` graph and calibrated thresholds (§6.5). Confirmed: registration, an export, the library span and one console note were the whole diff outside the metric; the shipped metrics produce identical results over every fixture with `coupling` registered; `stats`, config, suppressions and the JSON reporter took the new scope kind unmodified. Two findings decided by measurement: re-exports are edges, not coupling (barrels were the top scorer of 8 of 14 packages), and cycle membership is informational (most of every mature package is in one component).
8. **M7 — `dmetrics deps`, the aggregate graph view.** **Done 2026-09-12.** The first consumer of the coupling `detail` beyond a console note. Built like `stats`: a pure function of the finished run, no engine change beyond moving Tarjan to a shared graph file and adding the feedback-order heuristic next to it. Decided by looking at real output: a component's member list says nothing at pub's or dart-sass's scale, its back edges do; directory cycles marked by component membership marked every edge of every mature package, a layering with back edges reads; the directory fold must ignore exports or the barrel is a hub.

**Radar (post-M7, unscheduled):** baseline file for CI adoption (its matcher consumes `id` and `fingerprint`, §7.3) → `--dot` for `deps` (Graphviz of the directory graph) if the console layering proves not enough → Martin-style abstractness per package, which needs class kinds and so the resolved pipeline (instability is in `deps` per library) → a cycle metric with a verdict, once there is data on which back edges matter (§6.5; `deps` now names them) → editor shell as reviewer tooling → the resolved pipeline when a metric needs elements (CBO per class, inheritance depth, dead code; §9).

## 9. Open questions

- **Inline suppressions vs. agent-authored code (tracking — no change yet).** `// ignore:` assumes a human making a considered judgment; an agent under "make it pass" pressure can add one as easily as fixing the code, and it hides in a large diff. Candidate direction if this bites: drop inline suppressions, centralize all exceptions in reviewable config (baseline for legacy, path globs, named `overrides: {qualified_name: threshold}` for the rare genuine case), and have reporters surface active-override counts as a tracked number. The §7.3 rule that suppressions are always reported and counted is the first step in that direction regardless. Decision deferred to after M4.
- **Name.** `dmetrics` is a placeholder. (Waterfowl convention is taken by work — but a personal convention could start here.)
- **Baseline matching.** A v2 problem, deliberately not designed here. Inputs it will have: stable `id` for named scopes, ordinal-based `id` plus `fingerprint` for closures, spans. Known tension: an edited closure changes its fingerprint, and an inserted closure changes later ordinals, so the matcher will need a heuristic (parent + nearest ordinal + fingerprint similarity), not a key lookup. Constraint now: `id` stays opaque to reporters; the fingerprint algorithm may change until the baseline ships. Note that `id` embeds a run-root-relative path, so the baseline will store paths relative to its own location and normalize on load.
- **Null-aware collection elements and initializer-level branches.** Both flagged for M4 review with real code and closed there: `?x` counts +1 as `if` (§6.1), initializer-level branches stay ignored (§6.1, measured).
- **First resolved metric — decided by measurement (2026-09-12).** Import-graph coupling and cycles per library need no resolution at all. The cost probe (`tool/resolve_probe.dart`, 13 packages from the M4 corpus plus the Flutter framework) built the library graph two ways — import/export directives with `package:` URIs resolved through `package_config.json`, and the analyzer's element model — and got identical in-package and out-of-package edge counts on every package (Flutter: 4576/60; pub: 824/180; dart-sass: 1700/474). The directive pass costs the same as parsing (+1–8 ms). So the first dependency metric runs on a _directive_ pipeline (parse + package-config lookup), a third requirement level between `syntactic` and `resolved`, and every §5.1 commitment applies to it. Real resolution is reserved for metrics that need elements: CBO per class, inheritance depth, dead code.
- **Resolved-mode incrementality — measured (2026-09-12), not needed for a first resolved metric.** Cold `AnalysisContextCollection` cost is a fixed cost of linking the package's transitive dependency closure, not a function of its size: dmetrics (4 kLOC, imports the analyzer) 1.2 s / 446 MB peak; dart-sass (63 kLOC, few dependencies) 0.55 s elements-only, 0.83 s with every unit resolved, 186 MB; the Flutter framework (525 kLOC) 1.9 s elements-only, 6.7 s with every unit resolved, 815 MB. The first element or unit request pays nearly all of it. Element-only and fully resolved cost the same below ~40 kLOC and diverge above. Against 3–275 ms and 31–100 MB for parsing. Verdict: "resolved = CI-only, cold" is seconds and hundreds of MB, not minutes; warm or cached contexts are a later optimization, if ever.
- **Isolate parallelism.** File-level parallelism via isolates is trivially shardable for syntactic metrics given the per-run metric-instance rule in §5.0. Measure first at M4; don't build speculatively.
