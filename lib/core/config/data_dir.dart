// المكان الوحيد الذي يقرّر أين يحفظ التطبيق بياناته الدائمة.
//
// المتغير `PICPOS_DATA_DIR` (مسار مطلق): لو موجود، **كل** المواضع الدائمة
// (قاعدة البيانات، keyinfo، السجلات، النسخ الاحتياطية، SharedPreferences،
// التخزين الآمن/الشهادات) تُحوَّل إلى هذا المجلد. غير موجود = السلوك الحالي
// بالضبط (مجلد «المستندات» و`%APPDATA%`). مخصَّص لمعمل الاختبار (D:\qa\...)
// كي لا يلمس أي تشغيل تجريبي بيانات المالك الحقيقية.
//
// ممنوع استدعاء getApplicationDocumentsDirectory/getApplicationSupportDirectory
// خارج هذا الملف (يحرسه test/static/data_dir_guard_test.dart).
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart' as pp;

class DataDir {
  DataDir._();

  /// اسم متغير البيئة.
  static const String envName = 'PICPOS_DATA_DIR';

  /// للاختبارات فقط: بيئة بديلة بدل `Platform.environment`.
  static Map<String, String>? debugEnvironment;

  /// المسار المُعيَّن أو null. مسار غير مطلق = خطأ صريح (لا رجوع صامت
  /// إلى بيانات حقيقية).
  static String? get overridePath {
    final raw = (debugEnvironment ?? Platform.environment)[envName]?.trim();
    if (raw == null || raw.isEmpty) return null;
    if (!p.isAbsolute(raw)) {
      throw StateError('$envName must be an absolute path, got "$raw"');
    }
    return p.normalize(raw);
  }

  static bool get isOverridden => overridePath != null;

  static Directory _ensure(String path) {
    final d = Directory(path);
    if (!d.existsSync()) d.createSync(recursive: true);
    return d;
  }

  /// بديل `getApplicationDocumentsDirectory()`: قاعدة البيانات، keyinfo،
  /// السجلات، النسخ الاحتياطية، التصدير.
  static Future<Directory> documents() async {
    final o = overridePath;
    if (o != null) return _ensure(o);
    return pp.getApplicationDocumentsDirectory();
  }

  /// بديل `getApplicationSupportDirectory()`.
  static Future<Directory> support() async {
    final o = overridePath;
    if (o != null) return _ensure(p.join(o, 'support'));
    return pp.getApplicationSupportDirectory();
  }

  /// بديل `%APPDATA%` (نسخ العملاء الاحتياطية في api_data_system).
  static String roamingAppData() {
    final o = overridePath;
    if (o != null) return _ensure(p.join(o, 'appdata')).path;
    return Platform.environment['APPDATA'] ?? '.';
  }

  /// ملف SharedPreferences البديل (فقط مع التحويل).
  static String? get prefsFilePath {
    final o = overridePath;
    return o == null ? null : p.join(o, 'support', 'shared_preferences.json');
  }

  /// ملف التخزين الآمن البديل (فقط مع التحويل؛ نص عادي = معمل فقط).
  static String? get secureFilePath {
    final o = overridePath;
    return o == null ? null : p.join(o, 'support', 'secure_storage.json');
  }

  /// كل المواضع المحسومة (للاختبار والتوثيق).
  static Future<Map<String, String?>> resolvedLocations() async => {
        'documents': (await documents()).path,
        'support': (await support()).path,
        'roamingAppData': roamingAppData(),
        'prefsFile': prefsFilePath,
        'secureFile': secureFilePath,
      };
}
