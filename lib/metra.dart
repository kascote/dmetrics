/// Dart-native static code metrics engine (working name: metra).
///
/// Library-first: `analyze(sources, metrics, config)` is a pure API over
/// in-memory sources. See SPEC.md.
library;

export 'src/config/config.dart';
export 'src/engine/analyze.dart';
export 'src/engine/engine.dart';
export 'src/engine/measurement.dart';
export 'src/engine/metric.dart';
export 'src/engine/report.dart';
export 'src/engine/result.dart';
export 'src/engine/scope.dart';
export 'src/engine/source.dart';
export 'src/metrics/cyclomatic/cyclomatic.dart';
