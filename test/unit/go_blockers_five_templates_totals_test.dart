// ═══════════════════════════════════════════════════════════════════════════
// §٦‑١ — خمسةُ قوالبَ «لا تطبع أيَّ مجاميع»: قياسٌ لا نقل
// ═══════════════════════════════════════════════════════════════════════════
//
// تسليمُ 2026-09-01 يقول إنّ `a4_professional` · `a4_commercial` ·
// `thermal_classic/modern/comprehensive` لا تطبع إجماليّاً ولا ضريبةً ولا
// مجموعاً فرعيّاً، وإنّ «صيغتَها القديمة تُرشَّح خارجَ الراسم».
//
// وهذا الملفُّ يقيس الادّعاءَ على الورقة نفسِها: يستورد كلَّ قالبٍ، يجعله
// الافتراضيَّ لنوعه، يطبع بأرقامٍ متّسقةٍ محسوبةٍ يدويّاً، ثمّ يفتح الـPDF
// ويقرأ ما رُسم فعلاً.
//
// ⚠️ والأرقامُ مختارةٌ كي **لا تلتبس**: كلُّ مكوّنٍ رقمٌ فريدٌ لا يظهر إلّا
// مرّةً، فمطابقةٌ تامّةٌ على النصّ تكفي ولا يلزم `contains` الذي يمرُّ على
// `105.00` حين تبحث عن `5.00`.

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/database/database.dart';
import 'package:ural_erp/services/templated_invoice_service.dart';

import '../helpers/pdf_probe.dart';

// 200.00 − 0.00 + 30.00 = 230.00 — ثلاثةُ أرقامٍ متمايزة.
const _subtotal = 200.0;
const _discount = 0.0;
const _tax = 30.0;
const _total = 230.0;

/// (اسمُ الملفّ، النوع، الفئة، الاسمُ المتوقَّع في القاعدة)
///
/// ⚠️ **الفئةُ `receipt` للخمسة جميعاً** ولو كانت فواتيرَ A4: الاستيرادُ
/// يستنتج `templateCategory` من الملفّ ويسقط إلى `receipt` عند غيابه
/// (‏`importTemplateFromJson`)، و`a4_commercial`/`a4_professional` بلا الحقل.
/// وطلبُ `invoice` كان يجعل الحاسمَ يسقط إلى القالب المبذور «فاتورة A4» —
/// فيقيس الاختبارُ **قالباً آخرَ** ويمرُّ أخضرَ زوراً. وقع فعلاً 2026-09-01.
const _templates = <List<String>>[
  ['thermal_classic.json', 'thermal', 'receipt', 'فاتورة حرارية كلاسيكية'],
  ['thermal_modern.json', 'thermal', 'receipt', 'فاتورة حرارية عصرية'],
  ['thermal_comprehensive.json', 'thermal', 'receipt', 'فاتورة حرارية شاملة'],
  ['a4_commercial.json', 'a4', 'receipt', 'فاتورة A4 تجارية'],
  ['a4_professional.json', 'a4', 'receipt', 'فاتورة A4 احترافية'],
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;

  setUp(() async {
    db = AppDatabase.forTesting();
    await db.seedDefaultTemplates();
  });
  tearDown(() => db.close());

  /// يستورد القالبَ من الأصول ويجعله الافتراضيَّ، ثمّ يطبع ويعيد النصوص.
  Future<List<String>> printWith(
      String file, String type, String category, String expectedName) async {
    final json =
        await rootBundle.loadString('assets/invoice_templates/$file');
    final id = await db.importTemplateFromJson(json);
    await db.setDefaultTemplate(id);

    // 🔴 مرساةٌ غيرُ دائريّة: تُثبت أنّ الحاسمَ سيختار **هذا** القالبَ بعينه.
    // بدونها كان الاختبارُ يقيس القالبَ المبذور ويمرُّ أخضرَ على قالبٍ لم
    // يُرسَم أصلاً.
    final resolved = await db.getDefaultTemplateByCategory(type, category);
    expect(resolved?.name, expectedName,
        reason: 'الحاسمُ يجب أن يختار $file — وإلّا فالقياسُ على قالبٍ آخر');

    final bytes = await TemplatedInvoiceService.printWithTemplate(
      db: db,
      debugBuildOnly: true,
      type: type,
      category: category,
      invoiceNumber: 'TPL-1',
      date: DateTime(2026, 9, 1),
      customerName: 'عميل',
      customerPhone: null,
      customerAddress: null,
      items: const [
        {'name': 'صنف', 'quantity': 2.0, 'price': 100.0, 'total': 200.0}
      ],
      subtotal: _subtotal,
      discount: _discount,
      tax: _tax,
      deliveryFee: 0.0,
      total: _total,
      paid: _total,
      companyName: 'شركة',
      companyAddress: '',
      companyPhone: '',
      companyTaxId: null,
    );
    return probePdf(bytes).allTexts.map((t) => t.text.trim()).toList();
  }

  for (final t in _templates) {
    final file = t[0];
    final type = t[1];
    final category = t[2];
    final expectedName = t[3];

    test('$file يطبع المجموعَ الفرعيَّ والضريبةَ والإجمالي', () async {
      final texts = await printWith(file, type, category, expectedName);

      // مرساة: الورقةُ رُسمت فعلاً ولم تعد فارغةً — وإلّا مرَّ كلُّ توكيدٍ
      // سلبيٍّ زوراً.
      expect(texts, isNotEmpty, reason: 'مرساة: الـPDF فيه نصٌّ مرسوم');

      expect(texts.contains('230.00'), isTrue,
          reason: '$file — الإجماليُّ ٢٣٠٫٠٠ غائبٌ عن الورقة. '
              'ما طُبع: ${texts.where((s) => s.isNotEmpty).take(30).toList()}');
      expect(texts.contains('200.00'), isTrue,
          reason: '$file — المجموعُ الفرعيُّ ٢٠٠٫٠٠ غائب');
      expect(texts.contains('30.00'), isTrue,
          reason: '$file — الضريبةُ ٣٠٫٠٠ غائبة');
    });
  }
}
