export 'file_utils.dart';
export 'file_utils_io.dart'
    if (dart.library.html) 'file_utils_web.dart'
    if (dart.library.js_interop) 'file_utils_web.dart';
