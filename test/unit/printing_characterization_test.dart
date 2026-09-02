// شبكةُ الأمان قبل نقلِ الراسم — بصمةُ كلِّ قالبٍ كما يخرج على الورق **اليوم**.
//
// ── لماذا ────────────────────────────────────────────────────────────────
// الراسمان الحيّان ٢٨٩٢ سطراً، ولا اختبارَ واحدٌ منها يفتح الورقةَ وينظر.
// وأوّلُ نقلِ كتلةٍ إلى المحرّك الجديد يكسر مطبوعاً **ولا يقول**: الحراسُ
// البنيويةُ تؤكّد أن دالّةً تُنادى، لا أن الإجماليَّ بقي في موضعه.
//
// فهذا يُثبّت — لكلِّ قالب — عددَ الصفحات وقياسَها، وكلَّ نصٍّ بترتيبه ونقطته
// ووجهِ خطّه وحجمه، وكلَّ خطٍّ ومستطيلٍ يُرسم. أيُّ انزياحٍ يفوق ٠٫٠١ نقطة
// (‏٠٫٠٠٤ مم) يُسقط الاختبار ويشير إلى القالب بالاسم وإلى أوّل سطرٍ اختلف.
//
// ── مجموعتان لا واحدة — مقيسٌ لا مفترَض ──────────────────────────────────
// ‏`seedDefaultTemplates` تبذر **١٣** قالباً (‏٧ غيرَ باركود)، بينما
// `assets/invoice_templates/` فيه **١٩** ملفَّ JSON لا تُبذر بل تُستورد.
// ولا تلتقي المجموعتان: القوالبُ المبذورةُ مكتوبةٌ في Dart، والملفّاتُ
// التسعةَ عشرَ تدخل القاعدةَ عبر `importTemplateFromJson` وحدَها.
//
// فلو حَرَسنا المبذورةَ وحدَها لخرج أحدَ عشرَ ملفاً جديداً — وهي عينُ ما بُني
// المحرّكُ الجديدُ لأجله — بلا شبكةِ أمانٍ إطلاقاً.
//
// ── كيف تُحدَّث الملفّاتُ الذهبيّة ────────────────────────────────────────
//     flutter test test/unit/printing_characterization_test.dart --update-goldens
// ولا تُحدَّث إلّا بعد أن **تنظر** إلى الفرق وتُقرّ أنه مقصود.
//
// ⚠️ ولا يُقاس المطبوعُ ببصمةِ بايتات: الحزمةُ تكتب مُعرِّفَ وثيقةٍ مشتقّاً
// من الوقت، فنداءان لنفس المدخل يعطيان بايتاتٍ مختلفة. المقيسُ المحتوى
// والمواضع (‏`test/helpers/pdf_probe.dart`).

import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/database/database.dart';
import 'package:ural_erp/services/printing/template_pdf_renderer.dart';
import 'package:ural_erp/services/templated_invoice_service.dart';

import '../helpers/pdf_probe.dart';
import '../helpers/printing_characterization_fixture.dart';

const _goldenDir = 'test/goldens/printing';
const _assetDir = 'assets/invoice_templates';

