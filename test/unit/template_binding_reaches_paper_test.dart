// الرابطةُ تصل الورقةَ — لا تبقى صفّاً في جدول.
//
// ── الفجوةُ التي يسدّها ───────────────────────────────────────────────────
// جدولُ `TemplateBindings` والسلسلةُ السداسيّةُ في `template_resolver.dart`
// وDAO كاملٌ للتفعيل والفكّ والحسم — كلُّها مشحونة. و`grep` على مسار الطباعة
// يقول: **لا سطرَ يستشيرها**. القالبُ كان يُحسم بعَلَم `isDefault` وحدَه، وهو
// عَلَمٌ عالميٌّ لا يعرف فرعاً ولا طابعةً ولا لغة.
//
// فزرُّ «حفظ وتفعيل كافتراضي» في المكتبة — وهو الخطوةُ ٥ من فحص القبول —
// كان سيكتب رابطةً **لا تصل ورقةً أبداً**، والخطوتان ٦ و٧ مستحيلتان بنيوياً.
//
// وهذا يقيس الطرفين: أنّ الرابطةَ تُبدّل المطبوع، وأنّ غيابَها لا يُبدّله.

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/data/database/database.dart';
import 'package:picpos_erp/services/templated_invoice_service.dart';
import 'package:picpos_erp/services/printing/paper_compatibility.dart';

import '../helpers/pdf_probe.dart';
import '../helpers/printing_characterization_fixture.dart';

