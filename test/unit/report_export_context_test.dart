// ═══════════════════════════════════════════════════════════════════════════
// ملفُّ Excel المُصدَّر كان لا يقول عن أيّ فترةٍ ولا أيّ فرعٍ هو.
// ═══════════════════════════════════════════════════════════════════════════
//
// `exportReport({title, headers, rows})` كان يكتب الرؤوسَ والصفوفَ فقط. فملفٌّ
// اسمه «تقرير المبيعات» على القرص لا يُعرف: أهو يناير أم السنة كاملة؟ فرعُ
// المعادي أم الشركةُ كلها؟ ومن يجد الملفَّ بعد شهرٍ — أو يستلمه بالبريد — لا
// سبيل له لمعرفة ذلك. وملفَّان لفترتين مختلفتين لا يُفرَّق بينهما إلا بتاريخ
// الحفظ على نظام الملفات.
//
// ── وأخطرُ من غيابِ السطر أن يكذب ──────────────────────────────────────────
// مديرُ فرعٍ محصورٌ بفرعه يصدّر بلا اختيار فرعٍ في الفلتر. البياناتُ محصورةٌ
// بفروعه (‏branchScopeProvider)، فلو كُتب «كل الفروع» لصار الملفُّ يدّعي شمولاً
// ليس فيه — وهو أسوأ من سطرٍ غائب: الغائبُ يُسأل عنه، والكاذبُ يُصدَّق.
//
// فالتسميةُ تُشتقّ من **الفلتر الصريح والنطاق معاً** لا من أحدهما.
// ═══════════════════════════════════════════════════════════════════════════

import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/services/excel_service.dart';

void main() {
  const names = {1: 'فرع المعادي', 2: 'فرع مدينة نصر', 3: 'فرع طنطا'};

  group('تسمية الفرع — الفلتر والنطاق معاً', () {
    test('فلترٌ صريح ⇒ اسم الفرع', () {
      expect(
        reportBranchLabel(branchId: 2, scopedBranchIds: null, names: names),
        'فرع مدينة نصر',
      );
    });

    test('بلا فلتر ووصولٌ كامل ⇒ كل الفروع', () {
      expect(
        reportBranchLabel(branchId: null, scopedBranchIds: null, names: names),
        'كل الفروع',
      );
    });

    test('بلا فلتر ومستخدمٌ محصور ⇒ فروعُه بالاسم لا «كل الفروع»', () {
      expect(
        reportBranchLabel(
            branchId: null, scopedBranchIds: {1, 3}, names: names),
        'فرع المعادي، فرع طنطا',
        reason: 'كتابة «كل الفروع» هنا تجعل الملفَّ يدّعي شمولاً ليس فيه',
      );
    });

    test('الفلترُ الصريح يغلب النطاق', () {
      expect(
        reportBranchLabel(branchId: 1, scopedBranchIds: {1, 3}, names: names),
        'فرع المعادي',
      );
    });

    test('نطاقٌ فارغ ⇒ لا فرع (فشلٌ مقفول)', () {
      expect(
        reportBranchLabel(
            branchId: null, scopedBranchIds: <int>{}, names: names),
        'لا يوجد فرع مسموح',
      );
    });

    test('فرعٌ غيرُ معروف الاسم لا يُطبع رقماً عارياً', () {
      expect(
        reportBranchLabel(branchId: 99, scopedBranchIds: null, names: names),
        'فرع #99',
      );
    });
  });

  group('كتلةُ السياق فوق الجدول', () {
    final generatedAt = DateTime(2026, 8, 9, 14, 30);

    test('العنوانُ والفترةُ والفرعُ وتاريخُ التصدير', () {
      final rows = reportContextRows(
        title: 'تقرير المبيعات',
        periodFrom: DateTime(2026, 2, 1),
        periodTo: DateTime(2026, 2, 28),
        branchLabel: 'فرع المعادي',
        generatedAt: generatedAt,
      );

      final flat = rows.map((r) => r.join(' ')).join('\n');
      expect(flat, contains('تقرير المبيعات'));
      expect(flat, contains('2026/02/01'));
      expect(flat, contains('2026/02/28'));
      expect(flat, contains('فرع المعادي'));
      expect(flat, contains('2026/08/09'));
    });

    test('بلا فترة ⇒ لا سطرَ فترةٍ كاذب', () {
      final rows = reportContextRows(
        title: 'تقرير المخزون',
        periodFrom: null,
        periodTo: null,
        branchLabel: 'كل الفروع',
        generatedAt: generatedAt,
      );

      final flat = rows.map((r) => r.join(' ')).join('\n');
      expect(flat, isNot(contains('الفترة')),
          reason: 'تقريرُ المخزون لقطةٌ لحظية — سطرُ فترةٍ فيه اختراع');
      expect(flat, contains('كل الفروع'));
    });

    test('تاريخٌ واحد (حتى تاريخ) يُكتب بلا مدى', () {
      final rows = reportContextRows(
        title: 'الميزانية',
        periodFrom: null,
        periodTo: DateTime(2026, 3, 31),
        branchLabel: 'كل الفروع',
        generatedAt: generatedAt,
      );

      final flat = rows.map((r) => r.join(' ')).join('\n');
      expect(flat, contains('حتى 2026/03/31'));
    });

    test('آخرُ سطرٍ فارغ — فاصلٌ عن الرؤوس', () {
      final rows = reportContextRows(
        title: 'ت',
        periodFrom: DateTime(2026, 1, 1),
        periodTo: DateTime(2026, 1, 31),
        branchLabel: 'كل الفروع',
        generatedAt: generatedAt,
      );

      expect(rows.last.join(), isEmpty,
          reason: 'بلا فاصلٍ تلتصق كتلةُ السياق بصفِّ الرؤوس فتُقرأ عموداً');
    });
  });
}
