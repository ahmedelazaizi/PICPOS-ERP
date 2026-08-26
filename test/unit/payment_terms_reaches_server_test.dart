// مهلةُ السداد تعبر السلسلةَ كاملةً — من الحوار إلى الخادم.
//
// ═══ ما يحمي هذا الملفّ ═══
//
// حقلٌ يُكتَب في الحوار ولا يصل الخادمَ **لا يحمرّ شيء**: الطرفُ يُنشأ فعلاً،
// والشاشةُ تُغلَق، والمهلةُ تختفي بأوّل سحبِ دلتا فتعود الفاتورةُ مستحقّةً يومَ
// إصدارها. والمستخدمُ يظنّ أنّه ضبطها.
//
// ووقع هذا النمطُ في المستودع من قبل: «رسالةُ `permissionCodes` وحدَها —
// النمطُ المشروطُ لا ينتشر إلى الخادم» بندٌ مفتوحٌ موثَّق. فالسلسلةُ هنا
// **ستّةُ مواضعَ في أربعة ملفّات**، وانقطاعُ أيٍّ منها يُسقط الحقلَ صامتاً:
//
//   حوارُ الطرف ← ClientWriteInterceptor ← _CwiCommerce (حمولة + مرآة)
//               ← api_party_handler (إدراج + تحديث) ← api_handler (تسلسل)
//
// ⚠️ والفحصُ نصّيٌّ لا سلوكيّ — عمداً: تشغيلُ خادمٍ حقيقيٍّ في اختبارِ وحدةٍ
// يقتضي مقبساً وشبكةً، والانقطاعُ يقع في **التوصيل** لا في المنطق. فالمقيسُ
// هو أنّ الاسمَ حاضرٌ في كلّ حلقة، ولكلّ حلقةٍ مرساةٌ تُثبت أنّ القراءةَ نفسَها
// تعمل.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _read(String path) {
  final f = File(path);
  expect(f.existsSync(), isTrue, reason: 'مسارٌ تبدّل: $path');
  return f.readAsStringSync();
}

int _count(String src, String needle) => src.split(needle).length - 1;

void main() {
  const dialog =
      'lib/presentation/parties_picpos/dialogs/add_party_dialog_picpos.dart';
  const interceptor = 'lib/services/client_write_interceptor.dart';
  const commerce = 'lib/services/interceptor/cwi_commerce.dart';
  const partyApi = 'lib/services/api/api_party_handler.dart';
  const apiHandler = 'lib/services/api/api_handler.dart';

  test('الحوارُ يقرأ المهلةَ ويمرّرها في المسارين', () {
    final src = _read(dialog);
    // مرساة: الحدُّ الائتمانيُّ حلقةٌ مجاورةٌ معروفةُ الوصل — لو قرأ صفراً
    // فالملفُّ ليس ما نظنّ.
    expect(_count(src, 'creditLimit'), greaterThan(3),
        reason: 'مرساةُ الحوار سقطت');

    expect(src, contains('paymentTermsController'));
    // مسارُ الخادم (ClientWriteInterceptor) ومسارُ المستودع — كلاهما.
    expect(_count(src, 'paymentTermsDays: paymentTermsDays'), 1,
        reason: 'مسارُ وضع العميل لا يمرّر المهلة');
    expect(_count(src, 'paymentTermsDays: Value(paymentTermsDays)'), 1,
        reason: 'مسارُ المستودع لا يكتب المهلة');
  });

  test('المعترِضُ يمرّرها إلى _CwiCommerce', () {
    final src = _read(interceptor);
    expect(_count(src, 'createParty'), greaterThan(1),
        reason: 'مرساةُ المعترِض سقطت');
    expect(src, contains('int paymentTermsDays = 0'),
        reason: 'المعامل غائبٌ عن الواجهة الساكنة');
    expect(src, contains('paymentTermsDays: paymentTermsDays'),
        reason: 'المعترِضُ يقبلها ولا يمرّرها — تُبتلَع هنا');
  });

  test('الحمولةُ والمرآةُ كلتاهما تحملانها', () {
    final src = _read(commerce);
    expect(_count(src, "'creditLimit': creditLimit"), 1,
        reason: 'مرساةُ الحمولة سقطت');
    expect(_count(src, "'paymentTermsDays': paymentTermsDays"), 1,
        reason: 'حمولةُ الخادم بلا مهلة');
    expect(_count(src, 'paymentTermsDays: Value(paymentTermsDays)'), 1,
        reason: 'المرآةُ المحلّيّةُ بلا مهلة — تختفي حتى أوّل سحبِ دلتا');
  });

  test('الخادمُ يقرأها في الإدراج وفي التحديث معاً', () {
    final src = _read(partyApi);
    expect(_count(src, "data['creditLimit']"), 2,
        reason: 'مرساةُ الخادم سقطت — الحقلان لم يعودا اثنين');
    // الإدراجُ وحدَه لا يكفي: تعديلُ مهلةِ طرفٍ قائمٍ مسارٌ آخر.
    expect(_count(src, "data['paymentTermsDays']"), 2,
        reason: 'الخادمُ يقرؤها في مسارٍ واحدٍ فقط');
  });

  test('الخادمُ يُعيدها إلى العميل في التسلسل', () {
    final src = _read(apiHandler);
    expect(_count(src, "'creditLimit': p.creditLimit"), 1,
        reason: 'مرساةُ التسلسل سقطت');
    // بلا هذا يكتبها العميلُ وتُحفَظ مركزيّاً ثمّ يمسحها سحبُ الدلتا بصفر.
    expect(_count(src, "'paymentTermsDays': p.paymentTermsDays"), 1,
        reason: 'التسلسلُ العائدُ بلا مهلة — الدلتا تمسحها');
  });
}
