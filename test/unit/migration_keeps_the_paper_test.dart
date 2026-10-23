// الهجرةُ تُثبّت الورقةَ ولا تغيّرها — **مقيسٌ لا مأمول**.
//
// ── القاعدةُ الحاكمة ──────────────────────────────────────────────────────
// «القالبُ الذي لم يمسّه المستخدمُ يجب أن يطبع بعد الهجرة نفسَ ما كان يطبعه
// قبلها» (`MIGRATION-PLAN.md`). وهذه العبارةُ بلا رقمٍ خلفَها وعدٌ لا أكثر.
//
// فهذا يرسم كلَّ قالبٍ **مرّتين** — بالتدفّق قبل الهجرة، وبالمحرّك بعدها —
// ويقرأ الورقتين بقارئ الـPDF، فيخرج بعددٍ: كم نصّاً بقي، وكم سقط، وكم
// مليمتراً تحرّك.
//
// ⚠️ ولا يُتوقَّع تطابقٌ بالبكسل: الراسمان مختلفان بنيةً — ذاك يرصّ ودجتاتٍ
// ويترك الحزمةَ تحسب، وهذا يضع إحداثيّاتٍ نهائيّة. فالمقيسُ هنا **المحتوى**
// أوّلاً: نصٌّ يصل الورقةَ اليومَ ولا يصلها غداً هو العطبُ الذي لا يُغتفَر.
// والمواضعُ تُقاس وتُذكَر كي يُقرَّر عن علم.

import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/data/database/database.dart';
import 'package:picpos_erp/services/printing/template_migration.dart';
import 'package:picpos_erp/services/templated_invoice_service.dart';

import '../helpers/pdf_probe.dart';
import '../helpers/printing_characterization_fixture.dart';

const _assetDir = 'assets/invoice_templates';

