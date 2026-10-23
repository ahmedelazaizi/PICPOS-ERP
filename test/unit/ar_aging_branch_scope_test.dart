// ═══════════════════════════════════════════════════════════════════════════
// أعمار الديون كانت بتعرض أرصدة كل عملاء وموردي الشركة.
// ═══════════════════════════════════════════════════════════════════════════
//
// `getArAgingReport` مكانش بياخد حصراً إطلاقاً، فمستخدم محصور بفرع كان بيشوف
// اسم كل طرف في الشركة ورصيده وتوزيعه على شرائح التقادم.
//
// الحصر على مستوى **الطرف** لا الفاتورة بقصد: `p.balance` رصيد الطرف الكلي
// والأعمار محسوبة منه، فحصر الفواتير بفرع مع إبقاء الرصيد كلياً كان هيخلّي
// الأعمدة ما تجمعش على الرصيد المعروض جنبها — نفس فئة العطل اللي خلّت تسوية
// الضريبة تتحرس بصلاحية بدل ما تتحصر.
//
// ده الإثبات السلوكي اللي خط أساس report_screens_resolve_branch_scope_test
// بيشترطه لإزالة الشاشة منه: {} بتفشل **مقفولة**.
// ═══════════════════════════════════════════════════════════════════════════

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/data/database/database.dart';

void main() {
  late AppDatabase db;
  late int branchA;
  late int branchB;

  final asOf = DateTime(2026, 8, 31);

  Future<void> customer({
    required String name,
    required double balance,
    bool isGlobal = false,
    List<int> branches = const [],
  }) =>
      db.into(db.parties).insert(PartiesCompanion.insert(
            name: name,
            balance: Value(balance),
            isCustomer: const Value(true),
            isGlobal: Value(isGlobal),
            branchIds:
                Value(branches.isEmpty ? null : ',${branches.join(',')},'),
          ));

  Set<String> mine(List<ArAgingRow> rows) => rows
      .map((r) => r.partyName)
      .where((n) => n.startsWith('عميل '))
      .toSet();

  setUp(() async {
    db = AppDatabase.forTesting();
    branchA = await db.into(db.branches).insert(BranchesCompanion.insert(
        name: 'فرع أ', globalId: const Value('gid-br-ar-a')));
    branchB = await db.into(db.branches).insert(BranchesCompanion.insert(
        name: 'فرع ب', globalId: const Value('gid-br-ar-b')));

    await customer(name: 'عميل فرع أ', balance: 500, branches: [branchA]);
    await customer(name: 'عميل فرع ب', balance: 900, branches: [branchB]);
    await customer(name: 'عميل عام', balance: 300, isGlobal: true);
  });

  tearDown(() => db.close());

  test('null = وصول كامل — كل الأطراف المدينة', () async {
    final rows = await db.getArAgingReport(asOfDate: asOf);
    expect(mine(rows), <String>{'عميل فرع أ', 'عميل فرع ب', 'عميل عام'});
  });

  test('{A} = فرع أ + العام، ومفيش رصيد من فرع ب', () async {
    final rows =
        await db.getArAgingReport(asOfDate: asOf, allowedBranchIds: {branchA});
    expect(mine(rows), <String>{'عميل فرع أ', 'عميل عام'},
        reason: 'ظهور «عميل فرع ب» معناه تسريب اسم ورصيد ٩٠٠ من فرع تاني');
  });

  test('{} بتفشل مقفولة — مش «كل الأطراف»', () async {
    final rows =
        await db.getArAgingReport(asOfDate: asOf, allowedBranchIds: <int>{});
    expect(rows, isEmpty);
  });

  test('{B} ضابط — بيرجّع فرع ب فعلاً مش قايمة فاضية', () async {
    final rows =
        await db.getArAgingReport(asOfDate: asOf, allowedBranchIds: {branchB});
    expect(mine(rows), <String>{'عميل فرع ب', 'عميل عام'});
  });

  test('جانب الموردين محصور بنفس القاعدة', () async {
    await db.into(db.parties).insert(PartiesCompanion.insert(
          name: 'عميل مورد ب',
          balance: const Value(700),
          isCustomer: const Value(false),
          isSupplier: const Value(true),
          // لازم صراحةً: العمود قيمته الافتراضية true، فنسيانها بيخلّي الطرف
          // «عاماً» ومرئياً لأي نطاق — والاختبار يعدّي على تجهيزة غلط.
          isGlobal: const Value(false),
          branchIds: Value(',$branchB,'),
        ));
    final rows = await db.getArAgingReport(
        asOfDate: asOf, customersOnly: false, allowedBranchIds: {branchA});
    expect(mine(rows).contains('عميل مورد ب'), isFalse,
        reason: 'نسخة AP كانت هتتنسى لو الفلتر اتحطّ في استعلام واحد');
  });
}
