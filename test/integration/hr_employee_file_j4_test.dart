// J4 (الجزء ١) — ملفُّ الموظف وربطُ الأدوار على قاعدةٍ حقيقيّة.
//
// Proves:
//  * an employee saved with every tab (personal / job / contract & pay with
//    allowances / documents) reads back field by field, and the rows cross a
//    `SELECT *` sync copy to a second database intact (raw columns ride
//    `employees`; the five v191 tables carry the sync columns and are in the
//    pull / namespace lists);
//  * history is recorded automatically: appointment, transfer, promotion,
//    salary change, termination (with date + reason), user link;
//  * one login user ↔ one employee (DAO check + the partial UNIQUE index);
//  * rep linking writes rep_resources, sales_routes.sales_rep_id +
//    route_rep_history and voucher_books.holder_employee_id/holder_user_id;
//  * the current rep is found from the logged-in user's employee link —
//    used by «حفظ كعميل دائم» (preferred route) and by the cash-customer
//    sale's rep stamp — with no rep for a user that is not one;
//  * pre-v191 employees are back-filled without loss (code, job title from
//    the legacy role, status, contract dates, appointment event).

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/data/database/database.dart';
import 'package:picpos_erp/data/database/sync_interceptor.dart';
import 'package:picpos_erp/domain/models/hr_employee_file.dart';
import 'package:picpos_erp/services/delta_pull_service.dart';
import 'package:picpos_erp/services/id_namespace_service.dart';

