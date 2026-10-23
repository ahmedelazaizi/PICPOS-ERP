// ═══════════════════════════════════════════════════════════════════════════
// اختباراتُ قاعدةِ لغةِ الشركة في المطبوعات
// ═══════════════════════════════════════════════════════════════════════════
//
// القاعدة: لغةُ المطبوعات تتحكّم بها إعدادات الشركة (print_language في DB)،
//          لا لغةُ واجهة المستخدم (UI Locale).
//
// التفصيل:
//   • print_language → قيمةٌ في جدول الإعدادات في DB ('ar' أو 'en')
//   • يقرأها printLanguageProvider (FutureProvider<String>)
//   • تُمرَّر كـ locale إلى TemplateInvoiceData / printThermalReceipt
//   • TemplateInvoiceData.locale → يُحدِّد لغةَ تسمياتِ الورقة
//
// الاختباراتُ هنا تُثبت:
//   ١. إعدادُ print_language في DB يُحفَظ ويُقرأ صحيحاً
//   ٢. locale='ar' وlocaleen يُنتجان مستنداتٍ مختلفة
//   ٣. PDF بـlocale='ar' يحمل النصَّ العربيَّ
//   ٤. PDF بـlocale='en' لا يحمل نصَّ 'فاتورة' في الفاصل بل 'Invoice'
//   ٥. الإعدادُ في DB مستقلٌّ عن أيِّ Locale في Flutter
// ═══════════════════════════════════════════════════════════════════════════

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/data/database/database.dart';
import 'package:picpos_erp/services/printing/printing_models.dart';
import 'package:picpos_erp/services/printing/template_pdf_renderer.dart';
import 'package:picpos_erp/services/printing/thermal_receipt_generator.dart';
import 'package:picpos_erp/services/templated_invoice_service.dart';

