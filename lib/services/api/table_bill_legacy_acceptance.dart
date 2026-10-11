import '../../core/logging/diagnostic_logger.dart';
import '../../data/database/database.dart';
import 'table_bill_token.dart';

/// علمُ `settings` الذي يتحكّم بقبول رموز الطاولات المطبوعة بالمفتاح المشتقّ
/// القديم (قرار المالك ق-3 الخيار أ). **الافتراضُ مقبولٌ** (غيابُ القيمة = true)
/// كي لا يتعطّل QR مطبوعٌ عند الترحيل؛ وبعد إعادة الطباعة يُطفئه المشغّل.
const String kTableBillLegacyAcceptedKey = 'table_bill_legacy_accepted';

/// يطبّق/يُطفئ قبول المشتقّ القديم **للتحقّق فقط** في [TableBillToken.verifyTable].
class TableBillLegacyAcceptance {
  TableBillLegacyAcceptance._();

  /// هل القبولُ مفعّلٌ؟ (غياب القيمة ⇒ مفعّل.)
  static Future<bool> isEnabled(AppDatabase db) async =>
      (await db.getSettingValue(kTableBillLegacyAcceptedKey)) != 'false';

  /// عند إقلاع الخادم: يفعّل المفتاحَ القديم للتحقّق إن كان العلمُ مفعّلاً
  /// و[legacySeed] متاحاً، وإلا يعطّله.
  static Future<void> apply(AppDatabase db, String? legacySeed) async {
    final enabled = await isEnabled(db);
    TableBillToken.setLegacyVerifyKeyFromSeed(enabled ? legacySeed : null);
  }

  /// **طريقةُ الإطفاء**: «أعدتُ طباعة رموز الطاولات». تكتب العلمَ `false`
  /// وتُسقط المفتاحَ القديمَ من الذاكرة فوراً (فيُرفض كلُّ QR قديم).
  static Future<void> disable(AppDatabase db) async {
    await db.setSetting(kTableBillLegacyAcceptedKey, 'false');
    TableBillToken.setLegacyVerifyKeyFromSeed(null);
    await DiagnosticLogger.log(
        'SEC', 'أُطفئ قبول رموز الطاولات القديمة ($kTableBillLegacyAcceptedKey=false)');
  }
}
