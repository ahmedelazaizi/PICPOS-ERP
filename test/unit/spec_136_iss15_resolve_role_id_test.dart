import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart' hide isNotNull;
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:picpos_erp/data/database/database.dart';
import 'package:picpos_erp/services/api/api_data_handler.dart';
import 'package:picpos_erp/services/api/api_handler_base.dart' show WsSubscriberInfo;

/// Spec 136 ISS-15 — the server must resolve (or placeholder-create) a role by
/// globalId before writing its permissions, so a role created only on a mirror
/// (drifted local id, never pushed) does not crash role_permissions with
/// Postgres FK 23503.
void main() {
  late AppDatabase db;
  late ApiDataHandler handler;

  setUp(() async {
    db = AppDatabase.forTesting();
    handler = ApiDataHandler(db, <WebSocketChannel, WsSubscriberInfo>{});
  });

  tearDown(() async => db.close());

  test('resolves an existing role by globalId even when the id drifts',
      () async {
    // Server-side role under id A with a known globalId.
    final serverId = await db.into(db.roles).insert(
          RolesCompanion.insert(
            name: 'مدير الفرع',
            globalId: const Value('role-gid-aqaba'),
          ),
        );

    // Client pushes permissions for its LOCAL id 7 (drifted) but with the
    // shared globalId.
    final resolved = await handler.resolveRoleId(
      clientRoleId: 7,
      roleGlobalId: 'role-gid-aqaba',
    );

    expect(resolved, serverId,
        reason: 'globalId must win over the drifted client id');
  });

  test('auto-creates a placeholder role when neither id nor globalId exists',
      () async {
    final before = await db.select(db.roles).get();

    final resolved = await handler.resolveRoleId(
      clientRoleId: 99999, // no such local id on the server (seeded ids are low)
      roleGlobalId: 'role-gid-new',
      fallbackName: 'كاشير العقبة',
    );

    expect(resolved, isNotNull);
    final created = await (db.select(db.roles)
          ..where((r) => r.id.equals(resolved!)))
        .getSingle();
    expect(created.globalId, 'role-gid-new',
        reason: 'placeholder must preserve the UUID for later reconciliation');
    expect(created.name, 'كاشير العقبة');
    expect(await db.select(db.roles).get(), hasLength(before.length + 1));

    // The whole point: setting permissions on the resolved id must NOT FK-fail.
    final perms = await db.getAllPermissions();
    expect(perms, isNotEmpty);
    await db.setRolePermissions(resolved!, [perms.first.id]);
    final assigned = await db.getPermissionsForRole(resolved);
    expect(assigned.map((p) => p.id), contains(perms.first.id));
  });

  test('falls back to the client id when no globalId is supplied', () async {
    final serverId = await db.into(db.roles).insert(
          RolesCompanion.insert(name: 'دور بلا معرف عالمي'),
        );

    final resolved = await handler.resolveRoleId(clientRoleId: serverId);
    expect(resolved, serverId);
  });
}
