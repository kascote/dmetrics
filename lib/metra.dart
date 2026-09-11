/// Dart-native static code metrics engine (working name: metra).
///
/// Library-first: `analyze(sources, metrics, config)` is a pure API over
/// in-memory sources; `analyzePaths(targets, …)` composes it with the I/O
/// layer. See SPEC.md.
library;

export 'src/config/config.dart';
export 'src/config/loader.dart';
export 'src/engine/analyze.dart';
export 'src/engine/engine.dart';
export 'src/engine/measurement.dart';
export 'src/engine/metric.dart';
export 'src/engine/report.dart';
export 'src/engine/result.dart';
export 'src/engine/scope.dart';
export 'src/engine/source.dart';
export 'src/engine/suppress.dart';
export 'src/io/analyze_paths.dart';
export 'src/io/discovery.dart';
export 'src/metrics/cyclomatic/cyclomatic.dart';
export 'src/report/ansi.dart';
export 'src/report/console_reporter.dart';
export 'src/report/json_reporter.dart';
export 'src/report/run_result.dart';
export 'src/version.dart';
