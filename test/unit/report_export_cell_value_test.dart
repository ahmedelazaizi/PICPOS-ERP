// ═══════════════════════════════════════════════════════════════════════════
// §٣‑٧ — تصديرُ Excel كان يكتب دقّةَ الثنائيّ الخام في ثمانيَ عشرةَ شاشة.
// ═══════════════════════════════════════════════════════════════════════════
//
// العلاجُ نزل سنةَ ٢٠٢٦ في `ExcelExportHelper.toCellValue` — وذاك المسارُ
// يخدم **أربعَ** شاشاتٍ وحدَها (دفترُ الأستاذ العامّ بنسختَيه، قيودُ اليوميّة
// بهويّة PicPos، وتقريرُ المصروفات). أمّا `ExcelService.exportReport` فهي
// المسارُ العامُّ الذي تناديه **ثمانيَ عشرةَ** شاشة — وكانت تكتب:
//
//     if (cell is double) return DoubleCellValue(cell);   // خامّاً
//
// فالشاشةُ تعرض `12.346` والملفُّ يحمل `12.345678900000001`. والعطبُ صامت:
// الملفُّ يُفتح ويبدو سليماً تماماً، والفرقُ لا يظهر إلّا عند **الجمع** —
// فيقول المراجعُ إنّ التقريرَ لا يطابق النظام.
//
// ── ولماذا يبقى الصحيحُ صحيحاً ────────────────────────────────────────────
// `IntCellValue` لا يُحوَّل عائماً: عددُ الفواتير ليس كسراً، وتحويلُه يجعل
// عمود «عدد» يُعرَض `3.0` في كلّ صفّ.
//
// ⚠️ **مرساةُ الحارس**: أوّلُ اختبارٍ يقيس أنّ الاستخراجَ نفسَه يعمل — أنّ
// `reportCellValue` تُخرج `DoubleCellValue` أصلاً — كي لا يمرَّ الملفُّ كلُّه
// أخضرَ على دالّةٍ ترمي أو تُخرج نصّاً.
// ═══════════════════════════════════════════════════════════════════════════

import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/core/constants/app_constants.dart';
import 'package:ural_erp/data/services/excel_service.dart';

void main() {
  group('§٣‑٧ دقّةُ الخليّة في المسار العامّ (exportReport)', () {
    test('مرساة: الكسرُ يخرج خليّةً عدديّةً لا نصّاً', () {
      expect(reportCellValue(1.5), isA<DoubleCellValue>(),
          reason: 'لو صارت نصّاً لمرَّ كلُّ ما تحتها بلا معنى');
    });

    test('الكسرُ يُدوَّر لخاناتِ العملة قبل الكتابة', () {
      final cell = reportCellValue(12.3456789) as DoubleCellValue;

      expect(
        cell.value,
        closeTo(12.346, 1e-9),
        reason: 'بـ${AppConstants.decimalPlaces} خانات: 12.3456789 ⇒ 12.346. '
            'والكتابةُ الخام تُخرج 12.345678900000001.',
      );
    });

    test('🔴 مجموعُ المصدَّر == مجموعُ المعروض', () {
      // ثلاثةُ أرقامٍ يظهر كلٌّ منها مدوَّراً على الشاشة. هذا **أثرُ** العطب
      // على المراجع: عمودٌ في Excel لا يساوي عمودَ الشاشة.
      const raw = <double>[0.1234, 0.1234, 0.1234];

      final exported = raw
          .map((v) => (reportCellValue(v) as DoubleCellValue).value.toDouble())
          .fold<double>(0, (a, b) => a + b);

      final onScreen = raw
          .map((v) => double.parse(v.toStringAsFixed(AppConstants.decimalPlaces)))
          .fold<double>(0, (a, b) => a + b);

      expect(exported, closeTo(onScreen, 1e-9),
          reason: 'الخامُّ يجمع 0.3702 بينما الشاشةُ تعرض 0.369');
    });

    test('الصحيحُ يبقى صحيحاً — عددُ الفواتير ليس 3.0', () {
      final cell = reportCellValue(3);

      expect(cell, isA<IntCellValue>());
      expect((cell as IntCellValue).value, 3);
    });

    test('غيرُ الرقم يمرّ نصّاً', () {
      expect(reportCellValue('فرع المعادي'), isA<TextCellValue>());
    });
  });
}
