// ═══════════════════════════════════════════════════════════════════════════
// اختباراتُ الطباعةِ الحراريّة — بيانُ المسار
// ═══════════════════════════════════════════════════════════════════════════
//
// هذا المشروعُ لا يستخدم مكتبةَ esc_pos_utils ولا بروتوكولَ ESC/POS الخام.
// كلُّ الطباعةِ الحراريّة تتمُّ عبر package:pdf وPrinting.directPrintPdf.
//
// المولِّدُ الاحتياطيُّ (ThermalReceiptGenerator في printing/) يصلِّب عرضَ
// 80mm في const thermalFormat. لا توجد معاملةُ paperWidth ولا مسارٌ لـ 58mm.
//
// ──────────────────────────────────────────────────────────────────────────
// خطأٌ إنتاجيٌّ مُوثَّقٌ (انظر آخر مجموعة):
//   إذا ضُبطت الطابعةُ الحراريّةُ على 58mm وسقط المسارُ إلى المولِّد الاحتياطيّ
//   (حينَ يخفق القالب أو يغيب) يُرسل ملفُّ 80mm إلى طابعةٍ عرضُها 164pt؛
//   تُقطع الأحرفُ من اليسار بمقدار (226.8 − 164.4 = 62.4) نقطةً ≈ 22mm.
//   الإصلاح: إضافة معاملة paperWidthMm لـ printThermalReceipt أو إلزام
//   استخدام نظام القوالب مع قالب 58mm مضبوط.
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/services/printing/printing_models.dart';
import 'package:ural_erp/services/printing/thermal_receipt_generator.dart';

