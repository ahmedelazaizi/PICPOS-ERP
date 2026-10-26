// Login leftover #3: a device that ALREADY has two active `admin` rows (the
// seeded id 1 and a later renumbered row an old sync created) is repaired by an
// idempotent run: id 1 stays the single active system admin and adopts the
// main's credential / global id / stamp; the stray is deactivated (renamed),
// NEVER deleted - rows that reference it keep resolving.
//
// Reproduces the old FLEET/R7 duplicate (see synced_admin_identity_test.dart for
// the prevention side).
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:picpos_erp/core/logging/diagnostic_logger.dart';
import 'package:picpos_erp/data/database/database_barrel.dart';
import 'package:picpos_erp/services/auth/admin_duplicate_repair.dart';
import 'package:picpos_erp/services/auth/credential_stamp_store.dart';
import 'package:picpos_erp/services/deployment/provisioning_applier.dart';
import 'package:picpos_erp/services/deployment/provisioning_record.dart';
import 'package:picpos_erp/services/security_service.dart';
import 'package:picpos_erp/services/sync/strategies/user_sync_strategy.dart';

const _mainPw = 'Main#Admin2026x';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
          const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
          (call) async => null);
  late AppDatabase db;
  late String mainHash;

  setUpAll(() async {
    mainHash = await SecurityService.hashPasswordArgon2(_mainPw);
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({'network_api_token': 'tok'});
    DiagnosticLogger.enableTestMode();
    db = AppDatabase.forTesting();
    await db.getBranches(); // open + seed (admin id 1, admin/admin)
  });

  tearDown(() async {
    await Future<void>.delayed(const Duration(milliseconds: 400));
    await db.close();
  });

  Future<void> insertStray({
    int id = 5,
    String? globalId = 'host-admin-gid',
    String? hash,
    bool active = true,
  }) =>
      db.into(db.users).insert(UsersCompanion.insert(
            id: Value(id),
            username: 'admin',
            passwordHash: hash ?? mainHash,
            passwordSalt: const Value(''),
            displayName: 'المدير',
            globalId: Value(globalId),
            isActive: Value(active),
            roleId: const Value(1),
          ));

  Future<List<User>> activeAdmins() => (db.select(db.users)
        ..where((u) => u.username.equals('admin') & u.isActive.equals(true)))
      .get();

  Future<User> row(int id) =>
      (db.select(db.users)..where((u) => u.id.equals(id))).getSingle();

  test('two active admins -> exactly one (id 1) with the main credential',
      () async {
    await insertStray();
    expect((await activeAdmins()).map((a) => a.id), containsAll([1, 5]),
        reason: 'fixture must reproduce the duplicate');

    final r = await repairDuplicateAdmins(db);

    expect(r.changed, isTrue);
    expect((await activeAdmins()).map((a) => a.id).toList(), [1]);
    expect(await db.authenticateUser('admin', _mainPw), isNotNull);
    expect(await db.authenticateUser('admin', 'admin'), isNull,
        reason: 'the seeded admin/admin hash must not stay valid');
    expect((await row(1)).globalId, 'host-admin-gid');
  });

  test('the stray row is kept (inactive, renamed): history still resolves',
      () async {
    await insertStray();
    await db.customStatement(
        'INSERT INTO user_branch_access (user_id, branch_id) VALUES (5, 1)');

    await repairDuplicateAdmins(db);

    final stray = await row(5);
    expect(stray.isActive, isFalse);
    expect(stray.username, startsWith('__dup_5_'));
    expect(stray.globalId, isNull, reason: 'moved to id 1 (unique column)');
    final refs = await db
        .customSelect('SELECT COUNT(*) AS n FROM user_branch_access '
            'WHERE user_id = 5')
        .getSingle();
    expect(refs.read<int>('n'), 1, reason: 'no reference row was deleted');
    final fk = await db.customSelect('PRAGMA foreign_key_check').get();
    expect(fk, isEmpty, reason: 'every reference still points at a real user');
  });

  test('idempotent: the second run changes nothing', () async {
    await insertStray();
    await repairDuplicateAdmins(db);
    final before = await row(1);

    final r2 = await repairDuplicateAdmins(db);

    expect(r2.changed, isFalse);
    expect((await row(1)).passwordHash, before.passwordHash);
    expect((await activeAdmins()).map((a) => a.id).toList(), [1]);
  });

  test('a single admin is left alone', () async {
    final before = await row(1);
    final r = await repairDuplicateAdmins(db);
    expect(r.changed, isFalse);
    expect((await row(1)).passwordHash, before.passwordHash);
    expect(await db.authenticateUser('admin', 'admin'), isNotNull);
  });

  test('a stray without a usable credential never overwrites the id-1 hash',
      () async {
    await db.updateUserPassword(userId: 1, newPassword: 'Local#Admin2026x');
    await insertStray(hash: '', globalId: null);

    await repairDuplicateAdmins(db);

    expect((await activeAdmins()).map((a) => a.id).toList(), [1]);
    expect(await db.authenticateUser('admin', 'Local#Admin2026x'), isNotNull);
  });

  test('the main\'s stamp moves with the credential (grace is not lost)',
      () async {
    await insertStray();
    final at = DateTime.utc(2026, 10, 20, 8);
    final stamps = CredentialStampStore.forDb(db, clock: () => at);
    await stamps.stampFromSync(5, mainHash, serverTime: at);

    await repairDuplicateAdmins(db, stamps: stamps);

    final s = await stamps.read(1);
    expect(s, isNotNull);
    expect(s!.fp, credentialFingerprint(mainHash));
    expect(s.src, StampSource.sync);
    expect(s.at, at, reason: 'the original verification time is kept');
    expect(await stamps.read(5), isNull);
  });

  test('two strays: the one carrying the main credential wins, both go',
      () async {
    await insertStray(id: 5, globalId: null, hash: '');
    await insertStray(id: 9);

    await repairDuplicateAdmins(db);

    expect((await activeAdmins()).map((a) => a.id).toList(), [1]);
    expect(await db.authenticateUser('admin', _mainPw), isNotNull);
    expect((await row(5)).isActive, isFalse);
    expect((await row(9)).isActive, isFalse);
  });

  test('a later sync of the host admin (id 5) does not bring the duplicate '
      'back', () async {
    await insertStray();
    await repairDuplicateAdmins(db);

    await UserSyncStrategy(db).syncFromJson({
      'users': [
        {
          'id': 5,
          'username': 'admin',
          'passwordHash': mainHash,
          'passwordSalt': '',
          'displayName': 'المدير',
          'roleId': 1,
          'isActive': true,
        },
      ],
    });

    expect((await activeAdmins()).map((a) => a.id).toList(), [1],
        reason: 'the stray must stay retired');
    expect(await db.authenticateUser('admin', _mainPw), isNotNull);
  });

  test('the boot adoption of a paired device runs the repair; a standalone '
      'device is not touched', () async {
    await insertStray();
    await db.setSetting('setup_completed', 'true');
    await ProvisioningStore.write(
        db,
        ProvisioningRecord(
          mode: 'standalone',
          deviceKind: 'standalone',
          setupCompletedAt: DateTime.utc(2026, 10, 25),
        ));
    await ProvisioningApplier.ensure(db);
    expect((await activeAdmins()), hasLength(2),
        reason: 'only client/mirror devices carry sync-made duplicates');

    await ProvisioningStore.write(
        db,
        ProvisioningRecord(
          mode: 'client',
          deviceKind: 'client',
          branchId: 1,
          serverHost: '10.0.0.5',
          serverPort: 8080,
          firstSyncAt: DateTime.utc(2026, 10, 25),
          setupCompletedAt: DateTime.utc(2026, 10, 25),
        ));
    await ProvisioningApplier.ensure(db);
    expect((await activeAdmins()).map((a) => a.id).toList(), [1]);
  });
}