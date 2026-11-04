// قماشُ الملصق — القراءةُ والحفظُ **بأعمدة راسم الملصقات** على قاعدةٍ حقيقيّة.
//
// ═══ ما يُقاس ═══
//
// ‏١) **التكافؤ**: كلُّ ملصقٍ من الستّة المبذورة يُقرأ في النموذج بلا فقد
//    عنصرٍ ولا انحرافِ عمود — ويُحفظ بلا تعديلٍ فلا يتغيّر صفٌّ واحد.
// ‏٢) **التعديلُ يصل الصفوف**: تحريكٌ ومقاسٌ وخطٌّ وإضافةٌ وحذف ⇒ إعادةُ القراءة
//    تُرجع القيمَ نفسَها، و`layout_version` لا يُلمس و`x_mm` يبقى فارغاً.
// ‏٣) **الورقُ يقرأ ما حُفظ**: `printBarcodeWithTemplate` يبني PDF من الملصق
//    المعدَّل، وخطّةُ الرسم من صفوفه تطابق الإحداثيّاتِ المتوقّعة.
// ‏٤) **«ملصق جديد» بمقاسٍ مخصّص** يولد ملصقاً لا إيصالاً.
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/data/database/database.dart';
import 'package:picpos_erp/data/repositories/invoice_templates_repository_impl.dart';
import 'package:picpos_erp/domain/printing/label_design.dart';
import 'package:picpos_erp/services/printing/label_paint_plan.dart';
import 'package:picpos_erp/services/printing/paint_plan.dart';
import 'package:picpos_erp/services/printing/pdf_compute_helper.dart';
import 'package:picpos_erp/services/templated_invoice_service.dart';

/// الملصقاتُ الستّةُ المبذورة — بأسمائها في `_seedBarcodeTemplates`.
const kSeededLabels = <String>[
  'باركود قياسي',
  'بطاقة سعر',
  'ملصق كامل',
  'ملصق رف مضغوط',
  'ملصق مجوهرات',
  'ملصق كرتون كبير',
];

