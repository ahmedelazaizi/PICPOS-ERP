import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:intl/intl.dart';

class LogWriter {
  Future<void> writeLog(
    String? path,
    String message,
    Object? error,
    StackTrace? stackTrace,
  ) async {
    if (path == null) return;
    try {
      final file = File(path);
      final buffer = StringBuffer(message);
      if (error != null) buffer.writeln('\n  Error: $error');
      if (stackTrace != null) buffer.writeln('\n  Stack: $stackTrace');
      buffer.writeln();
      await file.writeAsString(buffer.toString(), mode: FileMode.append);
    } catch (_) {}
  }

  Future<String?> getLogPath() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final date = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final logDir = Directory('${dir.path}/logs');
      if (!await logDir.exists()) {
        await logDir.create(recursive: true);
      }
      return '${dir.path}/logs/monexia_$date.log';
    } catch (_) {
      return null;
    }
  }
}
