part of 'pos_settings_widget.dart';

// ═══════════════════════════════════════════════════════════════════════════
// نسبةُ الضريبة الافتراضية — الرفضُ عند المصدر
// ═══════════════════════════════════════════════════════════════════════════
//
// `pos_default_tax_rate` هو منبعُ اللقطة التي تُثبَّت على كلِّ طلبِ طاولة.
// وv156 جعل «مفعَّلةٌ بصفر» مستحيلةَ التمثيل، وv157 شدَّ الحدَّ إلى ١٪ — لكنّ
// الرفضَ عند فتح الطاولة رسالةٌ تحيل المستخدمَ إلى هنا. فالرفضُ **هنا** أوضح.

/// يتحقّق من نسبةِ الضريبة كما يكتبها المستخدمُ — **مئويّةً** (16 لا 0.16).
///
/// يُعيد رسالةَ الرفض أو `null` إن قُبلت، على عقد `FormFieldValidator<String>`.
///
/// والفارغُ وغيرُ الرقمِ مرفوضان لا مُبتلَعان: `onChanged` تتجاهل ما لا
/// يُحلَّل، فتبقى الحالةُ على قيمتها القديمة والحقلُ يعرض شيئاً آخر — والرفضُ
/// يُظهر ذلك الافتراقَ بدل أن يُخفيه.
@visibleForTesting
String? validateDefaultTaxRatePercent(String? raw) {
  final text = raw?.trim() ?? '';
  if (text.isEmpty) return tr('أدخل نسبةَ الضريبة');

  final percent = double.tryParse(text);
  if (percent == null) return tr('أدخل رقماً');

  if (!TaxRateBounds.isValidPercent(percent)) {
    return tr('النسبةُ إمّا صفرٌ (بلا ضريبة) أو ١٪ فأكثر — ولا تتجاوز ١٠٠٪');
  }
  return null;
}

/// هل تُمنَع «حفظُ الإعدادات» بسبب نسبةِ الضريبة؟
///
/// **مقيَّدٌ بـ[touched] عن قصد.** الحقلُ لا يُخفى عند نقص الصلاحية —
/// `PermissionGuard` يقفله والقيمةُ تُحمَّل وتُرحَّل مع الحفظ. فمنعٌ مطلقٌ
/// يعني أن مستخدماً لا يملك `settings_tax`، وقيمةً قديمةً مخالفةً ورثها،
/// **يعجز عن حفظ كلِّ إعدادٍ آخر** بسبب حقلٍ لا يُسمح له بلمسه.
///
/// فيُرفَض ما يكتبه المستخدمُ الآن لا ما ورثه — والموروثُ يحرسه البابان
/// الآخران على مسار المال: `setOrderTax` وقيدُ الجدول.
///
/// و[rate] **كسريّةٌ** لا مئويّة: إرجاعُها بالضرب في مئة ينزلق في ٨ من كلِّ
/// ١٠٠ نسبةٍ صحيحة — اقرأ [TaxRateBounds.isValidRate].
@visibleForTesting
bool blocksSaveForTaxRate({required bool touched, required double rate}) =>
    touched && !TaxRateBounds.isValidRate(rate);

/// حقلُ النسبة داخل `Form` خاصٍّ به.
///
/// **الـ`Form` شرطٌ لا زينة:** `validator:` وحدَه لا يعمل — لا أحدَ يستدعي
/// `validate()`. وهو حول هذا الحقل وحدَه كي لا يُقحَم بقيّةُ الشاشة في دورة
/// تحقّقٍ لا تخصّها.
///
/// [initialRate] و[onRateChanged] **كسريّتان**، والمعروضُ والمكتوبُ مئويّ.
@visibleForTesting
Widget buildDefaultTaxRateFormField({
  required GlobalKey<FormState> formKey,
  required double initialRate,
  required ValueChanged<double> onRateChanged,
}) {
  return Form(
    key: formKey,
    child: TextFormField(
      initialValue: (initialRate * 100).toStringAsFixed(0),
      decoration: const InputDecoration(suffixText: '%', isDense: true),
      keyboardType: TextInputType.number,
      textAlign: TextAlign.center,
      autovalidateMode: AutovalidateMode.onUserInteraction,
      validator: validateDefaultTaxRatePercent,
      onChanged: (v) {
        final val = double.tryParse(v);
        if (val != null) {
          onRateChanged(val / 100);
        }
      },
    ),
  );
}