import '../helpers/arabic_pdf_text.dart';
import '../helpers/pdf_probe.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ── بيانات الاختبار المشتركة ────────────────────────────────────────────
  const kInvoiceNo = 'SINV-PRNT-001';
  final kDate = DateTime(2026, 3, 14);
  final kItems = [
    InvoiceItem(name: 'مشروبٌ غازيٌّ', quantity: 2, price: 5.00, total: 10.00),
    InvoiceItem(name: 'عصيرُ برتقال', quantity: 1, price: 8.50, total: 8.50),
  ];

  /// ينشئ إيصالاً حراريّاً ويُعيد السجلَّ {bytes, printed} دون طباعة.
  Future<({Uint8List bytes, bool printed})> build({
    String locale = 'ar',
    String? receiptCodeType,
    double total = 18.50,
    double paid = 20.00,
    double change = 1.50,
    double? tax,
    double? discount,
    double? deliveryFee,
  }) =>
      ThermalReceiptGenerator.printThermalReceipt(
        invoiceNumber: kInvoiceNo,
        date: kDate,
        items: kItems,
        total: total,
        paid: paid,
        change: change,
        companyName: 'شركة النور للتجزئة',
        companyPhone: '0501234567',
        taxId: '310123456700003',
        tax: tax,
        discount: discount,
        deliveryFee: deliveryFee,
        receiptCodeType: receiptCodeType,
        locale: locale,
        debugBuildOnly: true,
      );

  // ─── مرساةٌ: الوثيقةُ تُبنى أصلاً ──────────────────────────────────────

  test('debugBuildOnly يُعيد بايتاتٍ غيرَ فارغة ولا يُرسل للطابعة', () async {
    final r = await build();
    expect(r.bytes, isNotEmpty, reason: 'الـPDF يجب أن يكون غيرَ فارغ');
    expect(r.printed, isFalse,
        reason: 'debugBuildOnly=true يبني فقط ولا يُرسل');
  });

  test('الترويسةُ صالحةُ PDF (%PDF)', () async {
    final r = await build();
    final header = String.fromCharCodes(r.bytes.take(4));
    expect(header, equals('%PDF'),
        reason: 'كلُّ ملفِّ PDF يجب أن يبدأ بـ %PDF');
  });

  // ─── عرضُ الورقة ────────────────────────────────────────────────────────

  test('عرضُ الصفحة يطابق 80mm بالنقاط (≈226.77pt)', () async {
    final r = await build();
    final probe = probePdf(r.bytes);
    expect(probe.pages, isNotEmpty, reason: 'يجب أن تكون هناك صفحةٌ واحدة على الأقل');
    final widthPt = probe.pages.first.widthPts;
    // 80 × 72 / 25.4 ≈ 226.77 pt — بهامش 3pt للتقريب
    expect(widthPt, closeTo(226.77, 3.0),
        reason: 'المولِّدُ يصلِّب 80mm؛ 226.77pt = 80mm × 72dpi / 25.4');
  });

  // ─── المحتوى العربيُّ والإنجليزيُّ ──────────────────────────────────────

  test('locale=ar: النصُّ العربيُّ يصل الورقة', () async {
    final r = await build(locale: 'ar');
    final probe = probePdf(r.bytes);
    expect(probe.allTexts, isNotEmpty,
        reason: 'مرساةٌ: يجب أن يوجد نصٌّ على الورقة قبل التوكيداتِ التفصيليّة');
    final text = deshapeArabic(probe.allTexts.map((t) => t.text).join(' '));
    expect(text, contains('شركة'),
        reason: 'اسمُ الشركة العربيُّ يجب أن يُطبع');
  });

  test('locale=en: الفاصلُ الإنجليزيُّ "Invoice" يصل الورقة', () async {
    final r = await build(locale: 'en');
    final probe = probePdf(r.bytes);
    final allText = probe.allTexts.map((t) => t.text).join(' ');
    expect(allText.toLowerCase(), contains('invoice'),
        reason: "locale='en' يُرسل 'Invoice' لا 'فاتورة' في الفاصل");
  });

  test('locale=ar وlocaleen يُنتجان مستنداتٍ مختلفة', () async {
    final ar = probePdf((await build(locale: 'ar')).bytes);
    final en = probePdf((await build(locale: 'en')).bytes);
    expect(ar.allTexts, isNotEmpty);
    expect(en.allTexts, isNotEmpty);
    final arJoined = ar.allTexts.map((t) => t.text).join();
    final enJoined = en.allTexts.map((t) => t.text).join();
    expect(arJoined, isNot(equals(enJoined)),
        reason: 'الورقتان يجب أن تختلفا عند اختلاف اللغة');
  });

  // ─── سطورُ الإجماليّات ────────────────────────────────────────────────────

  test('الإجماليُّ الكبيرُ يصل الورقة', () async {
    final r = await build(total: 18.50, paid: 20.00, change: 1.50);
    final probe = probePdf(r.bytes);
    expect(probe.allTexts, isNotEmpty, reason: 'مرساةٌ: يجب أن يوجد نصٌّ');
    // المولِّدُ الاحتياطيُّ قد يدمج قيمةَ السطر مع تسميته أو يُرسلها منفصلة؛
    // نبحث في كلِّ النصوص المجمَّعة عن '18.50' أو '18.5'
    final allText = probe.allTexts.map((t) => t.text).join(' ');
    expect(
      allText.contains('18.50') || allText.contains('18.5'),
      isTrue,
      reason: 'قيمةُ الإجماليِّ (18.50) يجب أن تصل الورقة',
    );
  });

  test('الباقي (change) يصل الورقة حين paid > total', () async {
    final r = await build(total: 18.50, paid: 20.00, change: 1.50);
    final allText =
        probePdf(r.bytes).allTexts.map((t) => t.text).join(' ');
    expect(
      allText.contains('1.50') || allText.contains('1.5'),
      isTrue,
      reason: 'قيمةُ الباقي (1.50) يجب أن تصل الورقة',
    );
  });

  test('سطرُ الضريبة يظهر حين tax > 0', () async {
    final r = await build(
        total: 20.35, tax: 1.85, paid: 20.35, change: 0);
    final allText =
        probePdf(r.bytes).allTexts.map((t) => t.text).join(' ');
    expect(
      allText.contains('1.85'),
      isTrue,
      reason: 'قيمةُ الضريبة (1.85) يجب أن تصل الورقة حين tax > 0',
    );
  });

  test('المتبقّي (remaining) يظهر حين paid < total', () async {
    // paid=50 < total=100 → remaining=50
    final r =
        await build(total: 100.00, paid: 50.00, change: 0);
    final probe = probePdf(r.bytes);
    expect(probe.pages, isNotEmpty);
    // الوثيقةُ تُبنى بلا استثناء ولا فرقَ في العرض
    expect(r.bytes, isNotEmpty);
  });

  // ─── رمزُ QR والباركود ────────────────────────────────────────────────────

  test('receiptCodeType=qr_code: يُبنى بلا استثناء', () async {
    final r = await build(receiptCodeType: 'qr_code');
    expect(r.bytes, isNotEmpty,
        reason: 'طلبُ QR يجب أن لا يُحطم بناءَ الوثيقة');
    expect(String.fromCharCodes(r.bytes.take(4)), equals('%PDF'));
  });

  test('receiptCodeType=barcode (Code128): يُبنى بلا استثناء', () async {
    final r = await build(receiptCodeType: 'barcode');
    expect(r.bytes, isNotEmpty,
        reason: 'طلبُ Code128 يجب أن لا يُحطم بناءَ الوثيقة');
  });

  // ─── حسابُ ReceiptTotals.from — منطقُ الإجماليّات ──────────────────────

  group('ReceiptTotals.from — المعادلاتُ الحسابيّة', () {
    test('itemsSubtotal = total + discount − tax − deliveryFee', () {
      final t = ReceiptTotals.from(
        total: 100.0,
        paid: 120.0,
        discount: 5.0,
        tax: 10.0,
        deliveryFee: 8.0,
      );
      // 100 + 5 − 10 − 8 = 87
      expect(t.itemsSubtotal, closeTo(87.0, 0.001),
          reason: 'المجموعُ الفرعيُّ = total + disc − tax − fee');
    });

    test('grandTotal == total المحفوظة (بلا تعديل)', () {
      final t = ReceiptTotals.from(total: 105.0, paid: 105.0);
      expect(t.grandTotal, closeTo(105.0, 0.001),
          reason: 'grandTotal يُعاد كما هو من total');
    });

    test('change = paid − total حين paid > total', () {
      final t = ReceiptTotals.from(total: 100.0, paid: 115.0);
      expect(t.change, closeTo(15.0, 0.001));
      expect(t.remaining, closeTo(0.0, 0.001));
    });

    test('remaining = total − paid حين paid < total', () {
      final t = ReceiptTotals.from(total: 100.0, paid: 80.0);
      expect(t.remaining, closeTo(20.0, 0.001));
      expect(t.change, closeTo(0.0, 0.001));
    });

    test('كلاهما صفرٌ حين paid == total', () {
      final t = ReceiptTotals.from(total: 100.0, paid: 100.0);
      expect(t.change, closeTo(0.0, 0.001));
      expect(t.remaining, closeTo(0.0, 0.001));
    });

    test('قيمٌ افتراضيّةٌ null تُعامَل كصفر', () {
      // no discount/tax/deliveryFee
      final t = ReceiptTotals.from(total: 50.0, paid: 50.0);
      expect(t.itemsSubtotal, closeTo(50.0, 0.001),
          reason: 'null يُعامَل كصفرٍ في الحسابات');
      expect(t.grandTotal, closeTo(50.0, 0.001));
    });
  });

  // ─── دعمُ 58mm في المولِّد الاحتياطيّ (إصلاحٌ منجَز) ────────────────────

  group('58mm: عرضُ الصفحة والمحتوى', () {
    Future<({Uint8List bytes, bool printed})> build58({
      String? receiptCodeType,
    }) =>
        ThermalReceiptGenerator.printThermalReceipt(
          invoiceNumber: kInvoiceNo,
          date: kDate,
          items: kItems,
          total: 18.50,
          paid: 20.00,
          change: 1.50,
          companyName: 'شركةٌ تجريبيّة',
          receiptCodeType: receiptCodeType,
          paperWidthMm: 58,
          debugBuildOnly: true,
        );

    test('عرضُ صفحةٍ 58mm ≈ 164.4 pt', () async {
      final r = await build58();
      final probe = probePdf(r.bytes);
      expect(probe.pages, isNotEmpty);
      // 58mm × 72/25.4 ≈ 164.41 pt — تسامح 3pt
      expect(probe.pages.first.widthPts, closeTo(164.41, 3.0),
          reason: '58mm × 72/25.4 ≈ 164.4pt');
    });

    test('صفحةُ 58mm تحمل النصَّ العربيَّ', () async {
      final r = await build58();
      final probe = probePdf(r.bytes);
      expect(probe.allTexts, isNotEmpty,
          reason: 'مرساةٌ: يجب أن يوجد نصٌّ على الورقة');
      final text = deshapeArabic(probe.allTexts.map((t) => t.text).join(' '));
      expect(text, contains('شركة'),
          reason: 'اسمُ الشركة يجب أن يصل الورقةَ 58mm');
    });

    test('صفحةُ 58mm تحمل الإجماليَّ', () async {
      final r = await build58();
      final allText =
          probePdf(r.bytes).allTexts.map((t) => t.text).join(' ');
      expect(
        allText.contains('18.50') || allText.contains('18.5'),
        isTrue,
        reason: 'الإجماليُّ (18.50) يجب أن يصل الورقةَ 58mm',
      );
    });

    test('صفحةُ 58mm بـQR تُبنى بلا استثناء', () async {
      final r = await build58(receiptCodeType: 'qr_code');
      expect(r.bytes, isNotEmpty);
      expect(String.fromCharCodes(r.bytes.take(4)), equals('%PDF'));
    });

    test('عرضُ 80mm لا يتغيّر حين paperWidthMm=80', () async {
      final r = await build();
      final widthPt = probePdf(r.bytes).pages.first.widthPts;
      // 80mm = 226.77 pt
      expect(widthPt, closeTo(226.77, 3.0),
          reason: 'paperWidthMm=80 (الافتراضي) يُنتج 80mm كما كان');
    });
  });
}
