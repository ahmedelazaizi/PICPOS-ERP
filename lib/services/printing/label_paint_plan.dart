/// خطّةُ رسم الملصق — [PaintOp] من [LabelDesign] **بمنطق راسم الملصقات**.
///
/// ── لماذا خطّةٌ لا رسمٌ في الواجهة ───────────────────────────────────────
/// المعاينةُ ومصغَّرةُ المكتبة تستهلكان [PaintOp] بـ`SheetPreviewView`
/// و`TemplateThumbnailView` القائمتين — فلا راسمَ ثالث. وهذا الملفُّ يترجم
/// فرعَ `switch` في `_buildSingleBarcodeLabel` حرفاً بحرف: أيُّ نوعٍ يُرسم
/// وبأيّ نصّ، وما يسقط إلى `content`.
///
/// ⚠️ **والمحاذاةُ مطلقةٌ لا اتّجاهيّة**: الراسمُ يأخذ `left/right` بـ
/// `pw.TextAlign.left/right`. و`SheetPreviewView` يضع `start` عند الحافّة
/// اليسرى للصندوق و`end` عند اليمنى (‏‏حسابُ `dx` فيه)، فتُقابَل كذلك.
///
/// نقيّ: لا `package:pdf` ولا `package:flutter`.
library;

import '../../domain/printing/label_design.dart';
import '../../domain/printing/template_document.dart' show TextAlignSpec;
import 'paint_plan.dart';

/// بياناتُ العيّنة — ما يمرّره المستدعي لـ`printBarcodeWithTemplate`.
class LabelSample {
  final String productName;
  final String? productCode;
  final String barcodeValue;
  final double? price;
  final String? companyName;
  final int decimals;

  /// بياناتُ ملصق الميزان — نفسُ `weight`/`total`/`packDate` في الراسم.
  final double? weight;
  final double? total;
  final DateTime? packDate;

  const LabelSample({
    required this.productName,
    required this.barcodeValue,
    this.productCode,
    this.price,
    this.companyName,
    this.decimals = 2,
    this.weight,
    this.total,
    this.packDate,
  });

  static const demo = LabelSample(
    productName: 'صنف تجريبي',
    productCode: 'P-1001',
    barcodeValue: '6221234567891',
    price: 25.5,
    companyName: 'اسم الشركة',
  );
}

TextAlignSpec _align(String a) => switch (a) {
      'left' => TextAlignSpec.start,
      'center' => TextAlignSpec.center,
      _ => TextAlignSpec.end, // ‏`right` وما لا يُعرف — افتراضُ الراسم.
    };

/// نصُّ العنصر كما يكتبه الراسم.
String labelElementText(LabelElement el, LabelSample s) {
  switch (el.type) {
    case LabelElementTypes.productName:
      return s.productName.length > 30
          ? '${s.productName.substring(0, 30)}...'
          : s.productName;
    case LabelElementTypes.productCode:
      return s.productCode ?? s.barcodeValue;
    case LabelElementTypes.barcode:
      return s.barcodeValue;
    case LabelElementTypes.price:
      return s.price == null ? '' : s.price!.toStringAsFixed(s.decimals);
    case LabelElementTypes.companyName:
      return s.companyName ?? '';
    case LabelElementTypes.line:
    case LabelElementTypes.divider:
    case LabelElementTypes.rectangle:
      return '';
    // عناصرُ ملصق الميزان — بنصّ `_buildSingleBarcodeLabel` حرفاً، وإلّا
    // عرضت المعاينةُ خاناتٍ فارغةً لما يُطبع على الورق.
    case 'scale_weight':
      return '${el.labelAr ?? 'الوزن'}: '
          '${s.weight?.toStringAsFixed(3) ?? ''} kg';
    case 'scale_unit_price':
      return '${el.labelAr ?? 'سعر الوحدة / كجم'}: '
          '${s.price?.toStringAsFixed(s.decimals) ?? ''}';
    case 'scale_total':
      return '${el.labelAr ?? 'الإجمالي'}: '
          '${s.total?.toStringAsFixed(s.decimals) ?? ''}';
    case 'scale_pack_date':
      final d = s.packDate ?? DateTime.now();
      String two(int v) => v.toString().padLeft(2, '0');
      return '${el.labelAr ?? 'تاريخ التعبئة'}: '
          '${two(d.day)}/${two(d.month)}/${d.year}';
    default:
      return el.content ?? '';
  }
}

/// عمليّاتُ رسم ملصقٍ واحد — بالمليمتر من يسار الملصق.
List<PaintOp> labelPaintOps(LabelDesign d,
    {LabelSample sample = LabelSample.demo}) {
  final ops = <PaintOp>[];
  for (final el in d.elements) {
    final PaintKind kind;
    var h = el.hMm;
    if (el.isBarcode) {
      kind = el.isQr ? PaintKind.qrCode : PaintKind.barcode;
    } else if (el.isLine) {
      kind = PaintKind.line;
      // الراسمُ يرسم خطّاً بسُمك ٠٫٥ نقطة أعلى الصندوق.
      h = 0.2;
    } else if (el.isRect) {
      kind = PaintKind.rect;
    } else {
      kind = PaintKind.text;
    }
    ops.add(PaintOp(
      id: el.key,
      kind: kind,
      leftMm: el.xMm,
      topMm: el.yMm,
      widthMm: el.wMm,
      heightMm: h,
      text: labelElementText(el, sample),
      fontSize: el.fontSize,
      bold: el.bold,
      align: _align(el.align),
      colorHex: el.color,
    ));
  }
  return List.unmodifiable(ops);
}
