import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/services/audit_log_integrity_service.dart';

/// PIR Integration Test 2: Hash Chain Integrity (ICR-03)
/// Verifies SHA-256 chain link validation and tamper detection.
void main() {
  group('PIR-006: Hash Chain Integrity', () {
    test('Generates consistent SHA-256 hash for same input', () {
      final hash1 = AuditLogIntegrityService.generateHash(
        previousHash: 'GENESIS',
        timestamp: DateTime(2026, 1, 1, 12, 0),
        action: 'login',
        data: 'user=admin',
        userId: 1,
      );
      final hash2 = AuditLogIntegrityService.generateHash(
        previousHash: 'GENESIS',
        timestamp: DateTime(2026, 1, 1, 12, 0),
        action: 'login',
        data: 'user=admin',
        userId: 1,
      );

      expect(hash1, equals(hash2), reason: 'Same input must produce same hash');
      expect(hash1.length, 64, reason: 'SHA-256 produces 64 hex chars');
    });

    test('Different input produces different hash', () {
      final hash1 = AuditLogIntegrityService.generateHash(
        previousHash: 'GENESIS',
        timestamp: DateTime(2026, 1, 1, 12, 0),
        action: 'login',
        data: 'user=admin',
        userId: 1,
      );
      final hash2 = AuditLogIntegrityService.generateHash(
        previousHash: 'GENESIS',
        timestamp: DateTime(2026, 1, 1, 12, 0),
        action: 'login',
        data: 'user=admin',
        userId: 2, // different user
      );

      expect(hash1, isNot(equals(hash2)));
    });

    test('Chain links are sequential and tamper-detectable', () {
      const genesis = 'GENESIS';

      // Build a valid chain
      final entry1Hash = AuditLogIntegrityService.generateHash(
        previousHash: genesis,
        timestamp: DateTime(2026, 1, 1, 12, 0),
        action: 'create_invoice',
        data: 'INV-001',
        userId: 1,
      );
      final entry2Hash = AuditLogIntegrityService.generateHash(
        previousHash: entry1Hash,
        timestamp: DateTime(2026, 1, 1, 12, 5),
        action: 'create_invoice',
        data: 'INV-002',
        userId: 1,
      );

      // Tampered chain (different previousHash)
      final tampered = AuditLogIntegrityService.generateHash(
        previousHash: 'TAMPERED_HASH',
        timestamp: DateTime(2026, 1, 1, 12, 5),
        action: 'create_invoice',
        data: 'INV-002',
        userId: 1,
      );

      expect(entry2Hash, isNot(equals(tampered)),
          reason: 'Tampering previous hash breaks the chain');
    });

    test('verifyChain detects tampered entry', () {
      const genesis = 'GENESIS';
      final hash1 = AuditLogIntegrityService.generateHash(
        previousHash: genesis,
        timestamp: DateTime(2026, 1, 1),
        action: 'A',
        data: 'data1',
        userId: 1,
      );
      final hash2 = AuditLogIntegrityService.generateHash(
        previousHash: hash1,
        timestamp: DateTime(2026, 1, 2),
        action: 'B',
        data: 'data2',
        userId: 1,
      );

      final validChain = [
        AuditEntry(id: 1, timestamp: DateTime(2026, 1, 1), action: 'A', data: 'data1', userId: 1, integrityHash: hash1),
        AuditEntry(id: 2, timestamp: DateTime(2026, 1, 2), action: 'B', data: 'data2', userId: 1, integrityHash: hash2),
      ];

      expect(AuditLogIntegrityService.verifyChain(validChain), -1,
          reason: 'Valid chain returns -1');

      // Tamper entry 2
      final tamperedChain = [
        AuditEntry(id: 1, timestamp: DateTime(2026, 1, 1), action: 'A', data: 'data1', userId: 1, integrityHash: hash1),
        AuditEntry(id: 2, timestamp: DateTime(2026, 1, 2), action: 'B', data: 'TAMPERED!', userId: 1, integrityHash: hash2),
      ];

      expect(AuditLogIntegrityService.verifyChain(tamperedChain), 1,
          reason: 'Tampered entry at index 1 detected');
    });
  });
}