/// الملصقاتُ مسارُ رسمٍ آخرُ بالكامل (`printBarcodeWithTemplate`)، فليست من
/// شبكة هذا الراسم.
const _skippedCategories = {'barcode'};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;

  setUp(() => db = AppDatabase.forTesting());
  tearDown(() => db.close());

  // ═════════════════════════════════════════════════════════════════════════
  // ضابط: النمطُ يمسك ما يدّعي
  // ═════════════════════════════════════════════════════════════════════════
  //
  // بصمةٌ لا تتحرّك حين يتحرّك المطبوعُ ليست شبكةَ أمان. فهذه تُغيّر خصائصَ
  // عنصرٍ في القاعدة وتؤكّد أن البصمةَ رأت الأثرَ **بمقداره** على المحورين —
  // لا أنها «تغيّرت» فحسب.
  //
  // وقد أمسكت عطباً في القارئ نفسِه: مِرشَّحُ الأرقام كان يبتلع المعاملاتِ
  // فتخرج النصوصُ كلُّها عند (٠،٠) بلا وجهٍ ولا حجم — وبصمةٌ كتلك تمرّ على
  // أيّ نقلٍ مهما كسر.
  group('ضابط: البصمةُ تمسك ما تدّعي', () {
    // ── ما يصل الورقةَ من خصائص العنصر — مقيسٌ لا مفترَض ────────────────
    //
    // الراسمُ الحيُّ **تدفّقيّ**: يرصّ العناصرَ عمودياً ويأخذ ارتفاعَها من
    // محتواها. فمن الخصائص الخمس لا يصل الورقةَ إلّا اثنتان:
    //
    //     الخاصيّة      تصل الورقة؟
    //     fontSize      نعم
    //     flexWidth     نعم
    //     height        **لا**
    //     yPosition     **لا**
    //     width         **لا**
    //
    // وهذا وحدَه يفسّر لماذا لا تمرّ الخطوةُ ٣ من فحص القبول اليوم: سحبُ
    // «الإجمالي المستحق» ٥ مم لأعلى **لا يغيّر المطبوع بحرف**. وهو عينُ ما
    // جاء `layout_version == 2` ليصلحه.
    //
    // فالضابطُ يُبنى على الخاصّيتين الحيّتين: لو بُني على `height` لبقي
    // أخضرَ أبداً — وحارسٌ لا يحمرّ ليس حارساً.
    test('تكبيرُ خطِّ عنصرٍ يظهر في البصمة — بحجمه وبإزاحة ما بعده', () async {
      await db.seedDefaultTemplates();
      final t = (await db.getAllTemplates()).firstWhere(
          (t) => t.type == 'thermal' && t.templateCategory == 'receipt');

      final before = probePdf(await _renderViaService(db, t.id));

      final els = await db.getTemplateElements(t.id);
      final target = els.firstWhere((e) => e.elementType == 'variable');
      await db.updateTemplateElement(
        target.id,
        InvoiceTemplateElementsCompanion(
          fontSize: Value(target.fontSize + 4),
        ),
      );

      final after = probePdf(await _renderViaService(db, t.id));

      expect(after.fingerprint(), isNot(equals(before.fingerprint())),
          reason: 'بصمةٌ عمياءُ عن تكبيرِ خطٍّ لا تحرس شيئاً');

      // ١ — الحجمُ الجديدُ نفسُه مقروءٌ من الورقة، لا مجرّدُ «تغيّرٍ ما».
      expect(after.allTexts.map((r) => r.size),
          contains(closeTo(target.fontSize + 4, 0.01)),
          reason: 'الحجمُ الجديدُ لم يصل الورقةَ — أو لم يصل القارئ');

      // ٢ — والهندسةُ تحرّكت: نصٌّ على الأقلّ غيّر ارتفاعَه.
      final beforeY = {for (final r in before.allTexts) r.text: r.y};
      final shifted = after.allTexts
          .where((r) => beforeY.containsKey(r.text))
          .where((r) => (beforeY[r.text]! - r.y).abs() > 0.5)
          .length;
      expect(shifted, greaterThan(0),
          reason: 'البصمةُ ترى النصَّ ولا ترى موضعَه — نصفُ حارس');
    });

    test('تغييرُ عرضِ عنصرٍ يزحزحه أفقياً في البصمة', () async {
      await db.seedDefaultTemplates();
      final t = (await db.getAllTemplates()).firstWhere(
          (t) => t.type == 'thermal' && t.templateCategory == 'receipt');

      final before = probePdf(await _renderViaService(db, t.id));

      final els = await db.getTemplateElements(t.id);
      final target = els.firstWhere((e) => e.elementType == 'variable');
      await db.updateTemplateElement(
        target.id,
        InvoiceTemplateElementsCompanion(
          flexWidth: Value(target.flexWidth >= 100 ? 50 : 100),
        ),
      );

      final after = probePdf(await _renderViaService(db, t.id));

      final beforeX = {for (final r in before.allTexts) r.text: r.x};
      final moved = after.allTexts
          .where((r) => beforeX.containsKey(r.text))
          .where((r) => (beforeX[r.text]! - r.x).abs() > 0.5)
          .length;
      expect(moved, greaterThan(0),
          reason: 'البصمةُ لا تقيس المحورَ الأفقيّ — عمودٌ ينزلق ولا تشكو');
    });

    test('البصمةُ تقرأ نصّاً ووجهاً وحجماً — لا صفراً في كلِّ حقل', () async {
      await db.seedDefaultTemplates();
      final t = (await db.getAllTemplates()).firstWhere(
          (t) => t.type == 'thermal' && t.templateCategory == 'receipt');
      final probe = probePdf(await _renderViaService(db, t.id));

      expect(probe.allTexts.length, greaterThan(20),
          reason: 'إيصالٌ بعشرين نصّاً فأقلَّ يعني أن القارئ لم يقرأ');
      expect(probe.allTexts.where((r) => r.x != 0 || r.y != 0).length,
          greaterThan(20),
          reason: 'نصوصٌ كلُّها عند (٠،٠) ⇒ المعاملاتُ لا تصل — عطبٌ حدث فعلاً');
      expect(probe.allTexts.every((r) => r.size > 0), isTrue,
          reason: 'حجمُ خطٍّ صفريٌّ ⇒ `Tf` لا يُقرأ');
      expect(probe.allTexts.map((r) => r.font).toSet(),
          contains(startsWith('Noto')),
          reason: 'وجهُ الخطّ لم يُحلّ من موارد الصفحة');
      expect(probe.allTexts.any((r) => r.text.contains('\u{FFFD}')), isFalse,
          reason: 'مُعرِّفُ رسمٍ بلا جدول `ToUnicode` ⇒ نصٌّ لا يُقرأ');
      expect(probe.allTexts.map((r) => r.text).join(),
          contains(kFixtureInvoiceNumber),
          reason: 'رقمُ الفاتورة لم يصل الورقة — أو لم يصل القارئ');
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  // المبذورةُ في القاعدة
  // ═════════════════════════════════════════════════════════════════════════
  test('كلُّ قالبٍ مبذورٍ له بصمةٌ ذهبيّةٌ مثبّتة', () async {
    await db.seedDefaultTemplates();
    final templates = (await db.getAllTemplates())
        .where((t) => !_skippedCategories.contains(t.templateCategory))
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));

    expect(templates.length, 7,
        reason: 'عددُ القوالب المبذورة غيرِ الباركود تغيّر — لو بقصدٍ فحدّث '
            'الرقمَ والملفّاتِ الذهبيّة معاً');

    await _pinAll(db, templates, prefix: 'seeded');
  });

  // ═════════════════════════════════════════════════════════════════════════
  // ملفّاتُ الأصول التسعةَ عشر
  // ═════════════════════════════════════════════════════════════════════════
  test('كلُّ ملفِّ قالبٍ في الأصول له بصمةٌ ذهبيّةٌ مثبّتة', () async {
    final files = Directory(_assetDir)
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.json'))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));

    expect(files.length, 19,
        reason:
            'عددُ ملفّات القوالب تغيّر — ملفٌّ جديدٌ بلا بصمةٍ يعبر بلا حراسة');

    // اسمُ الملفّ هو المُعرِّف، لا اسمُ القالب: ‏`a4_purchase.json` و
    // `a4_purchase_invoice.json` يحملان «فاتورة مشتريات A4» و«فاتورة
    // مشتريات — A4» — والشرطةُ تسقط في التسمية فيتصادمان ويدهس أحدُهما بصمةَ
    // الآخر. مقيسٌ: التصادمُ وقع فعلاً في أوّل تشغيل.
    final imported = <String, InvoiceTemplate>{};
    for (final f in files) {
      final id = await db.importTemplateFromJson(await f.readAsString());
      final base = f.uri.pathSegments.last.replaceAll('.json', '');
      imported[base] = (await db.getTemplateById(id))!;
    }

    await _pinAll(db, imported.values.toList(),
        prefix: 'asset', names: imported.keys.toList());
  });

  // ═════════════════════════════════════════════════════════════════════════
  // الراسمُ الثاني
  // ═════════════════════════════════════════════════════════════════════════
  test('راسمُ الإيصال الحراريِّ الثاني — بصمتُه مثبّتةٌ كذلك', () async {
    // `TemplatePdfRenderer` مسارٌ حيٌّ مستقلّ: `invoice_generator:74` وحدَه
    // يناديه، ولـ`(thermal, receipt)` وحدَها. فبصمتُه تُثبَّت على حدة.
    await db.seedDefaultTemplates();
    final templates = (await db.getAllTemplates())
        .where((t) => t.type == 'thermal' && t.templateCategory == 'receipt')
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));

    expect(templates, isNotEmpty,
        reason: 'لا قالبَ إيصالٍ حراريٍّ مبذور ⇒ المسارُ الثاني بلا حراسة');

    final failures = <String>[];
    for (final t in templates) {
      final data = await db.getTemplateWithData(t.id);
      final bytes = await TemplatePdfRenderer.generatePdf(
        templateData: data!,
        invoiceData: kFixtureRendererData,
      );
      final actual = probePdf(bytes).fingerprint(
          header: '# قالب «${t.name}»\n# راسم=TemplatePdfRenderer');
      final slug = 'renderer2_${_slug(t.name)}';
      final mismatch =
          await _compareGolden(File('$_goldenDir/$slug.txt'), actual);
      if (mismatch != null) failures.add('«${t.name}» → $mismatch');
    }

    expect(failures, isEmpty, reason: 'المطبوعُ تغيّر:\n${failures.join('\n')}');
  });
}