/// كلُّ عمودٍ في الصفّ — للمقارنة قبل الحفظ وبعده.
Map<String, Object?> _row(InvoiceTemplateElement e) => {
      'id': e.id,
      'type': e.elementType,
      'sort': e.sortOrder,
      'row': e.rowIndex,
      'flex': e.flexWidth,
      'x': e.xPosition,
      'y': e.yPosition,
      'w': e.width,
      'h': e.height,
      'align': e.textAlign,
      'family': e.fontFamily,
      'size': e.fontSize,
      'bold': e.isBold,
      'italic': e.isItalic,
      'color': e.fontColor,
      'bg': e.backgroundColor,
      'borderColor': e.borderColor,
      'border': e.borderWidth,
      'content': e.content,
      'labelAr': e.labelAr,
      'labelEn': e.labelEn,
      'visible': e.isVisible,
      'extra': e.extraStyles,
      'section': e.section,
      'formula': e.formula,
      'bandId': e.bandId,
      'xMm': e.xMm,
      'yMm': e.yMm,
      'wMm': e.wMm,
      'hMm': e.hMm,
      'condition': e.condition,
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('العنصر الجديد يختار أول موضع خالٍ داخل صفحة الملصق', () {
    const design = LabelDesign(
      templateId: 1,
      name: 'QA 58x40',
      widthMm: 58,
      heightMm: 40,
      elements: [
        LabelElement(
          key: 'name',
          type: LabelElementTypes.productName,
          xMm: 2,
          yMm: 2,
          wMm: 54,
          hMm: 6,
        ),
      ],
    );

    final (updated, key) = addLabelElement(design, LabelElementTypes.price);
    final added = updated.elements.singleWhere((element) => element.key == key);
    final existing = design.elements.single;

    expect(added.yMm, existing.yMm + existing.hMm);
    expect(added.xMm + added.wMm, lessThanOrEqualTo(design.widthMm));
    expect(added.yMm + added.hMm, lessThanOrEqualTo(design.heightMm));
    expect(
      added.xMm >= existing.xMm + existing.wMm ||
          added.xMm + added.wMm <= existing.xMm ||
          added.yMm >= existing.yMm + existing.hMm ||
          added.yMm + added.hMm <= existing.yMm,
      isTrue,
    );
  });

  late AppDatabase db;
  late InvoiceTemplatesRepositoryImpl repo;

  setUp(() async {
    db = AppDatabase.forTesting();
    repo = InvoiceTemplatesRepositoryImpl(db);
    await db.seedDefaultTemplates();
  });
  tearDown(() async {
    PdfComputeHelper.nativeLayoutOverride = null;
    await db.close();
  });

  Future<InvoiceTemplate> label(String name) async => (await db.getAllTemplates())
      .firstWhere((t) => t.templateCategory == 'barcode' && t.name == name);

  group('التكافؤ — الستّةُ المبذورة تُفتح بلا فقد', () {
    test('البذّارُ يزرع الستّةَ كلَّها في فئة barcode', () async {
      final names = (await db.getAllTemplates())
          .where((t) => t.templateCategory == 'barcode')
          .map((t) => t.name)
          .toSet();
      expect(names, containsAll(kSeededLabels));
    });

    test('وكلُّ قالبٍ آخرَ من فئة barcode في القاعدة يُقرأ بلا فقد', () async {
      for (final t in (await db.getAllTemplates())
          .where((t) => t.templateCategory == 'barcode')) {
        final rows = await db.getTemplateElements(t.id);
        final d = (await repo.getLabelDesign(t.id))!;
        expect(d.elements.map((e) => e.id).toList(), rows.map((r) => r.id).toList(),
            reason: '«${t.name}» فقد عناصر');
      }
    });

    for (final name in kSeededLabels) {
      test('«$name» — كلُّ عنصرٍ بأعمدته، وحفظٌ بلا تعديلٍ لا يغيّر صفّاً',
          () async {
        final t = await label(name);
        final rows = await db.getTemplateElements(t.id);
        expect(rows, isNotEmpty);

        final d = (await repo.getLabelDesign(t.id))!;
        expect(d.widthMm, t.paperWidth);
        expect(d.heightMm, t.paperHeight ?? 25);
        expect(d.elements.length, rows.length, reason: 'عنصرٌ ضاع عند الفتح');
        for (var i = 0; i < rows.length; i++) {
          final r = rows[i];
          final e = d.elements[i];
          expect(
            [e.id, e.type, e.xMm, e.yMm, e.wMm, e.hMm, e.fontSize, e.bold,
             e.italic, e.align, e.color, e.content, e.borderWidth],
            [r.id, r.elementType, r.xPosition, r.yPosition, r.width, r.height,
             r.fontSize, r.isBold, r.isItalic, r.textAlign, r.fontColor,
             r.content, r.borderWidth],
            reason: '«$name» العنصر $i انحرف عن صفّه',
          );
        }

        // خطّةُ الرسم ترى كلَّ عنصر — فلا يغيب شيءٌ عن المعاينة والمصغَّرة.
        expect(labelPaintOps(d).length, rows.length);

        await repo.saveLabelDesign(d);
        final after = await db.getTemplateElements(t.id);
        expect(after.map(_row).toList(), rows.map(_row).toList(),
            reason: 'حفظٌ بلا تعديلٍ غيّر صفوفَ «$name»');
        final t2 = (await db.getTemplateById(t.id))!;
        expect(t2.layoutVersion, t.layoutVersion);
        expect(t2.paperWidth, t.paperWidth);
        expect(t2.paperHeight, t.paperHeight);
        expect(t2.isDefault, t.isDefault);
      });
    }
  });

  group('التعديلُ يصل الصفوف ويعود بإعادة القراءة', () {
    late InvoiceTemplate t;
    late LabelDesign edited;

    Future<void> editAndSave() async {
      t = await label('بطاقة سعر');
      var d = (await repo.getLabelDesign(t.id))!;
      final name = d.elements.firstWhere((e) => e.type == 'product_name');
      final code = d.elements.firstWhere((e) => e.type == 'barcode_image');
      final price = d.elements.firstWhere((e) => e.type == 'product_price');

      d = moveLabelElement(d, code.key, 4, 10);
      d = resizeLabelElement(d, code.key, 40, 12);
      d = editLabelElement(d, name.key,
          fontSize: 8.5, bold: false, italic: true, align: 'right',
          color: '#B91C1C');
      d = editLabelElement(d, code.key, content: 'ean13');
      d = removeLabelElement(d, price.key);
      final String key;
      (d, key) = addLabelElement(d, 'text', content: 'SKU');
      d = resizeLabelElement(d, key, 20, 4);
      d = moveLabelElement(d, key, 1, 24);
      d = resizeLabel(d, widthMm: 52, heightMm: 30);
      edited = await repo.saveLabelDesign(d);
    }

    test('القيمُ المعدَّلةُ تعود كما هي', () async {
      await editAndSave();
      final reloaded = (await repo.getLabelDesign(t.id))!;
      expect(reloaded, edited);
      expect(reloaded.widthMm, 52);
      expect(reloaded.heightMm, 30);
      expect(reloaded.paperSize, '52x30');
      expect(reloaded.elements.map((e) => e.type).toList(),
          ['product_name', 'barcode_image', 'text']);

      final n = reloaded.elements[0];
      expect([n.fontSize, n.bold, n.italic, n.align, n.color],
          [8.5, false, true, 'right', '#B91C1C']);
      final c = reloaded.elements[1];
      expect([c.xMm, c.yMm, c.wMm, c.hMm, c.content], [4, 10, 40, 12, 'ean13']);
      final txt = reloaded.elements[2];
      expect(txt.id, isNotNull, reason: 'العنصرُ الجديدُ لم يُكتب');
      expect([txt.xMm, txt.yMm, txt.wMm, txt.hMm, txt.content],
          [1, 24, 20, 4, 'SKU']);
    });

    test('بنيةُ الصفّ كما يتوقّعها الراسم — لا نطاقات ولا ترقية نسخة', () async {
      final before = await label('بطاقة سعر');
      final beforeRows = {
        for (final r in await db.getTemplateElements(before.id)) r.id: r,
      };
      await editAndSave();
      final row = (await db.getTemplateById(t.id))!;
      expect(row.layoutVersion, before.layoutVersion,
          reason: 'الحفظُ رفع `layout_version` — راسمُ الملصقات لا يعرفه');
      expect(row.templateCategory, 'barcode');
      expect(row.type, 'thermal');
      expect(row.paperSize, '52x30');

      final rows = await db.getTemplateElements(t.id);
      expect(rows.length, 3);
      for (final r in rows) {
        // أعمدةُ النطاقات لا يكتبها قماشُ الملصق: الجديدُ بلا قيم، والقائمُ
        // كما بذره البذّار.
        final old = beforeRows[r.id];
        expect([r.bandId, r.xMm, r.yMm, r.wMm, r.hMm],
            [old?.bandId, old?.xMm, old?.yMm, old?.wMm, old?.hMm],
            reason: 'كُتبت أعمدةُ النطاقات — والراسمُ يقرأ x_position');
      }
      expect(rows.map((r) => r.sortOrder).toList(), [0, 1, 2]);
      // التسميةُ المخزَّنةُ لا يطبعها الراسم — لكنّها لا تضيع بالحفظ.
      expect(rows[0].labelAr, 'اسم المنتج');
      // الراسمُ يقرأ هذه الأعمدةَ بعينها:
      expect([rows[1].xPosition, rows[1].yPosition, rows[1].width, rows[1].height],
          [4, 10, 40, 12]);
    });

    test('الورقُ يقرأ الملصقَ المعدَّل — PDF من مسار الطباعة وخطّةٌ بالإحداثيّات',
        () async {
      await editAndSave();

      Uint8List? captured;
      String? jobName;
      PdfComputeHelper.nativeLayoutOverride = (bytes, name) async {
        captured = bytes;
        jobName = name;
        return true;
      };
      final printed = await TemplatedInvoiceService.printBarcodeWithTemplate(
        db: db,
        templateId: t.id,
        barcodeValue: '6221234567891',
        productName: 'صنف تجريبي',
        productCode: 'P-1001',
        price: 25.5,
        copies: 3,
        directPrint: false,
      );
      expect(printed, isTrue);
      expect(captured, isNotNull, reason: 'مسارُ الطباعة لم يُخرج PDF');
      expect(String.fromCharCodes(captured!.take(5)), '%PDF-');
      expect(jobName, 'Barcode_6221234567891_x3');

      // ما يقرؤه الراسمُ من القاعدة هو ما حفظه المحرّر — بخطّته نفسِها.
      final reread = (await repo.getLabelDesign(t.id))!;
      final ops = labelPaintOps(reread,
          sample: const LabelSample(
              productName: 'صنف تجريبي',
              productCode: 'P-1001',
              barcodeValue: '6221234567891',
              price: 25.5));
      expect(ops.map((o) => o.kind).toList(),
          [PaintKind.text, PaintKind.barcode, PaintKind.text]);
      expect([ops[1].leftMm, ops[1].topMm, ops[1].widthMm, ops[1].heightMm],
          [4, 10, 40, 12]);
      expect(ops[1].text, '6221234567891');
      expect(ops[0].text, 'صنف تجريبي');
      expect(ops[2].text, 'SKU');
      expect([ops[2].leftMm, ops[2].topMm], [1, 24]);
    });
  });

  group('«ملصق جديد» بمقاسٍ مخصّص', () {
    test('يولد ملصقاً بفئته ومقاسه وعنصرين — لا عناصرَ إيصال', () async {
      final id = await repo.createLabelTemplate(
          name: 'ملصق رف 70×35', widthMm: 70, heightMm: 35);
      final t = (await db.getTemplateById(id))!;
      expect([t.templateCategory, t.type, t.paperWidth, t.paperHeight,
              t.paperSize, t.isDefault, t.layoutVersion],
          ['barcode', 'thermal', 70, 35, '70x35', false, 1]);

      final d = (await repo.getLabelDesign(id))!;
      expect(d.elements.map((e) => e.type).toList(),
          ['product_name', 'barcode_image']);
      for (final e in d.elements) {
        expect(e.xMm + e.wMm, lessThanOrEqualTo(70));
        expect(e.yMm + e.hMm, lessThanOrEqualTo(35));
      }
      // الافتراضيُّ القائمُ لا يُخطف.
      final defaults = (await db.getAllTemplates())
          .where((x) => x.templateCategory == 'barcode' && x.isDefault)
          .map((x) => x.name);
      expect(defaults, ['باركود قياسي']);
    });

    test('المقاسُ يُقصّ إلى الحدود', () async {
      final id = await repo.createLabelTemplate(
          name: 'x', widthMm: 2, heightMm: 900);
      final t = (await db.getTemplateById(id))!;
      expect([t.paperWidth, t.paperHeight], [kLabelMinMm, kLabelMaxMm]);
    });

    test('قالبُ فاتورةٍ ليس ملصقاً — `getLabelDesign` يرفضه', () async {
      final invoice = (await db.getAllTemplates())
          .firstWhere((t) => t.templateCategory != 'barcode');
      expect(await repo.getLabelDesign(invoice.id), isNull);
    });
  });
}
