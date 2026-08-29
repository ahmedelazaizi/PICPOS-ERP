// المسارُ الثاني — `layout_version == 2` يصل الورقةَ فعلاً.
//
// ── لماذا هذا الملفّ ──────────────────────────────────────────────────────
// المحرّكُ كان جزيرةً: `TemplateMapper` و`LayoutEngine` و`planPage`
// و`PdfPainter` مشحونةٌ ومُختبَرةٌ بثمانيةِ اختباراتِ منعِ انتكاس، والأعمدةُ
// في المخطَّط — و**لا سطرَ في `lib/` يقرأ أيّاً منها**. فكان يمكن أن يمرّ
// المشروعُ كلُّه أخضرَ والمطبوعُ لم يلمس المحرّكَ قطّ.
//
// فهذه تقيس الوصلَ نفسَه: هل تدخل البوّابةُ؟ وهل يخرج ورقٌ فيه بيانات؟ وهل
// **يصل الإحداثيُّ** الورقةَ — وهو الشيءُ الوحيدُ الذي لا يستطيعه المسارُ
// القديمُ بحال، والخطوةُ ٣ من فحص القبول.

import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/database/database.dart';
import 'package:ural_erp/services/templated_invoice_service.dart';

import '../helpers/pdf_probe.dart';
import '../helpers/printing_characterization_fixture.dart';

const _assetDir = 'assets/invoice_templates';

