// ═══════════════════════════════════════════════════════════════════════════
// J4 (v191) — ملفُّ الموظف وربطُ الأدوار على PostgreSQL
// ═══════════════════════════════════════════════════════════════════════════
//
// الجداولُ الخمسةُ وأعمدةُ `employees` الجديدة **SQL خامٌّ بلا صنفِ drift**،
// فيُنشئها `ensureHrCoreSchema` على PG بصيغتها (`SERIAL` · `BIGINT`). وهنا
// يُقاس أنّها موجودةٌ بأعمدة الدلتا، وأنّ الحفظَ بقيمٍ فارغةٍ في أعمدةٍ رقميّة
// (‏PG يرفض NULL غيرَ مُنمَّط في عمود INTEGER) والسجلَّ والربطَ الفريدَ
// والاستكمالَ تعمل على PG كما على SQLite.
//
// ⚠️ يعمل عبر `dart run scripts/run_pg_tests.dart` وحدَه.

@Tags(['pg'])
library;

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/data/database/database.dart';
import 'package:picpos_erp/domain/models/hr_employee_file.dart';

import '_support/pg_fixture.dart';

void main() {
  late AppDatabase db;

  setUp(() async {
    final fx = await bootPgTestSchema();
    addTearDown(fx.tearDown);
    db = fx.db;
    await db.select(db.accounts).get(); // يُجبر الهجرةَ ومسارَ الإقلاع
  });

  Future<Set<String>> columnsOf(String table) async {
    final rows = await db
        .customSelect(
          "SELECT column_name FROM information_schema.columns "
          "WHERE table_name = '$table'",
        )
        .get();
    return rows.map((r) => r.data['column_name'] as String).toSet();
  }

  test('الجداولُ الخمسةُ وأعمدةُ الموظف موجودةٌ على PG', () async {
    for (final t in [
      'hr_departments',
      'hr_job_titles',
      'employee_allowances',
      'employee_documents',
      'employee_history',
    ]) {
      expect(
          await columnsOf(t),
          containsAll(const [
            'global_id',
            'last_modified_at',
            'deleted_at',
            'origin_client_id',
            'row_version',
          ]),
          reason: t);
    }
    expect(
        await columnsOf('employees'),
        containsAll(const [
          'employee_code',
          'department_id',
          'job_title_id',
          'manager_id',
          'employment_status',
          'termination_date',
          'contract_end',
          'iban',
          'user_id',
          'role_tags',
        ]));
  });

  test('الحفظُ والسجلُّ والربطُ الفريدُ والاستكمال', () async {
    final dept = await db.saveHrDepartment(name: 'المبيعات');
    await db.saveHrDepartment(id: dept, name: 'المبيعات', code: null);
    final title = await db.saveHrJobTitle(name: 'مندوب', departmentId: dept);
    final id = await db.saveEmployeeProfile(
      EmployeeProfile(
          name: 'أحمد',
          departmentId: dept,
          jobTitleId: title,
          birthDate: DateTime(1990, 5, 1),
          basicSalary: 4000),
      allowances: const [EmployeeAllowance(name: 'سكن', amount: 500.5)],
    );
    final p = (await db.getEmployeeProfile(id))!;
    expect(p.code, startsWith('EMP-'));
    expect(p.birthDate, DateTime(1990, 5, 1));
    expect(p.departmentName, 'المبيعات');
    expect((await db.listEmployeeAllowances(id)).single.amount, 500.5);

    await db.saveEmployeeProfile(EmployeeProfile(
        id: id,
        code: p.code,
        name: p.name,
        basicSalary: 4500,
        status: EmployeeStatus.terminated,
        terminationReason: 'نهاية عقد'));
    final types = [
      for (final e in await db.listEmployeeHistory(id)) e.eventType,
    ];
    expect(
        types,
        containsAll(const [
          HrEventType.appointment,
          HrEventType.transfer,
          HrEventType.promotion,
          HrEventType.salaryChange,
          HrEventType.termination,
        ]));

    await db.saveEmployeeDocument(
        id, const EmployeeDocument(docType: 'هوية'));
    expect((await db.listEmployeeDocuments(id)).single.expiryDate, isNull);
    expect(await db.expiringDocumentCounts(), isEmpty);

    final u = await db.createUser(
        username: 'pg.rep', password: 'pg-rep-pw-1', displayName: 'PG');
    final other = await db.saveEmployeeProfile(
        const EmployeeProfile(name: 'آخر'));
    await db.linkEmployeeUser(employeeId: other, userId: u);
    await expectLater(db.linkEmployeeUser(employeeId: id, userId: u),
        throwsA(isA<HrException>()));
    expect(await db.employeeIdForUser(u), other);
    await db.setEmployeeRoleTags(other, {HrRoleTag.rep});
    final route =
        await db.saveDistributionRoute(name: 'خط', repEmployeeId: other);
    expect((await db.currentRepForUser(u))!.preferredRouteId, route);

    final legacy = await db.into(db.employees).insert(
        EmployeesCompanion.insert(name: 'قديم', role: const Value('waiter')));
    await db.backfillHrCoreData();
    await db.backfillHrCoreData();
    final lp = (await db.getEmployeeProfile(legacy))!;
    expect(lp.jobTitleName, 'نادل');
    expect(lp.status, EmployeeStatus.active);
    expect((await db.listEmployeeHistory(legacy)), hasLength(1));
  });
}