const _assetDir = 'assets/invoice_templates';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  setUp(() => db = AppDatabase.forTesting());
  tearDown(() => db.close());

  test('بلا رابطاتٍ يحسم كما كان — الافتراضيُّ بالفئة', () async {
    // السقوطُ إلى المستوى الأخير هو ما يجعل الوصلَ آمناً: قاعدةٌ قائمةٌ بلا
    // رابطةٍ واحدةٍ تطبع ما كانت تطبعه بالضبط.
    await db.seedDefaultTemplates();
    final t = (await db.getAllTemplates()).firstWhere(
      (t) => t.type == 'a4' && t.templateCategory == 'invoice',
    );
    await db.setDefaultTemplate(t.id);

    final withoutType = probePdf(await _render(db, t));
    final withType = probePdf(
      await _render(db, t, documentType: 'sales_invoice'),
    );

    expect(
      withType.fingerprint(),
      withoutType.fingerprint(),
      reason: 'استشارةُ السلسلة غيّرت المطبوعَ وجدولُ الرابطات فارغ',
    );
  });

  test('رابطةٌ تُحوّل المطبوعَ إلى قالبٍ آخر', () async {
    // قالبان في نفس (النوع، الفئة): الأوّلُ افتراضيٌّ بالعَلَم، والثاني
    // مربوطٌ بـ`sales_invoice`. فالرابطةُ يجب أن تتقدّم.
    final defaultId = await _import(db, 'a4_sales_tax_invoice.json');
    final boundId = await _import(db, 'a4_commercial.json');
    await db.setDefaultTemplate(defaultId);

    final before = probePdf(
      await _render(
        db,
        (await db.getTemplateById(defaultId))!,
        documentType: 'sales_invoice',
      ),
    );

    await db.activateBinding(
      templateId: boundId,
      documentType: 'sales_invoice',
    );

    final after = probePdf(
      await _render(
        db,
        (await db.getTemplateById(defaultId))!,
        documentType: 'sales_invoice',
      ),
    );

    expect(
      after.fingerprint(),
      isNot(equals(before.fingerprint())),
      reason: 'الرابطةُ كُتبت ولم تصل الورقةَ — الحلقةُ مكسورة',
    );

    // والمقيسُ أنّه **القالبُ المربوطُ بعينه** لا «شيءٌ تغيّر»: لكلٍّ منهما
    // عنوانٌ ثابتٌ لا يوجد في الآخر.
    final boundData = await db.getTemplateWithData(boundId);
    final direct = probePdf(
      (await TemplatedInvoiceService.printWithTemplate(
        db: db,
        debugBuildOnly: true,
        type: boundData!.template.type,
        category: boundData.template.templateCategory,
        documentType: 'sales_invoice',
        invoiceNumber: kFixtureInvoiceNumber,
        date: kFixtureDate,
        customerName: kFixtureCustomerName,
        customerPhone: kFixtureCustomerPhone,
        customerAddress: kFixtureCustomerAddress,
        items: kFixtureItems,
        subtotal: kFixtureSubtotal,
        discount: kFixtureDiscount,
        tax: kFixtureTax,
        deliveryFee: kFixtureDeliveryFee,
        total: kFixtureTotal,
        paid: kFixturePaid,
        companyName: kFixtureCompanyName,
        companyAddress: kFixtureCompanyAddress,
        companyPhone: kFixtureCompanyPhone,
        companyTaxId: kFixtureCompanyTaxId,
      )).bytes,
    );
    expect(
      after.fingerprint(),
      direct.fingerprint(),
      reason: 'حُسم قالبٌ ثالثٌ لا هذا ولا ذاك',
    );
  });

  test(
    'printerId reaches resolution and renders each printer binding',
    () async {
      final narrowId = await _import(db, 'thermal58_quick_sale.json');
      final wideId = await _import(db, 'thermal80_quick_sale.json');
      final narrowPrinter = await db.insertPrinter(
        name: 'printer 58',
        paperWidthMm: 58,
      );
      final widePrinter = await db.insertPrinter(
        name: 'printer 80',
        paperWidthMm: 80,
      );
      await db.activateBinding(
        documentType: 'sales_receipt',
        templateId: narrowId,
        branchId: 7,
        printerId: narrowPrinter,
        locale: 'ar',
      );
      await db.activateBinding(
        documentType: 'sales_receipt',
        templateId: wideId,
        branchId: 7,
        printerId: widePrinter,
        locale: 'ar',
      );

      final narrow = probePdf(
        await _render(
          db,
          (await db.getTemplateById(narrowId))!,
          documentType: 'sales_receipt',
          branchId: 7,
          printerId: narrowPrinter,
          locale: 'ar',
        ),
      );
      final wide = probePdf(
        await _render(
          db,
          (await db.getTemplateById(wideId))!,
          documentType: 'sales_receipt',
          branchId: 7,
          printerId: widePrinter,
          locale: 'ar',
        ),
      );
      final narrowDirect = probePdf(
        (await TemplatedInvoiceService.printWithTemplate(
          db: db,
          debugBuildOnly: true,
          type: 'thermal',
          category: 'receipt',
          documentType: 'sales_receipt',
          branchId: 7,
          printerId: narrowPrinter,
          locale: 'ar',
          invoiceNumber: kFixtureInvoiceNumber,
          date: kFixtureDate,
          customerName: kFixtureCustomerName,
          customerPhone: kFixtureCustomerPhone,
          customerAddress: kFixtureCustomerAddress,
          items: kFixtureItems,
          subtotal: kFixtureSubtotal,
          discount: kFixtureDiscount,
          tax: kFixtureTax,
          deliveryFee: kFixtureDeliveryFee,
          total: kFixtureTotal,
          paid: kFixturePaid,
          companyName: kFixtureCompanyName,
          companyAddress: kFixtureCompanyAddress,
          companyPhone: kFixtureCompanyPhone,
          companyTaxId: kFixtureCompanyTaxId,
        )).bytes,
      );

      expect(narrow.fingerprint(), narrowDirect.fingerprint());
      expect(narrow.fingerprint(), isNot(wide.fingerprint()));
    },
  );

  test('فكُّ الرابطة يُعيد الحسمَ إلى الافتراضيّ', () async {
    final defaultId = await _import(db, 'a4_sales_tax_invoice.json');
    final boundId = await _import(db, 'a4_commercial.json');
    await db.setDefaultTemplate(defaultId);
    final t = (await db.getTemplateById(defaultId))!;

    final base = probePdf(await _render(db, t, documentType: 'sales_invoice'));

    await db.activateBinding(
      templateId: boundId,
      documentType: 'sales_invoice',
    );
    await db.deactivateBinding(documentType: 'sales_invoice');

    final back = probePdf(await _render(db, t, documentType: 'sales_invoice'));
    expect(
      back.fingerprint(),
      base.fingerprint(),
      reason: 'الفكُّ لم يُعِد الحسم — رابطةٌ ميّتةٌ تبقى تحكم الورق',
    );
  });

  group('المطبخ — كان يتخطّى السلسلةَ كلَّها', () {
    // كان النداءُ يتفرّع قبل الحسم: `category == 'kitchen'` ⇒
    // `getDefaultTemplateWithData('kitchen')` مباشرةً. فأمرُ المطبخ لا يعرف
    // رابطةً ولا فرعاً ولا طابعة، ومطعمٌ بمحطّتَي تحضيرٍ لا يستطيع أن يعطي
    // كلَّ محطّةٍ قالبَها.
    test('بلا رابطةٍ يحسم كما كان — بالنوع لا بالفئة', () async {
      // ⚠️ والفهرسةُ بالنوع وحدَه ليست تفضيلاً: ملفُّ
      // `kitchen_professional.json` بلا `templateCategory` فيُستورد فئتُه
      // `receipt`. فالبحثُ بـ(kitchen, kitchen) يُفلته.
      await db.seedDefaultTemplates();
      final t = (await db.getAllTemplates()).firstWhere(
        (t) => t.type == 'kitchen',
      );

      final probe = probePdf(
        await _render(db, t, documentType: 'kitchen_order'),
      );
      expect(
        probe.allTexts,
        isNotEmpty,
        reason: 'أمرُ المطبخ لم يجد قالبَه بعد إدخاله السلسلة',
      );
    });

    test('ورابطةٌ تُحوّله إلى قالبٍ آخر', () async {
      await db.seedDefaultTemplates();
      final seeded = (await db.getAllTemplates()).firstWhere(
        (t) => t.type == 'kitchen',
      );
      final other = await _import(db, 'kitchen_professional.json');

      final before = probePdf(
        await _render(db, seeded, documentType: 'kitchen_order'),
      );

      await db.activateBinding(
        templateId: other,
        documentType: 'kitchen_order',
      );

      final after = probePdf(
        await _render(db, seeded, documentType: 'kitchen_order'),
      );

      expect(
        after.fingerprint(),
        isNot(equals(before.fingerprint())),
        reason:
            'رابطةُ المطبخ لا تصل الورقةَ — الفرعُ ما زال يتخطّى '
            'السلسلة',
      );
    });
  });

  test(
    'فاتورة البيع والمرتجع يختاران قالب الطابعة المربوطة عند الطباعة',
    () async {
      final invoiceBase = await _import(db, 'a4_sales_tax_invoice.json');
      final invoiceBound = await _import(db, 'a4_commercial.json');
      final returnBase = await _import(db, 'a4_sales_return.json');
      final returnBound = await _import(db, 'thermal80_sales_return.json');
      final a4Printer = await db.insertPrinter(
        name: 'A4 route',
        printerType: 'laser',
        paperWidthMm: 210,
      );
      final secondPrinter = await db.insertPrinter(
        name: 'Second A4 route',
        printerType: 'laser',
        paperWidthMm: 210,
      );

      for (final entry in [
        ('sales_invoice', invoiceBase, invoiceBound, 'invoice'),
        ('sales_return', returnBase, returnBound, 'sales_return'),
      ]) {
        await db.activateBinding(
          templateId: entry.$2,
          documentType: entry.$1,
          printerId: a4Printer,
          locale: 'ar',
          printerWidthMm: 210,
        );
        await db.activateBinding(
          templateId: entry.$3,
          documentType: entry.$1,
          printerId: secondPrinter,
          locale: 'ar',
          printerWidthMm: 210,
        );
        final context = entry.$1 == 'sales_invoice'
            ? (type: 'a4', category: entry.$4)
            : (type: 'a4', category: entry.$4);
        final resolvedA4 = await db.resolveTemplateFor(
          documentType: entry.$1,
          category: context.category,
          printerId: a4Printer,
          locale: 'ar',
          paperType: context.type,
        );
        final resolvedThermal = await db.resolveTemplateFor(
          documentType: entry.$1,
          category: context.category,
          printerId: secondPrinter,
          locale: 'ar',
          paperType: context.type,
        );
        expect(
          resolvedA4.templateId,
          entry.$2,
          reason: '${entry.$1} A4 printer',
        );
        expect(
          resolvedThermal.templateId,
          entry.$3,
          reason: '${entry.$1} second printer',
        );

        final a4Bytes = probePdf(
          await _render(
            db,
            (await db.getTemplateById(entry.$2))!,
            documentType: entry.$1,
            printerId: a4Printer,
            locale: 'ar',
          ),
        );
        final thermalBytes = probePdf(
          await _render(
            db,
            (await db.getTemplateById(entry.$3))!,
            documentType: entry.$1,
            printerId: secondPrinter,
            locale: 'ar',
          ),
        );
        expect(a4Bytes.fingerprint(), isNot(thermalBytes.fingerprint()));
      }
    },
  );

  test('حراري 58/80 على A4 تحذير مفهوم وA4 على الحراري رفض مفهوم', () async {
    for (final width in [58.0, 80.0]) {
      final verdict = checkPaperFit(
        templateWidthMm: width,
        printerWidthMm: 210,
      );
      expect(verdict.isWarning, isTrue);
      expect(verdict.reason, contains('${width.toStringAsFixed(0)}مم'));
      expect(verdict.reason, contains('210مم'));
      expect(verdict.reason, contains('هامش'));
    }
    final rejected = checkPaperFit(templateWidthMm: 210, printerWidthMm: 80);
    expect(rejected.isRejected, isTrue);
    expect(rejected.reason, contains('سيُقصّ المطبوع'));
  });

  test('ضابط: حسمٌ منهارٌ لا يُسقِط المطبوع', () async {
    // نوعُ مستندٍ لا تعرفه السلسلةُ — يجب أن يسقط إلى الافتراضيّ لا أن
    // يرمي. فاتورةٌ لا تُطبع أسوأُ من فاتورةٍ بقالبٍ عامّ.
    await db.seedDefaultTemplates();
    final t = (await db.getAllTemplates()).firstWhere(
      (t) => t.type == 'a4' && t.templateCategory == 'invoice',
    );
    await db.setDefaultTemplate(t.id);

    final probe = probePdf(
      await _render(db, t, documentType: 'نوعٌ_لا_وجودَ_له'),
    );
    expect(
      probe.allTexts,
      isNotEmpty,
      reason: 'نوعُ مستندٍ مجهولٌ أسقط الطباعةَ بدل أن يسقط مستوىً',
    );
  });
}

