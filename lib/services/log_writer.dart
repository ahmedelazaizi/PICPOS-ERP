export 'log_writer_io.dart'
    if (dart.library.html) 'log_writer_web.dart'
    if (dart.library.js_interop) 'log_writer_web.dart';
