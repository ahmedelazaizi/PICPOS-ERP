// ملصقٌ بقالبٍ مخصّص (‏58×40) — مقاسُ الصفحة ومقاسُ ورق السائق وخطّةُ المعاينة.
//
// التحقّقُ الحيّ 2026-11-03: «QA 58x40» خرج على A4 والملصقُ صغيرٌ في ركنها،
// والمعاينةُ تعرض الاسم وحده. السببان: `Printing.layoutPdf` كان يُنادى بلا
// `format` فتطلب الحزمةُ ورقةَ A4 من السائق، ومعاينةُ الحوار لا تعرف عناصرَ
// القالب. هنا يُقاس الثلاثة: MediaBox في البايتات، والمقاسُ المطلوبُ من
// السائق، وأنّ كلَّ عنصرٍ في خطّة المعاينة وصل الـPDF في صندوقه.
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart';
import 'package:picpos_erp/data/database/database.dart';
import 'package:picpos_erp/data/repositories/label_layout_writer.dart';
import 'package:picpos_erp/domain/printing/label_design.dart';
import 'package:picpos_erp/services/printing/barcode_label_printer.dart';
import 'package:picpos_erp/services/printing/barcode_label_spec.dart';
import 'package:picpos_erp/services/printing/label_item_sample.dart';
import 'package:picpos_erp/services/printing/label_paint_plan.dart';
import 'package:picpos_erp/services/printing/paint_plan.dart';
import 'package:picpos_erp/services/printing/pdf_compute_helper.dart';
import 'package:picpos_erp/services/templated_invoice_service.dart';
import 'package:printing/printing.dart' as printing;

import '../helpers/pdf_probe.dart';

const _mmPt = 72 / 25.4;

/// قالبُ «QA 58x40» كما بُني حيّاً: اسمٌ وباركودٌ وسعرٌ تحته.
Future<LabelDesign> _qaTemplate(AppDatabase db) async {
  final id = await createLabelTemplate(
    db,
    name: 'QA 58x40',
    widthMm: 58,
    heightMm: 40,
  );
  var d = (await loadLabelDesign(db, id))!;
  final String priceKey;
  (d, priceKey) = addLabelElement(d, LabelElementTypes.price);
  d = moveLabelElement(d, priceKey, 2, 30, snap: false);
  return saveLabelDesign(db, d);
}

