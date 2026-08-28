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
import 'package:ural_erp/data/database/database.dart';
import 'package:ural_erp/services/templated_invoice_service.dart';

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
        (t) => t.type == 'a4' && t.templateCategory == 'invoice');
    await db.setDefaultTemplate(t.id);

    final withoutType = probePdf(await _render(db, t));
    final withType = probePdf(await _render(db, t, documentType: 'sales_invoice'));

    expect(withType.fingerprint(), withoutType.fingerprint(),
        reason: 'استشارةُ السلسلة غيّرت المطبوعَ وجدولُ الرابطات فارغ');
  });

  test('رابطةٌ تُحوّل المطبوعَ إلى قالبٍ آخر', () async {
    // قالبان في نفس (النوع، الفئة): الأوّلُ افتراضيٌّ بالعَلَم، والثاني
    // مربوطٌ بـ`sales_invoice`. فالرابطةُ يجب أن تتقدّم.
    final defaultId = await _import(db, 'a4_sales_tax_invoice.json');
    final boundId = await _import(db, 'a4_commercial.json');
    await db.setDefaultTemplate(defaultId);

    final before = probePdf(await _render(
      db,
      (await db.getTemplateById(defaultId))!,
      documentType: 'sales_invoice',
    ));

    await db.activateBinding(
      templateId: boundId,
      documentType: 'sales_invoice',
    );

    final after = probePdf(await _render(
      db,
      (await db.getTemplateById(defaultId))!,
      documentType: 'sales_invoice',
    ));

    expect(after.fingerprint(), isNot(equals(before.fingerprint())),
        reason: 'الرابطةُ كُتبت ولم تصل الورقةَ — الحلقةُ مكسورة');

    // والمقيسُ أنّه **القالبُ المربوطُ بعينه** لا «شيءٌ تغيّر»: لكلٍّ منهما
    // عنوانٌ ثابتٌ لا يوجد في الآخر.
    final boundData = await db.getTemplateWithData(boundId);
    final direct = probePdf(await TemplatedInvoiceService.printWithTemplate(
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
    ));
    expect(after.fingerprint(), direct.fingerprint(),
        reason: 'حُسم قالبٌ ثالثٌ لا هذا ولا ذاك');
  });

  test('فكُّ الرابطة يُعيد الحسمَ إلى الافتراضيّ', () async {
    final defaultId = await _import(db, 'a4_sales_tax_invoice.json');
    final boundId = await _import(db, 'a4_commercial.json');
    await db.setDefaultTemplate(defaultId);
    final t = (await db.getTemplateById(defaultId))!;

    final base = probePdf(await _render(db, t, documentType: 'sales_invoice'));

    await db.activateBinding(
        templateId: boundId, documentType: 'sales_invoice');
    await db.deactivateBinding(documentType: 'sales_invoice');

    final back = probePdf(await _render(db, t, documentType: 'sales_invoice'));
    expect(back.fingerprint(), base.fingerprint(),
        reason: 'الفكُّ لم يُعِد الحسم — رابطةٌ ميّتةٌ تبقى تحكم الورق');
  });

  test('ضابط: حسمٌ منهارٌ لا يُسقِط المطبوع', () async {
    // نوعُ مستندٍ لا تعرفه السلسلةُ — يجب أن يسقط إلى الافتراضيّ لا أن
    // يرمي. فاتورةٌ لا تُطبع أسوأُ من فاتورةٍ بقالبٍ عامّ.
    await db.seedDefaultTemplates();
    final t = (await db.getAllTemplates()).firstWhere(
        (t) => t.type == 'a4' && t.templateCategory == 'invoice');
    await db.setDefaultTemplate(t.id);

    final probe = probePdf(
        await _render(db, t, documentType: 'نوعٌ_لا_وجودَ_له'));
    expect(probe.allTexts, isNotEmpty,
        reason: 'نوعُ مستندٍ مجهولٌ أسقط الطباعةَ بدل أن يسقط مستوىً');
  });
}

// ═══════════════════════════════════════════════════════════════════════════

Future<int> _import(AppDatabase db, String file) async =>
    db.importTemplateFromJson(await File('$_assetDir/$file').readAsString());

Future<Uint8List> _render(
  AppDatabase db,
  InvoiceTemplate t, {
  String? documentType,
}) =>
    TemplatedInvoiceService.printWithTemplate(
      db: db,
      debugBuildOnly: true,
      type: t.type,
      category: t.templateCategory,
      documentType: documentType,
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
    );