// ═══════════════════════════════════════════════════════════════════════════

Future<void> _pinAll(
  AppDatabase db,
  List<InvoiceTemplate> templates, {
  required String prefix,
  List<String>? names,
}) async {
  final failures = <String>[];
  final seen = <String>{};

  for (var i = 0; i < templates.length; i++) {
    final t = templates[i];
    if (_skippedCategories.contains(t.templateCategory)) continue;

    final id = names != null
        ? names[i]
        : '${t.type}_${t.templateCategory}_${t.name}';
    final slug = '${prefix}_${_slug(id)}';
    expect(seen.add(slug), isTrue,
        reason: 'قالبان بنفس اسم الملفّ «$slug» — أحدُهما يدهس بصمةَ الآخر');

    final bytes = await _renderViaService(db, t.id);
    final actual = probePdf(bytes).fingerprint(
      header: '# قالب «${t.name}»\n'
          '# نوع=${t.type} فئة=${t.templateCategory} ورق=${t.paperWidth}mm\n'
          '# راسم=TemplatedInvoiceService',
    );

    final mismatch = await _compareGolden(File('$_goldenDir/$slug.txt'), actual);
    if (mismatch != null) failures.add('«${t.name}» → $mismatch');
  }

  expect(failures, isEmpty,
      reason: 'المطبوعُ تغيّر في هذه القوالب:\n${failures.join('\n\n')}');
}

