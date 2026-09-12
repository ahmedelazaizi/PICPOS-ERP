// حارسُ العقد: كلُّ رايةِ ميزةٍ لها **كاتبٌ في الواجهة** — وإلّا فالميزةُ
// مطفأةٌ إلى الأبد.
//
// ═══ فئةُ العطب — وهي مقيسةٌ لا مفترضة ═══
//
// `table_bill_guest_order_enabled` شُحنت في 3.1.4.253 و‎254 ولها:
//   • قارئٌ في `api_handler.dart` يحرس مسارَي كتابةِ الضيف،
//   • وطابورٌ في الذاكرة، ومحرّكُ اعتمادٍ، وبانرٌ للنادل، ونقطتا API،
//   • وثلاثةَ عشرَ اختبارَ تكاملٍ **تكتب الرايةَ بنفسها** فتمرّ خضراء،
//   • و**صفرَ كُتّابٍ في `lib/` كلِّها**.
//
// فالنصفُ الذي طلبه المالكُ صراحةً («أبدأ فيه الآن») مبنيٌّ ومشحونٌ
// و**لا سبيلَ لتشغيله** من داخل البرنامج. ولا اختبارٌ لاحظ ذلك: اختباراتُ
// التكامل تزرع الرايةَ في قاعدتها، فالمسارُ الذي تقيسه لا يمرّ بأيّ واجهة.
//
// ⚠️ **ولماذا لا يُعمَّم الحارسُ على كلّ مفتاح**: مفاتيحُ الخادم (‏أسرارُ
// الفاتورة الإلكترونيّة مثلاً) تُكتَب بقرارِ مالكٍ من خارج الواجهة، فحارسٌ
// شاملٌ يُبلِّغ عنها خطأً. فالقائمةُ صريحةٌ ويُضاف إليها كلُّ مفتاحٍ
// **يُفترَض أن يضبطه المستخدم**.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// اسمُ الثابت ← وصفُه للرسالة.
const _userFacingKeys = <String, String>{
  'kTableBillQrEnabledKey': 'تشغيل رمز حساب الطاولة',
  'kTableBillGuestOrderEnabledKey': 'السماح للضيف بطلب أصناف',
  'kTableBillPublicBaseUrlKey': 'نشرُ الخادم على دومين عامّ',
  'kWhatsAppCountryCodeKey': 'رمزُ دولة واتساب',
};

/// نصُّ ملفّات العرض كلِّها، بلا أسطر التعليق.
///
/// ⚠️ والتعليقاتُ تُجرَّد لأنّ شرحَ الراية يكتب اسمَها حرفياً — فحارسٌ يقرأ
/// التعليقَ يرى «كاتباً» حيث لا كاتب، وهو أسوأُ من لا حارس.
String _presentationCode() {
  final buf = StringBuffer();
  for (final f in Directory('lib/presentation').listSync(recursive: true)) {
    if (f is! File || !f.path.endsWith('.dart')) continue;
    for (final line in f.readAsStringSync().split('\n')) {
      if (line.trimLeft().startsWith('//')) continue;
      buf
        ..write(line)
        ..write('\n');
    }
  }
  return buf.toString();
}

void main() {
  late String ui;

  /// نفسُ النصّ بلا أيّ مسافة — فالمطابقةُ لا تتعلّق بلفّ الأسطر.
  ///
  /// ⚠️ وهذا ليس تسهيلاً: نداءٌ واحدٌ مكتوبٌ على سطرَين وآخرُ على خمسة،
  /// وأوّلُ صياغةٍ للحارس طابقت النصَّ حرفاً بحرفٍ فأبلغت عن أربع «فجوات»
  /// بعد أن صارت الكتابةُ كلُّها عبر معبرٍ واحد — أي أبلغت عن الإصلاح.
  late String flat;

  setUpAll(() {
    ui = _presentationCode();
    flat = ui.replaceAll(RegExp(r'\s+'), '');
  });

  test('مرساةُ القراءة — شجرةُ العرض قُرئت غيرَ فارغة', () {
    expect(ui.length, greaterThan(100000),
        reason: 'قُرئ نصٌّ ضئيل — الفحوصُ تحته تقرأ لا شيء');
    expect(ui.contains('setSetting('), isTrue,
        reason: 'لا كتابةَ إعدادٍ واحدةٍ في العرض كلِّه — النمطُ تبدّل');
  });

  for (final entry in _userFacingKeys.entries) {
    test('ويُكتَب «${entry.value}» من الواجهة', () {
      // الكتابةُ عبر المعبر الواحد، أو مباشرةً — المهمُّ **أن تقع**.
      final written = flat.contains('writeFeatureSetting(ref,${entry.key},') ||
          flat.contains('setSetting(${entry.key},');
      expect(written, isTrue,
          reason: 'الرايةُ «${entry.key}» تُقرأ ولا تُكتَب — '
              'فـ«${entry.value}» مطفأٌ إلى الأبد ولا سبيلَ لتشغيله');
    });
  }

  test('والكتابةُ كلُّها عبر المعبر الواحد — فالإبطالُ لا يُنسى', () {
    // ⚠️ كتابةٌ مباشرةٌ بـ`setSetting` تحفظ القيمةَ ولا تُبطل مزوّدَها،
    // فيبقى كلُّ سطحٍ على قيمته القديمة ويظنُّ المستخدمُ أنّ الحفظَ لم يقع.
    for (final key in _userFacingKeys.keys) {
      expect(flat.contains('setSetting($key,'), isFalse,
          reason: 'كتابةٌ مباشرةٌ تتخطّى `writeFeatureSetting`: $key');
    }
  });

  test('والمفاتيحُ تُقرأ من ثوابتها لا مكتوبةً نصّاً', () {
    // مفتاحٌ مكتوبٌ نصّاً في موضعٍ وثابتاً في آخرَ ينتج راياتٍ متوازيةً
    // لا تتفق: الواجهةُ تكتب في واحدةٍ والخادمُ يقرأ الأخرى.
    for (final raw in const [
      "'table_bill_qr_enabled'",
      "'table_bill_guest_order_enabled'",
      "'table_bill_public_base_url'",
      "'whatsapp_default_country_code'",
    ]) {
      expect(ui.contains(raw), isFalse,
          reason: 'مفتاحٌ مكتوبٌ نصّاً في العرض: $raw');
    }
  });
}
