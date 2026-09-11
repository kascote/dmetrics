/// Annotated fixture format (SPEC §8, "Testing").
///
/// Scope expectations, on the line(s) immediately before a scope's
/// declaration; several may be stacked:
///
///     // expect: cyclomatic=4
///     // expect: cyclomatic=4 rolled=6        (value under include_in_parent)
///     // expect: cyclomatic=4 cognitive=3     (several metrics on one line)
///     // expect: none                         (no scope may start here)
///
/// File directives, anywhere in the file:
///
///     // expect: partial                      (the file has parse errors)
///     // run: cyclomatic.count_case_arms=false (run-global setting override)
///
/// An expectation targets the first non-annotation line below it. `rolled=`
/// attaches to the metric key immediately before it. Annotations must be on
/// their own line; code before `//` on the same line is a format error, so
/// `dart format` (which keeps leading comments attached) cannot move them.
library;

class FixtureFormatException implements Exception {
  final String path;
  final int line;
  final String message;

  FixtureFormatException(this.path, this.line, this.message);

  @override
  String toString() => '$path:$line: $message';
}

/// One `metric=value [rolled=value]` expectation attached to a target line.
class Expectation {
  final String metric;
  final num value;

  /// Expected aggregated value under `include_in_parent`, if stated.
  final num? rolled;

  /// 1-based line of the annotation comment itself.
  final int annotationLine;

  const Expectation({
    required this.metric,
    required this.value,
    required this.rolled,
    required this.annotationLine,
  });

  @override
  String toString() =>
      '$metric=$value${rolled == null ? '' : ' rolled=$rolled'}';
}

class Fixture {
  final String path;
  final String content;

  /// Expectations by 1-based target line, then by metric id.
  final Map<int, Map<String, Expectation>> expectations;

  /// 1-based lines where no scope may start.
  final Set<int> noneLines;

  /// The file declares `// expect: partial`.
  final bool expectPartial;

  /// `// run:` overrides, raw string values.
  final Map<String, String> runSettings;

  const Fixture({
    required this.path,
    required this.content,
    required this.expectations,
    required this.noneLines,
    required this.expectPartial,
    required this.runSettings,
  });

  /// Every metric id named by at least one expectation.
  Set<String> get metrics => {
    for (final byMetric in expectations.values) ...byMetric.keys,
  };

  bool get hasRolled => expectations.values.any(
    (byMetric) => byMetric.values.any((e) => e.rolled != null),
  );

  /// Parses [content]; throws [FixtureFormatException] on malformed
  /// annotations.
  static Fixture parse(String path, String content) {
    final lines = content.split('\n');
    final expectations = <int, Map<String, Expectation>>{};
    final noneLines = <int>{};
    final runSettings = <String, String>{};
    var expectPartial = false;

    bool isAnnotation(int index) =>
        index < lines.length && _annotation.hasMatch(lines[index]);

    for (var i = 0; i < lines.length; i++) {
      final lineNo = i + 1;
      final m = _annotation.firstMatch(lines[i]);
      if (m == null) continue;
      final kind = m.namedGroup('kind')!;
      final body = m.namedGroup('body')!.trim();
      if (m.namedGroup('code')!.trim().isNotEmpty) {
        throw FixtureFormatException(
          path,
          lineNo,
          '`// $kind:` must be on its own line',
        );
      }
      final tokens = body
          .split(_whitespace)
          .where((t) => t.isNotEmpty)
          .toList();
      if (tokens.isEmpty) {
        throw FixtureFormatException(
          path,
          lineNo,
          'empty `// $kind:` annotation',
        );
      }

      if (kind == 'run') {
        for (final t in tokens) {
          final kv = _keyValue.firstMatch(t);
          if (kv == null) {
            throw FixtureFormatException(
              path,
              lineNo,
              'expected key=value in `// run:`, got `$t`',
            );
          }
          runSettings[kv.group(1)!] = kv.group(2)!;
        }
        continue;
      }

      if (tokens.length == 1 && tokens.first == 'partial') {
        expectPartial = true;
        continue;
      }

      // Scope expectations target the first non-annotation line below.
      var target = i + 1;
      while (isAnnotation(target)) {
        target++;
      }
      target += 1; // to 1-based

      if (tokens.length == 1 && tokens.first == 'none') {
        noneLines.add(target);
        continue;
      }

      final byMetric = expectations.putIfAbsent(target, () => {});
      String? lastMetric;
      num? lastValue;
      num? lastRolled;
      void flush() {
        if (lastMetric == null) return;
        if (byMetric.containsKey(lastMetric)) {
          throw FixtureFormatException(
            path,
            lineNo,
            'duplicate expectation for `$lastMetric` targeting line $target',
          );
        }
        byMetric[lastMetric!] = Expectation(
          metric: lastMetric!,
          value: lastValue!,
          rolled: lastRolled,
          annotationLine: lineNo,
        );
        lastMetric = null;
        lastRolled = null;
      }

      for (final t in tokens) {
        final kv = _keyValue.firstMatch(t);
        if (kv == null) {
          throw FixtureFormatException(
            path,
            lineNo,
            'expected metric=value, got `$t`',
          );
        }
        final key = kv.group(1)!;
        final value = num.tryParse(kv.group(2)!);
        if (value == null) {
          throw FixtureFormatException(
            path,
            lineNo,
            'expected a number for `$key`, got `${kv.group(2)}`',
          );
        }
        if (key == 'rolled') {
          if (lastMetric == null || lastRolled != null) {
            throw FixtureFormatException(
              path,
              lineNo,
              '`rolled=` must directly follow a metric=value',
            );
          }
          lastRolled = value;
        } else {
          flush();
          lastMetric = key;
          lastValue = value;
        }
      }
      flush();
    }

    for (final line in noneLines) {
      if (expectations.containsKey(line)) {
        throw FixtureFormatException(
          path,
          line,
          'line $line has both `none` and a scope expectation',
        );
      }
    }

    return Fixture(
      path: path,
      content: content,
      expectations: expectations,
      noneLines: noneLines,
      expectPartial: expectPartial,
      runSettings: runSettings,
    );
  }

  static final _annotation = RegExp(
    r'^(?<code>.*?)//\s*(?<kind>expect|run):(?<body>.*)$',
  );
  static final _whitespace = RegExp(r'\s+');
  static final _keyValue = RegExp(r'^([A-Za-z_][A-Za-z0-9_.\-]*)=(.+)$');
}
