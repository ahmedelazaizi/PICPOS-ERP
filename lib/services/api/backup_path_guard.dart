// S-02: تعقيم اسم العميل المستعمل في مسار نسخة `POST /api/backup`.
import 'package:path/path.dart' as p;

/// أقصى طول لاسم العميل داخل اسم الملف.
const int kBackupClientNameMaxLength = 40;

/// يُحوّل [raw] القادم من العميل إلى اسم آمن: `[A-Za-z0-9_-]` فقط (كل ما عداه،
/// ومنه الفواصل والنقطة وأحرف التحكم وUnicode، يُستبدل بـ`_`)، وبحدٍّ أقصى
/// [kBackupClientNameMaxLength]. الفارغ يصير `unknown`.
String sanitizeBackupClientName(String? raw) {
  final cleaned = (raw ?? '')
      .replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_')
      .trim();
  final cut = cleaned.length > kBackupClientNameMaxLength
      ? cleaned.substring(0, kBackupClientNameMaxLength)
      : cleaned;
  return cut.isEmpty ? 'unknown' : cut;
}

/// مسار ملف النسخة داخل [backupDir]، أو `null` إن خرج المسار المُحلَّل عنه.
String? resolveBackupFilePath(
    String backupDir, String? clientName, String timestamp) {
  final name = 'backup_${sanitizeBackupClientName(clientName)}_$timestamp.sqlite';
  final resolved = p.normalize(p.absolute(p.join(backupDir, name)));
  final root = p.normalize(p.absolute(backupDir));
  return p.isWithin(root, resolved) ? resolved : null;
}
