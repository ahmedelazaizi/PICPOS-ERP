import 'legacy_identifiers.dart';

/// أسماءُ مفاتيح التخزين الآمن الخاصّة بمفتاح قاعدة البيانات (المرحلة ب).
///
/// ⚠️ **لماذا `__` لا `::` كما في المسودّة.** على ويندوز يكتب
/// `flutter_secure_storage` القيمةَ في ملفٍّ اسمُه المفتاحُ نفسُه
/// (`<key>.secure`) — فنقطتان رأسيّتان في الاسم تعنيان *مجرى بيانات بديلًا*
/// (ADS) على NTFS لا ملفًّا عاديًّا. لذا تُنقّى هنا كلُّ الأسماء إلى
/// `[A-Za-z0-9._-]`.
///
/// ملفٌّ بلا اعتماداتٍ (لا `dart:io` ولا drift) كي يستورده
/// `SecureStorageService` دون جرِّ المحرّك.
class DbKeyNames {
  DbKeyNames._();


  /// مفتاحُ الفتحة الاحتياطيّ القديم (`SecurityService`) — مرشّحُ قراءةٍ فقط.
  ///
  /// الاسمُ القديم (من إصدارات سابقة) يُقرأ ويُرحَّل إلى هذا الاسم عبر
  /// `StorageKeyMigration` — انظر [legacyFallbackOld].
  static const String legacyFallback = 'picpos_db_fallback_enc_key';

  /// اسمُ المفتاح الاحتياطيّ في إصداراتٍ سابقة (مصدرُ ترحيلٍ للقراءة فقط).
  static String get legacyFallbackOld =>
      LegacyIdentifiers.dbFallbackStorageKey;

  static String safe(String dbFileName) =>
      dbFileName.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');

  /// المفتاح الأساسيّ.
  static String primary(String dbFileName) => 'db_key_v2__${safe(dbFileName)}';

  /// الفتحة الثانية (ضدّ بتر الكتابة غير الذرّيّة).
  static String shadow(String dbFileName) =>
      'db_key_v2_shadow__${safe(dbFileName)}';

  /// رمزُ الاسترداد بانتظار أن يؤكّد المدير حفظَه.
  static String recoveryPending(String dbFileName) =>
      'db_recovery_pending__${safe(dbFileName)}';

  /// مفتاحٌ تجريبيٌّ لمسبار الكتابة/القراءة قبل الترحيل.
  static String probe(String dbFileName) => 'db_key_probe__${safe(dbFileName)}';

  /// هل هذا المفتاحُ من مفاتيح القاعدة التي يجب ألّا يمحوها أيُّ مسحٍ عامّ؟
  static bool isProtected(String key) =>
      key.startsWith('db_key_') ||
      key.startsWith('db_recovery_') ||
      key == legacyFallback ||
      key == legacyFallbackOld;
}
