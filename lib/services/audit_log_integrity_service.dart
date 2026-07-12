// ═══════════════════════════════════════════════════════════════════════════
// C-06: Audit Log Immutability — Integrity Checksums
// Ensures audit log entries cannot be tampered with
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:convert';
import 'package:crypto/crypto.dart';

/// Service to generate and verify integrity checksums for audit log entries.
///
/// Each log entry gets a SHA-256 hash composed of:
/// - Previous entry's hash (chain)
/// - Entry timestamp
/// - Entry action
/// - Entry data
/// - User ID
///
/// Verification walks the chain to ensure no entry has been modified.
class AuditLogIntegrityService {
  /// Generate an integrity hash for a new log entry
  static String generateHash({
    required String previousHash,
    required DateTime timestamp,
    required String action,
    required String data,
    required int userId,
  }) {
    final payload = '$previousHash|${timestamp.toIso8601String()}|$action|$data|$userId';
    return sha256.convert(utf8.encode(payload)).toString();
  }

  /// Verify a chain of log entries for integrity
  /// Returns the index of the first tampered entry, or -1 if all valid.
  static int verifyChain(List<AuditEntry> entries) {
    if (entries.isEmpty) return -1;

    String previousHash = 'GENESIS'; // First entry chain start
    for (int i = 0; i < entries.length; i++) {
      final entry = entries[i];
      final expectedHash = generateHash(
        previousHash: previousHash,
        timestamp: entry.timestamp,
        action: entry.action,
        data: entry.data,
        userId: entry.userId,
      );

      if (entry.integrityHash != expectedHash) {
        return i; // Tampered!
      }
      previousHash = entry.integrityHash;
    }
    return -1; // All valid
  }
}

/// Represents an audit log entry with integrity hash
class AuditEntry {
  final int id;
  final DateTime timestamp;
  final String action;
  final String data;
  final int userId;
  final String integrityHash;

  const AuditEntry({
    required this.id,
    required this.timestamp,
    required this.action,
    required this.data,
    required this.userId,
    required this.integrityHash,
  });
}
