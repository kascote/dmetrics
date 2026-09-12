// expect: coupling=3
import 'dart:async';
import 'dart:io' as io;
import 'a.dart';
import 'b.dart' show B;
import 'b.dart' hide C;
import 'sub/c.dart' deferred as c;
import 'package:meta/meta.dart';
import 'package:collection/collection.dart';

void f() {}
