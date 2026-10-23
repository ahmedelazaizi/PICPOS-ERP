// ═══════════════════════════════════════════════════════════════════════════
// H6 — الرواتب كانت تُقرأ عبر الفروع كلها.
// ═══════════════════════════════════════════════════════════════════════════
//
// عمود `employees.branch_id` موجود في السكيما من قديم، و`addEmployee`
// **لم يكتبه قطّ**. وشاشات HR ليس فيها ذكرٌ واحد لـ`branchId`. فمديرُ فرعٍ
// يفتح تبويب الرواتب فيقرأ رواتب الشركة كاملة.
//
// ── الترتيب داخل الإصلاح إلزامي ────────────────────────────────────────────
// الكتابة **قبل** الحصر. الحصر أوّلاً يُعطي صفر صفوف لكل الموظفين القدامى
// (كلّهم `branch_id = NULL`) — مظهرُ إصلاحٍ وهو تعطيل. فالمجموعة الأولى من
// الاختبارات (العمود يُكتب) هي الشرط، والثانية (الحصر) هي النتيجة.
//
// ── دلالة NULL ─────────────────────────────────────────────────────────────
// `branch_id = NULL` تعني موظفاً على مستوى الشركة (مدير عام · محاسب مركزي)
// ويظلّ مرئياً لكل نطاق — نفس قاعدة [BranchScope.isAllowed] بالحرف.
// ومجموعةٌ **فارغة** غير null تعني «لا يرى شيئاً» ⇒ صفر صفوف، فشلٌ مقفول
// مطابقٌ لكل تقرير محصور آخر في المستودع.
// ═══════════════════════════════════════════════════════════════════════════

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/data/database/database.dart';
import 'package:picpos_erp/data/database/extensions/hr_extensions.dart';

void main() {
  late AppDatabase db;
  late int branchA;
  late int branchB;

  setUp(() async {
    db = AppDatabase.forTesting();
    branchA = await db.into(db.branches).insert(BranchesCompanion.insert(
        name: 'فرع أ', globalId: const Value('gid-br-h6-a')));
    branchB = await db.into(db.branches).insert(BranchesCompanion.insert(
        name: 'فرع ب', globalId: const Value('gid-br-h6-b')));
  });

  tearDown(() => db.close());

  group('H6/١ — العمود يُكتب (شرط الحصر)', () {
    test('addEmployee يكتب branch_id', () async {
      final id = await db.addEmployee(
        name: 'موظف أ',
        salary: 3000,
        branchId: branchA,
      );

      final row = await db.getEmployeeById(id);
      expect(row!.branchId, branchA,
          reason: 'addEmployee كان يتجاهل العمود تماماً');
    });

    test('addEmployee بلا فرع يكتب NULL — موظف على مستوى الشركة', () async {
      final id = await db.addEmployee(name: 'مدير عام', salary: 9000);

      expect((await db.getEmployeeById(id))!.branchId, isNull);
    });

    test('updateEmployee ينقل الموظف بين الفروع', () async {
      final id = await db.addEmployee(name: 'موظف', branchId: branchA);

      await db.updateEmployee(id: id, branchId: branchB);

      expect((await db.getEmployeeById(id))!.branchId, branchB);
    });

    test('updateEmployee بلا branchId لا يمسح الفرع القائم', () async {
      final id = await db.addEmployee(name: 'موظف', branchId: branchA);

      await db.updateEmployee(id: id, name: 'موظف معدَّل');

      final row = await db.getEmployeeById(id);
      expect(row!.name, 'موظف معدَّل');
      expect(row.branchId, branchA,
          reason: 'تعديل الاسم لا يجوز أن يُخرج الموظف من فرعه');
    });
  });

  group('H6/٢ — الحصر بعد الكتابة', () {
    Future<List<String>> namesFor(Set<int>? scope) async {
      final rows = await db.getAllEmployees(allowedBranchIds: scope);
      return rows.map((e) => e.name).toList();
    }

    setUp(() async {
      await db.addEmployee(name: 'أ-موظف', salary: 3000, branchId: branchA);
      await db.addEmployee(name: 'ب-موظف', salary: 4000, branchId: branchB);
      await db.addEmployee(name: 'ج-مركزي', salary: 9000);
    });

    test('بلا حصر (‏null) = وصول كامل', () async {
      expect(await namesFor(null),
          containsAll(<String>['أ-موظف', 'ب-موظف', 'ج-مركزي']));
    });

    test('{أ} تستبعد موظف فرع ب وتُبقي المركزي', () async {
      final names = await namesFor({branchA});
      expect(names, contains('أ-موظف'));
      expect(names, contains('ج-مركزي'));
      expect(names, isNot(contains('ب-موظف')),
          reason: 'راتب ٤٠٠٠ لفرع آخر — هذا هو التسريب بعينه');
    });

    test('{ب} تستبعد موظف فرع أ', () async {
      final names = await namesFor({branchB});
      expect(names, contains('ب-موظف'));
      expect(names, isNot(contains('أ-موظف')));
    });

    test('{أ، ب} ترى الاثنين', () async {
      final names = await namesFor({branchA, branchB});
      expect(names, containsAll(<String>['أ-موظف', 'ب-موظف']));
    });

    test('المجموعة الفارغة تفشل مقفولة — صفر صفوف', () async {
      expect(await namesFor(<int>{}), isEmpty);
    });

    test('watchAllEmployees محصورة كذلك', () async {
      final rows = await db
          .watchAllEmployees(allowedBranchIds: {branchA})
          .first;
      final names = rows.map((e) => e.name);
      expect(names, contains('أ-موظف'));
      expect(names, isNot(contains('ب-موظف')));
    });

    test('watchAllEmployees بمجموعة فارغة تفشل مقفولة', () async {
      expect(
        await db.watchAllEmployees(allowedBranchIds: <int>{}).first,
        isEmpty,
      );
    });
  });

  group('H6/٣ — منشئ التقارير لم يعد يرفض employees', () {
    test('تقرير الموظفين محصورٌ فعلاً بدل أن يُرفض', () async {
      await db.addEmployee(name: 'أ-موظف', salary: 3000, branchId: branchA);
      await db.addEmployee(name: 'ب-موظف', salary: 4000, branchId: branchB);

      final reportId = await db.into(db.customReports).insert(
            CustomReportsCompanion.insert(
              name: 'ت',
              sourceEntity: 'employees',
              columns: 'name',
            ),
          );

      final rows =
          await db.executeReport(reportId, allowedBranchIds: {branchA});

      expect(rows.map((r) => r['name']), ['أ-موظف'],
          reason: 'كان `_scopeClauseFor` يُرجع null فيُرفض التقرير كاملاً');
    });

    test('المجموعة الفارغة ما زالت تفشل مقفولة', () async {
      await db.addEmployee(name: 'أ-موظف', branchId: branchA);
      final reportId = await db.into(db.customReports).insert(
            CustomReportsCompanion.insert(
              name: 'ت',
              sourceEntity: 'employees',
              columns: 'name',
            ),
          );

      expect(
        await db.executeReport(reportId, allowedBranchIds: <int>{}),
        isEmpty,
      );
    });
  });
}
