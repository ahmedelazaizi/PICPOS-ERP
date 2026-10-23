// ignore_for_file: avoid_dynamic_calls
import 'package:flutter/foundation.dart';
import 'package:drift/drift.dart';
import 'package:picpos_erp/data/database/database.dart';
import 'package:picpos_erp/services/unusable_credential.dart';
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
      final existingUser = await (db.select(db.users)..where((t) => t.id.equals(id))).getSingleOrNull();

      // Clean up stale duplicate: if a local user has the same username but a
      // different ID (created offline before server assigned its ID), deactivate
      // it so authentication doesn't get confused by duplicate usernames.
      // IMPORTANT: Preserve the duplicate's password hash so it can be used
      // for the new server-ID row (the offline user had the real password).
      User? deactivatedDuplicate;
      if (existingUser == null) {
        // This is a new server ID not yet local — check for username duplicate
        final duplicate = await (db.select(db.users)
              ..where((t) => t.username.equals(username) & t.id.equals(id).not()))
            .getSingleOrNull();
        if (duplicate != null) {
          // Feature 011 / Issue 9 — defense-in-depth: NEVER rename the
          // bootstrap admin (id=1). It is the system's emergency-access
          // identity; renaming it to `__dup_1_admin` and deactivating it
          // (as the legacy code did) leaves a client unable to log in as
          // admin even after the server-side _getUsers fix at
          // api_handler.dart:1458 lands. If a server response carries a
          // DIFFERENT user with username='admin', skip this server row
          // entirely rather than overwriting the local bootstrap.
          if (duplicate.id == 1) {
            debugPrint('[UserSync] Refusing to rename bootstrap admin '
                '(local id=1, username="$username"): server response carries '
                'a different user with the same username (server id=$id). '
                'Skipping this row to preserve admin login. See '
                'specs/011/PROMPT.md §Issue 9.');
            continue;
          }
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

      // Resolve password hash/salt — priority order:
      // 1. Server-provided hash (authoritative if present)
      // 2. Existing local user's hash (same ID — e.g. password changed on server)
      // 3. Deactivated duplicate's hash (offline-created user's real password)
      // 4. Generate temporary password as last resort
      final serveHash = u['passwordHash'] as String?;
      final serveSalt = u['passwordSalt'] as String?;
      final servePin = u['pin'] as String?;

      var hashToSave = '';
      var saltToSave = '';
      String? pinToSave;

      // P5 (Issue #4): Require BOTH hash AND salt before adopting server
      // credentials. Previously the check was hash-only, so a server row
      // with `passwordHash="<valid>"` but `passwordSalt=""` overwrote the
      // local salt with empty — the next boot's "Admin Password Integrity
      // Check" then fired heal because `salt.length=0`.
      //
      // EXCEPTION: Argon2id PHC hashes ($argon2id$...) embed their salt in
      // the hash string itself, so password_salt is legitimately "" for
      // those — that's not corruption, that's the Week-8 hash format. Treat
      // an Argon2 hash as a complete authoritative credential even with an
      // empty salt column. Without this, the post-Argon2-rehash server admin
      // could never propagate to clients (the local PBKDF2 'admin' would
      // win every sync, blocking the operator's real password).
      final isArgon2 =
          serveHash != null && serveHash.startsWith(r'$argon2');
      final serveCredsValid = serveHash != null &&
          serveHash.isNotEmpty &&
          (isArgon2 ||
              (serveSalt != null && serveSalt.isNotEmpty));
      if (serveCredsValid) {
        // Server sent authoritative credentials. For Argon2 the salt column
        // is intentionally empty (salt embedded in PHC string) — store ''
        // rather than the nullable serveSalt to keep the column non-null.
        hashToSave = serveHash;
        saltToSave = serveSalt ?? '';
        // الخادم مابقاش بيبعت `pin` (تسريب B11 — شوف api_handler `_getUsers`).
        // كان `= servePin` مباشرةً، فغياب الحقل كان هيمسح الـPIN المحلي على
        // كل مزامنة. الـPIN بقى سرّاً محلياً: بيتظبط عبر نقطة النهاية
        // المخصّصة وبيتحقق محلياً، والمزامنة ما بتلمسهوش.
        pinToSave = servePin ?? existingUser?.pin;
      } else if (existingUser != null &&
          existingUser.passwordHash.isNotEmpty &&
          existingUser.passwordSalt.isNotEmpty) {
        // Existing local user (same ID) — preserve their password.
        // Require BOTH hash AND salt to be non-empty so that a previously
        // delta-pull-corrupted row (hash=OK, salt="") is not perpetuated here.
        hashToSave = existingUser.passwordHash;
        saltToSave = existingUser.passwordSalt;
        pinToSave = servePin ?? existingUser.pin;
      } else if (deactivatedDuplicate != null &&
          deactivatedDuplicate.passwordHash.isNotEmpty &&
          deactivatedDuplicate.passwordSalt.isNotEmpty) {
        // Offline-created duplicate — carry over their real password
        hashToSave = deactivatedDuplicate.passwordHash;
        saltToSave = deactivatedDuplicate.passwordSalt;
        pinToSave = servePin ?? deactivatedDuplicate.pin;
        debugPrint('[UserSync] Preserved password from offline duplicate for "$username"');
      } else {
        // SEC-004: no password anywhere — store an UNUSABLE random credential
        // (never the guessable `<username>123`); a real one arrives later.
        final unusable = await UnusableCredential.mint();
        saltToSave = unusable.salt;
        hashToSave = unusable.hash;
        pinToSave = servePin;
        debugPrint('[UserSync] New user "$username" synced without password — '
            'unusable credential stored, forcePasswordChange enabled');
      }

      final forceChange = !serveCredsValid &&
          existingUser == null &&
          deactivatedDuplicate == null;

      await db.into(db.users).insertOnConflictUpdate(
        UsersCompanion(
          id: Value(id),
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