import 'dart:io';

import 'db_key_types.dart';
import 'db_keyinfo_file.dart';
import 'sqlcipher_engine.dart';

class PortableExportException implements Exception {
  const PortableExportException(this.message);
  final String message;
  @override
  String toString() => 'PortableExportException: $message';
}

/// تصديرٌ محمولٌ بكلمة مرور (E-01 §5.2-ب) — دالةٌ فقط، بلا واجهة.
///
/// الملفُّ الناتجُ مشفَّرٌ بعبارة مرورٍ (PBKDF2 داخل SQLCipher) فيُفتح على أيّ
/// جهازٍ/حسابٍ بالكلمة وحدَها، ويُنسخ معه `user_version`.
class PortableExport {
  PortableExport(this.engine);

  final SqlCipherEngine engine;

  /// الحدُّ الأدنى لطول الكلمة (الملف قد يُسرق مع USB).
  static const int minPasswordLength = 12;

  /// يصدّر [src] (المفتوح بـ[srcKey]) إلى [out] بـ[password]، ثم يتحقّق من
  /// أنّ الكلمةَ تفتحه وأنّ المحتوى يطابق الأصل. عند الفشل يُحذف [out].
  Future<void> export({
    required File src,
    required DbKey srcKey,
    required File out,
    required String password,
    DateTime? now,
  }) async {
    if (password.length < minPasswordLength) {
      throw const PortableExportException(
          'كلمة المرور أقصر من الحدّ الأدنى (12 حرفًا)');
    }
    if (p(out) == p(src)) {
      throw const PortableExportException('الوجهة هي نفس ملف القاعدة');
    }
    final key = DbKey(DbKeyKind.passphrase, password);
    try {
      await engine.exportTo(src, srcKey, out, key);
      if (!await engine.canOpen(out, key)) {
        throw const PortableExportException('الملف المصدَّر لا يُفتح بالكلمة');
      }
      final a = await engine.inspect(src, srcKey);
      final b = await engine.inspect(out, key);
      if (!b.quickCheckOk || !a.matches(b)) {
        throw const PortableExportException('اختلف محتوى التصدير عن الأصل');
      }
      await KeyInfoFile.write(
        out,
        KeyInfo(
          kind: DbKeyKind.passphrase,
          createdAt: (now ?? DateTime.now()).toIso8601String(),
          // بلا بصمة: لا تكشف شيئًا عن كلمة المرور.
        ),
      );
    } catch (_) {
      if (await out.exists()) await out.delete();
      rethrow;
    }
  }

  static String p(File f) => f.absolute.path.toLowerCase();
}
