// تصديرُ Excel يتبع خاناتِ العملة — لا يكتب دقّةَ الثنائيّ الخام.
//
// `ExcelExportHelper.export` كان يكتب `xl.DoubleCellValue(cell.toDouble())`
// بلا تدوير. والشاشةُ تعرض الرقمَ مدوَّراً لـ`AppConstants.decimalPlaces`،
// فما يُصدَّر ليس ما يُعرَض:
//
//   • الشاشة: ‏12.346   ·   الملف: ‏12.345678900000001
//   • ومجموعُ عمودٍ في Excel يفترق عن مجموع الشاشة في الكسور، فيقول
//     المراجعُ إن التقريرَ لا يطابق النظام.
//
// والعطبُ صامت: الملفُّ يُفتح ويبدو سليماً، والفرقُ يظهر عند الجمع وحدَه.

import 'package:excel/excel.dart' as xl;
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/core/constants/app_constants.dart';
import 'package:ural_erp/services/excel_export_helper.dart';

void main() {
  test('الرقمُ يُدوَّر لخاناتِ العملة قبل الكتابة', () {
    final cell = ExcelExportHelper.toCellValue(12.3456789);

    expect(cell, isA<xl.DoubleCellValue>());
    expect(
      (cell as xl.DoubleCellValue).value,
      closeTo(12.346, 1e-9),
      reason: 'بـ${AppConstants.decimalPlaces} خانات: 12.3456789 ⇒ 12.346. '
          'الكتابةُ الخام تُخرج 12.345678900000001 فيفترق مجموعُ Excel '
          'عن مجموع الشاشة.',
    );
  });

  test('مجموعُ المصدَّر == مجموعُ المعروض', () {
    // ثلاثةُ أرقامٍ يظهر كلٌّ منها مدوَّراً على الشاشة.
    const raw = <double>[0.1234, 0.1234, 0.1234];

    final exported = raw
        .map((v) => (ExcelExportHelper.toCellValue(v) as xl.DoubleCellValue)
            .value
            .toDouble())
        .fold<double>(0, (a, b) => a + b);

    final onScreen = raw
        .map((v) =>
            double.parse(v.toStringAsFixed(AppConstants.decimalPlaces)))
        .fold<double>(0, (a, b) => a + b);

    expect(exported, closeTo(onScreen, 1e-9),
        reason: 'لو صُدِّر الخامُ لصار المجموعُ 0.3702 مقابل 0.369 معروضة');
  });

  test('غيرُ الرقم يمرّ كما هو — نصّاً', () {
    expect(ExcelExportHelper.toCellValue(null), isA<xl.TextCellValue>());
    expect(ExcelExportHelper.toCellValue('نصّ'), isA<xl.TextCellValue>());
  });
}
