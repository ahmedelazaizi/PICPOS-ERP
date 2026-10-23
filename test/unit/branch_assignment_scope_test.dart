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
import 'package:picpos_erp/domain/models/branch_assignment_scope.dart';

/// أخفُّ من `Warehouse` وكافٍ: القاعدةُ لا تعرف إلا `branchId`.
typedef _Row = ({int id, int? branchId});

List<int> _idsOf(List<_Row> rows) => rows.map((r) => r.id).toList();

List<_Row> _restrict(
  List<_Row> all,
  Set<int>? allowed, {
  EmptyScopePolicy onEmpty = EmptyScopePolicy.widen,
}) =>
    restrictForAssignment(all, allowed,
        branchIdOf: (r) => r.branchId, onEmpty: onEmpty);

void main() {
  const hq = (id: 1, branchId: 1);
  const tanta = (id: 2, branchId: 2);
  const branchless = (id: 3, branchId: null);

  group('restrictForAssignment', () {
    test('بلا نطاق (null) ⇒ القائمةُ كما هي', () {
      expect(_idsOf(_restrict([hq, tanta, branchless], null)), [1, 2, 3]);
    });

    test('نطاقٌ محدَّد ⇒ صفوفُ الفرعِ وحدَها', () {
      expect(_idsOf(_restrict([hq, tanta, branchless], {2})), [2]);
    });

    test('نطاقٌ متعدّدُ الفروع (المرآة) ⇒ اتّحادُ فروعِه', () {
      expect(_idsOf(_restrict([hq, tanta, branchless], {1, 2})), [1, 2],
          reason: 'مديرُ المرآةِ المخصَّصُ له فرعان يُنسِب إليهما معاً — '
              'وهو ما يسلّمه الخادمُ بعد FR-1');
    });

    test('الصفُّ بلا فرعٍ يسقط — النسبةُ صارمةٌ وإن كانت الرؤيةُ متسامحة', () {
      expect(_idsOf(_restrict([hq, branchless], {1})), [1],
          reason: 'مستندٌ يُنسَب لمخزنٍ بلا فرعٍ يظهر في كلِّ الفروع لأن قصَّ '
              'القوائم يقرأ `IS NULL` رؤيةً عامّة');
    });

    test('مجموعةٌ خاويةٌ ⇒ لا شيء، ولا توسيعَ ولو طُلب', () {
      expect(_restrict([hq, tanta], const {}), isEmpty);
      expect(_restrict([hq, tanta], const {}, onEmpty: EmptyScopePolicy.widen),
          isEmpty,
          reason: '`{}` فشلٌ مقفولٌ قرّره المزوّد (مستخدمٌ سيّئُ التزويد) — '
              'وتوسيعُه يُبطل كلَّ حصرٍ فرعيٍّ في المستودع');
    });

    test('فرعٌ بلا صفوفٍ + توسيع ⇒ القائمةُ الكاملة (المستقلُّ والخادم)', () {
      expect(_idsOf(_restrict([hq, tanta], {99})), [1, 2],
          reason: 'محلٌّ بجهازٍ واحدٍ ما ينفعش يقف — سابقةُ المالك 2026-08-04');
    });

    test('فرعٌ بلا صفوفٍ + رفض ⇒ خاوية (العميلُ والمرآة)', () {
      expect(
          _restrict([hq, tanta], {99}, onEmpty: EmptyScopePolicy.refuse), isEmpty,
          reason: 'الأجهزةُ التي تسرّب تُقفل، والحفظُ يرفض برسالةٍ قابلةٍ للإصلاح');
    });

    test('قائمةٌ خاويةٌ أصلاً تبقى خاوية', () {
      expect(_restrict(const [], {1}), isEmpty,
          reason: 'الاحتياطُ يردّ الكاملةَ، ولا شيءَ ليُردّ هنا');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // حارسُ الحفظ — لأن ترشيحَ القائمةِ يحرس المعروضَ لا المحفوظ
  // ═══════════════════════════════════════════════════════════════════════
  group('resolveAssignedWarehouseId', () {
    test('بلا اختيارٍ صريح ⇒ أوّلُ مخزنٍ في النطاق لا الثابتُ ١', () {
      final id = resolveAssignedWarehouseId(
        selected: null,
        scopedWarehouseIds: const [6, 7],
      );

      expect(id, 6);
      expect(id, isNot(1), reason: 'الثابتُ ١ كان يختم المستندَ على فرعٍ عشوائي');
    });

    test('نطاقٌ خاوٍ ⇒ رميٌ برسالةٍ مفهومةٍ بدل اختراعِ مخزن', () {
      expect(
        () => resolveAssignedWarehouseId(
            selected: null, scopedWarehouseIds: const []),
        throwsA(isA<Exception>()),
      );
    });

    test('اختيارٌ داخلَ النطاق يمرّ', () {
      expect(
        resolveAssignedWarehouseId(selected: 7, scopedWarehouseIds: const [6, 7]),
        7,
      );
    });

    test('اختيارٌ خارجَ النطاق يُرفض — هذا هو ما كان مسارُ الحفظ يثق به', () {
      expect(
        () => resolveAssignedWarehouseId(
            selected: 99, scopedWarehouseIds: const [6, 7]),
        throwsA(isA<Exception>()),
      );
    });

    test('التعديلُ يُبقي مخزنَ المستندِ القائمِ ولو خرج عن النطاق', () {
      expect(
        resolveAssignedWarehouseId(
          selected: 99,
          scopedWarehouseIds: const [6, 7],
          isEditMode: true,
        ),
        99,
        reason: 'الحصرُ يمنع ختماً جديداً ولا يجمّد ما هو مختومٌ فعلاً',
      );
    });

    test('التعديلُ بلا اختيارٍ يسقط إلى قواعدِ الإنشاء', () {
      expect(
        resolveAssignedWarehouseId(
          selected: null,
          scopedWarehouseIds: const [6, 7],
          isEditMode: true,
        ),
        6,
      );
    });
  });
}
