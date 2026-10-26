import 'dart:io';
import '../core/config/data_dir.dart';
import 'package:intl/intl.dart';

import '../core/config/brand.dart';

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
      final dir = await DataDir.documents();
      final date = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final logDir = Directory('${dir.path}/logs');
      if (!await logDir.exists()) {
        await logDir.create(recursive: true);
      }
      // كان `monexia_$date.log` — اسم علامة تالتة بيتكتب على قرص العميل.
      // الملفات دي بيشوفها العميل، فالاسم جزء من الهوية. قيمة UralCash
      // متروكة بالحرف عشان ملفات السجل القديمة تفضل بنفس النمط.
      const prefix = Brand.isPicPos ? Brand.dbPrefix : 'monexia';
      return '${dir.path}/logs/${prefix}_$date.log';
    } catch (_) {
      return null;
    }
  }
}
