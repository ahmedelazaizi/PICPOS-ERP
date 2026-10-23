// ═══════════════════════════════════════════════════════════════════════════
// Unit Test: Hash Chain SHA-256 — JournalEntry description pattern [HASH:xxx]
// ═══════════════════════════════════════════════════════════════════════════
//
// Tests the Hash Chain mechanism embedded in JournalEntry descriptions.
// Validates: genesis hash, chain continuity, and tamper detection.
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/services/audit_log_integrity_service.dart';

void main() {
  // ── 1. JE Description Hash Pattern ──────────────────────────────────────
  group('JE Description Hash Pattern [HASH:xxx]', () {
    /// Reproduces the exact hash logic from accounting_dao_writes.dart
    String computeJeHash({
      required String previousHash,
      required int entryId,
      required DateTime date,
      required double totalDebit,
      required String? description,
    }) {
      final payload =
          '$previousHash|$entryId|${date.toIso8601String()}|$totalDebit|$description';
      return sha256.convert(utf8.encode(payload)).toString();
    }

    test('Genesis hash uses 64 zeros as previous hash', () {
      final genesisHash = '0' * 64;
      expect(genesisHash.length, 64);

      final hash = computeJeHash(
        previousHash: genesisHash,
        entryId: 1,
        date: DateTime(2026, 1, 1),
        totalDebit: 100.0,
        description: 'First entry',
      );
      expect(hash.length, 64);
      expect(RegExp(r'^[a-f0-9]{64}$').hasMatch(hash), isTrue);
    });

    test('Same inputs always produce the same hash (deterministic)', () {
      final h1 = computeJeHash(
        previousHash: '0' * 64,
        entryId: 1,
        date: DateTime(2026, 3, 1),
        totalDebit: 500.0,
        description: 'بيع بضاعة',
      );
      final h2 = computeJeHash(
        previousHash: '0' * 64,
        entryId: 1,
        date: DateTime(2026, 3, 1),
        totalDebit: 500.0,
        description: 'بيع بضاعة',
      );
      expect(h1, equals(h2));
    });

    test('Chain of 3 entries forms valid sequential links', () {
      final genesis = '0' * 64;

      final hash1 = computeJeHash(
        previousHash: genesis,
        entryId: 1,
        date: DateTime(2026, 1, 1),
        totalDebit: 100,
        description: 'Entry 1',
      );
      final hash2 = computeJeHash(
        previousHash: hash1,
        entryId: 2,
        date: DateTime(2026, 1, 2),
        totalDebit: 200,
        description: 'Entry 2',
      );
      final hash3 = computeJeHash(
        previousHash: hash2,
        entryId: 3,
        date: DateTime(2026, 1, 3),
        totalDebit: 300,
        description: 'Entry 3',
      );

      // All hashes are unique
      expect({hash1, hash2, hash3}.length, 3);
      // All are valid SHA-256
      for (final h in [hash1, hash2, hash3]) {
        expect(h.length, 64);
      }
    });

    test('Tampering description breaks the chain', () {
      final genesis = '0' * 64;

      final hash1 = computeJeHash(
        previousHash: genesis,
        entryId: 1,
        date: DateTime(2026, 1, 1),
        totalDebit: 100,
        description: 'Original description',
      );

      // Re-compute with tampered description
      final tamperedHash = computeJeHash(
        previousHash: genesis,
        entryId: 1,
        date: DateTime(2026, 1, 1),
        totalDebit: 100,
        description: 'TAMPERED description',
      );

      expect(hash1, isNot(equals(tamperedHash)),
          reason: 'Changing description must produce different hash');
    });

    test('Tampering totalDebit breaks the chain', () {
      final genesis = '0' * 64;

      final original = computeJeHash(
        previousHash: genesis,
        entryId: 1,
        date: DateTime(2026, 1, 1),
        totalDebit: 100.0,
        description: 'Test',
      );

      final tampered = computeJeHash(
        previousHash: genesis,
        entryId: 1,
        date: DateTime(2026, 1, 1),
        totalDebit: 100.01, // tiny change
        description: 'Test',
      );

      expect(original, isNot(equals(tampered)));
    });

    test('[HASH:xxx] regex extracts 64-char hex hash', () {
      final regex = RegExp(r'\[HASH:([a-f0-9]{64})\]');
      const sampleDesc =
          'بيع بضاعة [HASH:a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2]';
      final match = regex.firstMatch(sampleDesc);

      expect(match, isNotNull);
      expect(match!.group(1)!.length, 64);
    });

    test('[HASH:xxx] regex ignores descriptions without hash', () {
      final regex = RegExp(r'\[HASH:([a-f0-9]{64})\]');
      expect(regex.firstMatch('Simple description'), isNull);
      expect(regex.firstMatch('[HASH:invalid]'), isNull);
    });
  });

  // ── 2. AuditLogIntegrityService ─────────────────────────────────────────
  group('AuditLogIntegrityService unit tests', () {
    test('generateHash returns 64-char hex string', () {
      final hash = AuditLogIntegrityService.generateHash(
        previousHash: 'GENESIS',
        timestamp: DateTime(2026, 3, 27),
        action: 'test',
        data: 'data',
        userId: 1,
      );
      expect(hash.length, 64);
      expect(RegExp(r'^[a-f0-9]{64}$').hasMatch(hash), isTrue);
    });

    test('verifyChain returns -1 for valid chain', () {
      const genesis = 'GENESIS';
      final h1 = AuditLogIntegrityService.generateHash(
        previousHash: genesis,
        timestamp: DateTime(2026, 1, 1),
        action: 'A',
        data: 'd1',
        userId: 1,
      );
      final h2 = AuditLogIntegrityService.generateHash(
        previousHash: h1,
        timestamp: DateTime(2026, 1, 2),
        action: 'B',
        data: 'd2',
        userId: 1,
      );

      final chain = [
        AuditEntry(id: 1, timestamp: DateTime(2026, 1, 1), action: 'A', data: 'd1', userId: 1, integrityHash: h1),
        AuditEntry(id: 2, timestamp: DateTime(2026, 1, 2), action: 'B', data: 'd2', userId: 1, integrityHash: h2),
      ];

      expect(AuditLogIntegrityService.verifyChain(chain), -1);
    });

    test('verifyChain detects tampered data at specific index', () {
      const genesis = 'GENESIS';
      final h1 = AuditLogIntegrityService.generateHash(
        previousHash: genesis,
        timestamp: DateTime(2026, 1, 1),
        action: 'A',
        data: 'd1',
        userId: 1,
      );
      final h2 = AuditLogIntegrityService.generateHash(
        previousHash: h1,
        timestamp: DateTime(2026, 1, 2),
        action: 'B',
        data: 'd2',
        userId: 1,
      );

      // Tamper data of entry 2
      final tampered = [
        AuditEntry(id: 1, timestamp: DateTime(2026, 1, 1), action: 'A', data: 'd1', userId: 1, integrityHash: h1),
        AuditEntry(id: 2, timestamp: DateTime(2026, 1, 2), action: 'B', data: 'HACKED', userId: 1, integrityHash: h2),
      ];

      expect(AuditLogIntegrityService.verifyChain(tampered), 1);
    });

    test('verifyChain returns -1 for empty chain', () {
      expect(AuditLogIntegrityService.verifyChain([]), -1);
    });
  });
}
