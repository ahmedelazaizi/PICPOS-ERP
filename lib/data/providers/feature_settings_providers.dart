// lib/data/providers/feature_settings_providers.dart
//
// راياتُ فيتشرَي 2026-09-12 وإعداداتُهما — **مصدرٌ واحدٌ يقرأ منه الجميع**.
//
// ⚠️ **ولماذا لا تبقى مزوّداتٍ خاصّةً في ملفّ الحوار.** كانت
// `_tableBillEnabledProvider` و`_publicBaseUrlProvider` خاصّتَين في
// `table_bill_qr_dialog.dart`. فلمّا صار للإعداد سطحان (‏حوارُ الطباعة
// وقسمُ الإعدادات) كان كلُّ سطحٍ سيحمل مزوّدَه: يكتب أحدُهما ويُبطل مزوّدَه،
// فيبقى الآخرُ على قيمةٍ قديمةٍ حتى يُعاد تركيبُه. ومستخدمٌ يُشعِل الرايةَ
// في الإعدادات ثمّ يفتح الحوارَ فيراها مطفأةً — يظنُّ الحفظَ لم يقع.
//
// وهذه عينُ المصيدة المسجَّلة في هذا المستودع: «الكتابةُ عبر مستودعٍ
// والقراءةُ من آخرَ تُنتج إعداداً لا يتفاعل».
//
// ⚠️ **ومفاتيحُ الإعداد لا تُكتَب نصّاً في طبقة العرض.** مفتاحٌ نصِّيٌّ في
// موضعٍ وثابتٌ في آخرَ يُنتج رايتَين متوازيتَين: الواجهةُ تكتب في واحدةٍ
// والخادمُ يقرأ الأخرى، والميزةُ تبدو معطوبةً بلا سببٍ ظاهر.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/api/table_bill_token.dart';
import 'providers.dart';

/// رمزُ دولةِ واتساب الافتراضيّ.
///
/// ⚠️ **ولا قيمةَ افتراضيّةً في الشيفرة.** المنتجُ يُشحَن في أكثرَ من سوق،
/// وافتراضُ دولةٍ بعينها يُشوِّه أرقامَ السوق الآخر كلَّها بصمت. والفارغُ
/// يعني «غيرُ مضبوط» فلا يُبنى رابطٌ أصلاً — لا رابطٌ ناقص.
const String kWhatsAppCountryCodeKey = 'whatsapp_default_country_code';

/// رمزُ الدولة المضبوط — فارغٌ يعني «غيرُ مضبوط».
final whatsAppCountryCodeProvider = FutureProvider<String>((ref) async {
  final db = ref.watch(databaseProvider);
  return (await db.getSettingValue(kWhatsAppCountryCodeKey))?.trim() ?? '';
});

/// هل رمزُ حساب الطاولة مُشغَّل؟ مطفأٌ ما لم يُكتَب `'true'` بالحرف.
final tableBillQrEnabledProvider = FutureProvider<bool>((ref) async {
  final db = ref.watch(databaseProvider);
  return (await db.getSettingValue(kTableBillQrEnabledKey)) == 'true';
});

/// هل يُسمَح للضيف بطلب أصناف من هاتفه؟
///
/// ⚠️ **رايةٌ ثانيةٌ مستقلّةٌ عن العرض** عن قصد: أن يرى الضيفُ حسابَه شيء،
/// وأن يكتب في طلبٍ مفتوحٍ شيءٌ آخر. ومن أراد الأولى وحدَها لا يُفتَح له
/// البابُ الثاني ضمناً.
final tableBillGuestOrderEnabledProvider = FutureProvider<bool>((ref) async {
  final db = ref.watch(databaseProvider);
  return (await db.getSettingValue(kTableBillGuestOrderEnabledKey)) == 'true';
});

/// أصلُ العنوان العامّ للخادم — `null` إن لم يُنشَر أو كان غيرَ صالح.
final tableBillPublicBaseUrlProvider = FutureProvider<String?>((ref) async {
  final db = ref.watch(databaseProvider);
  return normalizeTableBillBaseUrl(
    await db.getSettingValue(kTableBillPublicBaseUrlKey),
  );
});

/// يكتب رايةً أو قيمةً ويُبطل مزوّدَها — **المعبرُ الوحيد للكتابة**.
///
/// ⚠️ **والإبطالُ جزءٌ من الكتابة لا خطوةٌ بعدها.** كتابةٌ بلا إبطالٍ تترك
/// كلَّ سطحٍ على قيمته القديمة، والميزةُ تبدو كأنّها لم تُحفَظ.
/// ⚠️ ويُبطَل المزوّدُ **بالاسم لا بجدولٍ مشترك**: الأربعةُ أنواعٌ مختلفة
/// (`bool` · `String` · `String?`) ولا سلفَ مشتركاً يجمعها في هذا الإصدار،
/// فجدولُ `key ← provider` لا يُترجَم. ومفتاحٌ بلا فرعٍ يرمي بدل أن يُهمَل
/// صامتاً — فإضافةُ رايةٍ بلا إبطالٍ تسقط في أوّل تشغيل.
Future<void> writeFeatureSetting(
  WidgetRef ref,
  String key,
  String value,
) async {
  await ref.read(databaseProvider).setSetting(key, value);
  switch (key) {
    case kTableBillQrEnabledKey:
      ref.invalidate(tableBillQrEnabledProvider);
    case kTableBillGuestOrderEnabledKey:
      ref.invalidate(tableBillGuestOrderEnabledProvider);
    case kTableBillPublicBaseUrlKey:
      ref.invalidate(tableBillPublicBaseUrlProvider);
    case kWhatsAppCountryCodeKey:
      ref.invalidate(whatsAppCountryCodeProvider);
    default:
      throw ArgumentError('لا مزوّدَ للمفتاح: $key');
  }
}