const _newTables = [
  'hr_departments',
  'hr_job_titles',
  'employee_allowances',
  'employee_documents',
  'employee_history',
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase db;
  late int warehouseId;
  late int productId;

  setUp(() async {
    SyncInterceptor.instance = null;
    db = AppDatabase.forTesting();
    warehouseId = (await db.getDefaultWarehouse())!.id;
    productId = await db.insertProduct(ProductsCompanion.insert(
      code: 'J4-1',
      name: 'منتج',
      salePrice: const Value(100.0),
      costPrice: const Value(60.0),
      currentStock: const Value(0.0),
      trackInventory: const Value(false),
    ));
    if ((await db.select(db.fiscalYears).get()).isEmpty) {
      final now = DateTime.now();
      await db.into(db.fiscalYears).insert(FiscalYearsCompanion.insert(
            name: '${now.year}',
            startDate: DateTime(now.year, 1, 1),
            endDate: DateTime(now.year, 12, 31),
            isClosed: const Value(false),
          ));
    }
  });
  tearDown(() async {
    await db.close();
    SyncInterceptor.instance = null;
  });

  Future<int> user(String name) => db.createUser(
      username: name, password: 'pw-$name-1', displayName: name);

  Future<int> branch(String name) =>
      db.into(db.branches).insert(BranchesCompanion.insert(name: name));

  Future<List<String>> events(int id) async =>
      [for (final e in await db.listEmployeeHistory(id)) e.eventType];

  group('ملفُّ الموظف بكلّ تبويباته', () {
    test('يُحفَظ ويُقرأ حقلاً حقلاً، والبدلاتُ والمستندات', () async {
      final sales = await db.saveHrDepartment(name: 'المبيعات', code: 'S');
      final repTitle =
          await db.saveHrJobTitle(name: 'مندوب مبيعات', departmentId: sales);
      final b = await branch('فرع الشرق');
      final manager = await db.saveEmployeeProfile(
          const EmployeeProfile(name: 'مدير المبيعات'));
      final id = await db.saveEmployeeProfile(
        EmployeeProfile(
          name: 'أحمد علي',
          nameEn: 'Ahmed Ali',
          nationalId: '29001011234567',
          birthDate: DateTime(1990, 1, 1),
          gender: EmployeeGender.male,
          nationality: 'مصري',
          phone: '0100',
          phone2: '0111',
          email: 'a@x.com',
          address: 'القاهرة',
          emergencyContactName: 'محمد (أخ)',
          emergencyContactPhone: '0122',
          photoPath: r'C:\p.png',
          departmentId: sales,
          jobTitleId: repTitle,
          branchId: b,
          managerId: manager,
          hireDate: DateTime(2024, 3, 1),
          employmentType: EmploymentType.contract,
          contractStart: DateTime(2024, 3, 1),
          contractEnd: DateTime(2025, 3, 1),
          probationEnd: DateTime(2024, 6, 1),
          basicSalary: 5000,
          paymentMethod: SalaryPaymentMethod.bank,
          bankName: 'بنك مصر',
          bankAccount: '123',
          iban: 'EG00',
        ),
        allowances: const [
          EmployeeAllowance(name: 'سكن', amount: 1000),
          EmployeeAllowance(
              name: 'انتقال', amount: 10, type: AllowanceType.percent),
        ],
      );
      final p = (await db.getEmployeeProfile(id))!;
      expect(p.code, 'EMP-0002', reason: 'the next free EMP code');
      expect(p.nameEn, 'Ahmed Ali');
      expect(p.nationalId, '29001011234567');
      expect(p.birthDate, DateTime(1990, 1, 1));
      expect(p.gender, EmployeeGender.male);
      expect(p.nationality, 'مصري');
      expect([p.phone, p.phone2, p.email], ['0100', '0111', 'a@x.com']);
      expect(p.address, 'القاهرة');
      expect(p.emergencyContactName, 'محمد (أخ)');
      expect(p.emergencyContactPhone, '0122');
      expect(p.photoPath, r'C:\p.png');
      expect(p.departmentName, 'المبيعات');
      expect(p.jobTitleName, 'مندوب مبيعات');
      expect(p.branchName, 'فرع الشرق');
      expect(p.managerName, 'مدير المبيعات');
      expect(p.hireDate, DateTime(2024, 3, 1));
      expect(p.employmentType, EmploymentType.contract);
      expect(p.status, EmployeeStatus.active);
      expect(p.contractStart, DateTime(2024, 3, 1));
      expect(p.contractEnd, DateTime(2025, 3, 1));
      expect(p.probationEnd, DateTime(2024, 6, 1));
      expect(p.basicSalary, 5000);
      expect(p.paymentMethod, SalaryPaymentMethod.bank);
      expect([p.bankName, p.bankAccount, p.iban], ['بنك مصر', '123', 'EG00']);

      final allowances = await db.listEmployeeAllowances(id);
      expect(allowances.map((a) => a.name), ['سكن', 'انتقال']);
      expect(allowances.fold<double>(0, (s, a) => s + a.valueFor(5000)), 1500);

      // Edit: one allowance kept (by id), one removed, one added.
      await db.saveEmployeeProfile(p, allowances: [
        EmployeeAllowance(id: allowances.first.id, name: 'سكن', amount: 1200),
        const EmployeeAllowance(name: 'هاتف', amount: 100),
      ]);
      expect([
        for (final a in await db.listEmployeeAllowances(id)) '${a.name}:${a.amount}'
      ], ['سكن:1200.0', 'هاتف:100.0']);

      final now = DateTime.now();
      await db.saveEmployeeDocument(
          id,
          EmployeeDocument(
              docType: 'بطاقة هوية',
              docNumber: '2900',
              issueDate: DateTime(2020),
              expiryDate: now.add(const Duration(days: 10)),
              filePath: r'C:\id.pdf'));
      await db.saveEmployeeDocument(
          id,
          EmployeeDocument(
              docType: 'جواز سفر',
              expiryDate: now.add(const Duration(days: 400))));
      final docs = await db.listEmployeeDocuments(id);
      expect(docs.map((d) => d.docType), ['بطاقة هوية', 'جواز سفر']);
      expect(docs.first.expiryState(now), DocumentExpiryState.expiringSoon);
      expect(docs.last.expiryState(now), DocumentExpiryState.valid);
      expect(await db.expiringDocumentCounts(), {id: 1});
      expect(
          () => db.saveEmployeeDocument(
              id,
              EmployeeDocument(
                  docType: 'x',
                  issueDate: DateTime(2024),
                  expiryDate: DateTime(2023))),
          throwsA(isA<HrException>()));
      await db.deleteEmployeeDocument(docs.last.id!);
      expect(await db.listEmployeeDocuments(id), hasLength(1));

      // The legacy screens still see the employee through drift.
      final legacy = await (db.select(db.employees)
            ..where((e) => e.id.equals(id)))
          .getSingle();
      expect(legacy.salary, 1 * 5000);
      expect(legacy.isActive, isTrue);
      expect(legacy.branchId, b);
    });

    test('السجلُّ يُسجَّل تلقائياً: تعيين ونقل وترقية وراتب وإنهاء خدمة',
        () async {
      final a = await db.saveHrDepartment(name: 'أ');
      final bDept = await db.saveHrDepartment(name: 'ب');
      final t1 = await db.saveHrJobTitle(name: 'كاشير');
      final t2 = await db.saveHrJobTitle(name: 'مشرف');
      final id = await db.saveEmployeeProfile(EmployeeProfile(
          name: 'سارة', departmentId: a, jobTitleId: t1, basicSalary: 3000));
      expect(await events(id), [HrEventType.appointment]);

      var p = (await db.getEmployeeProfile(id))!;
      await db.saveEmployeeProfile(EmployeeProfile(
        id: id,
        code: p.code,
        name: p.name,
        departmentId: bDept,
        jobTitleId: t2,
        basicSalary: 3500,
        hireDate: p.hireDate,
      ));
      expect((await events(id)).toSet(), {
        HrEventType.appointment,
        HrEventType.transfer,
        HrEventType.promotion,
        HrEventType.salaryChange,
      });
      final history = await db.listEmployeeHistory(id);
      final promotion =
          history.firstWhere((e) => e.eventType == HrEventType.promotion);
      expect([promotion.fromValue, promotion.toValue], ['كاشير', 'مشرف']);

      p = (await db.getEmployeeProfile(id))!;
      await db.saveEmployeeProfile(EmployeeProfile(
        id: id,
        code: p.code,
        name: p.name,
        departmentId: p.departmentId,
        jobTitleId: p.jobTitleId,
        basicSalary: p.basicSalary,
        hireDate: p.hireDate,
        status: EmployeeStatus.terminated,
        terminationReason: 'استقالة',
      ));
      p = (await db.getEmployeeProfile(id))!;
      expect(p.status, EmployeeStatus.terminated);
      expect(p.terminationDate, isNotNull,
          reason: 'termination without a date takes today');
      expect(p.terminationReason, 'استقالة');
      final termination = (await db.listEmployeeHistory(id))
          .firstWhere((e) => e.eventType == HrEventType.termination);
      expect(termination.notes, 'استقالة');
      final legacy = await (db.select(db.employees)
            ..where((e) => e.id.equals(id)))
          .getSingle();
      expect(legacy.isActive, isFalse,
          reason: 'legacy lists hide a terminated employee');
    });

    test('قيود: كودٌ مكرّر، مديرُ نفسه، حلقةٌ في الهيكل، قسمٌ مستعمَل',
        () async {
      final a = await db.saveEmployeeProfile(
          const EmployeeProfile(name: 'أ', code: 'X-1'));
      expect(
          () => db.saveEmployeeProfile(
              const EmployeeProfile(name: 'ب', code: 'X-1')),
          throwsA(isA<HrException>()));
      final b = await db.saveEmployeeProfile(
          EmployeeProfile(name: 'ب', managerId: a));
      final pa = (await db.getEmployeeProfile(a))!;
      expect(
          () => db.saveEmployeeProfile(EmployeeProfile(
              id: a, code: pa.code, name: pa.name, managerId: a)),
          throwsA(isA<HrException>()));
      expect(
          () => db.saveEmployeeProfile(EmployeeProfile(
              id: a, code: pa.code, name: pa.name, managerId: b)),
          throwsA(isA<HrException>()),
          reason: 'b reports to a — a cannot report to b');
      final dept = await db.saveHrDepartment(name: 'المخازن');
      final pb = (await db.getEmployeeProfile(b))!;
      await db.saveEmployeeProfile(EmployeeProfile(
          id: b,
          code: pb.code,
          name: pb.name,
          managerId: a,
          departmentId: dept));
      expect(() => db.deleteHrDepartment(dept), throwsA(isA<HrException>()));
      final empty = await db.saveHrDepartment(name: 'فارغ');
      await db.deleteHrDepartment(empty);
      expect((await db.listHrDepartments()).map((d) => d.name), ['المخازن']);
      expect(
          buildOrgChart(await db.listEmployeeProfiles())
              .map((n) => (n.employee.name, n.reports.length)),
          [('أ', 1)]);
    });
  });

  group('مستخدمٌ واحدٌ لكلّ موظف', () {
    test('الربطُ يُرفَض لمستخدمٍ مربوطٍ بغيره، والفهرسُ الفريد يحرس',
        () async {
      final u = await user('ahmed');
      final e1 = await db.saveEmployeeProfile(const EmployeeProfile(name: 'أ'));
      final e2 = await db.saveEmployeeProfile(const EmployeeProfile(name: 'ب'));
      await db.linkEmployeeUser(employeeId: e1, userId: u);
      expect(await db.employeeIdForUser(u), e1);
      expect((await db.getEmployeeProfile(e1))!.username, 'ahmed');
      expect(await events(e1), contains(HrEventType.userLink));
      await expectLater(db.linkEmployeeUser(employeeId: e2, userId: u),
          throwsA(isA<HrException>()));
      expect((await db.linkableUsers(e2)).map((x) => x.id), isNot(contains(u)));
      // The partial UNIQUE index holds even if the DAO is bypassed.
      await expectLater(
          db.customStatement(
              'UPDATE employees SET user_id = $u WHERE id = $e2'),
          throwsA(anything));
      // Unlink frees the user for another employee.
      await db.linkEmployeeUser(employeeId: e1, userId: null);
      await db.linkEmployeeUser(employeeId: e2, userId: u);
      expect(await db.employeeIdForUser(u), e2);
    });
  });

  group('ربطُ المندوب', () {
    test('العهدةُ والمساراتُ والدفاترُ تُكتَب متّسقة', () async {
      final u = await user('rep1');
      final rep = await db.saveEmployeeProfile(
          const EmployeeProfile(name: 'مندوب الشرق'));
      await db.setEmployeeRoleTags(rep, {HrRoleTag.rep});
      expect((await db.getEmployeeProfile(rep))!.isRep, isTrue);
      await db.linkEmployeeUser(employeeId: rep, userId: u);

      final van = await db
          .into(db.warehouses)
          .insert(WarehousesCompanion.insert(name: 'سيارة 1'));
      final safe = await db.into(db.safes).insert(SafesCompanion.insert(
          name: 'عهدة 1', safeType: const Value('cash')));
      await db.saveRepResources(
          employeeId: rep, vanWarehouseId: van, custodySafeId: safe);
      final res = (await db.getRepResources(rep))!;
      expect([res.vanWarehouseId, res.custodySafeId], [van, safe]);

      final route = await db.saveDistributionRoute(name: 'خط السبت');
      await db.setRouteRep(route, rep);
      expect((await db.routeRepHistory(route)).single.repEmployeeId, rep);
      expect(
          (await db.listDistributionRoutes()).single.repEmployeeId, rep);

      final book = await db.createVoucherBook(
          type: 'receipt', rangeFrom: 1, rangeTo: 50, label: 'دفتر 1');
      await db.setVoucherBookHolder(book, rep);
      final held = (await db.listVoucherBooks()).single;
      expect(held.holderEmployeeId, rep);
      expect(held.holderUserId, u,
          reason: 'the holder user follows the linked login user');

      // Relinking the employee to another user moves the book's user too.
      final u2 = await user('rep1b');
      await db.linkEmployeeUser(employeeId: rep, userId: null);
      await db.linkEmployeeUser(employeeId: rep, userId: u2);
      expect((await db.listVoucherBooks()).single.holderUserId, u2);

      await db.setVoucherBookHolder(book, null);
      expect((await db.listVoucherBooks()).single.holderEmployeeId, isNull);
    });
  });

  group('المندوبُ الحاليّ من ربط المستخدم', () {
    test('حفظ كعميل دائم: مسارُ اليوم مقترَح، وغيرُ المندوب بلا اقتراح',
        () async {
      final u = await user('rep2');
      final rep = await db.saveEmployeeProfile(
          const EmployeeProfile(name: 'مندوب'));
      await db.linkEmployeeUser(employeeId: rep, userId: u);
      final today = DateTime(2026, 10, 3); // Saturday (ISO 6)
      final sat = await db.saveDistributionRoute(
          name: 'السبت', repEmployeeId: rep, visitDays: [6]);
      await db.saveDistributionRoute(
          name: 'الأحد', repEmployeeId: rep, visitDays: [7]);
      final ctx = (await db.currentRepForUser(u, now: today))!;
      expect(ctx.repEmployeeId, rep);
      expect(ctx.routeIds, hasLength(2));
      expect(ctx.preferredRouteId, sat);

      // The dialog's pick is passed to the J3 save path unchanged.
      final c = await db.createPermanentCustomerFromCashSale(
          name: 'بقالة جديدة', routeId: ctx.preferredRouteId);
      expect((await db.currentRouteOfCustomer(c))!.repEmployeeId, rep);

      final other = await user('cashier');
      final cashierEmp = await db.saveEmployeeProfile(
          const EmployeeProfile(name: 'كاشير'));
      await db.linkEmployeeUser(employeeId: cashierEmp, userId: other);
      expect(await db.currentRepForUser(other), isNull,
          reason: 'not a rep ⇒ the route picker stays the fallback');
      expect(await db.currentRepForUser(await user('nobody')), isNull);
    });

    test('بيعُ «عميل نقدي» يُختَم بمندوب المستخدم، وعميلُ المسار بمندوبه',
        () async {
      final u = await user('rep3');
      final rep = await db.saveEmployeeProfile(
          const EmployeeProfile(name: 'مندوب الغرب'));
      await db.setEmployeeRoleTags(rep, {HrRoleTag.rep});
      await db.linkEmployeeUser(employeeId: rep, userId: u);
      final cash = (await db.systemPartyId(kSystemRoleCashCustomer))!;

      Future<int> sale(int? customerId, int userId) => db.createSalesInvoice(
            invoiceNumber: 'J4-${DateTime.now().microsecondsSinceEpoch}',
            warehouseId: warehouseId,
            userId: userId,
            subtotal: 100,
            discount: 0,
            tax: 0,
            total: 100,
            paid: 100,
            paymentMethod: 'cash',
            customerId: customerId,
            items: [
              SalesInvoiceItemsCompanion.insert(
                invoiceId: 0,
                productId: productId,
                quantity: 1,
                unitPrice: 100,
                total: 100,
                costPrice: const Value(60.0),
              ),
            ],
          );

      final inv = await sale(cash, u);
      expect((await db.getDocumentRepStamp('sales_invoices', inv)).repEmployeeId,
          rep);

      final admin = await user('plain');
      final inv2 = await sale(cash, admin);
      expect(
          (await db.getDocumentRepStamp('sales_invoices', inv2)).repEmployeeId,
          isNull,
          reason: 'a user with no rep link leaves the sale unstamped');

      // A routed customer keeps its route's rep — the user link never wins.
      final otherRep =
          await db.saveEmployeeProfile(const EmployeeProfile(name: 'آخر'));
      final route =
          await db.saveDistributionRoute(name: 'خط', repEmployeeId: otherRep);
      final c = await db.into(db.parties).insert(PartiesCompanion.insert(
          name: 'عميل خط', isCustomer: const Value(true)));
      await db.assignCustomerToRoute(customerId: c, routeId: route);
      final inv3 = await sale(c, u);
      expect(
          (await db.getDocumentRepStamp('sales_invoices', inv3)).repEmployeeId,
          otherRep);
    });
  });

  group('الهجرةُ والمزامنة', () {
    test('موظفو ما قبل v191 يُستكمَلون بلا فقد', () async {
      final legacy = await db.into(db.employees).insert(
          EmployeesCompanion.insert(
              name: 'قديم',
              role: const Value('cashier'),
              salary: const Value(2500),
              isActive: const Value(false)));
      await db.into(db.employeeContracts).insert(
          EmployeeContractsCompanion.insert(
              employeeId: legacy,
              startDate: DateTime(2023, 1, 1),
              endDate: Value(DateTime(2024, 1, 1)),
              salary: 2500));
      await db.backfillHrCoreData();
      await db.backfillHrCoreData(); // idempotent
      final p = (await db.getEmployeeProfile(legacy))!;
      expect(p.code, 'EMP-${legacy.toString().padLeft(4, '0')}');
      expect(p.jobTitleName, 'كاشير');
      expect(p.status, EmployeeStatus.suspended);
      expect(p.roleTags, {HrRoleTag.cashier});
      expect(p.contractStart, DateTime(2023, 1, 1));
      expect(p.contractEnd, DateTime(2024, 1, 1));
      expect(p.basicSalary, 2500);
      expect(await events(legacy), [HrEventType.appointment],
          reason: 'one appointment event, not one per startup');
      expect(
          (await db.listHrJobTitles()).where((t) => t.name == 'كاشير'),
          hasLength(1));
    });

    test('الجداولُ الخمسةُ في قوائم المزامنة، وتعبر نسخةَ SELECT *', () async {
      for (final t in _newTables) {
        expect(DeltaPullService.pullTables, contains(t));
        expect(DeltaPullService.deltaOnlyTables, contains(t));
        expect(DeltaPullService.branchScopedPullTables, contains(t));
        expect(IdNamespaceService.namespacedTables, contains(t));
        final cols = {
          for (final c in await db.customSelect('PRAGMA table_info($t)').get())
            c.data['name'] as String,
        };
        expect(
            cols,
            containsAll(<String>[
              'global_id',
              'last_modified_at',
              'deleted_at',
              'origin_client_id',
              'row_version',
            ]),
            reason: t);
      }
      final dept = await db.saveHrDepartment(name: 'المبيعات');
      final id = await db.saveEmployeeProfile(
        EmployeeProfile(
            name: 'منقول',
            departmentId: dept,
            iban: 'EG11',
            employmentType: EmploymentType.partTime),
        allowances: const [EmployeeAllowance(name: 'سكن', amount: 300)],
      );
      await db.saveEmployeeDocument(
          id, const EmployeeDocument(docType: 'هوية', docNumber: '1'));

      final other = AppDatabase.forTesting();
      addTearDown(other.close);
      await other.customSelect('SELECT 1').get();
      for (final table in ['employees', ..._newTables]) {
        for (final row in await db.customSelect('SELECT * FROM $table').get()) {
          final cols = row.data.keys.toList();
          await other.customStatement(
            'INSERT OR REPLACE INTO $table (${cols.join(', ')}) '
            'VALUES (${List.filled(cols.length, '?').join(', ')})',
            [for (final col in cols) row.data[col]],
          );
        }
      }
      final p = (await other.getEmployeeProfile(id))!;
      expect(p.departmentName, 'المبيعات');
      expect(p.iban, 'EG11');
      expect(p.employmentType, EmploymentType.partTime);
      expect((await other.listEmployeeAllowances(id)).single.amount, 300);
      expect((await other.listEmployeeDocuments(id)).single.docNumber, '1');
      expect(await other.listEmployeeHistory(id), isNotEmpty);
    });
  });
}
