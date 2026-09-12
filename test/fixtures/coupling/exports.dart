// expect: coupling=2
export 'a.dart';
export 'b.dart' show B;
import 'b.dart';
import 'c.dart';
export 'c.dart';
export 'dart:async';
export 'package:meta/meta.dart';
