/// بياناتُ ملصق صنفٍ واحد — **مصدرٌ واحدٌ** للمعاينة وللطباعة.
///
/// ── لماذا ملفٌّ مستقلّ ─────────────────────────────────────────────────────
/// حوارُ طباعة الباركود كان يبني وسائطَ `printBarcodeWithTemplate` في موضعٍ
/// والمعاينةُ لا تبني شيئاً (‏تعرض اسمَ الصنف وحده). فخرجت ورقةٌ بالسعر
/// والباركود ومعاينةٌ بالاسم فقط (‏التحقّق الحيّ 2026-11-03). هنا تُشتقّ
/// القيمُ مرّةً، فتقرأ المعاينةُ (‏`labelPaintOps`) والراسمُ الشيءَ نفسَه.
///
/// نقيّ: لا `package:pdf` ولا `package:flutter`.
library;

import 'barcode_label_spec.dart';
import 'label_paint_plan.dart';

/// [now] لملصق الميزان وحده (‏تاريخ التعبئة) — يُحقن في الاختبار.
LabelSample labelSampleForItem(BarcodeLabelItem item, {DateTime? now}) {
  final scale = item.scaleBarcode != null;
  return LabelSample(
    productName: item.name,
    barcodeValue: item.scaleBarcode ?? item.barcode,
    productCode: item.scalePluNumber?.toString(),
    price: item.price,
    weight: item.scaleWeight,
    total: scale ? (item.scaleWeight ?? 0) * (item.price ?? 0) : item.price,
    packDate: scale ? (now ?? DateTime.now()) : null,
  );
}
