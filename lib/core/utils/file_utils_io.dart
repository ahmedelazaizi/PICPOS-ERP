import 'dart:io';
import 'file_utils.dart';

class FileUtilsIO implements FileUtils {
  @override
  Future<void> saveFile(String path, List<int> bytes) async {
    final file = File(path);
    await file.writeAsBytes(bytes);
  }

  @override
  Future<void> openFolder(String path) async {
    await Process.run('explorer', [path]);
  }
}

void initFileUtils() {
  fileUtils = FileUtilsIO();
}
