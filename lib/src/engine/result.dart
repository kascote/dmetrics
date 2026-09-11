import 'package:source_span/source_span.dart' show FileSpan;

import 'measurement.dart';
import 'scope.dart';

enum Verdict { ok, warn, fail }

/// Threshold pair that applied to a result, after overrides.
class Threshold {
  final num warn;
  final num fail;

  const Threshold({required this.warn, required this.fail});

  /// Config value for "no thresholds": overrides a metric's built-in
  /// default. Never reaches a result; the pipeline maps it to null.
  static const none = Threshold(warn: double.infinity, fail: double.infinity);

  Verdict evaluate(num value) {
    if (value >= fail) return Verdict.fail;
    if (value >= warn) return Verdict.warn;
    return Verdict.ok;
  }

  @override
  bool operator ==(Object other) =>
      other is Threshold && other.warn == warn && other.fail == fail;

  @override
  int get hashCode => Object.hash(warn, fail);

  @override
  String toString() => 'Threshold(warn: $warn, fail: $fail)';
}

enum SuppressionKind { ignore, ignoreForFile }

class Suppression {
  final SuppressionKind kind;
  final FileSpan span;

  const Suppression({required this.kind, required this.span});
}

/// What the engine emits after aggregation, suppression and thresholds.
class MetricResult {
  /// As measured, always preserved.
  final Measurement measurement;

  /// The value verdicts apply to (after roll-up).
  final num value;

  /// Direct child results folded into [value]; empty unless rolled up.
  final List<ScopeId> includes;

  /// The threshold that applied, or null when none is configured.
  final Threshold? threshold;

  final Verdict verdict;

  /// Non-null when an ignore applies; verdict is then forced to [Verdict.ok].
  final Suppression? suppressed;

  const MetricResult({
    required this.measurement,
    required this.value,
    required this.includes,
    required this.threshold,
    required this.verdict,
    required this.suppressed,
  });

  num get measured => measurement.value;

  @override
  String toString() =>
      'MetricResult(${measurement.metricId}: measured=$measured value=$value '
      'includes=${includes.length} verdict=$verdict)';
}
