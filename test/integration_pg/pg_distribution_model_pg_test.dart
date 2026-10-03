// ═══════════════════════════════════════════════════════════════════════════
// المرحلة و (v185) — نموذجُ التوزيع على PostgreSQL
// ═══════════════════════════════════════════════════════════════════════════
//
// الجداولُ الأربعةُ وأعمدةُ الختم **SQL خامٌّ بلا صنفِ drift**، فيُنشئها
// `ensureDistributionModelSchema` على PG بصيغتها (`SERIAL` · `BIGINT`). وهنا
// يُقاس أنّها موجودةٌ بأعمدة الدلتا، وأنّ القاعدة (مسارٌ واحدٌ للعميل) والختمَ
// يعملان على PG كما على SQLite — ومنها معاملاتٌ بقيمٍ فارغةٍ في أعمدةٍ رقميّة
// (‏PG يرفض NULL غيرَ مُنمَّط في عمود INTEGER).
//
// ⚠️ يعمل عبر `dart run scripts/run_pg_tests.dart` وحدَه.

@Tags(['pg'])
library;

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/database/database.dart';

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

  test('الجداولُ الأربعةُ وأعمدةُ الختم موجودةٌ على PG', () async {
    for (final t in [
      'distribution_areas',
      'route_customers',
      'route_rep_history',
      'rep_resources',
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
    expect(await columnsOf('sales_routes'),
        containsAll(const ['area_id', 'visit_days']));
    for (final t in kRepStampedTables) {
      expect(await columnsOf(t),
          containsAll(const ['rep_employee_id', 'route_id']),
          reason: t);
    }
  });

  test('مسارٌ واحدٌ للعميل، والمندوبُ مشتقٌّ، والتاريخُ محفوظ', () async {
    final x = await db
        .into(db.employees)
        .insert(EmployeesCompanion.insert(name: 'س'));
    final y = await db
        .into(db.employees)
        .insert(EmployeesCompanion.insert(name: 'ص'));
    final area = await db.saveDistributionArea(name: 'الشرق');
    await db.saveDistributionArea(id: area, name: 'الشرق ١');
    final a = await db.saveDistributionRoute(
        name: 'أ', repEmployeeId: x, areaId: area, visitDays: [1, 4]);
    final b = await db.saveDistributionRoute(name: 'ب', repEmployeeId: y);
    final c = await db.into(db.parties).insert(PartiesCompanion.insert(
        name: 'عميل', isCustomer: const Value(true)));

    await db.assignCustomerToRoute(customerId: c, routeId: a);
    expect((await db.currentRouteOfCustomer(c))!.repEmployeeId, x);
    expect((await db.currentRouteOfCustomer(c))!.areaName, 'الشرق ١');

    await db.assignCustomerToRoute(customerId: c, routeId: b);
    final info = (await db.currentRouteOfCustomer(c))!;
    expect((info.routeId, info.repEmployeeId), (b, y));
    expect(await db.customerRouteHistory(c), hasLength(2));

    await db.setRouteRep(b, x);
    expect((await db.routeRepHistory(b)).map((h) => h.repEmployeeId), [y, x]);
    expect((await db.listDistributionRoutes()).length, 2);

    await db.saveRepResources(employeeId: x);
    expect((await db.getRepResources(x))!.vanWarehouseId, isNull);
  });

  test('v194 field expense categories seed and remain editable on PG', () async {
    expect(await columnsOf('field_expense_categories'), containsAll(const [
      'id', 'name', 'account_code', 'global_id', 'last_modified_at',
      'deleted_at', 'origin_client_id', 'row_version',
    ]));
    expect(await columnsOf('route_visits'),
        containsAll(const ['latitude', 'longitude', 'field_geo']));
    for (final table in ['sales_invoices', 'safe_transactions']) {
      expect(await columnsOf(table), contains('field_geo'), reason: table);
    }

    final seeded = await db.listFieldExpenseCategories();
    expect(seeded, hasLength(6));
    expect(seeded.map((category) => category.nameEn),
        containsAll(const ['Fuel', 'Parking', 'Other']));
    final id = await db.saveFieldExpenseCategory(
        name: 'اختبار', accountCode: '614');
    await db.saveFieldExpenseCategory(
        id: id, name: 'اختبار معدل', accountCode: '617', isActive: false);
    final saved = (await db.listFieldExpenseCategories())
        .singleWhere((category) => category.id == id);
    expect((saved.name, saved.accountCode, saved.isActive),
        ('اختبار معدل', '617', false));
    expect(saved.globalId, isNotNull);
  });
}
