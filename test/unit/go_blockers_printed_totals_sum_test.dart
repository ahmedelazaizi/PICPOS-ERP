// ═══════════════════════════════════════════════════════════════════════════
// البند ٤‑١ — المطبوعُ لا تجمع أسطرُه إلى إجماليّه
// ═══════════════════════════════════════════════════════════════════════════
//
// ── العطب ─────────────────────────────────────────────────────────────────
//
// `deliveryFee` عمودٌ في `sales_invoices`، والإجماليُّ المحفوظ يشمله بالبناء
// (`sales_transaction_orchestrator.dart:695`):
//
//     total = subtotal − discount + tax + deliveryFee
//
// وكان سطرُ رسم التوصيل **غائباً عن كلِّ قالبٍ في المستودع**. فالورقةُ تطبع
// المكوّناتِ الثلاثةَ الأولى ثمّ إجماليّاً أكبرَ منها — **مستندٌ ضريبيٌّ لا
// تتّسق أسطرُه مع إجماليّه**، والفرقُ = رسمُ التوصيل بالضبط.
//
// ── لماذا ملفٌّ منفصلٌ عن البصمات الذهبيّة ────────────────────────────────
//
// بصماتُ `printing_characterization_test` تُثبّت **الشكل** لا **الحساب**،
// ومدخلُها (`printing_characterization_fixture`) لا يحترم المتطابقةَ أصلاً:
//     611.76 − 5.00 + 11.76 + 20.00 = 638.52  ≠  626.76
// فهي تُثبّت ورقةً غيرَ متّسقةٍ ولا تستطيع كشفَ عدم الاتّساق. ⚠️ ولا تُصلَح
// الـfixture هنا: تثبيتُ شكلٍ قائمٍ غرضٌ مشروعٌ آخر، وتغييرُ أرقامها يحرّك
// ٢٧ بصمةً لغرضٍ لا يخصّها.
//
// فهذا الملفّ يطبع بأرقامٍ **متّسقةٍ محسوبةٍ يدويّاً**، يفتح الـPDF، ويجمع
// ما طُبع فعلاً.

import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/database/database.dart';
import 'package:ural_erp/services/templated_invoice_service.dart';

import '../helpers/pdf_probe.dart';

// ── مدخلٌ يحترم المتطابقة ────────────────────────────────────────────────
//   100.00 − 0.00 + 0.00 + 5.00 = 105.00
// أرقامٌ نظيفةٌ عمداً: صفرُ خصمٍ وصفرُ ضريبةٍ يجعلان الفارقَ المتوقَّعَ عند
// الفشل **مساوياً لرسم التوصيل بالضبط** فلا يلتبس بتقريبٍ أو بخصم.
const _subtotal = 100.0;
const _discount = 0.0;
const _tax = 0.0;
const _delivery = 5.0;
const _total = 105.0; // = 100 − 0 + 0 + 5
const _paid = 105.0;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;

  setUp(() async {
    db = AppDatabase.forTesting();
    await db.seedDefaultTemplates();
  });
  tearDown(() => db.close());

  /// يطبع بقالبِ (نوع، فئة) ويعيد كلَّ النصوص المرسومة.
  Future<List<String>> printAndReadTexts(String type, String category) async {
    final bytes = (await TemplatedInvoiceService.printWithTemplate(
      db: db,
      debugBuildOnly: true,
      type: type,
      category: category,
      invoiceNumber: 'DLV-1',
      date: DateTime(2026, 8, 31),
      customerName: 'عميل التوصيل',
      customerPhone: null,
      customerAddress: null,
      items: const [
        {
          'name': 'صنف',
          'quantity': 1.0,
          'price': 100.0,
          'total': 100.0,
        }
      ],
      subtotal: _subtotal,
      discount: _discount,
      tax: _tax,
      deliveryFee: _delivery,
      total: _total,
      paid: _paid,
      companyName: 'شركة',
      companyAddress: '',
      companyPhone: '',
      companyTaxId: null,
      salesType: 'delivery',
    )).bytes;
    return probePdf(bytes).allTexts.map((t) => t.text).toList();
  }

  group('رسمُ التوصيل يبلغ الورقة', () {
    test('🔴 الإيصالُ الحراريُّ يطبع 5.00 — وكان لا يطبعه', () async {
      final texts = await printAndReadTexts('thermal', 'receipt');

      expect(texts.any((t) => t.trim() == '105.00'), isTrue,
          reason: 'ضابطٌ: الإجماليُّ نفسُه يجب أن يكون على الورقة');
      expect(texts.any((t) => t.trim() == '5.00'), isTrue,
          reason: 'سطرُ رسم التوصيل غائبٌ عن المطبوع — والإجماليُّ يشمله، '
              'فالورقةُ لا تجمع بفارقٍ = ٥٫٠٠ بالضبط');
    });

    test('🔴 فاتورةُ A4 تطبع 5.00 — وكانت لا تطبعه', () async {
      final texts = await printAndReadTexts('a4', 'invoice');

      expect(texts.any((t) => t.trim() == '105.00'), isTrue,
          reason: 'ضابطٌ');
      expect(texts.any((t) => t.trim() == '5.00'), isTrue,
          reason: 'A4 كان معطوباً من طرفين: القالبُ بلا سطرٍ، و'
              '`invoice_generator.dart` يمرّر `deliveryFee: 0` صلباً');
    });
  });

  group('الرسمُ الصفريُّ لا يلوّث الفاتورةَ العاديّة', () {
    test('بلا توصيلٍ لا يظهر سطرُ «رسوم التوصيل»', () async {
      // ⚠️ ضابطٌ لازم: `resolveContentValue` تُرجع "0.00" لا "" لرسمٍ صفريّ.
      // فبلا الشرط `delivery_fee > 0` كان السطرُ يظهر على **كلِّ** فاتورةٍ
      // عاديّةٍ بقيمة صفر — ضجيجٌ على كلِّ ورقةٍ تُطبع في المحلّ.
      final bytes = (await TemplatedInvoiceService.printWithTemplate(
        db: db,
        debugBuildOnly: true,
        type: 'thermal',
        category: 'receipt',
        invoiceNumber: 'NO-DLV',
        date: DateTime(2026, 8, 31),
        customerName: 'عميل',
        customerPhone: null,
        customerAddress: null,
        items: const [
          {'name': 'صنف', 'quantity': 1.0, 'price': 100.0, 'total': 100.0}
        ],
        subtotal: 100.0,
        discount: 0.0,
        tax: 0.0,
        deliveryFee: 0.0,
        total: 100.0,
        paid: 100.0,
        companyName: 'شركة',
        companyAddress: '',
        companyPhone: '',
        companyTaxId: null,
      )).bytes;
      final texts = probePdf(bytes).allTexts.map((t) => t.text).toList();

      expect(texts.any((t) => t.trim() == '100.00'), isTrue,
          reason: 'ضابطٌ: الإجماليُّ على الورقة');
      // النصُّ العربيُّ يخرج بأشكالٍ متّصلةٍ في الـPDF، فنبحث عن الجذر.
      final joined = texts.join(' ');
      expect(joined.contains('ﺗﻮﺻﻴﻞ') || joined.contains('توصيل'), isFalse,
          reason: 'سطرُ التوصيل ظهر على فاتورةٍ بلا توصيل — الشرطُ معطَّل');
    });
  });
}
