abstract class FileUtils {
  Future<void> saveFile(String name, List<int> bytes);
  Future<void> openFolder(String path);
}

// Global instance
late final FileUtils fileUtils;
