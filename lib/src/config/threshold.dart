/// A metric's warn and fail levels and the verdict they yield. Config data
/// (the two numbers a user writes in `analysis_options.yaml`) with the one
/// rule that turns a value into a verdict, so both config and engine can
/// speak of thresholds without the engine's result model.
library;

enum Verdict { ok, warn, fail }

/// Threshold pair that applies to a result, after overrides.
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
