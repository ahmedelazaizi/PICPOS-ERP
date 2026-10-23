// حارسُ العقد: إرسالُ مستندات العميل على واتساب — ثلاثةُ أشياء تسقط صامتةً.
//
// ═══ فئاتُ العطب ═══
//
// **١ — رقمٌ يُمرَّر خاماً.** `wa.me` يقبل أرقاماً دوليّةً بلا رموز. ورقمٌ
// كما كتبه صاحبُه (`010 1234 5678`، `+20…`، `٠١٠…`) يُنتج رابطاً تفتحه
// واتساب بـ«الرقمُ غيرُ صالح» — فيظنّ الموظّفُ أنّ العميلَ ليس على واتساب.
// والإخفاقُ **من جهتنا** ولا أثرَ له في أيّ سجلّ.
//
// **٢ — نصٌّ بلا ترميز.** `#` تقطعه عند المرساة و`&` تُقرأ فاصلَ معاملات.
// وكلاهما في نصوصنا: «فاتورة #1024» و«خصم 10% & شكراً». فيصل الزبونَ
// مبتوراً بلا أن يعلم أحد.
//
// **٣ — رمزُ دولةٍ مكتوبٌ في الشيفرة.** المنتجُ يُشحَن في أكثرَ من سوق،
// وافتراضُ دولةٍ بعينها يُشوِّه أرقامَ السوق الآخر كلَّها.
//
// ⚠️ ولا اختبارَ ودجت يمسك الثلاثةَ: كلٌّ منها يُنتج **رابطاً صالحَ الشكل**
// يفتح صفحةً لا نتحكّم فيها. فالمقياسُ بنيويّ.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/core/permissions/permission_codes.dart';
import 'package:picpos_erp/domain/models/whatsapp_message.dart';

const _dialogPath =
    'lib/presentation/shared_widgets/whatsapp_send_dialog.dart';
const _modelPath = 'lib/domain/models/whatsapp_message.dart';

/// ملفّاتُ `lib` التي **تُركِّب** رقماً في رابط واتساب.
///
/// ⚠️ **والمقياسُ الاستيفاءُ لا ذكرُ النطاق.** أوّلُ صياغةٍ بحثت عن `wa.me`
/// فأبلغت عن ستّةِ ملفّاتٍ خمسةٌ منها **سليمة**: `brand.dart` يحمل رقمَ دعمٍ
/// **ثابتاً** للمورِّد (لا رقمَ عميل)، وثلاثةٌ تذكر النطاقَ في تعليقٍ يشرح
/// القاعدة، وشاشةُ الدخول تفتح رابطَ المورِّد. فالمخالفةُ هي `wa.me/$…` —
/// رقمٌ يُستوفى في زمن التشغيل.
List<File> _urlBuilders() => Directory('lib')
    .listSync(recursive: true)
    .whereType<File>()
    .where((f) => f.path.endsWith('.dart'))
    .where((f) => f.readAsStringSync().contains(r'wa.me/$'))
    .toList();

