// ignore_for_file: avoid_dynamic_calls
import 'package:flutter/foundation.dart';
import 'package:drift/drift.dart';
import 'package:picpos_erp/data/database/database.dart';
import 'package:picpos_erp/services/sync/user_credential_merge.dart';
import 'package:picpos_erp/services/sync/sync_strategy.dart';
import 'package:picpos_erp/services/sync_event_bus.dart';

class UserSyncStrategy extends SyncStrategy {
  UserSyncStrategy(super.db);

  @override
  String get tableName => 'users';

  @override
  String get apiEndpoint => '/api/users';

  @override
  Future<void> syncFromJson(Map<String, dynamic> json) async {
    final users = json['users'] as List;
    for (final u in users) {
      final id = parseInt(u['id']);
      final username = u['username'] as String;

      // Read existing user by server ID to preserve local passwords
      var rowId = id;
      var existingUser = await (db.select(db.users)..where((t) => t.id.equals(id))).getSingleOrNull();

      // Clean up stale duplicate: a local user with the same username but a
      // different ID (created offline before the server assigned its ID) is
      // deactivated so authentication is not confused by duplicate usernames,
      // and its password hash is carried over to the server-ID row.
      User? deactivatedDuplicate;
      if (existingUser == null) {
        final duplicate = await (db.select(db.users)
              ..where((t) => t.username.equals(username) & t.id.equals(id).not()))
            .getSingleOrNull();
        if (duplicate != null) {
          if (duplicate.id == 1) {
            // The bootstrap admin (local id=1) is the system's emergency-access
            // identity and is NEVER renamed/deactivated. A server user with the
            // same name but another id (e.g. a PostgreSQL sequence that moved
            // admin off id 1) maps ONTO the local row — one admin identity —
            // instead of being skipped (which left the host admin unreachable).
            existingUser = duplicate;
            rowId = duplicate.id;
            debugPrint('[UserSync] Mapping server "$username" (id=$id) onto '
                'the local bootstrap row id=1');
            try {
              await db.storeFkMapping(
                  tableName: 'users', localId: rowId, remoteId: id);
            } catch (_) {}
          } else {
            deactivatedDuplicate = duplicate;
            debugPrint('[UserSync] Deduplicating user "$username": '
                'renaming old local id=${duplicate.id} to prevent auth conflict');
            await (db.update(db.users)..where((t) => t.id.equals(duplicate.id))).write(
              UsersCompanion(
                username: Value('__dup_${duplicate.id}_$username'),
                isActive: const Value(false),
              ),
            );
          }
        }
      }

      // Credential priority (user_credential_merge.dart): complete server
      // credential → complete local row (Argon2id rows legitimately have
      // salt='') → the offline duplicate's real password → unusable (SEC-004).
      final serveHash = u['passwordHash'] as String?;
      final serveSalt = u['passwordSalt'] as String?;
      final servePin = u['pin'] as String?;
      final cred = await resolveCredential(
        serverHash: serveHash,
        serverSalt: serveSalt,
        localHash: existingUser?.passwordHash,
        localSalt: existingUser?.passwordSalt,
        dupHash: deactivatedDuplicate?.passwordHash,
        dupSalt: deactivatedDuplicate?.passwordSalt,
      );
      final hashToSave = cred.hash;
      final saltToSave = cred.salt;
      // The server never sends `pin` (B11 leak): it is device-local, so an
      // absent field must not wipe the local PIN.
      final pinToSave = servePin ?? existingUser?.pin ?? deactivatedDuplicate?.pin;
      if (cred.source == CredentialSource.unusable) {
        debugPrint('[UserSync] New user "$username" synced without password — '
            'unusable credential stored, forcePasswordChange enabled');
      }

      final forceChange = cred.source == CredentialSource.unusable &&
          existingUser == null &&
          deactivatedDuplicate == null;

      await db.into(db.users).insertOnConflictUpdate(
        UsersCompanion(
          id: Value(rowId),
          username: Value(u['username'] as String),
          passwordHash: Value(hashToSave),
          passwordSalt: Value(saltToSave),
          displayName: Value(u['displayName'] as String? ?? ''),
          roleId: Value(parseIntNullable(u['roleId'])),
          pin: Value(pinToSave),
          defaultScreen: Value(u['defaultScreen'] as String? ?? 'pos'),
          isLocked: Value(parseBool(u['isLocked'], false)),
          isActive: Value(parseBool(u['isActive'], true)),
          maxDiscountPercent: Value(parseDoubleNullable(u['maxDiscountPercent'])),
          discountLimitIsPercent: Value(parseBool(u['discountLimitIsPercent'], true)),
          // الخادم لا يُرسل cardCode إلا لعميل مصادَق (يُسقطه عن الاستجابات
          // العامة): غيابُ الحقل لا يمسح البطاقة المحلية.
          cardCode: u.containsKey('cardCode')
              ? Value(u['cardCode'] as String?)
              : const Value.absent(),
          forcePasswordChange: forceChange ? const Value(true) : const Value.absent(),
        ),
      );
    }
    // Force UI refresh after sync
    if (users.isNotEmpty) {
      db.markTablesUpdated({db.users});
      // Bridge: notify Riverpod listeners (PermissionSyncBridge). Users sync
      // can change a user's roleId, so any cached permission lookup keyed by
      // user.roleId must be invalidated.
      SyncEventBus.instance.emit(SyncTablePulled('users', users.length));
    }
  }

  @override
  Future<int> syncIncremental(DateTime since) async => 0;

  @override
  Future<void> upsert(Insertable record) async {
    await db.into(db.users).insertOnConflictUpdate(record as UsersCompanion);
  }
}