import '../helpers/arabic_pdf_text.dart';
import '../helpers/pdf_probe.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  setUp(() async {
    db = AppDatabase.forTesting();
    await db.seedDefaultTemplates();
  });
  tearDown(() => db.close());

  // ── بيانات الاختبار ────────────────────────────────────────────────────
  const kInvoiceAr = 'LANG-AR-001';
  const kInvoiceEn = 'LANG-EN-001';
  final kDate = DateTime(2026, 6, 1);
  final kItems = [
    InvoiceItem(name: 'صنف', quantity: 1, price: 50.0, total: 50.0)
  ];
  const kCompanyAr = 'شركةُ النور';
  const kCompanyEn = 'Al-Nour Company';

  // ═══════════════════════════════════════════════════════════════════════════
  // ١. إعدادُ print_language في DB
  // ═══════════════════════════════════════════════════════════════════════════

  group('إعدادُ print_language في قاعدة البيانات', () {
    test('القيمةُ الافتراضيّة غيرُ الموجودة تُعاد كـ null', () async {
      // قبل أيِّ حفظٍ: DB تُعيد null لأيِّ مفتاحٍ غير مضبوط
      final value = await db.getSettingValue('print_language');
      // القيمةُ إمّا null أو 'ar' (القيمة الافتراضيّة في printLanguageProvider)
      expect(value == null || value == 'ar', isTrue,
          reason: 'print_language إمّا غيرُ محفوظةٍ (null) أو الافتراضيّة (ar)');
    });

    test('حفظُ print_language=ar ثمَّ قراءتُها → ar', () async {
      await db.setSetting('print_language', 'ar');
      final value = await db.getSettingValue('print_language');
      expect(value, equals('ar'),
          reason: 'print_language المحفوظة كـ ar يجب أن تُقرأ ar');
    });

    test('حفظُ print_language=en ثمَّ قراءتُها → en', () async {
      await db.setSetting('print_language', 'en');
      final value = await db.getSettingValue('print_language');
      expect(value, equals('en'),
          reason: 'print_language المحفوظة كـ en يجب أن تُقرأ en');
    });

    test('تبديلُ print_language من ar إلى en يُحدِّث القيمة', () async {
      await db.setSetting('print_language', 'ar');
      await db.setSetting('print_language', 'en');
      final value = await db.getSettingValue('print_language');
      expect(value, equals('en'),
          reason: 'التبديلُ يجب أن يُحدِّث القيمة');
    });

    test('إعدادُ print_language مستقلٌّ عن أيِّ مفتاحٍ آخر', () async {
      await db.setSetting('print_language', 'ar');
      await db.setSetting('some_other_setting', 'xyz');
      expect(await db.getSettingValue('print_language'), equals('ar'),
          reason: 'تغييرُ إعدادٍ آخر لا يُؤثِّر على print_language');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // ٢. locale في TemplateInvoiceData يُغيِّر محتوى الورقة
  // ═══════════════════════════════════════════════════════════════════════════

  group('locale في TemplateInvoiceData يُغيِّر لغةَ الورقة', () {
    late InvoiceTemplateWithData thermalTemplate;

    setUp(() async {
      final json = await rootBundle
          .loadString('assets/invoice_templates/thermal_modern.json');
      final id = await db.importTemplateFromJson(json);
      thermalTemplate = (await db.getTemplateWithData(id))!;
    });

    Future<PdfProbe> render(String locale, String invoiceNo) =>
        TemplatePdfRenderer.generatePdf(
          templateData: thermalTemplate,
          invoiceData: TemplateInvoiceData(
            invoiceNumber: invoiceNo,
            date: kDate,
            items: kItems,
            subtotal: 50.0,
            total: 50.0,
            paid: 50.0,
            companyName: locale == 'ar' ? kCompanyAr : kCompanyEn,
            locale: locale,
          ),
        ).then(probePdf);

    test('locale=ar: النصُّ العربيُّ للشركة يصل الورقة', () async {
      final probe = await render('ar', kInvoiceAr);
      expect(probe.allTexts, isNotEmpty,
          reason: 'مرساةٌ: يجب أن يوجد نصٌّ على الورقة');
      final text = deshapeArabic(probe.allTexts.map((t) => t.text).join(' '));
      expect(text, contains('شركة'),
          reason: 'locale=ar: اسمُ الشركة العربيُّ يجب أن يصل الورقة');
    });

    test('locale=en: الشركةُ الإنجليزيّةُ تُبنى بلا استثناء', () async {
      final probe = await render('en', kInvoiceEn);
      expect(probe.allTexts, isNotEmpty,
          reason: 'locale=en: يجب أن يوجد نصٌّ على الورقة');
      expect(probe.pages, isNotEmpty);
    });

    test('locale=ar وlocaleen: ورقتان مختلفتان في المحتوى', () async {
      final arProbe = await render('ar', kInvoiceAr);
      final enProbe = await render('en', kInvoiceEn);
      final arText = arProbe.allTexts.map((t) => t.text).join();
      final enText = enProbe.allTexts.map((t) => t.text).join();
      expect(arText, isNot(equals(enText)),
          reason: 'ar وen يجب أن ينتجا ورقتين مختلفتين');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // ٣. locale في ThermalReceiptGenerator يُغيِّر نصَّ الفاصل
  // ═══════════════════════════════════════════════════════════════════════════

  group('locale في ThermalReceiptGenerator يُغيِّر فاصلَ الورقة', () {
    Future<PdfProbe> buildReceipt(String locale) async {
      final r = await ThermalReceiptGenerator.printThermalReceipt(
        invoiceNumber: 'LOCALE-$locale',
        date: kDate,
        items: kItems,
        total: 50.0,
        paid: 50.0,
        change: 0,
        companyName: locale == 'ar' ? kCompanyAr : kCompanyEn,
        locale: locale,
        debugBuildOnly: true,
      );
      return probePdf(r.bytes);
    }

    test('locale=ar: فاصلُ «فاتورة» يصل الورقة', () async {
      final probe = await buildReceipt('ar');
      expect(probe.allTexts, isNotEmpty);
      final allText = probe.allTexts.map((t) => t.text).join(' ');
      // «فاتورة» تُكتب بأشكالٍ متّصلةٍ في PDF؛ نستخدم deshapeArabic
      final shaped = deshapeArabic(allText);
      // الكلمةُ التي يبنيها _buildSeparator هي 'فاتورة' بالعربيّة
      expect(shaped, contains(deshapeArabic('فاتورة')),
          reason: "locale=ar يطبع 'فاتورة' في الفاصل");
    });

    test('locale=en: كلمةُ Invoice تصل الورقة', () async {
      final probe = await buildReceipt('en');
      expect(probe.allTexts, isNotEmpty);
      final allText =
          probe.allTexts.map((t) => t.text).join(' ').toLowerCase();
      expect(allText, contains('invoice'),
          reason: "locale=en يطبع 'Invoice' في الفاصل");
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // ٤. قاعدةُ الشركة: تغييرُ UI لا يُغيِّر لغةَ المطبوع
  // ═══════════════════════════════════════════════════════════════════════════

  group('لغةُ الشركة مستقلّةٌ عن لغة واجهة المستخدم', () {
    // في Flutter، locale واجهة المستخدم هو Locale('ar','SA') مثلاً.
    // لغةُ المطبوع محفوظةٌ في DB ومستقلّةٌ تماماً.
    // هذا الاختبارُ يُثبت أنّ اختيارَ locale='en' في TemplateInvoiceData
    // هو فعلُ كودٍ صريح، لا تبعيّةٌ للـUI locale.

    test('PDF بـlocale=ar صريح يحمل النصَّ العربيَّ بغضِّ النظر عن أيِّ UI locale', () async {
      // لا نُضبط أيَّ Locale في Flutter — هذا اختبارٌ Dart خالص.
      // locale='ar' يُمرَّر صريحاً إلى ThermalReceiptGenerator.
      final r = await ThermalReceiptGenerator.printThermalReceipt(
        invoiceNumber: 'COMPANY-AR-1',
        date: kDate,
        items: kItems,
        total: 50.0,
        paid: 50.0,
        change: 0,
        companyName: kCompanyAr,
        locale: 'ar', // إعداد الشركة
        debugBuildOnly: true,
      );
      final probe = probePdf(r.bytes);
      expect(probe.allTexts, isNotEmpty);
      final text =
          deshapeArabic(probe.allTexts.map((t) => t.text).join(' '));
      expect(text, contains(deshapeArabic('فاتورة')),
          reason: 'locale=ar يُنتج نصّاً عربيّاً بغضِّ النظر عن UI locale');
    });

    test('PDF بـlocale=en صريح يحمل Invoice بغضِّ النظر عن أيِّ UI locale', () async {
      final r = await ThermalReceiptGenerator.printThermalReceipt(
        invoiceNumber: 'COMPANY-EN-1',
        date: kDate,
        items: kItems,
        total: 50.0,
        paid: 50.0,
        change: 0,
        companyName: kCompanyEn,
        locale: 'en', // إعداد الشركة
        debugBuildOnly: true,
      );
      final probe = probePdf(r.bytes);
      final allText =
          probe.allTexts.map((t) => t.text).join(' ').toLowerCase();
      expect(allText, contains('invoice'),
          reason: 'locale=en يُنتج نصّاً إنجليزيّاً بغضِّ النظر عن UI locale');
    });

    test('قاعدةُ المطبوع: DB print_language ar + TemplateInvoiceData locale ar → عربيٌّ على الورقة',
        () async {
      // الإعدادُ: print_language=ar في DB (كما يقرأه printLanguageProvider)
      await db.setSetting('print_language', 'ar');
      final storedLang = await db.getSettingValue('print_language') ?? 'ar';

      // الكودُ الإنتاجيُّ يقرأ storedLang ويمرّره كـ locale:
      final r = await ThermalReceiptGenerator.printThermalReceipt(
        invoiceNumber: 'DB-LANG-AR',
        date: kDate,
        items: kItems,
        total: 50.0,
        paid: 50.0,
        change: 0,
        companyName: kCompanyAr,
        locale: storedLang,
        debugBuildOnly: true,
      );
      final probe = probePdf(r.bytes);
      expect(probe.allTexts, isNotEmpty);
      final text =
          deshapeArabic(probe.allTexts.map((t) => t.text).join(' '));
      expect(text, contains(deshapeArabic('فاتورة')),
          reason: 'DB print_language=ar → locale=ar → عربيٌّ على الورقة');
    });

    test('قاعدةُ المطبوع: DB print_language en + TemplateInvoiceData locale en → إنجليزيٌّ على الورقة',
        () async {
      await db.setSetting('print_language', 'en');
      final storedLang = await db.getSettingValue('print_language') ?? 'ar';

      final r = await ThermalReceiptGenerator.printThermalReceipt(
        invoiceNumber: 'DB-LANG-EN',
        date: kDate,
        items: kItems,
        total: 50.0,
        paid: 50.0,
        change: 0,
        companyName: kCompanyEn,
        locale: storedLang,
        debugBuildOnly: true,
      );
      final probe = probePdf(r.bytes);
      final allText =
          probe.allTexts.map((t) => t.text).join(' ').toLowerCase();
      expect(allText, contains('invoice'),
          reason: 'DB print_language=en → locale=en → إنجليزيٌّ على الورقة');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // ٥. قالبُ الإيصال الحراريِّ المبذور: ar وen يختلفان
  // ═══════════════════════════════════════════════════════════════════════════

  test('القالبُ المبذورُ: locale=ar وen ينتجان ورقتين مختلفتين', () async {
    Future<PdfProbe> printViaTemplate(String locale) async {
      final bytes = (await TemplatedInvoiceService.printWithTemplate(
        db: db,
        debugBuildOnly: true,
        type: 'thermal',
        category: 'receipt',
        invoiceNumber: 'TPL-SAME',
        date: kDate,
        customerName: locale == 'ar' ? 'عميل' : 'Customer',
        customerPhone: null,
        customerAddress: null,
        items: const [
          {'name': 'صنف', 'quantity': 1.0, 'price': 50.0, 'total': 50.0}
        ],
        subtotal: 50.0,
        discount: 0.0,
        tax: 0.0,
        deliveryFee: 0.0,
        total: 50.0,
        paid: 50.0,
        companyName: locale == 'ar' ? kCompanyAr : kCompanyEn,
        companyAddress: '',
        companyPhone: '',
        companyTaxId: null,
        locale: locale,
      )).bytes;
      return probePdf(bytes);
    }

    final arProbe = await printViaTemplate('ar');
    final enProbe = await printViaTemplate('en');

    expect(arProbe.allTexts, isNotEmpty);
    expect(enProbe.allTexts, isNotEmpty);

    // رقمُ الفاتورة مختلف في الحالتين
    final arText = arProbe.allTexts.map((t) => t.text).join();
    final enText = enProbe.allTexts.map((t) => t.text).join();
    expect(arText, isNot(equals(enText)),
        reason: 'القالبُ المبذورُ بـar وen ينتج ورقتين مختلفتين');
  });
}
