// بوّابةُ `hasDefaultTemplate` تتفق مع ما تحسمه الطباعةُ فعلاً.
//
// العطبُ: البوّابةُ كانت تتحقق من `is_default` وحدَه، بينما الطباعةُ تحسم
// بالروابط (`template_bindings`) أولاً. فمن ربط قالباً بنوع مستندٍ ولا
// افتراضيَّ له بالفئة كانت البوّابةُ تقول «لا قالب» فيُطبع بالمولّد الثابت
// صامتاً. هنا: ربطٌ بلا افتراضيّ ⇒ يُطبع بالقالب المربوط.

import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/data/database/database.dart';
import 'package:picpos_erp/data/providers/template_library_providers.dart'
    show effectiveTemplateIds;
import 'package:picpos_erp/services/templated_invoice_service.dart';

import '../helpers/pdf_probe.dart';
import '../helpers/printing_characterization_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  setUp(() async {
    db = AppDatabase.forTesting();
    // القاعدةُ التجريبيةُ تبذر افتراضيّاتٍ؛ نُسقطها كي يكون الحسمُ للرابطة
    // وحدَها — هذا هو الحالُ الذي يخصّه الاختبار.
    await db.update(db.invoiceTemplates).write(
        const InvoiceTemplatesCompanion(isDefault: Value(false)));
  });
  tearDown(() => db.close());

  Future<int> importBound() async => db.importTemplateFromJson(
      await File('assets/invoice_templates/a4_commercial.json')
          .readAsString());

  Future<dynamic> render(InvoiceTemplate t, {String? documentType}) async =>
      (await TemplatedInvoiceService.printWithTemplate(
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
      ))
          .bytes;

  test('ربطٌ بلا افتراضيّ ⇒ البوّابةُ تفتح والطباعةُ بالقالب المربوط', () async {
    final id = await importBound();
    final t = (await db.getTemplateById(id))!;
    expect(t.isDefault, isFalse, reason: 'الفرضية: لا افتراضيَّ بالفئة');
    expect(await db.getDefaultTemplateByCategory('a4', 'invoice'), isNull);

    // قبل الربط: لا قالبَ ⇒ الطباعةُ تسقط للمولّد الثابت.
    expect(
      await TemplatedInvoiceService.hasDefaultTemplate(db, 'a4',
          category: 'invoice', documentType: 'sales_invoice'),
      isFalse,
    );

    await db.activateBinding(templateId: id, documentType: 'sales_invoice');

    // البوّابةُ القديمةُ (بلا documentType) كانت تقول لا — وهذا العطب.
    expect(
      await TemplatedInvoiceService.hasDefaultTemplate(db, 'a4',
          category: 'invoice'),
      isFalse,
    );
    expect(
      await TemplatedInvoiceService.hasDefaultTemplate(db, 'a4',
          category: 'invoice', documentType: 'sales_invoice'),
      isTrue,
      reason: 'ربطٌ بلا افتراضيّ يُطبع بالمولّد الثابت صامتاً',
    );

    // الواجهةُ تتفق: القالبُ المربوطُ هو الفعّال.
    expect(await effectiveTemplateIds(db), contains(id));

    // والطباعةُ تخرج بالقالب المربوط لا بالثابت: تطابقُ بصمتها مع بصمة نفس
    // القالب حين يُجعل افتراضياً ويُطبع بلا documentType (مسارٌ مستقلّ).
    final viaBinding = probePdf(await render(t, documentType: 'sales_invoice'));
    expect(viaBinding.allTexts, isNotEmpty);
    await db.setDefaultTemplate(id);
    final viaDefault = probePdf(await render(t));
    expect(viaBinding.fingerprint(), viaDefault.fingerprint());
  });

  test('افتراضيٌّ بالعَلَم بلا ربط ما زال يفتح البوّابة ويُحسب فعّالاً', () async {
    await db.seedDefaultTemplates();
    final t = (await db.getAllTemplates()).firstWhere(
        (t) => t.type == 'a4' && t.templateCategory == 'invoice');
    await db.setDefaultTemplate(t.id);

    expect(
      await TemplatedInvoiceService.hasDefaultTemplate(db, 'a4',
          category: 'invoice', documentType: 'sales_invoice'),
      isTrue,
    );
    expect(await effectiveTemplateIds(db), contains(t.id));
  });
  test('لا ربط ولا افتراضيّ ⇒ لا فعّال', () async {
    final id = await importBound();
    expect(await effectiveTemplateIds(db), isNot(contains(id)));
  });
}
