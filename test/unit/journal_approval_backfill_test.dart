import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/database/database.dart';

void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase.forTesting();
  });

  tearDown(() => db.close());

  test('backfills approval once and preserves a later revocation', () async {
    final create = await (db.select(db.permissions)
          ..where((p) => p.code.equals('accounting_journal')))
        .getSingle();
    final approve = await (db.select(db.permissions)
          ..where((p) => p.code.equals('approve_journal')))
        .getSingle();
    final roleId = await db.into(db.roles).insert(RolesCompanion.insert(
          name: 'backfill-test-role',
          description: const Value('test'),
          globalId: const Value('backfill-test-role'),
        ));
    await db.into(db.rolePermissions).insert(RolePermissionsCompanion.insert(
          roleId: roleId,
          permissionId: create.id,
        ));

    await (db.delete(db.settings)
          ..where((s) => s.key.equals('approve_journal_backfill_done')))
        .go();
    await db.backfillJournalApprovalPermissionOnce();
    expect(
      await (db.select(db.rolePermissions)
            ..where((rp) =>
                rp.roleId.equals(roleId) & rp.permissionId.equals(approve.id)))
          .getSingleOrNull(),
      isNotNull,
    );

    await (db.delete(db.rolePermissions)
          ..where((rp) =>
              rp.roleId.equals(roleId) & rp.permissionId.equals(approve.id)))
        .go();
    await db.backfillJournalApprovalPermissionOnce();
    expect(
      await (db.select(db.rolePermissions)
            ..where((rp) =>
                rp.roleId.equals(roleId) & rp.permissionId.equals(approve.id)))
          .getSingleOrNull(),
      isNull,
    );
  });
}
