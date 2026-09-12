import 'package:source_span/source_span.dart' show FileSpan;

import '../config/threshold.dart';
import 'measurement.dart';
import 'scope.dart';

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