/// ٥ مم بالنقاط — وحدةُ القياس في هذا الملفّ كلِّه.
const double _fiveMmPts = 5 * 72 / 25.4; // ١٤٫١٧٣

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  setUp(() => db = AppDatabase.forTesting());
  tearDown(() => db.close());

  // ═════════════════════════════════════════════════════════════════════════
  // البوّابة
  // ═════════════════════════════════════════════════════════════════════════
  group('بوّابةُ نسخة التخطيط', () {
    test('القالبُ عند ١ يسلك المسارَ القديم — والمطبوعُ لا يتغيّر', () async {
      final id = await _import(db, 'a4_sales_tax_invoice.json');
      final v1 = probePdf(await _render(db, id));

      // إعادةُ رسمٍ ثانيةٍ بلا أيّ تغيير — نفسُ الورقة بالضبط.
      final again = probePdf(await _render(db, id));
      expect(again.fingerprint(), v1.fingerprint(),
          reason: 'المسارُ القديمُ صار غيرَ حتميّ — وهو أوّلُ ما يُفسد بصمة');
    });

    test('الترقيةُ إلى ٢ تُبدّل المطبوعَ فعلاً — البوّابةُ ليست زينة', () async {
      final id = await _import(db, 'a4_sales_tax_invoice.json');
      final v1 = probePdf(await _render(db, id));

      await _setVersion(db, id, 2);
      final v2 = probePdf(await _render(db, id));

      expect(v2.fingerprint(), isNot(equals(v1.fingerprint())),
          reason: 'بوّابةٌ لا تُغيّر شيئاً تعني أن المحرّكَ لم يُنادَ أصلاً');
      expect(v2.allTexts, isNotEmpty,
          reason: 'المسارُ الجديدُ أخرج ورقةً فارغة — أسوأُ من ألّا يُوصَل');
    });

    test('كلُّ ملفِّ أصولٍ يخرج بورقٍ فيه بياناتٌ تحت النسخة ٢', () async {
      final files = _assetFiles();
      expect(files.length, 19);

      final empty = <String>[];
      final missingNumber = <String>[];

      for (final f in files) {
        final id = await db.importTemplateFromJson(await f.readAsString());
        await _setVersion(db, id, 2);
        final probe = probePdf(await _render(db, id));

        final name = f.uri.pathSegments.last;
        if (probe.allTexts.length < 5) empty.add(name);

        // ورقةٌ فيها نصٌّ ليست ورقةً فيها **بيانات**: قالبٌ يطبع عناوينَه
        // الثابتةَ ويسقط كلَّ قيمةٍ يمرّ هذا الفحصَ لو اكتفينا بالعدّ.
        final all = probe.allTexts.map((r) => r.text).join(' ');
        final carriesData = all.contains(kFixtureInvoiceNumber) ||
            all.contains('626.76') ||
            all.contains('14/3/2026');
        if (!carriesData) missingNumber.add(name);
      }

      expect(empty, isEmpty,
          reason: 'هذه القوالبُ تخرج شبهَ فارغةٍ تحت المحرّك الجديد');

      // ── ثلاثةٌ لا تحمل بيانَ فاتورةٍ **بحقّ** ─────────────────────────
      //
      // كشفا الحساب والتقريرُ العامُّ مستنداتٌ من نوعٍ آخر: حقولُها
      // `period_from` و`opening_balance` و`total_debit` و`ledger_table` و
      // `report_title` — ولا يمرّ بها رقمُ فاتورةٍ ولا إجماليُّها.
      // و`report_pdf_generator.dart` لا يقرأ القوالبَ إطلاقاً بعد.
      //
      // فوصلُها هو **الخطوة ٤** (`EXTENSION-SPEC.md`). والقائمةُ مساواةٌ لا
      // احتواء: حين تُوصَل يسقط هذا الفحصُ ويُجبِر على تقليصها — استثناءٌ
      // يتقاعد بنفسه بدل أن يتحجّر.
      expect(
        missingNumber..sort(),
        const [
          'a4_customer_statement.json',
          'a4_report_generic.json',
          'a4_supplier_statement.json',
        ],
        reason: 'قالبٌ فاتورةٍ صار لا يطبع بياناً، أو كشفُ حسابٍ صار يطبعه',
      );
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  // الإحداثيُّ يصل الورقة — وهو ما لا يستطيعه المسارُ القديم
  // ═════════════════════════════════════════════════════════════════════════
  group('النطاقاتُ بإحداثيّاتٍ بالمليمتر', () {
    // المرساةُ عنصرٌ **نزرعه بأنفسنا** بنصٍّ فريد. مرساةٌ مأخوذةٌ من محتوى
    // القالب تلتقط عنصراً آخرَ حين يتكرّر النصّ، فيقيس الاختبارُ شيئاً لم
    // نُحرّكه ويمرّ أو يسقط لسببٍ لا علاقةَ له بالمقصود.
    const marker = 'MARKER-QZ7';

    test('سحبُ عنصرٍ ٥ مم لأعلى يرفعه ٥ مم على الورق — بالمقدار', () async {
      final id = await _importPositioned(db, 'a4_sales_tax_invoice.json');
      // ⚠️ ‏٢٠ لا ٤٠. القياسُ فرقُ موضعٍ **على نفس الصفحة**، وانقسامُ ورقةٍ
      //    بين الرسمتين يجعل الفرقَ ارتفاعَ صفحةٍ لا خمسةَ مليمترات.
      //    وكان ٤٠ يضع المستندَ عند ٢٨٩٫٨مم من ٢٨٧ متاحة — أي صفحتان — ثمّ
      //    يعيده السحبُ إلى صفحةٍ واحدة، فقُرئ الفرقُ ‏−٢٥٥ نقطة. مقيسٌ
      //    2026-08-29 يومَ أشعلت العناوينُ الثنائيّةُ رأسَ الجدول (‏+٣٫٦مم)
      //    فتجاوزت التجهيزةُ الحافّةَ التي كانت على بُعد مليمترٍ منها.
      final elId = await _plantMarker(db, id, marker, xMm: 10, yMm: 20);

      final before = probePdf(await _render(db, id));
      final y0 = _yOf(before, marker);
      expect(y0, isNotNull,
          reason: 'العنصرُ المزروعُ لم يصل الورقةَ — القياسُ على فراغ');
      // والشرطُ المسبقُ **مُعلَنٌ لا مضمَر**: يسقط الاختبارُ بسببه لا برقمٍ
      // لا معنى له، فيعرف من يقرؤه أنّ التجهيزةَ تحتاج فسحةً لا أنّ
      // الإحداثيَّ انكسر.
      expect(before.pageCount, 1,
          reason: 'التجهيزةُ تجاوزت الصفحةَ — القياسُ عبر انقسامٍ لا يعني شيئاً');

      await db.updateTemplateElement(
        elId,
        const InvoiceTemplateElementsCompanion(yMm: Value(15)),
      );

      final after = probePdf(await _render(db, id));
      final y1 = _yOf(after, marker);
      expect(y1, isNotNull);
      expect(after.pageCount, 1, reason: 'انقسمت الورقةُ بعد السحب');

      // أعلى على الورق = ‏y أكبر (أصلُ الـPDF أسفلَ اليسار).
      expect(y1! - y0!, closeTo(_fiveMmPts, 0.3),
          reason: 'الإحداثيُّ الرأسيُّ لا يصل الورقةَ — وهي عينُ الخطوة ٣ '
              'من فحص القبول. المقيس: ${(y1 - y0).toStringAsFixed(2)} نقطة');
    });

    test('إزاحةٌ أفقيّةٌ ٥ مم تصل الورقةَ كذلك', () async {
      final id = await _importPositioned(db, 'a4_sales_tax_invoice.json');
      final elId = await _plantMarker(db, id, marker, xMm: 10, yMm: 40);

      final x0 = _xOf(probePdf(await _render(db, id)), marker);
      expect(x0, isNotNull);

      await db.updateTemplateElement(
        elId,
        const InvoiceTemplateElementsCompanion(xMm: Value(15)),
      );

      final x1 = _xOf(probePdf(await _render(db, id)), marker);
      expect(x1, isNotNull);

      // المحرّكُ يقيس السيناتِ من حافّة **البداية**، واليمينُ هو البداية في
      // RTL — فزيادةُ `x_mm` تُزحزح العنصرَ يساراً على الورق. والمقيسُ
      // المقدارُ لا الاتّجاه.
      expect((x1! - x0!).abs(), closeTo(_fiveMmPts, 0.3),
          reason: 'المحورُ الأفقيُّ لا يصل الورقة');
    });
    test('عنصرٌ بلا إحداثيّاتٍ لا يُفرِغ الورقةَ — يُشتقّ من التدفّق', () async {
      // القالبُ المرقَّى إلى ٢ قبل أن يكتب المحرّرُ إحداثيّاتِه: مستندٌ
      // مشتقٌّ خيرٌ من ورقةٍ بيضاء.
      final id = await _import(db, 'thermal_classic.json');
      await _setVersion(db, id, 2);

      final els = await db.getTemplateElements(id);
      expect(els.every((e) => e.bandId == null), isTrue,
          reason: 'المقدّمةُ سقطت — الملفُّ صار يحمل إحداثيّاتٍ فالفحصُ يقيس '
              'مساراً آخر');

      final probe = probePdf(await _render(db, id));
      expect(probe.allTexts.length, greaterThan(10),
          reason: 'الاشتقاقُ من التدفّق لم يعمل، والورقةُ خرجت فارغة');
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  // لا قيمةَ تسقط بين النسختين
  // ═════════════════════════════════════════════════════════════════════════
  test('كلُّ قيمةِ بيانٍ تصل الورقةَ في ١ تصلها في ٢', () async {
    // المسارانِ يقرآن **نفسَ** حاسبِ القيم (`domain/printing/print_values`)،
    // فالمقيسُ هنا أن الوصلَ لم يُسقط شيئاً في الطريق: مفتاحٌ لم يُبنَ في
    // خريطة القيم، أو عنصرٌ رُمي في نطاقٍ لا يُرسم.
    //
    // والمقارنةُ على **القيم** لا على النصّ الكامل: المسارُ القديم يطبع
    // «الهاتف: 0111» والجديدُ يطبع القيمةَ وحدَها — التسميةُ في العنصر.
    const values = [
      kFixtureInvoiceNumber,
      '14/3/2026',
      '310-123-456-789',
      '626.76', // الإجمالي
      '500.00', // المدفوع
      '11.76', // الضريبة
    ];

    final id = await _import(db, 'a4_sales_tax_invoice.json');
    final v1 = (await _renderProbe(db, id)).allTexts.map((r) => r.text).join(' ');

    await _setVersion(db, id, 2);
    final v2 = (await _renderProbe(db, id)).allTexts.map((r) => r.text).join(' ');

    final lostInV2 = [
      for (final v in values)
        if (v1.contains(v) && !v2.contains(v)) v
    ];
    expect(lostInV2, isEmpty,
        reason: 'قيمٌ تصل الورقةَ في المسار القديم وتسقط في الجديد');
  });
}

// ═══════════════════════════════════════════════════════════════════════════

List<File> _assetFiles() => Directory(_assetDir)
    .listSync()
    .whereType<File>()
    .where((f) => f.path.endsWith('.json'))
    .toList()
  ..sort((a, b) => a.path.compareTo(b.path));

Future<int> _import(AppDatabase db, String file) async =>
    db.importTemplateFromJson(
        await File('$_assetDir/$file').readAsString());

/// يستورد القالبَ ويكتب له نطاقاتٍ وإحداثيّاتٍ — محاكاةً لما يفعله المحرّرُ
/// عند أوّل فتحٍ (الهجرةُ الكسولة).
Future<int> _importPositioned(AppDatabase db, String file) async {
  final id = await _import(db, file);
  // ورقٌ بقاعٍ ثابت — انظر شرحَ الاختبار.
  await db.updateTemplate(
    id,
    const InvoiceTemplatesCompanion(
      layoutVersion: Value(2),
      paperHeight: Value(297),
    ),
  );

  const bandOf = {
    'header': 'header',
    'info': 'info',
    'party': 'party',
    'details': 'details',
    'totals': 'totals',
    'footer': 'footer',
    'body': 'info',
  };

  final els = await db.getTemplateElements(id);
  final yByBand = <String, double>{};
  for (final e in els) {
    final band = bandOf[e.section] ?? 'info';
    final y = yByBand[band] ?? 0.0;
    final h = e.fontSize * 0.42 + 2; // مليمتراتٌ تقريبيّةٌ تكفي للتكديس
    await db.updateTemplateElement(
      e.id,
      InvoiceTemplateElementsCompanion(
        bandId: Value(band),
        xMm: const Value(0),
        yMm: Value(y),
        wMm: const Value(60),
        hMm: Value(h),
      ),
    );
    yByBand[band] = y + h + 1;
  }
  return id;
}

Future<void> _setVersion(AppDatabase db, int id, int v) => db.updateTemplate(
      id,
      InvoiceTemplatesCompanion(layoutVersion: Value(v)),
    );

Future<PdfProbe> _renderProbe(AppDatabase db, int id) async =>
    probePdf(await _render(db, id));

Future<Uint8List> _render(AppDatabase db, int templateId) async {
  final t = (await db.getTemplateById(templateId))!;
  await db.setDefaultTemplate(templateId);

  return TemplatedInvoiceService.printWithTemplate(
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
  );
}

/// يزرع عنصرَ نصٍّ بمرساةٍ فريدةٍ وإحداثيّاتٍ صريحة.
Future<int> _plantMarker(
  AppDatabase db,
  int templateId,
  String marker, {
  required double xMm,
  required double yMm,
}) async {
  final id = await db.addTemplateElement(
    templateId: templateId,
    elementType: 'text',
    content: marker,
    sortOrder: 9999,
    fontSize: 10,
  );
  await db.updateTemplateElement(
    id,
    InvoiceTemplateElementsCompanion(
      bandId: const Value('totals'),
      xMm: Value(xMm),
      yMm: Value(yMm),
      wMm: const Value(40),
      hMm: const Value(6),
    ),
  );
  return id;
}

double? _yOf(PdfProbe p, String text) {
  final hits = p.allTexts.where((r) => r.text == text).toList();
  return hits.length == 1 ? hits.first.y : null;
}

double? _xOf(PdfProbe p, String text) {
  final hits = p.allTexts.where((r) => r.text == text).toList();
  return hits.length == 1 ? hits.first.x : null;
}
