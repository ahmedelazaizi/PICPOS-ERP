// ═══════════════════════════════════════════════════════════════════════════
// الاسمُ الإنجليزيُّ والسجلُّ التجاريُّ على المطبوع
// ═══════════════════════════════════════════════════════════════════════════
//
// معالجُ الإعداد يحفظ `company_name_en` و`company_cr_number` ولم يكن مطبوعٌ
// يقرؤهما. القاعدة (‏`domain/printing/company_identity.dart`):
//   • مستندٌ إنجليزيّ: الاسمُ الإنجليزيُّ هو الرئيسيّ.
//   • مستندٌ عربيّ: العربيُّ رئيسيٌّ والإنجليزيُّ سطرٌ ثانويٌّ.
//   • السجلُّ بجوار الرقم الضريبيّ: «س.ت: …» / "CR: …".
//   • فارغٌ ⇒ لا شيء.
//
// المقيسُ **ما وصل الورقةَ** (‏`probePdf`) لا نصُّ المصدر، على: فاتورةِ A4
// وإيصالٍ حراريٍّ — من القالب المبذور ومن المولِّد الاحتياطيّ — بلغتَي المستند.

import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/database/database.dart';
import 'package:ural_erp/domain/printing/company_identity.dart';
import 'package:ural_erp/services/printing/printing_models.dart';
import 'package:ural_erp/services/printing/report_pdf_generator.dart';
import 'package:ural_erp/services/printing/thermal_receipt_generator.dart';
import 'package:ural_erp/services/templated_invoice_service.dart';

import '../helpers/arabic_pdf_text.dart';
import '../helpers/pdf_probe.dart';

const _nameAr = 'شركةُ النور';
const _nameEn = 'Al-Nour Trading Co';
const _cr = '1020304050';
const _tax = '310-123-456';

/// ما على الورقة بترتيبه **البصريّ**: سطراً سطراً من الأعلى، وكلُّ سطرٍ من
/// اليسار إلى اليمين.
///
/// ⚠️ لا بترتيب الرسم: الراسمُ يرسم في الصفحات العربيّة من اليمين إلى اليسار،
/// فنصٌّ لاتينيٌّ متعدّدُ الكلمات (‏`Al-Nour Trading Co`) يصل في مجرى المحتوى
/// بكلماتٍ معكوسةِ الترتيب مع أنّه على الورق سليم. والتوكيدُ على ترتيب الرسم
/// كان يُسقط ورقةً صحيحة (قِيس: «Co Trading» عند x=371 و«Trading» عند x=306
/// و«Al-Nour» أقصى اليسار).
String _flat(PdfProbe p) {
  final lines = <int, List<PdfTextRun>>{};
  for (final t in p.allTexts) {
    lines.putIfAbsent(t.page * 10000 - t.y.round() ~/ 3, () => []).add(t);
  }
  final keys = lines.keys.toList()..sort();
  final out = StringBuffer();
  for (final k in keys) {
    final runs = lines[k]!..sort((a, b) => a.x.compareTo(b.x));
    out.write('${runs.map((r) => r.text).join(' ')} ');
  }
  return deshapeArabic(out.toString());
}

