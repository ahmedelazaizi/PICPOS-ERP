// ═══════════════════════════════════════════════════════════════════════════
// قوائمُ الموظفين خارجَ شاشات HR كانت غيرَ محصورة — H6 غطّى HR وحدها.
// ═══════════════════════════════════════════════════════════════════════════
//
// أغلق H6 تسريبَ **الرواتب** بحلّ النطاق مرةً واحدةً في `hr_notifier`، فلا
// مسارَ غيرَ محصورٍ متاحٌ لشاشات HR. لكن ستّةَ مُنادين خارجَها بقوا على
// `getAllEmployees()` بلا نطاق:
//   • أربعةُ تبويباتِ توزيع عبر `DistributionController`
//   • حوارُ طلبات الطاولات
//   • إعداداتُ البصمة
//
// والمسرَّبُ هنا **الأسماءُ والأدوار** لا الرواتب — أخفُّ من H6 وليس بلا أثر:
// مديرُ فرعٍ يفتح «تحصيلاتُ المندوبين» فيرى مندوبي الشركة كلَّها في المنسدلة،
// ويقدر يُسنِد تحصيلاً لمندوبِ فرعٍ لا يملكه.
//
// والحلُّ في **الطبقة الوسيطة** لا في كلّ شاشة — نفسُ مبدأ H6: لا مسارَ غيرَ
// محصورٍ متاحٌ للشاشة، فنسيانُ شاشةٍ جديدةٍ للحصر يصير مستحيلاً.
// ═══════════════════════════════════════════════════════════════════════════

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/data/providers/providers.dart';
import 'package:picpos_erp/presentation/screens/providers/distribution_controller.dart';

void main() {
  late AppDatabase db;
  late int branchA;
  late int branchB;

  setUp(() async {
    db = AppDatabase.forTesting();
    branchA = await db.into(db.branches).insert(BranchesCompanion.insert(
        name: 'فرع أ', globalId: const Value('gid-br-emp-a')));
    branchB = await db.into(db.branches).insert(BranchesCompanion.insert(
        name: 'فرع ب', globalId: const Value('gid-br-emp-b')));

    Future<void> emp(String name, int branchId) =>
        db.into(db.employees).insert(EmployeesCompanion.insert(
              name: name,
              branchId: Value(branchId),
            ));
    await emp('مندوب أ', branchA);
    await emp('مندوب ب', branchB);
  });

  tearDown(() => db.close());

  ProviderContainer containerFor(BranchScope scope) => ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(db),
          branchScopeProvider.overrideWith((ref) async => scope),
        ],
      );

  test('مستخدمٌ محصورٌ بفرعٍ لا يرى موظفي الفرع الآخر في تبويبات التوزيع',
      () async {
    final c = containerFor(
        BranchScope(allowedBranchIds: {branchA}, primaryBranchId: branchA));
    addTearDown(c.dispose);

    final names = (await c.read(distributionControllerProvider).getAllEmployees())
        .map((e) => e.name)
        .toList();

    expect(names, ['مندوب أ'],
        reason: 'مديرُ فرعٍ يرى مندوبي الشركة كلَّها في المنسدلة، ويقدر '
            'يُسنِد تحصيلاً لمندوبِ فرعٍ لا يملكه');
  });

  test('صاحبُ الوصول الكامل يرى الجميع', () async {
    final c = containerFor(const BranchScope.fullAccess());
    addTearDown(c.dispose);

    final names = (await c.read(distributionControllerProvider).getAllEmployees())
        .map((e) => e.name)
        .toList();

    expect(names, hasLength(2),
        reason: 'الحصرُ ليس تضييقاً على الإدارة');
  });

  test('نطاقٌ فارغ ⇒ صفرُ صفوفٍ لا القائمةُ كاملة', () async {
    // فشلٌ مقفول: مستخدمٌ بلا فرعٍ مسموح لا يُعطى الشركةَ كلَّها.
    final c = containerFor(
        const BranchScope(allowedBranchIds: <int>{}, primaryBranchId: null));
    addTearDown(c.dispose);

    expect(
        await c.read(distributionControllerProvider).getAllEmployees(), isEmpty);
  });

  test('الموظفُ بلا فرعٍ (مستوى الشركة) يبقى مرئياً', () async {
    await db.into(db.employees).insert(
        EmployeesCompanion.insert(name: 'موظف الشركة'));
    final c = containerFor(
        BranchScope(allowedBranchIds: {branchA}, primaryBranchId: branchA));
    addTearDown(c.dispose);

    final names = (await c.read(distributionControllerProvider).getAllEmployees())
        .map((e) => e.name)
        .toList();
    expect(names, containsAll(<String>['مندوب أ', 'موظف الشركة']),
        reason: 'مطابقةً لدلالة `_employeeBranchScope` — NULL = مستوى الشركة');
    expect(names, isNot(contains('مندوب ب')));
  });
}
