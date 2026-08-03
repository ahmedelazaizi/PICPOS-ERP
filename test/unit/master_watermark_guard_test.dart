// المرحلة ١ / W1 — الجداول الأساسية المحصورة يجب ألّا تقدّم watermark
// على سحب قبل تسجيل الدخول.
//
// الخادم يقصّ هذه الجداول على سنتينل `-1` للمستدعي بلا هوية، فالرد
// مقصوص أو فارغ. لو قدّم العميل الـwatermark عليه، فبعد الدخول يسأل
// عمّا هو أحدث فقط ⇒ الصفوف الأقدم لا تعود أبداً. وهذا يتكرر عند **كل
// إقلاع**، لا عند التزويد الأوّلي فحسب.
//
// حارس بنيوي: أي جدول يُضاف لحصر الخادم مستقبلاً ولا يُضاف هنا يكسر
// البناء بدل أن يصمت.

import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/services/delta_pull_service.dart';

void main() {
  test('الجداول الأساسية الأربعة محروسة من تقديم الـwatermark', () {
    const phase1MasterTables = {
      'branches',
      'warehouses',
      'safes',
      'cost_centers',
    };

    final missing = phase1MasterTables
        .difference(DeltaPullService.branchScopedMasterPullTables);

    expect(
      missing,
      isEmpty,
      reason: 'جداول محصورة على الخادم وغائبة عن حارس الـwatermark: '
          '$missing — سحب قبل الدخول سيحفظ watermark على رد مقصوص، '
          'فالصفوف الأقدم لن تعود بعد تسجيل الدخول',
    );
  });

  test('الحارس الجديد منفصل عن قائمة المنع التعاملية', () {
    // المجموعتان تصفان عقدين مختلفين. خلطهما يكسر
    // `p1_8b_transactional_set_parity_test` الذي يثبّت تساوي القائمة
    // التعاملية مع نظيرتها على الخادم بتساوٍ صارم.
    expect(
      DeltaPullService.branchScopedMasterPullTables
          .intersection(DeltaPullService.branchScopedPullTables),
      isEmpty,
      reason: 'الجداول الأساسية تسرّبت إلى القائمة التعاملية',
    );
  });

  // ── قرار الحارس نفسه — ليس المجموعة فقط ────────────────────────────────
  //
  // الاختباران أعلاه يثبّتان محتوى `branchScopedMasterPullTables` وانفصالها،
  // لكن لا شيء منهما يتحقّق من أن الحارس الفعلي في `pullTable` يستعملها.
  // لو حذف أحدهم `|| branchScopedMasterPullTables.contains(table)` من
  // الحارس، تبقى المجموعة موجودة ويبقى الاختباران أعلاه أخضرين، ويعود
  // تسميم الـwatermark بصمت. لذلك نختبر [DeltaPullService.shouldWithholdWatermark]
  // مباشرة — التعبير الوحيد للقاعدة الفعلية.
  group('shouldWithholdWatermark — سلوك الحارس الفعلي', () {
    for (final table in {'branches', 'warehouses', 'safes', 'cost_centers'}) {
      test('$table: يُحجَب بلا هوية', () {
        expect(
          DeltaPullService.shouldWithholdWatermark(table,
              hasSessionToken: false),
          isTrue,
          reason: 'جدول أساسي محصور بلا هوية يجب أن يُحجَب watermark عنه',
        );
      });

      test('$table: لا يُحجَب مع وجود هوية', () {
        expect(
          DeltaPullService.shouldWithholdWatermark(table,
              hasSessionToken: true),
          isFalse,
          reason:
              'بعد الدخول تُقدَّم الـwatermark عادياً — لا سبب للحجب بوجود توكن',
        );
      });
    }

    test('جدول تعاملي (sales_invoices) لا يزال يُحجَب بلا هوية', () {
      // يثبت أن هذا التوسيع لم يُضيّق القاعدة القائمة لقائمة المنع
      // التعاملية.
      expect(
        DeltaPullService.shouldWithholdWatermark('sales_invoices',
            hasSessionToken: false),
        isTrue,
      );
    });

    test('جدول أساسي غير محصور (products) لا يُحجَب أبداً', () {
      expect(
        DeltaPullService.shouldWithholdWatermark('products',
            hasSessionToken: false),
        isFalse,
      );
      expect(
        DeltaPullService.shouldWithholdWatermark('products',
            hasSessionToken: true),
        isFalse,
      );
    });
  });
}