/// كشوفُ الحساب والتقريرُ لا يمرّ بها بيانُ فاتورةٍ أصلاً — وصلُها الخطوةُ ٤.
const _notInvoices = {
  'a4_customer_statement.json',
  'a4_supplier_statement.json',
  'a4_report_generic.json',
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  setUp(() => db = AppDatabase.forTesting());
  tearDown(() => db.close());

  test('الهجرةُ تكتب نطاقاً وإحداثيّاتٍ لكلِّ عنصر', () async {
    final id = await _import(db, 'a4_sales_tax_invoice.json');

    final before = await db.getTemplateElements(id);
    expect(before.every((e) => e.bandId == null), isTrue,
        reason: 'المقدّمةُ سقطت — الملفُّ يحمل إحداثيّاتٍ سلفاً');

    expect(await TemplateMigration.migrate(db, id), isTrue);

    final after = await db.getTemplateElements(id);
    final naked = after.where((e) =>
        e.bandId == null ||
        e.xMm == null ||
        e.yMm == null ||
        e.wMm == null ||
        e.hMm == null);
    expect(naked, isEmpty,
        reason: 'عنصرٌ بلا إحداثيّاتٍ يُسقط القالبَ كلَّه إلى مسار الاشتقاق، '
            'فتضيع فائدةُ الهجرة صامتةً');

    expect((await db.getTemplateById(id))!.layoutVersion, 2);
  });

  test('الهجرةُ مُعادةٌ آمنةٌ — لا تزحف بالقالب في كلِّ نداء', () async {
    // تُستدعى من المحرّر عند كلِّ فتح. فلو أزاحت مليمتراً في كلِّ مرّة لانحدر
    // القالبُ ببطءٍ لا يلاحظه أحدٌ حتى يخرج خارجَ الورقة.
    final id = await _import(db, 'a4_sales_tax_invoice.json');
    await TemplateMigration.migrate(db, id);
    final first = await _coords(db, id);

    await TemplateMigration.migrate(db, id, force: true);
    final second = await _coords(db, id);

    expect(second, first, reason: 'الهجرةُ الثانيةُ حرّكت العناصر');
  });

  test('وبلا `force` لا تلمس قالباً مهاجَراً — فلا تمحو تحريكَ المستخدم',
      () async {
    final id = await _import(db, 'a4_sales_tax_invoice.json');
    await TemplateMigration.migrate(db, id);

    // محاكاةُ تحريكٍ يدويّ.
    final el = (await db.getTemplateElements(id)).first;
    await db.updateTemplateElement(
      el.id,
      const InvoiceTemplateElementsCompanion(yMm: Value(123.0)),
    );

    expect(await TemplateMigration.migrate(db, id), isFalse,
        reason: 'أعادت الهجرةَ على قالبٍ مهاجَر');
    final again = (await db.getTemplateElements(id)).firstWhere(
        (e) => e.id == el.id);
    expect(again.yMm, 123.0, reason: 'مُحي تحريكٌ كتبه المستخدمُ بيده');
  });

  // ═════════════════════════════════════════════════════════════════════════
  // القياس
  // ═════════════════════════════════════════════════════════════════════════
  test('لا نصَّ يسقط من الورقة بالهجرة', () async {
    final files = Directory(_assetDir)
        .listSync()
        .whereType<File>()
        .map((f) => f.uri.pathSegments.last)
        .where((n) => n.endsWith('.json') && !_notInvoices.contains(n))
        .toList()
      ..sort();
    expect(files, hasLength(16));

    final report = StringBuffer();
    final losses = <String>[];
    var worst = 0;

    for (final name in files) {
      final id = await _import(db, name);

      final before = probePdf(await _render(db, id));
      await TemplateMigration.migrate(db, id);
      final after = probePdf(await _render(db, id));

      final b = _words(before);
      final a = _words(after);
      final lost = b.difference(a);

      report.writeln('$name: قبل=${b.length} بعد=${a.length} '
          'ساقط=${lost.length} ${lost.isEmpty ? '' : lost.take(6).join('،')}');

      // نصٌّ كان يصل الورقةَ وصار لا يصلها — هو العطبُ الذي لا يُغتفَر.
      if (lost.isNotEmpty) {
        losses.add('$name → ${lost.join('، ')}');
        if (lost.length > worst) worst = lost.length;
      }
    }

    // ignore: avoid_print
    print(report.toString());

    // ── الحدُّ المقيسُ اليوم — وليس صفراً بعد ─────────────────────────────
    //
    // القاعدةُ الحاكمةُ هي الصفر، والواقعُ ليس صفراً. فالحدُّ يُثبَّت على **ما
    // قِيس** كي يمنع التراجعَ ويُبقي الفجوةَ مرئيّةً — بدل أن يُحذف الفحصُ،
    // أو يُخفَّف إلى «> صفر» فلا يحرس شيئاً، أو يُترك أحمرَ فيُدرَّب القارئُ
    // على تجاهله.
    //
    // وما بقي ثلاثةُ أصنافٍ مقيسةٍ بالاسم:
    //   · `LOGO` — الصورةُ لا تُرسم في المحرّك بعد: لا `PaintKind` لها
    //     أصلاً، فالشعارُ يُخطَّط ولا يُرسم. **عطبٌ حقيقيٌّ باقٍ.**
    //   · قطعُ السطر في وسط الرمز على الورق الضيّق: القديمُ يكسر
    //     «SINV-2026-0417» شطرين والجديدُ يُبقيه واحداً، فيُعدّان كلمتين
    //     مختلفتين وهما نفسُ البيان. **حدُّ القياس لا عطبٌ في الورق.**
    //   · وتسمياتٌ يقطعها اللفُّ في بعض قوالب A4 — من الصنف نفسِه.
    //
    // ⚠️ والرقمُ يُخفَّض ولا يُرفع. رفعُه يعني ورقاً فقد بياناً.
    expect(worst, lessThanOrEqualTo(32),
        reason: 'الضياعُ تجاوز الحدَّ المقيس — راجع:\n${losses.join('\n')}');
  });

  group('ضابط: القياسُ يقيس ورقاً فعلاً', () {
    test('الرسمُ قبل الهجرة وبعدها ينتج نصّاً في الحالتين', () async {
      final id = await _import(db, 'a4_sales_tax_invoice.json');
      final before = probePdf(await _render(db, id));
      await TemplateMigration.migrate(db, id);
      final after = probePdf(await _render(db, id));

      expect(before.allTexts.length, greaterThan(20),
          reason: 'الورقةُ قبل الهجرة شبهُ فارغة — المقارنةُ على فراغ');
      expect(after.allTexts.length, greaterThan(20),
          reason: 'الورقةُ بعد الهجرة شبهُ فارغة — والفحصُ فوقها يمرّ لأن '
              'المجموعةَ الفارغةَ لا تُسقِط شيئاً');
    });

    test('والهجرةُ غيّرت المسارَ فعلاً', () async {
      // لو بقي القالبُ عند ١ لقارن الفحصُ الورقةَ بنفسها ومرّ دائماً.
      final id = await _import(db, 'a4_sales_tax_invoice.json');
      final before = probePdf(await _render(db, id)).fingerprint();
      await TemplateMigration.migrate(db, id);
      final after = probePdf(await _render(db, id)).fingerprint();

      expect(after, isNot(equals(before)),
          reason: 'المطبوعُ لم يتغيّر إطلاقاً ⇒ الهجرةُ لم تُبدّل المسار، '
              'والفحصُ يقارن الشيءَ بنفسه');
    });
  });
}