void main() {
  test('مرساةُ القراءة — المسارُ موجودٌ وحوارُ الإرسال موصول', () {
    expect(File(_dialogPath).existsSync(), isTrue, reason: _dialogPath);
    expect(File(_modelPath).existsSync(), isTrue, reason: _modelPath);
  });

  test('ولا يُبنى رابطُ واتساب إلّا في النموذج الخالص', () {
    // ⚠️ بانٍ ثانٍ في طبقة العرض يتجاوز التسويةَ والترميزَ معاً — وهو
    // الطريقُ الأقصرُ لمن يريد «إرسالاً سريعاً» من شاشةٍ جديدة.
    final builders = _urlBuilders()
        .map((f) => f.path.replaceAll(r'\', '/'))
        .where((p) => p != _modelPath)
        .toList();
    expect(builders, isEmpty,
        reason: 'رابطٌ يُبنى خارجَ `buildWhatsAppUrl`: $builders');
  });

  test('والرقمُ يمرّ بالتسوية قبل بناء الرابط', () {
    final model = File(_modelPath).readAsStringSync();
    // التسويةُ والبناءُ في ملفٍّ واحد؛ والمطلوبُ أن البناءَ لا يُصدِّق
    // مُدخَلَه: `normalizeWhatsAppPhone` هي البوّابةُ الوحيدة.
    expect(model.contains('String? normalizeWhatsAppPhone('), isTrue);
    expect(model.contains('Uri.encodeComponent(message)'), isTrue,
        reason: 'النصُّ يُمرَّر بلا ترميز — `#` و`&` تبتره');
  });

  test('ولا رمزَ دولةٍ مكتوبٌ في الشيفرة', () {
    // ⚠️ والفحصُ على **الافتراض** لا على ذكرِ الرقم: تعليقٌ يقول «مثال: 20»
    // مقبولٌ، وقيمةٌ افتراضيّةٌ في توقيعٍ أو في قراءة الإعداد ليست كذلك.
    final dialog = File(_dialogPath).readAsStringSync();
    for (final bad in const [
      "defaultCountryCode: '20'",
      "defaultCountryCode: '966'",
      "?? '20'",
      "?? '966'",
    ]) {
      expect(dialog.contains(bad), isFalse,
          reason: 'افتراضُ دولةٍ في الشيفرة: $bad');
    }
    final model = File(_modelPath).readAsStringSync();
    expect(model.contains("defaultCountryCode = '"), isFalse,
        reason: 'رمزُ الدولة صار افتراضاً في النموذج');
  });

  test('والفتحُ محروسٌ بصلاحيةٍ تُفحَص إمضاءً لا لفّاً', () {
    final dialog = File(_dialogPath).readAsStringSync();
    expect(dialog.contains('PermissionCodes.customerMessageSend'), isTrue,
        reason: 'الإرسالُ بلا صلاحية — وأمرُ المالك أنه يفرق من مستخدمٍ لآخر');
    expect(dialog.contains('ensurePermission('), isTrue,
        reason: '`PermissionGuard` وحدَه يُخفي ولا يمنع مساراً برمجيّاً');
  });

  test('والكودُ مسجَّلٌ في masterList فيظهر لمدير الصلاحيات', () {
    // كودٌ مُنفَّذٌ وغيرُ مسجَّلٍ لا يستطيع أحدٌ منحَه — فالميزةُ حصرُ مديرِ
    // النظام إلى الأبد بلا سببٍ ظاهر.
    final codes = PermissionCodes.masterList.map((m) => m['code']).toSet();
    expect(codes, contains(PermissionCodes.customerMessageSend));
  });

  test('ونصوصُ الرسائل الثلاثةُ كلُّها موصولة', () {
    // ⚠️ مؤلِّفٌ يُكتَب ولا يُنادى ميزةٌ ميّتةٌ صامتة — وهي عائلةُ عطبٍ
    // موثَّقةٌ في هذا المستودع بنصّها.
    final src = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .where((f) => !f.path.replaceAll(r'\', '/').endsWith(_modelPath))
        .map((f) => f.readAsStringSync())
        .join('\n');
    for (final fn in const [
      'composeInvoiceMessage(',
      'composeStatementMessage(',
      'composeDueReminderMessage(',
    ]) {
      expect(src.contains(fn), isTrue, reason: 'مؤلِّفٌ بلا منادٍ: $fn');
    }
  });

  test('والدالّاتُ الثلاثُ تعمل فعلاً — مرساةُ سلوك', () {
    // بلا هذه المرساة قد تصير الفحوصُ فوقَ نصّاً يطابق نصّاً.
    expect(
      normalizeWhatsAppPhone('01012345678', defaultCountryCode: '20'),
      '201012345678',
    );
    expect(
      buildWhatsAppUrl(phone: '201012345678', message: 'x'),
      'https://wa.me/201012345678?text=x',
    );
  });
}
