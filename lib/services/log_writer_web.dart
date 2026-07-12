class LogWriter {
  Future<void> writeLog(
    String? path,
    String message,
    Object? error,
    StackTrace? stackTrace,
  ) async {
    // No-op on web
  }

  Future<String?> getLogPath() async {
    return null; // No file logging on web
  }
}
