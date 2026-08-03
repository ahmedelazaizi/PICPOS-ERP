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
}
