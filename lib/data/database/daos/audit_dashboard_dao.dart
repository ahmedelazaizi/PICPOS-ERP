import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import '../database.dart';

/// Service for Audit Dashboard operations.
/// Provides Hash Chain verification and Sync Conflict management.
class AuditDashboardDao {
  final AppDatabase db;
  AuditDashboardDao(this.db);

  // ── Hash Chain Verification ──────────────────────────────────────────

  /// Verifies the integrity of the Hash Chain across all journal entries.
  Future<Map<String, dynamic>> verifyHashChain() async {
    final entries = await (db.select(db.journalEntries)
          ..orderBy([(e) => OrderingTerm.asc(e.id)]))
        .get();

    if (entries.isEmpty) {
      return {
        'isValid': true,
        'totalEntries': 0,
        'signedEntries': 0,
        'unsignedEntries': 0,
        'brokenAt': null,
        'brokenReason': null,
      };
    }

    final hashRegex = RegExp(r'\[HASH:([a-f0-9]{64})\]');
    int signedCount = 0;
    int unsignedCount = 0;
    String previousHash = '0' * 64;

    for (int i = 0; i < entries.length; i++) {
      final entry = entries[i];
      final desc = entry.description ?? '';
      final match = hashRegex.firstMatch(desc);

      if (match == null) {
        unsignedCount++;
        continue;
      }

      signedCount++;
      final storedHash = match.group(1)!;

      final originalDesc =
          desc.replaceAll(RegExp(r'\s*\[HASH:[a-f0-9]{64}\]'), '');

      final totalDebit = await _getEntryTotalDebit(entry.id);
      final payload =
          '$previousHash|${entry.id}|${entry.entryDate.toIso8601String()}|$totalDebit|$originalDesc';
      final expectedHash = sha256.convert(utf8.encode(payload)).toString();

      if (storedHash != expectedHash) {
        return {
          'isValid': false,
          'totalEntries': entries.length,
          'signedEntries': signedCount,
          'unsignedEntries': unsignedCount,
          'brokenAt': entry.id,
          'brokenReason':
              'قيد رقم ${entry.id}: الـ Hash المخزن لا يتطابق مع القيمة المحسوبة',
        };
      }

      previousHash = storedHash;
    }

    return {
      'isValid': true,
      'totalEntries': entries.length,
      'signedEntries': signedCount,
      'unsignedEntries': unsignedCount,
      'brokenAt': null,
      'brokenReason': null,
    };
  }

  Future<double> _getEntryTotalDebit(int entryId) async {
    final lines = await (db.select(db.journalEntryLines)
          ..where((l) => l.entryId.equals(entryId)))
        .get();
    return lines.fold<double>(0, (sum, l) => sum + l.debit);
  }

  /// Get Hash Chain statistics (fast, no verification)
  Future<Map<String, int>> getHashChainStats() async {
    final entries = await db.select(db.journalEntries).get();
    final hashRegex = RegExp(r'\[HASH:[a-f0-9]{64}\]');

    int signed = 0;
    int unsigned = 0;
    for (final e in entries) {
      if (hashRegex.hasMatch(e.description ?? '')) {
        signed++;
      } else {
        unsigned++;
      }
    }

    return {'total': entries.length, 'signed': signed, 'unsigned': unsigned};
  }

  // ── Sync Conflict Log ────────────────────────────────────────────────

  Future<List<SyncConflictLogItem>> getSyncConflicts({
    String? tableName,
    int limit = 100,
  }) async {
    final query = db.select(db.syncConflictLog)
      ..orderBy([(c) => OrderingTerm.desc(c.detectedAt)])
      ..limit(limit);

    if (tableName != null) {
      query.where((c) => c.conflictTable.equals(tableName));
    }

    return query.get();
  }

  Future<int> getUnresolvedConflictCount() async {
    final result = await (db.select(db.syncConflictLog)
          ..where((c) => c.resolution.equals('skipped')))
        .get();
    return result.length;
  }

  Future<List<String>> getConflictTableNames() async {
    final results = await db.customSelect(
      'SELECT DISTINCT table_name FROM sync_conflict_log ORDER BY table_name',
    ).get();
    return results.map((r) => r.read<String>('table_name')).toList();
  }

  Future<void> resolveConflict(int id, String resolution) async {
    await (db.update(db.syncConflictLog)..where((c) => c.id.equals(id))).write(
      SyncConflictLogCompanion(resolution: Value(resolution)),
    );
  }

  Future<int> purgeResolvedConflicts({int olderThanDays = 30}) async {
    final cutoff = DateTime.now().subtract(Duration(days: olderThanDays));
    return (db.delete(db.syncConflictLog)
          ..where((c) =>
              c.resolution.isIn(['server_wins', 'client_wins', 'merged']) &
              c.detectedAt.isSmallerThanValue(cutoff)))
        .go();
  }
}
