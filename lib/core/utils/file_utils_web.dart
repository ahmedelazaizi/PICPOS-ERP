import 'package:flutter/foundation.dart';
import 'file_utils.dart';

class FileUtilsWeb implements FileUtils {
  @override
  Future<void> saveFile(String name, List<int> bytes) async {
    // On web, we could triggers a download, but for now we stub it or use a web-specific library
    // For trial purposes, we'll log it.
    debugPrint('Web: File save requested for $name');
  }

  @override
  Future<void> openFolder(String path) async {
    debugPrint('Web: Open folder requested for $path');
  }
}

void initFileUtils() {
  fileUtils = FileUtilsWeb();
}