const _item = BarcodeLabelItem(
  name: 'Milk 1L',
  barcode: '6221234567891',
  price: 12.5,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    PdfComputeHelper.nativeLayoutOverride = null;
    PdfComputeHelper.directPrintOverride = null;
    PdfComputeHelper.lastRequestedFormat = null;
  });

  test('حوار الطباعة: صفحةٌ 58×40 وورقُ السائق 58×40 لا A4', () async {
    final db = AppDatabase.forTesting();
    try {
      final design = await _qaTemplate(db);
      Uint8List? sent;
      PdfComputeHelper.nativeLayoutOverride = (bytes, _) async {
        sent = bytes;
        return true;
      };
      final s = labelSampleForItem(_item);
      final printed = await TemplatedInvoiceService.printBarcodeWithTemplate(
        db: db,
        templateId: design.templateId,
        barcodeValue: s.barcodeValue,
        productName: s.productName,
        productCode: s.productCode,
        price: s.price,
        directPrint: false,
      );
      expect(printed, isTrue);

      final probe = probePdf(sent!);
      expect(probe.pageCount, 1);
      expect(probe.pages.single.widthPts, closeTo(58 * _mmPt, 0.01));
      expect(probe.pages.single.heightPts, closeTo(40 * _mmPt, 0.01));

      // ما يبني منه Windows بنيةَ DEVMODE — كان `null` ⇒ PdfPageFormat.standard.
      final f = PdfComputeHelper.lastRequestedFormat;
      expect(f, isNotNull, reason: 'بلا format تطلب حزمةُ printing ورقةَ A4');
      expect(f!.width, closeTo(58 * PdfPageFormat.mm, 0.01));
      expect(f.height, closeTo(40 * PdfPageFormat.mm, 0.01));
    } finally {
      await db.close();
    }
  });

  test('خطّةُ المعاينة = الخرج: الاسم والسعر والباركود في صناديقها', () async {
    final db = AppDatabase.forTesting();
    try {
      final design = await _qaTemplate(db);
      final sample = labelSampleForItem(_item);
      final ops = labelPaintOps(design, sample: sample);

      // الخطّة تحمل العناصرَ الثلاثة بقيم العيّنة — لا الاسمَ وحده.
      final byType = {
        for (final e in design.elements)
          e.type: ops.singleWhere((o) => o.id == e.key),
      };
      expect(byType[LabelElementTypes.productName]!.text, 'Milk 1L');
      expect(byType[LabelElementTypes.price]!.text, '12.50');
      expect(byType[LabelElementTypes.barcode]!.kind, PaintKind.barcode);
      expect(byType[LabelElementTypes.barcode]!.text, '6221234567891');

      Uint8List? sent;
      await TemplatedInvoiceService.printBarcodeWithTemplate(
        db: db,
        templateId: design.templateId,
        barcodeValue: sample.barcodeValue,
        productName: sample.productName,
        productCode: sample.productCode,
        price: sample.price,
        directPrint: false,
        pdfSender: (bytes, _) async {
          sent = bytes;
          return true;
        },
      );
      final page = probePdf(sent!).pages.single;

      // كلُّ نصٍّ في الخطّة وصل الورقةَ داخلَ صندوقِ عنصره. والكلماتُ تُكتب
      // مقاطعَ منفصلةً في اتّجاه RTL، فتُطابَق كلمةً كلمة.
      for (final op in [
        byType[LabelElementTypes.productName]!,
        byType[LabelElementTypes.price]!,
        byType[LabelElementTypes.barcode]!,
      ]) {
        for (final word in op.text.split(' ')) {
          final run = page.texts.where((t) => t.text == word);
          expect(run, isNotEmpty, reason: '«$word» غائبٌ عن الـPDF');
          final t = run.first;
          final xMm = t.x / _mmPt;
          final fromTopMm = (page.heightPts - t.y) / _mmPt;
          expect(xMm, inInclusiveRange(op.leftMm - 0.5, op.leftMm + op.widthMm));
          expect(
            fromTopMm,
            inInclusiveRange(op.topMm, op.topMm + op.heightMm + 1),
            reason: '«$word» خارج صندوقه رأسيّاً',
          );
        }
      }

      // خطوطُ الباركود (مستطيلات) داخل صندوق عنصره.
      final bar = byType[LabelElementTypes.barcode]!;
      final bars = page.rects.where((r) {
        final left = r.x / _mmPt;
        final top = (page.heightPts - r.y - r.h) / _mmPt;
        return left >= bar.leftMm - 0.5 &&
            left <= bar.leftMm + bar.widthMm + 0.5 &&
            top >= bar.topMm - 0.5 &&
            top <= bar.topMm + bar.heightMm + 0.5;
      });
      expect(bars.length, greaterThan(20), reason: 'لا خطوطَ باركود في صندوقه');
    } finally {
      await db.close();
    }
  });

  test('الطباعة المباشرة تمرّر مقاس الملصق للسائق أيضاً', () async {
    PdfComputeHelper.directPrintOverride = (_, _) async => true;
    final ok = await PdfComputeHelper.directPrintBytes(
      printer: const printing.Printer(url: 'QA Label', name: 'QA Label'),
      bytes: Uint8List(0),
      format: const PdfPageFormat(58 * PdfPageFormat.mm, 40 * PdfPageFormat.mm),
    );
    expect(ok, isTrue);
    expect(
      PdfComputeHelper.lastRequestedFormat!.width,
      closeTo(58 * PdfPageFormat.mm, 0.01),
    );
  });

  test('المسار القديم (رول بلا قالب) يطلب ورقَ الرول لا A4', () async {
    PdfComputeHelper.nativeLayoutOverride = (_, _) async => true;
    final ok = await BarcodeLabelPrinter.print(
      const [_item],
      spec: LabelSpec.defaultSpec,
    );
    expect(ok, isTrue);
    final f = PdfComputeHelper.lastRequestedFormat!;
    expect(f.width, closeTo(LabelSpec.defaultSpec.pageWidthMm * PdfPageFormat.mm, 0.01));
    expect(f.height, closeTo(LabelSpec.defaultSpec.pageHeightMm * PdfPageFormat.mm, 0.01));
  });

  test('عيّنةُ الميزان: الوزن والإجمالي وتاريخ التعبئة في الخطّة كما في الراسم', () {
    final item = const BarcodeLabelItem(
      name: 'تفاح',
      barcode: '10000355',
      price: 12,
      isSoldByWeight: true,
      scalePluNumber: 12345,
    ).withScaleData(weight: 1.25, value: '2112345012500');
    final s = labelSampleForItem(item, now: DateTime(2026, 11, 3));
    expect(s.barcodeValue, '2112345012500');
    expect(s.total, 15);
    const design = LabelDesign(
      templateId: 1,
      name: 'ملصق ميزان',
      widthMm: 58,
      heightMm: 40,
      elements: [
        LabelElement(key: 'a', type: 'scale_weight', xMm: 2, yMm: 8, wMm: 26, hMm: 5, labelAr: 'الوزن'),
        LabelElement(key: 'b', type: 'scale_total', xMm: 2, yMm: 14, wMm: 54, hMm: 6, labelAr: 'الإجمالي'),
        LabelElement(key: 'c', type: 'scale_pack_date', xMm: 2, yMm: 20, wMm: 54, hMm: 4, labelAr: 'تاريخ التعبئة'),
      ],
    );
    final texts = [for (final o in labelPaintOps(design, sample: s)) o.text];
    expect(texts, [
      'الوزن: 1.250 kg',
      'الإجمالي: 15.00',
      'تاريخ التعبئة: 03/11/2026',
    ]);
  });
}
