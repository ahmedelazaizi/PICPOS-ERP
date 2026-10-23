// ═══════════════════════════════════════════════════════════════════════════
// B11 — PIN hashing must use Argon2id, not the salt-coupled legacy KDF
// ═══════════════════════════════════════════════════════════════════════════
//
// THE HOLE THIS CLOSES
//
// `GET /api/users` (api_handler.dart:1657-1661) ships `passwordHash`,
// `passwordSalt` AND `pin` together to every bearer on the LAN — by design,
// so clients can authenticate locally while offline. That is defensible for a
// password. It is NOT defensible for the PIN, because `updateUserPin` hashed
// the PIN with PBKDF2-SHA256 keyed on **that same leaked `passwordSalt`**.
// A PIN is 4-6 digits — at most 1.1M candidates. With the salt in hand the
// whole keyspace is exhausted offline in well under a second.
//
// Argon2id fixes this without a schema change: the PHC string is
// self-describing (`$argon2id$v=19$m=..,t=..,p=..$salt$hash`) and carries its
// OWN random 16-byte salt, so `passwordSalt` stops being the PIN's salt, and
// the memory-hard KDF makes each guess cost ~4MB + 3 passes instead of one
// cheap SHA256 round.
//
// SecurityService already had the whole mechanism (hashPasswordArgon2 :124,
// verifyPasswordFull :167, isLegacyPin :368) — only the three call sites in
// permissions_dao.dart were still on the old path. These tests pin all three.
//
// Backward compatibility is a hard requirement, not a nicety: PIN hashes
// arrive over sync from servers that have not been upgraded yet, so
// `verifyUserPin` must keep accepting legacy PBKDF2 hashes AND legacy
// plaintext PINs — and must transparently upgrade both on the next
// successful verify.

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/data/database/database.dart';
import 'package:picpos_erp/services/security_service.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting();
  });

  tearDown(() => db.close());

  /// Inserts a user carrying a known `passwordSalt` — the value that leaks
  /// over `GET /api/users` and that the old PIN hash was keyed on.
  Future<int> insertUser({
    required String username,
    required String salt,
    String? pin,
  }) {
    return db.into(db.users).insert(
          UsersCompanion.insert(
            username: username,
            passwordHash: 'irrelevant-for-pin-tests',
            displayName: username,
            passwordSalt: Value(salt),
            pin: Value(pin),
          ),
        );
  }

  Future<String?> storedPin(int userId) async {
    final row =
        await (db.select(db.users)..where((u) => u.id.equals(userId))).getSingle();
    return row.pin;
  }

  group('B11 — updateUserPin writes Argon2id', () {
    test('stored PIN is an Argon2id PHC string, not a legacy KDF digest',
        () async {
      final id = await insertUser(username: 'pin_argon_1', salt: 'LEAKED_SALT');

      await db.updateUserPin(id, '1234');

      final hash = await storedPin(id);
      expect(hash, isNotNull);
      expect(SecurityService.isArgon2Hash(hash!), isTrue,
          reason: 'PIN must be hashed with Argon2id, not the legacy KDF');
    });

    test('stored PIN is NOT reproducible from the leaked passwordSalt',
        () async {
      const salt = 'LEAKED_SALT';
      final id = await insertUser(username: 'pin_argon_2', salt: salt);

      await db.updateUserPin(id, '1234');

      // This is the actual attack: attacker holds `passwordSalt` from
      // GET /api/users and walks 0000..999999 through the legacy KDF.
      final legacyGuess = SecurityService.hashPassword('1234', salt);
      expect(await storedPin(id), isNot(equals(legacyGuess)));
    });

    test('two users with the same PIN and same salt get different hashes',
        () async {
      const salt = 'SHARED_SALT';
      final a = await insertUser(username: 'pin_argon_3a', salt: salt);
      final b = await insertUser(username: 'pin_argon_3b', salt: salt);

      await db.updateUserPin(a, '4321');
      await db.updateUserPin(b, '4321');

      // Per-hash random salt ⇒ one cracked PIN never reveals another user's.
      expect(await storedPin(a), isNot(equals(await storedPin(b))));
    });

    test('null PIN still clears the column', () async {
      final id = await insertUser(username: 'pin_argon_4', salt: 's');
      await db.updateUserPin(id, '5555');
      expect(await storedPin(id), isNotNull);

      await db.updateUserPin(id, null);
      expect(await storedPin(id), isNull);
    });
  });

  group('B11 — verifyUserPin', () {
    test('accepts the correct PIN against an Argon2id hash', () async {
      final id = await insertUser(username: 'pin_verify_1', salt: 's');
      await db.updateUserPin(id, '2468');

      expect(await db.verifyUserPin(id, '2468'), isTrue);
    });

    test('rejects a wrong PIN against an Argon2id hash', () async {
      final id = await insertUser(username: 'pin_verify_2', salt: 's');
      await db.updateUserPin(id, '2468');

      expect(await db.verifyUserPin(id, '1357'), isFalse);
    });

    test('still accepts a legacy PBKDF2 PIN hash arriving from an old server',
        () async {
      const salt = 'OLD_SERVER_SALT';
      final legacyHash = SecurityService.hashPassword('9876', salt);
      final id = await insertUser(
          username: 'pin_verify_3', salt: salt, pin: legacyHash);

      expect(await db.verifyUserPin(id, '9876'), isTrue,
          reason: 'old hashes sync in from un-upgraded servers');
    });

    test('rejects a wrong PIN against a legacy PBKDF2 hash', () async {
      const salt = 'OLD_SERVER_SALT';
      final legacyHash = SecurityService.hashPassword('9876', salt);
      final id = await insertUser(
          username: 'pin_verify_4', salt: salt, pin: legacyHash);

      expect(await db.verifyUserPin(id, '1111'), isFalse);
    });

    test('transparently upgrades a legacy PBKDF2 hash on successful verify',
        () async {
      const salt = 'OLD_SERVER_SALT';
      final legacyHash = SecurityService.hashPassword('9876', salt);
      final id = await insertUser(
          username: 'pin_verify_5', salt: salt, pin: legacyHash);

      expect(await db.verifyUserPin(id, '9876'), isTrue);

      final after = await storedPin(id);
      expect(SecurityService.isArgon2Hash(after!), isTrue,
          reason: 'needsRehash must actually rehash, not just report');
      // And the upgraded hash must still verify.
      expect(await db.verifyUserPin(id, '9876'), isTrue);
    });

    test('does NOT rehash when the legacy PIN was wrong', () async {
      const salt = 'OLD_SERVER_SALT';
      final legacyHash = SecurityService.hashPassword('9876', salt);
      final id = await insertUser(
          username: 'pin_verify_6', salt: salt, pin: legacyHash);

      expect(await db.verifyUserPin(id, '0000'), isFalse);
      expect(await storedPin(id), equals(legacyHash),
          reason: 'a failed guess must never overwrite the stored hash');
    });

    test('legacy plaintext PIN auto-migrates to Argon2id on verify', () async {
      final id =
          await insertUser(username: 'pin_verify_7', salt: 's', pin: '7777');

      expect(await db.verifyUserPin(id, '7777'), isTrue);

      final after = await storedPin(id);
      expect(SecurityService.isArgon2Hash(after!), isTrue);
    });
  });

  group('B11 — migrateLegacyPlaintextPins (boot migration)', () {
    test('rewrites plaintext PINs as Argon2id, not as legacy digests',
        () async {
      const salt = 'BOOT_SALT';
      final id = await insertUser(
          username: 'pin_boot_1', salt: salt, pin: '3141');

      final migrated = await db.migrateLegacyPlaintextPins();
      expect(migrated, 1);

      final hash = await storedPin(id);
      expect(SecurityService.isArgon2Hash(hash!), isTrue);
      expect(hash, isNot(equals(SecurityService.hashPassword('3141', salt))));
      expect(await db.verifyUserPin(id, '3141'), isTrue);
    });

    test('leaves already-hashed PINs untouched', () async {
      final id = await insertUser(username: 'pin_boot_2', salt: 's');
      await db.updateUserPin(id, '2718');
      final before = await storedPin(id);

      expect(await db.migrateLegacyPlaintextPins(), 0);
      expect(await storedPin(id), equals(before));
    });
  });
}