/// الاسمُ العربيُّ يصل الورقةَ مشكَّلاً — يُقارَن بعد فكّ التشكيل.
final _crAr = deshapeArabic('س.ت');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('قواعد company_identity', () {
    test('مستندٌ إنجليزيّ: الاسمُ الإنجليزيُّ رئيسيّ', () {
      expect(
          companyDisplayName(nameAr: _nameAr, nameEn: _nameEn, locale: 'en'),
          _nameEn);
    });
    test('مستندٌ عربيّ: العربيُّ رئيسيٌّ والإنجليزيُّ تحته', () {
      expect(
          companyDisplayName(nameAr: _nameAr, nameEn: _nameEn, locale: 'ar'),
          '$_nameAr\n$_nameEn');
    });
    test('بلا اسمٍ إنجليزيٍّ لا يتغيّر شيء', () {
      for (final en in [null, '', '   ']) {
        expect(companyDisplayName(nameAr: _nameAr, nameEn: en), _nameAr);
        expect(
            companyDisplayName(nameAr: _nameAr, nameEn: en, locale: 'en'),
            _nameAr);
      }
    });
    test('السجلُّ: «س.ت» عربيّاً و"CR" إنجليزيّاً، وفارغٌ ⇒ لا شيء', () {
      expect(companyCrLine(_cr), contains('س.ت: '));
      expect(companyCrLine(_cr, locale: 'en'), contains('CR: '));
      expect(companyCrLine(''), '');
      expect(companyCrLine(null), '');
    });
    test('الرقمُ الضريبيُّ يحمل السجلَّ بجواره، وبلا ضريبيٍّ لا يُطبع سجلٌّ يتيم',
        () {
      final both = companyTaxWithCr(taxId: _tax, crNumber: _cr);
      expect(both, contains(_tax));
      expect(both, contains(_cr));
      expect(companyTaxWithCr(taxId: _tax, crNumber: ''), contains(_tax));
      expect(companyTaxWithCr(taxId: null, crNumber: _cr), '');
    });
  });

  group('القالبُ المبذور (قوالبُ v1/v2 عبر printWithTemplate)', () {
    late AppDatabase db;
    setUp(() async {
      db = AppDatabase.forTesting();
      await db.seedDefaultTemplates();
    });
    tearDown(() => db.close());

    Future<PdfProbe> render({
      required String type,
      required String category,
      required String locale,
      String? documentType,
    }) async {
      final r = await TemplatedInvoiceService.printWithTemplate(
        db: db,
        debugBuildOnly: true,
        type: type,
        category: category,
        documentType: documentType,
        invoiceNumber: 'IDN-001',
        date: DateTime(2026, 6, 1),
        customerName: 'عميل',
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
        companyName: _nameAr,
        companyAddress: 'عمّان',
        companyPhone: '0790000000',
        companyTaxId: _tax,
        locale: locale,
      );
      return probePdf(r.bytes);
    }

    Future<void> setIdentity({String en = _nameEn, String cr = _cr}) async {
      await db.setSetting(kCompanyNameEnSetting, en);
      await db.setSetting(kCompanyCrNumberSetting, cr);
    }

    final cases = <(String, String, String?)>[
      ('a4', 'invoice', 'sales_invoice'),
      ('thermal', 'receipt', 'sales_receipt'),
    ];

    for (final (type, category, docType) in cases) {
      group('$type/$category', () {
        test('عربيّ: الاسمُ الإنجليزيُّ ثانويٌّ والسجلُّ «س.ت» بجوار الضريبيّ',
            () async {
          await setIdentity();
          final text = _flat(await render(
              type: type, category: category, documentType: docType,
              locale: 'ar'));
          expect(text, contains(deshapeArabic('النور')),
              reason: 'الاسمُ العربيُّ يبقى الرئيسيّ');
          expect(text, contains(_nameEn));
          expect(text, contains(_cr));
          expect(text, contains(_crAr));
          // القالبُ الحراريُّ المبذور بلا عنصرِ رقمٍ ضريبيّ أصلاً (قبل هذا
          // العمل) — فالسجلُّ فيه سطرُه المستقلُّ، وبجوار الضريبيّ في A4.
          if (type == 'a4') {
            expect(text, contains(_tax), reason: 'الرقمُ الضريبيُّ لم يُمسَّ');
          }
        });

        test('إنجليزيّ: الاسمُ الإنجليزيُّ هو الرئيسيّ والسجلُّ "CR"', () async {
          await setIdentity();
          final text = _flat(await render(
              type: type, category: category, documentType: docType,
              locale: 'en'));
          expect(text, contains(_nameEn));
          expect(text, contains('CR:'));
          expect(text, contains(_cr));
          expect(text, isNot(contains(deshapeArabic('النور'))),
              reason: 'الاسمُ العربيُّ لا يزاحم الإنجليزيَّ في مستندٍ إنجليزيّ');
        });

        for (final locale in ['ar', 'en']) {
          test('فارغٌ ($locale): لا اسمَ إنجليزيّاً ولا سجلاً ولا تسميةً معلَّقة',
              () async {
            await setIdentity(en: '', cr: '');
            final text = _flat(await render(
                type: type, category: category, documentType: docType,
                locale: locale));
            expect(text, isNot(contains(_nameEn)));
            expect(text, isNot(contains(_cr)));
            expect(text, isNot(contains('CR:')));
            expect(text, isNot(contains(_crAr)));
          });
        }
      });
    }
  });

  group('المولِّداتُ الاحتياطيّة (بلا قالب)', () {
    Future<PdfProbe> thermal(String locale,
        {String? en = _nameEn, String? cr = _cr}) async {
      final r = await ThermalReceiptGenerator.printThermalReceipt(
        invoiceNumber: 'FB-T-1',
        date: DateTime(2026, 6, 1),
        items: [InvoiceItem(name: 'صنف', quantity: 1, price: 50, total: 50)],
        total: 50,
        paid: 50,
        change: 0,
        companyName: _nameAr,
        companyNameEn: en,
        companyCrNumber: cr,
        taxId: _tax,
        locale: locale,
        debugBuildOnly: true,
      );
      return probePdf(r.bytes);
    }

    Future<PdfProbe> a4(String locale,
        {String? en = _nameEn, String? cr = _cr}) async {
      final doc = await ReportPdfGenerator.buildSalesInvoiceDocument(
        invoiceNumber: 'FB-A-1',
        date: DateTime(2026, 6, 1),
        customerName: 'عميل',
        items: [InvoiceItem(name: 'صنف', quantity: 1, price: 50, total: 50)],
        subtotal: 50,
        discount: 0,
        tax: 0,
        total: 50,
        paid: 50,
        companyName: _nameAr,
        companyNameEn: en,
        companyCrNumber: cr,
        companyTaxId: _tax,
        locale: locale,
      );
      return probePdf(await doc.save());
    }

    // `en`/`cr` تُمرَّران صراحةً (‏`null` يعني «غيرُ مضبوط»)؛ والافتراضُ مضبوط.
    final builders = <String, Future<PdfProbe> Function(String, String?, String?)>{
      'thermal': (l, en, cr) => thermal(l, en: en, cr: cr),
      'A4': (l, en, cr) => a4(l, en: en, cr: cr),
    };

    builders.forEach((name, build) {
      test('$name عربيّ: اسمٌ إنجليزيٌّ ثانويٌّ + «س.ت»', () async {
        final text = _flat(await build('ar', _nameEn, _cr));
        expect(text, contains(deshapeArabic('النور')));
        expect(text, contains(_nameEn));
        expect(text, contains(_crAr));
        expect(text, contains(_cr));
        // ⚠️ الرقمُ الضريبيُّ لا يُفحَص هنا: المولّدُ الاحتياطيُّ لا يعزله بـ`LRM`
        // فيخرج `456-123-310` مقلوبَ المقاطع في صفحةٍ عربيّة — عطبٌ قائمٌ قبل
        // هذا العمل ولم يُلمس.
      });

      test('$name إنجليزيّ: الاسمُ الإنجليزيُّ رئيسيٌّ + "CR"', () async {
        final text = _flat(await build('en', _nameEn, _cr));
        expect(text, contains(_nameEn));
        expect(text, contains('CR:'));
        expect(text, contains(_cr));
        expect(text, isNot(contains(deshapeArabic('النور'))));
      });

      for (final locale in ['ar', 'en']) {
        test('$name فارغٌ ($locale): لا شيءَ يُطبع', () async {
          for (final empty in [null, '']) {
            final text = _flat(await build(locale, empty, empty));
            expect(text, isNot(contains(_nameEn)));
            expect(text, isNot(contains(_cr)));
            expect(text, isNot(contains('CR:')));
            expect(text, isNot(contains(_crAr)));
          }
        });
      }
    });
  });
}
