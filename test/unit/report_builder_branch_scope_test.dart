// ═══════════════════════════════════════════════════════════════════════════
// منشئ التقارير كان بيقرا كل الجداول بلا أي حصر فروع.
// ═══════════════════════════════════════════════════════════════════════════
//
// آخر تسريب في خط أساس report_screens_resolve_branch_scope_test. مستخدم محصور
// بفرع كان يقدر يبني تقريراً على `sales_invoices` أو `parties` ويشوف الشركة
// كلها.
//
// ── ليه خريطة لكل كيان لا فلتر واحد ─────────────────────────────────────────
// الحصر دلالته مختلفة لكل مصدر:
//   sales_invoices / purchase_invoices → branch_id مباشرةً
//   employees                          → branch_id مباشرةً (اتقفل H6)
//   parties                            → is_global OR branch_ids LIKE
//   products                           → بيانات أساسية على مستوى الشركة
//   journal_entries / inventory_balances → **مالهمش فلتر مدعوم**
//
// `employees` كان مرفوضاً لأن `branch_id` **ما كانش بيتكتب أصلاً** (مانع H6)،
// فحصره كان بيدي صفر صفوف مضلّلاً. اتقفل H6 — `addEmployee` بيكتب العمود —
// فبقى الحصر ذا معنى، وهو المصدر الوحيد في منشئ التقارير اللي فيه **رواتب**.
//
// ── القرار: الرفض لا الحصر الجزئي ───────────────────────────────────────────
// كيان مالوش فلتر مدعوم بيرجّع **فاضي** لمستخدم محصور. الحصر الجزئي أخطر من
// غيابه: التقرير هيبان محصوراً والمستخدم هيثق فيه بينما الكيانات دي بتسرّب.
// ═══════════════════════════════════════════════════════════════════════════

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/data/database/database.dart';

void main() {
  late AppDatabase db;
  late int branchA;
  late int branchB;
  late int whA;
  late int whB;

  Future<int> report(String entity, String columns) =>
      db.into(db.customReports).insert(CustomReportsCompanion.insert(
          name: 'ت', sourceEntity: entity, columns: columns));

  setUp(() async {
    db = AppDatabase.forTesting();
    branchA = await db.into(db.branches).insert(BranchesCompanion.insert(
        name: 'فرع أ', globalId: const Value('gid-br-rb-a')));
    branchB = await db.into(db.branches).insert(BranchesCompanion.insert(
        name: 'فرع ب', globalId: const Value('gid-br-rb-b')));
    whA = await db.into(db.warehouses).insert(
        WarehousesCompanion.insert(name: 'مخزن أ', branchId: Value(branchA)));
    whB = await db.into(db.warehouses).insert(
        WarehousesCompanion.insert(name: 'مخزن ب', branchId: Value(branchB)));

    for (final (num_, wh, br) in [('INV-A', whA, branchA), ('INV-B', whB, branchB)]) {
      await db.into(db.salesInvoices).insert(SalesInvoicesCompanion.insert(
            invoiceNumber: num_,
            warehouseId: wh,
            userId: 1,
            invoiceDate: DateTime(2026, 8, 10),
            branchId: Value(br),
            total: const Value(100),
          ));
    }

    await db.into(db.parties).insert(PartiesCompanion.insert(
        name: 'طرف أ',
        isGlobal: const Value(false),
        branchIds: Value(',$branchA,')));
    await db.into(db.parties).insert(PartiesCompanion.insert(
        name: 'طرف ب',
        isGlobal: const Value(false),
        branchIds: Value(',$branchB,')));
  });

  tearDown(() => db.close());

  group('الفواتير — حصر بـbranch_id', () {
    test('null = وصول كامل', () async {
      final id = await report('sales_invoices', 'invoice_number');
      final rows = await db.executeReport(id);
      expect(rows.map((r) => r['invoice_number']),
          containsAll(<String>['INV-A', 'INV-B']));
    });

    test('{A} بتستبعد فواتير فرع ب', () async {
      final id = await report('sales_invoices', 'invoice_number');
      final rows = await db.executeReport(id, allowedBranchIds: {branchA});
      expect(rows.map((r) => r['invoice_number']), ['INV-A']);
    });

    test('{} بتفشل مقفولة', () async {
      final id = await report('sales_invoices', 'invoice_number');
      expect(await db.executeReport(id, allowedBranchIds: <int>{}), isEmpty);
    });
  });

  group('الأطراف — حصر بـis_global أو branch_ids', () {
    test('{A} بتستبعد أطراف فرع ب', () async {
      final id = await report('parties', 'name');
      final rows = await db.executeReport(id, allowedBranchIds: {branchA});
      final names =
          rows.map((r) => r['name'] as String).where((n) => n.startsWith('طرف '));
      expect(names, ['طرف أ']);
    });
  });

  group('كيان بلا فلتر مدعوم — رفض لا حصر جزئي', () {
    test('journal_entries بترجّع فاضي لمستخدم محصور', () async {
      final id = await report('journal_entries', 'date');
      expect(await db.executeReport(id, allowedBranchIds: {branchA}), isEmpty,
          reason: 'الحصر الجزئي أخطر من غيابه — التقرير هيبان محصوراً وهو بيسرّب');
    });

    test('نفس الكيان شغّال عادي لمستخدم بوصول كامل', () async {
      final id = await report('journal_entries', 'date');
      // مفيش قيود يومية مزروعة — المهم إنه **ما يرفضش** (مفيش استثناء).
      expect(await db.executeReport(id), isEmpty);
    });

  });

  group('الموظفون — حصر بـbranch_id بعد ما اتقفل H6', () {
    setUp(() async {
      await db.into(db.employees).insert(EmployeesCompanion.insert(
          name: 'موظف أ', branchId: Value(branchA)));
      await db.into(db.employees).insert(EmployeesCompanion.insert(
          name: 'موظف ب', branchId: Value(branchB)));
      await db.into(db.employees)
          .insert(EmployeesCompanion.insert(name: 'موظف مركزي'));
    });

    test('{A} بتستبعد موظف فرع ب وتُبقي المركزي', () async {
      final id = await report('employees', 'name');
      final rows = await db.executeReport(id, allowedBranchIds: {branchA});
      final names = rows.map((r) => r['name'] as String);
      expect(names, containsAll(<String>['موظف أ', 'موظف مركزي']));
      expect(names, isNot(contains('موظف ب')),
          reason: 'ده المصدر الوحيد اللي فيه رواتب — التسريب هنا فلوس');
    });

    test('null = وصول كامل', () async {
      final id = await report('employees', 'name');
      final names =
          (await db.executeReport(id)).map((r) => r['name'] as String);
      expect(names,
          containsAll(<String>['موظف أ', 'موظف ب', 'موظف مركزي']));
    });

    test('{} بتفشل مقفولة', () async {
      final id = await report('employees', 'name');
      expect(await db.executeReport(id, allowedBranchIds: <int>{}), isEmpty);
    });
  });
}
