/// Week-8 Unit Tests — SecurityService Argon2id upgrade
///
/// 8 tests that pin the contract of the new Argon2id hashing layer
/// in SecurityService:
///
///   • New hashes use the Argon2id PHC string format (`$argon2id$...`)
///   • Legacy PBKDF2-SHA256 hashes are still verified correctly
///   • verifyPasswordFull() signals `needsRehash` for legacy hashes
///   • Wrong passwords always return false — for both algorithms
///   • hashPasswordArgon2() is non-deterministic (unique salt each call)
///   • verifyArgon2() parses and verifies the PHC string correctly
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/services/security_service.dart';

void main() {
  group('SecurityService — Argon2id hashing (Week 8)', () {
    // ── Hash format ────────────────────────────────────────────────────────

    test('hashPasswordArgon2 produces a PHC string starting with \$argon2id\$',
        () async {
      final hash = await SecurityService.hashPasswordArgon2('TestPassword1!');
      expect(hash, startsWith('\$argon2id\$'));
    });

    test('hashPasswordArgon2 returns a different hash on each call (unique salt)',
        () async {
      final h1 = await SecurityService.hashPasswordArgon2('SamePassword1!');
      final h2 = await SecurityService.hashPasswordArgon2('SamePassword1!');
      expect(h1, isNot(equals(h2)));
    });

    test('isArgon2Hash returns true for Argon2id PHC strings', () async {
      final hash = await SecurityService.hashPasswordArgon2('AnyPass1!');
      expect(SecurityService.isArgon2Hash(hash), isTrue);
    });

    test('isArgon2Hash returns false for legacy PBKDF2 hashes', () {
      final salt = SecurityService.generateSalt();
      final legacyHash = SecurityService.hashPassword('AnyPass1!', salt);
      expect(SecurityService.isArgon2Hash(legacyHash), isFalse);
    });

    // ── Argon2id verification ──────────────────────────────────────────────

    test('verifyArgon2 returns true for the correct password', () async {
      const password = 'CorrectPassword9#';
      final phc = await SecurityService.hashPasswordArgon2(password);
      expect(await SecurityService.verifyArgon2(password, phc), isTrue);
    });

    test('verifyArgon2 returns false for a wrong password', () async {
      final phc = await SecurityService.hashPasswordArgon2('RightPassword1!');
      expect(
        await SecurityService.verifyArgon2('WrongPassword1!', phc),
        isFalse,
      );
    });

    // ── Unified verifyPasswordFull — migration contract ────────────────────

    test(
        'verifyPasswordFull: correct legacy hash → verified=true, needsRehash=true',
        () async {
      const password = 'LegacyPass1!';
      final salt = SecurityService.generateSalt();
      final legacyHash = SecurityService.hashPassword(password, salt);

      final result = await SecurityService.verifyPasswordFull(
        password,
        salt,
        legacyHash,
      );
      expect(result.verified, isTrue);
      expect(result.needsRehash, isTrue,
          reason: 'legacy hash should trigger Argon2id rehash');
    });

    test(
        'verifyPasswordFull: correct Argon2id hash → verified=true, needsRehash=false',
        () async {
      const password = 'NewFormatPass1!';
      final phc = await SecurityService.hashPasswordArgon2(password);

      final result = await SecurityService.verifyPasswordFull(
        password,
        '',   // salt unused for Argon2id
        phc,
      );
      expect(result.verified, isTrue);
      expect(result.needsRehash, isFalse,
          reason: 'already Argon2id — no rehash needed');
    });
  });
}