// ═══════════════════════════════════════════════════════════════════════════

Future<int> _import(AppDatabase db, String file) async =>
    db.importTemplateFromJson(await File('$_assetDir/$file').readAsString());

Future<Uint8List> _render(
  AppDatabase db,
  InvoiceTemplate t, {
  String? documentType,
  int? branchId,
  int? printerId,
  String? locale,
}) async => (await TemplatedInvoiceService.printWithTemplate(
  db: db,
  debugBuildOnly: true,
  type: t.type,
  category: t.templateCategory,
  documentType: documentType,
  branchId: branchId,
  printerId: printerId,
  locale: locale ?? 'ar',
  invoiceNumber: kFixtureInvoiceNumber,
  date: kFixtureDate,
  customerName: kFixtureCustomerName,
  customerPhone: kFixtureCustomerPhone,
  customerAddress: kFixtureCustomerAddress,
  items: kFixtureItems,
  subtotal: kFixtureSubtotal,
  discount: kFixtureDiscount,
  tax: kFixtureTax,
  deliveryFee: kFixtureDeliveryFee,
  total: kFixtureTotal,
  paid: kFixturePaid,
  companyName: kFixtureCompanyName,
  companyAddress: kFixtureCompanyAddress,
  companyPhone: kFixtureCompanyPhone,
  companyTaxId: kFixtureCompanyTaxId,
)).bytes;
