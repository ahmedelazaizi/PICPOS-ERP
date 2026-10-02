// يقرأ الاسمَ الإنجليزيَّ والسجلَّ التجاريَّ من إعدادات الشركة لمسارات الطباعة
// التي تملك `AppDatabase` ولا تملك هذين الحقلَين. القواعدُ في
// `domain/printing/company_identity.dart`.
import '../../data/database/database.dart';
import '../../domain/printing/company_identity.dart';

typedef CompanyIdentityValues = ({String? nameEn, String? crNumber});

/// `null`/فارغٌ ⇒ `null`، فلا يُطبع شيء. ولا يرمي: هويّةٌ ناقصةٌ لا تُسقط
/// طباعةَ فاتورة.
Future<CompanyIdentityValues> loadCompanyIdentity(AppDatabase? db) async {
  if (db == null) return (nameEn: null, crNumber: null);
  try {
    String? read(String? v) {
      final t = v?.trim();
      return (t == null || t.isEmpty) ? null : t;
    }

    return (
      nameEn: read(await db.getSettingValue(kCompanyNameEnSetting)),
      crNumber: read(await db.getSettingValue(kCompanyCrNumberSetting)),
    );
  } catch (_) {
    return (nameEn: null, crNumber: null);
  }
}
