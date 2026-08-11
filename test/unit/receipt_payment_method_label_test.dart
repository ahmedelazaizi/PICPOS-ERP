// §٥-٣ — تسميةُ طريقة الدفع في المطبوع.
//
// ── فئةُ العطب ────────────────────────────────────────────────────────────
// الإيصالُ المرصود ميدانياً (2026-08-11) طبع «طريقة الدفع: cash» — كودٌ
// إنجليزيٌّ في مستندٍ عربيٍّ بالكامل يقرؤه العميل.
//
// و`payment_method` كان يُطبع **خاماً** كما يصل من المنادي بلا مُحوِّل، بينما
// `_mapSaleTypeLabel` المجاور في نفس الملفّ يحوّل نوعَ البيع منذ البداية.
// فالفجوةُ لم تكن في المعرفة بل في أن أحدَ الحقلين مرَّ بلا تحويل.
//
// وهذا الملفُّ يقيس المحوّلَ نفسَه. وصلُه بموضعَي العرض (‏عنصرُ
// `payment_method` الصريح و`_getDataValue` الافتراضيّ) محروسٌ في
// `test/structural/receipt_no_dangling_labels_test.dart`.

import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/services/templated_invoice_service.dart';

void main() {
  String label(String code) =>
      TemplatedInvoiceService.mapPaymentMethodLabel(code);

  group('كودُ الدفع يصير تسميةً عربية', () {
    const expected = <String, String>{
      'cash': 'نقدي',
      'card': 'بطاقة',
      'visa': 'بطاقة',
      'bank': 'تحويل بنكي',
      'transfer': 'تحويل بنكي',
      'click': 'كليك',
      'credit': 'آجل',
      'wallet': 'محفظة',
      'mixed': 'مختلط',
    };

    expected.forEach((code, ar) {
      test('«$code» ⇒ «$ar»', () => expect(label(code), ar));
    });

    test('الحالةُ والفراغُ لا يمنعان التحويل', () {
      // المنادي قد يمرّر ما يقرؤه من قاعدةٍ أو من واجهة، وحرفٌ كبيرٌ واحدٌ
      // كان سيُعيد الكودَ خاماً للعميل.
      expect(label('CASH'), 'نقدي');
      expect(label('  Cash '), 'نقدي');
    });
  });

  group('ضوابط', () {
    test('تسميةٌ عربيةٌ وصلت جاهزةً تمرّ كما هي', () {
      // بعضُ المنادين يمرّرون التسميةَ لا الكود. تحويلُها ثانيةً أو مسحُها
      // كان سيُفقد المعلومة.
      expect(label('نقدي'), 'نقدي');
      expect(label('فيزا'), 'فيزا');
    });

    test('كودٌ غيرُ معروفٍ يظهر كما هو لا يختفي', () {
      // لولا هذا لمرّ الحلُّ بإرجاع '' لكلّ ما لا يعرفه — فيختفي الحقلُ من
      // الإيصال بدل أن يُرى فيُبلَّغ عنه.
      expect(label('crypto'), 'crypto');
      expect(label(''), '');
    });
  });
}
