// ignore_for_file: avoid_dynamic_calls
import 'package:drift/drift.dart';
import 'package:picpos_erp/data/database/database.dart';
import 'package:picpos_erp/services/sync/sync_strategy.dart';
import 'package:flutter/foundation.dart';

class PaymentSyncStrategy extends SyncStrategy {
  PaymentSyncStrategy(super.db);

  @override
  String get tableName => 'payments';

  @override
  String get apiEndpoint => '/api/payments';

  /// R5 — receipt / payment headers are append-only at the server but
  /// `serverWins` is chosen so void / cancellation status updates (which
  /// mutate the same row) propagate authoritatively from the server.
  /// Without this, a local edit could mask a server-side void.
  @override
  ConflictPolicy get conflictPolicy => ConflictPolicy.serverWins;

  @override
  Future<void> syncFromJson(Map<String, dynamic> json) async {
    final payments = json['payments'] as List? ?? [];
    int inserted = 0;
    int updated = 0;
    for (final p in payments) {
      final result = await _syncSinglePayment(p as Map<String, dynamic>);
      if (result == _SyncResult.inserted) inserted++;
      if (result == _SyncResult.updated) updated++;
    }
    if (inserted > 0 || updated > 0) {
      db.markTablesUpdated({db.payments});
      debugPrint('[Sync] Payments: $inserted new, $updated updated');
    }
  }

  @override
  Future<int> syncIncremental(DateTime since) async => 0;

  Future<_SyncResult> _syncSinglePayment(Map<String, dynamic> map) async {
    final serverId = parseInt(map['id']);
    final serverIsDeleted = parseBool(map['isDeleted']);
    final serverDeletedAt = DateTime.tryParse(map['deletedAt']?.toString() ?? '');
    final serverDeletedBy = parseIntNullable(map['deletedBy']);
    final serverUpdatedAt = DateTime.tryParse(map['updatedAt']?.toString() ?? '');

    try {
      var result = _SyncResult.skipped;
      await db.transaction(() async {
        final existing = await (db.select(db.payments)
          ..where((p) => p.id.equals(serverId))
          ..limit(1)
        ).getSingleOrNull();

        if (existing != null) {
          // Update mutable fields (soft-delete, etc.)
          final needsUpdate =
              existing.isDeleted != serverIsDeleted ||
              existing.deletedAt != serverDeletedAt;
          if (needsUpdate) {
            await (db.update(db.payments)
              ..where((p) => p.id.equals(serverId))
            ).write(PaymentsCompanion(
              isDeleted: Value(serverIsDeleted),
              deletedAt: Value(serverDeletedAt),
              deletedBy: Value(serverDeletedBy),
              updatedAt: Value(serverUpdatedAt ?? DateTime.now()),
            ));
            result = _SyncResult.updated;
          }
          return;
        }

        // Dedup by globalId
        final globalId = map['globalId'] as String?;
        if (globalId != null && globalId.isNotEmpty) {
          final byGlobal = await (db.select(db.payments)
            ..where((p) => p.globalId.equals(globalId))
            ..limit(1)
          ).getSingleOrNull();
          if (byGlobal != null) return;
        }

        // Dedup by idempotencyKey
        final idempotencyKey = map['idempotencyKey'] as String?;
        if (idempotencyKey != null && idempotencyKey.isNotEmpty) {
          final byKey = await (db.select(db.payments)
            ..where((p) => p.idempotencyKey.equals(idempotencyKey))
            ..limit(1)
          ).getSingleOrNull();
          if (byKey != null) return;
        }

        result = _SyncResult.inserted;
        await db.into(db.payments).insertOnConflictUpdate(
          PaymentsCompanion(
            id: Value(serverId),
            paymentNumber: Value(map['paymentNumber'] as String? ?? 'PAY-$serverId'),
            paymentDate: Value(DateTime.tryParse(map['paymentDate']?.toString() ?? '') ?? DateTime.now()),
            amount: Value(parseDouble(map['amount'])),
            paymentMethod: Value(map['paymentMethod'] as String? ?? 'cash'),
            safeId: Value(parseInt(map['safeId'])),
            partyId: Value(parseIntNullable(map['partyId'])),
            paymentType: Value(map['paymentType'] as String? ?? 'receipt'),
            notes: Value(map['notes'] as String?),
            userId: Value(parseIntNullable(map['userId'])),
            safeTransactionId: Value(parseIntNullable(map['safeTransactionId'])),
            globalId: Value(globalId),
            idempotencyKey: Value(idempotencyKey),
            isDeleted: Value(serverIsDeleted),
            deletedAt: Value(serverDeletedAt),
            deletedBy: Value(serverDeletedBy),
            updatedAt: Value(serverUpdatedAt ?? DateTime.now()),
            createdAt: Value(DateTime.tryParse(map['createdAt']?.toString() ?? '') ?? DateTime.now()),
          ),
        );
      });
      return result;
    } on Exception catch (e) {
      if (e.toString().contains('UNIQUE constraint failed') ||
          e.toString().contains('duplicate key')) {
        debugPrint('[Sync] Payment already synced (duplicate): $serverId');
        return _SyncResult.skipped;
      }
      debugPrint('[Sync] Error in PaymentSyncStrategy: $e');
      rethrow;
    }
  }

  @override
  Future<void> upsert(Insertable record) async {
    if (record is PaymentsCompanion) {
      await db.into(db.payments).insertOnConflictUpdate(record);
    }
  }
}

enum _SyncResult { inserted, updated, skipped }