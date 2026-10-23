// F.6 (2026-10-18) — الحجوزات انتقلت من tables_view إلى bookings_view؛ وكلُّ دورٍ
// يملك الأولى يُمنَح الثانية في إقلاعٍ idempotent (علَمٌ مرّةً واحدة).
import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/data/database/database.dart';
import 'package:picpos_erp/services/role_grant_preflight_service.dart';

const _flag = 'bookings_view_from_tables_view_backfill_done';

void main() {
  late AppDatabase db;
  late RoleGrantPreflightService svc;

  Future<int> permId(String code) async => (await (db.select(db.permissions)
            ..where((p) => p.code.equals(code)))
          .getSingle())
      .id;

  Future<Set<int>> holders(String code) async {
    final id = await permId(code);
    final rows = await (db.select(db.rolePermissions)
          ..where((rp) => rp.permissionId.equals(id)))
        .get();
    return {for (final r in rows) r.roleId};
  }

  Future<int> newRole(String name, {required List<String> codes}) async {
    final id = await db.into(db.roles).insert(RolesCompanion.insert(name: name));
    for (final c in codes) {
      await db.into(db.rolePermissions).insert(RolePermissionsCompanion.insert(
          roleId: id, permissionId: await permId(c)));
    }
    return id;
  }

  setUp(() {
    db = AppDatabase.forTesting();
    svc = RoleGrantPreflightService(db);
  });
  tearDown(() => db.close());

  test('دورٌ مخصَّص بـtables_view يُمنح bookings_view، ومن لا يملكها لا', () async {
    final withTables = await newRole('دور طاولات', codes: ['tables_view']);
    final without = await newRole('دور بلا طاولات', codes: ['products_view']);
    // الإقلاعُ ختم العلَم مبكراً — نُعيد الحالة كما قبل الترقية.
    await db.setSetting(_flag, 'false');

    final n = await svc.grantBookingsViewToTablesViewHoldersOnce();
    expect(n, greaterThanOrEqualTo(1));

    final bv = await holders('bookings_view');
    expect(bv, contains(withTables));
    expect(bv, isNot(contains(without)));
    // كلُّ حاملٍ لـtables_view صار حاملاً لـbookings_view.
    expect((await holders('tables_view')).difference(bv), isEmpty);
  });

  test('idempotent، ولا يُعيد منحاً نزعه المشغّل بعد الختم', () async {
    await newRole('دور طاولات 2', codes: ['tables_view']);
    await db.setSetting(_flag, 'false');
    await svc.grantBookingsViewToTablesViewHoldersOnce();
    expect(await db.getSettingValue(_flag), 'true');
    final before = await holders('bookings_view');
    expect(await svc.grantBookingsViewToTablesViewHoldersOnce(), 0);
    expect(await holders('bookings_view'), before);
  });

  test('نزعُ المشغّل بعد الختم لا يُردّ في الإقلاع التالي', () async {
    final role = await newRole('دور طاولات 3', codes: ['tables_view']);
    await db.setSetting(_flag, 'false');
    await svc.grantBookingsViewToTablesViewHoldersOnce();
    final bvId = await permId('bookings_view');
    await (db.delete(db.rolePermissions)
          ..where((rp) =>
              rp.roleId.equals(role) & rp.permissionId.equals(bvId)))
        .go();

    expect(await svc.grantMissingDefaultsOnce(), isA<int>());
    expect(await holders('bookings_view'), isNot(contains(role)));
  });
}
