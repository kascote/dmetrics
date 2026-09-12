// expect: coupling=1
import 'io_stub.dart'
    if (dart.library.io) 'io_impl.dart'
    if (dart.library.js_interop) 'web_impl.dart';
