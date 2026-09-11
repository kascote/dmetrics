import '../config/config.dart';
import 'metric.dart';
import 'report.dart';
import 'source.dart';

/// The engine entry point shape: pure, in-memory sources in, report out.
/// The test harness is written against this signature.
typedef Analyze = Report Function(
  List<SourceFile> sources,
  List<Metric> metrics,
  AnalysisConfig config,
);
