import 'package:picpos_erp/core/i18n/tr.dart';
// تسمياتُ قماش الملصق — دوالُّ تُنادى داخل `build` لا ثوابتُ علويّة
// (‏`i18n_runtime_safety_test`: لغةُ الواجهة تتبدّل في التشغيل).

import 'package:flutter/widgets.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../domain/printing/label_design.dart';

/// اسمُ نوع العنصر كما يراه المستخدم.
String labelTypeName(String type, {String? content}) {
  switch (type) {
    case LabelElementTypes.productName:
      return tr('اسم المنتج');
    case LabelElementTypes.productCode:
      return tr('كود المنتج');
    case LabelElementTypes.barcode:
      return content == 'qrCode' ? tr('رمز QR') : tr('صورة الباركود');
    case LabelElementTypes.price:
      return tr('سعر المنتج');
    case LabelElementTypes.companyName:
      return tr('اسم الشركة');
    case LabelElementTypes.text:
      return tr('نص ثابت');
    case LabelElementTypes.line:
    case LabelElementTypes.divider:
      return tr('خط فاصل');
    case LabelElementTypes.rectangle:
      return tr('مستطيل');
    default:
      return type;
  }
}

IconData labelTypeIcon(String type, {String? content}) {
  switch (type) {
    case LabelElementTypes.productName:
      return PhosphorIconsBold.tag;
    case LabelElementTypes.productCode:
      return PhosphorIconsBold.hash;
    case LabelElementTypes.barcode:
      return content == 'qrCode'
          ? PhosphorIconsBold.qrCode
          : PhosphorIconsBold.barcode;
    case LabelElementTypes.price:
      return PhosphorIconsBold.currencyDollar;
    case LabelElementTypes.companyName:
      return PhosphorIconsBold.buildings;
    case LabelElementTypes.text:
      return PhosphorIconsBold.textT;
    case LabelElementTypes.line:
    case LabelElementTypes.divider:
      return PhosphorIconsBold.lineSegment;
    case LabelElementTypes.rectangle:
      return PhosphorIconsBold.square;
    default:
      return PhosphorIconsBold.question;
  }
}

/// اسمُ رمز الباركود — المفاتيحُ كما يحلّها الراسم.
String labelSymbologyName(String key) =>
    key == 'qrCode' ? tr('رمز QR') : key.toUpperCase();