/// يجعل القالبَ افتراضياً لفئته ثمّ يرسمه عبر مسار الإنتاج نفسِه.
///
/// `printWithTemplate` تحلّ القالبَ بنفسها من (نوع، فئة)، فالتثبيتُ بجعله
/// الافتراضيَّ — لا بحقنِ القالب — كي يمرّ الرسمُ بنفس الحلّ الذي يمرّ به في
/// الإنتاج، فيدخل حلُّ الفئة في المقيس.
Future<Uint8List> _renderViaService(AppDatabase db, int templateId) async {
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
    shift: kFixtureShift,
  )).bytes;
}

/// يعيد وصفَ الفرق، أو `null` إن طابق.
Future<String?> _compareGolden(File file, String actual) async {
  if (autoUpdateGoldenFiles) {
    await file.parent.create(recursive: true);
    await file.writeAsString(actual);
    return null;
  }
  if (!await file.exists()) {
    // ‏«غائبٌ ⇒ اكتبه وانجح» ثقبٌ: حذفُ المجلّد يُفرِغ السويّةَ من معناها.
    return 'لا ملفَّ ذهبيّ (${file.path}) — شغّل `--update-goldens` وانظر إليه';
  }
  // ⚠️ تسويةُ نهايات السطور قبل المقارنة — لا رفاهيةَ فيها.
  //
  // ‏`core.autocrlf = true` في هذا المستودع: الملفُّ يُحفظ LF ويُخرَج CRLF.
  // فالبصمةُ تُكتب هنا بـLF وتُقرأ من القرص بـCRLF، وكلُّ ملفٍّ ذهبيٍّ
  // يختلف عند السطر الأوّل في أوّل استنساخٍ جديد. مقيسٌ: حوّلتُ ملفاً واحداً
  // إلى CRLF فسقط الاختبارُ فوراً.
  final expected = _normalize(await file.readAsString());
  actual = _normalize(actual);
  if (expected == actual) return null;

  final e = expected.split('\n');
  final a = actual.split('\n');
  for (var i = 0; i < (e.length > a.length ? e.length : a.length); i++) {
    final el = i < e.length ? e[i] : '(لا سطر)';
    final al = i < a.length ? a[i] : '(لا سطر)';
    if (el != al) {
      return 'أوّلُ فرقٍ في السطر ${i + 1}:\n'
          '        كان: $el\n'
          '        صار: $al';
    }
  }
  return 'فرقٌ في الطول: ${e.length} → ${a.length}';
}

/// تسويةُ نهايات السطور — انظر شرحَ `_compareGolden`.
String _normalize(String s) => s.replaceAll('\r\n', '\n');

/// اسمُ ملفٍّ مقروءٌ بالعين — العربيةُ تبقى كما هي (‏Git وWindows يحملانها)،
/// وكلُّ ما ليس حرفاً ولا رقماً يصير شرطةً سفليّة.
String _slug(String s) {
  final buf = StringBuffer();
  for (final r in s.runes) {
    final c = String.fromCharCode(r);
    final keep =
        RegExp(r'[a-zA-Z0-9]').hasMatch(c) || (r >= 0x0600 && r <= 0x06FF);
    buf.write(keep ? c.toLowerCase() : '_');
  }
  return buf
      .toString()
      .replaceAll(RegExp('_+'), '_')
      .replaceAll(RegExp(r'^_|_$'), '');
}
