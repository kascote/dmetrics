import '../config/config.dart';
import 'metric.dart';
import 'report.dart';
import 'source.dart';

/// The engine entry point shape: pure, in-memory sources in, report out.
///
/// The real implementation arrives with the engine skeleton (M1). The test
/// harness is written against this signature so that it can run unchanged
/// against a stub today and the engine tomorrow.
typedef Analyze = Report Function(
  List<SourceFile> sources,
  List<Metric> metrics,
  AnalysisConfig config,
);