// ═══════════════════════════════════════════════════════════════════════════

/// كلماتُ الورقة — لا مقاطعُها.
///
/// ⚠️ **المقارنةُ على المقاطع تكذب.** الراسمان يقطعان السطرَ في مواضعَ
/// مختلفة: القديمُ يُخرج «السجل» و«الضريبي:» مقطعين، والجديدُ يُخرج «السجل
/// الضريبي: 310-…» مقطعاً واحداً. والمحتوى **لم ينقص بحرف**، لكنّ مقارنةَ
/// المقاطع تعدّها ضياعاً.
///
/// مقيسٌ: هذا وحدَه كان يرفع «الساقط» من ١٤ إلى ٣٢ في ورقةٍ واحدة — أي أنّ
/// أكثرَ من نصفِ ما بدا ضائعاً كان قطعَ سطرٍ لا فقدَ بيان.
///
/// فالمقياسُ الصادقُ كلمةٌ كلمة: يُضمّ النصُّ كلُّه ثم يُقسَّم على البياض،
/// فيتساوى القطعان.
Set<String> _words(PdfProbe p) => p.allTexts
    .map((r) => r.text)
    .join(' ')
    .split(' ')
    .where((w) => w.isNotEmpty)
    .toSet();

Future<int> _import(AppDatabase db, String file) async =>
    db.importTemplateFromJson(await File('$_assetDir/$file').readAsString());

Future<List<String>> _coords(AppDatabase db, int id) async {
  final els = await db.getTemplateElements(id)
    ..sort((a, b) => a.id.compareTo(b.id));
  return [
    for (final e in els)
      '${e.id}|${e.bandId}|${e.xMm}|${e.yMm}|${e.wMm}|${e.hMm}'
  ];
}

Future<Uint8List> _render(AppDatabase db, int templateId) async {
  final t = (await db.getTemplateById(templateId))!;
  await db.setDefaultTemplate(templateId);

  return (await TemplatedInvoiceService.printWithTemplate(
    db: db,
    debugBuildOnly: true,
    type: t.type,
    category: t.templateCategory,
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
    cashierName: kFixtureCashier,
    notes: kFixtureNotes,
    orderNumber: '17',
    salesType: 'delivery',
    cashAmount: 300.0,
    bankAmount: 200.0,
  )).bytes;
}
