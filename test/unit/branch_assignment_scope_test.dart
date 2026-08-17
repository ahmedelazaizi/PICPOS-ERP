// ═══════════════════════════════════════════════════════════════════════════
// نطاقُ النسبة — القاعدةُ الخالصةُ التي كانت منسوخةً في ستّةِ مواضع
// ═══════════════════════════════════════════════════════════════════════════
//
// سؤالان مختلفان يتشابهان في الشكل ويفترقان في الجواب:
//
//   • **الرؤية** — أيُّ صفوفٍ يراها هذا الجهاز؟ يجيبه `ClientScope` وقصُّ
//     الخادم في `/api/sync/pull`، ودلالتُه متسامحة: `branch_id = x OR IS NULL`
//     (الصفُّ بلا فرعٍ عامٌّ فيبقى ظاهراً — قرارُ مالكٍ موثّق في
//     `api_handler.dart:2301`).
//
//   • **النسبة** — إلى أيِّ مخزنٍ يجوز أن يُنسَب مستندٌ **جديد**؟ ودلالتُه
//     صارمة، وهذا ما يقيسه هذا الملفّ.
//
// والفرقُ ليس ذوقاً: فرعُ الفاتورة يُشتقُّ من مخزنها، وقائمةُ الفواتير تقصّ
// بـ`branch_id IN (…) OR branch_id IS NULL`. فلو تسامحنا في النسبة وسمحنا
// بمخزنٍ بلا فرعٍ لخرجت فاتورةٌ `branch_id = NULL` تظهر في **كلِّ** الفروع —
// وهو عطبٌ أوسعُ من «غائبةٍ عن فرعها» لا علاجٌ له.

import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/domain/models/branch_assignment_scope.dart';

/// أخفُّ من `Warehouse` وكافٍ: القاعدةُ لا تعرف إلا `branchId`.
typedef _Row = ({int id, int? branchId});

List<int> _idsOf(List<_Row> rows) => rows.map((r) => r.id).toList();

List<_Row> _restrict(List<_Row> all, int? branchId) =>
    restrictForAssignment(all, branchId, branchIdOf: (r) => r.branchId);

void main() {
  const hq = (id: 1, branchId: 1);
  const tanta = (id: 2, branchId: 2);
  const branchless = (id: 3, branchId: null);

  group('restrictForAssignment', () {
    test('بلا نطاق (null) ⇒ القائمةُ كما هي', () {
      expect(_idsOf(_restrict([hq, tanta, branchless], null)), [1, 2, 3]);
    });

    test('نطاقٌ محدَّد ⇒ صفوفُ الفرعِ وحدَها', () {
      expect(_idsOf(_restrict([hq, tanta, branchless], 2)), [2]);
    });

    test('الصفُّ بلا فرعٍ يسقط — النسبةُ صارمةٌ وإن كانت الرؤيةُ متسامحة', () {
      expect(_idsOf(_restrict([hq, branchless], 1)), [1],
          reason: 'مستندٌ يُنسَب لمخزنٍ بلا فرعٍ يظهر في كلِّ الفروع لأن قصَّ '
              'القوائم يقرأ `IS NULL` رؤيةً عامّة');
    });

    test('الترشيحُ يُفرغ القائمة ⇒ تعود الكاملة (احتياطُ Spec 103)', () {
      expect(_idsOf(_restrict([hq, tanta], 99)), [1, 2],
          reason: 'قائمةٌ خاويةٌ تُوقف المحلَّ؛ والاحتياطُ قرارٌ لا سهو');
    });

    test('كلُّ الصفوفِ بلا فرعٍ ونطاقٌ محدَّد ⇒ تعود الكاملة لا الخاوية', () {
      expect(_idsOf(_restrict([branchless], 1)), [3]);
    });

    test('قائمةٌ خاويةٌ أصلاً تبقى خاوية', () {
      expect(_restrict(const [], 1), isEmpty,
          reason: 'الاحتياطُ يردّ الكاملةَ، ولا شيءَ ليُردّ هنا');
    });
  });
}
