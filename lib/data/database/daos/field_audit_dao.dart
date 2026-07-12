part of '../database.dart';

// ═══════════════════════════════════════════════════════════════════════════
// FIELD AUDIT DAO — سجل تغييرات الحقول (Phase C7)
// ═══════════════════════════════════════════════════════════════════════════

extension FieldAuditDao on AppDatabase {
  /// Log a single field change
  Future<int> logFieldChange({
    required String entityType,
    required int entityId,
    required String fieldName,
    required String fieldKey,
    String? oldValue,
    String? newValue,
    required int changedBy,
    required String changedByName,
    String? changeReason,
    String? transactionId,
  }) {
    // Skip when no authenticated user (server-side paths handling client requests).
    // changed_by has a FK to users; inserting 0 violates it and under PostgreSQL
    // poisons the surrounding transaction (25P02 at COMMIT).
    if (changedBy <= 0) {
      return Future.value(0);
    }
    return into(fieldAuditLogs).insert(
      FieldAuditLogsCompanion.insert(
        entityType: entityType,
        entityId: entityId,
        fieldName: fieldName,
        fieldKey: fieldKey,
        oldValue: Value(oldValue),
        newValue: Value(newValue),
        changedBy: changedBy,
        changedByName: changedByName,
        changeReason: Value(changeReason),
        transactionId: Value(transactionId),
        createdAt: Value(DateTime.now()),
      ),
    );
  }

  /// Log multiple field changes as a batch (same transaction)
  Future<void> logBatchFieldChanges({
    required String entityType,
    required int entityId,
    required int changedBy,
    required String changedByName,
    required String transactionId,
    required List<FieldChange> changes,
    String? changeReason,
  }) async {
    if (changedBy <= 0) return; // see logFieldChange for rationale
    await batch((b) {
      for (final change in changes) {
        b.insert(
          fieldAuditLogs,
          FieldAuditLogsCompanion.insert(
            entityType: entityType,
            entityId: entityId,
            fieldName: change.fieldName,
            fieldKey: change.fieldKey,
            oldValue: Value(change.oldValue),
            newValue: Value(change.newValue),
            changedBy: changedBy,
            changedByName: changedByName,
            changeReason: Value(changeReason),
            transactionId: Value(transactionId),
            createdAt: Value(DateTime.now()),
          ),
        );
      }
    });
  }

  /// Get field change history for a specific entity
  Future<List<FieldAuditLog>> getFieldHistory({
    required String entityType,
    required int entityId,
    String? fieldKey,
    int limit = 100,
    int offset = 0,
  }) {
    final query = select(fieldAuditLogs)
      ..where((t) => t.entityType.equals(entityType))
      ..where((t) => t.entityId.equals(entityId))
      ..orderBy([(t) => OrderingTerm.desc(t.createdAt)])
      ..limit(limit, offset: offset);

    if (fieldKey != null) {
      query.where((t) => t.fieldKey.equals(fieldKey));
    }

    return query.get();
  }

  /// Get timeline for a specific field on a specific entity
  Future<List<FieldAuditLog>> getFieldTimeline({
    required String entityType,
    required int entityId,
    required String fieldKey,
  }) {
    return (select(fieldAuditLogs)
          ..where((t) => t.entityType.equals(entityType))
          ..where((t) => t.entityId.equals(entityId))
          ..where((t) => t.fieldKey.equals(fieldKey))
          ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]))
        .get();
  }

  /// Get recent changes across all entities
  Future<List<FieldAuditLog>> getRecentFieldChanges({
    int limit = 50,
    String? entityType,
    int? changedBy,
    DateTime? fromDate,
    DateTime? toDate,
  }) {
    final query = select(fieldAuditLogs)
      ..orderBy([(t) => OrderingTerm.desc(t.createdAt)])
      ..limit(limit);

    if (entityType != null) {
      query.where((t) => t.entityType.equals(entityType));
    }
    if (changedBy != null) {
      query.where((t) => t.changedBy.equals(changedBy));
    }
    if (fromDate != null) {
      query.where((t) => t.createdAt.isBiggerOrEqual(Variable(fromDate)));
    }
    if (toDate != null) {
      query.where((t) => t.createdAt.isSmallerOrEqual(Variable(toDate)));
    }

    return query.get();
  }

  /// Get changes grouped by transaction ID
  Future<List<FieldAuditLog>> getTransactionChanges(String transactionId) {
    return (select(fieldAuditLogs)
          ..where((t) => t.transactionId.equals(transactionId))
          ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]))
        .get();
  }

  /// Count total changes for an entity
  Future<int> getFieldChangeCount({
    required String entityType,
    required int entityId,
  }) async {
    final query = selectOnly(fieldAuditLogs)
      ..addColumns([fieldAuditLogs.id.count()]);
    query.where(fieldAuditLogs.entityType.equals(entityType));
    query.where(fieldAuditLogs.entityId.equals(entityId));
    final result = await query.getSingle();
    return result.read(fieldAuditLogs.id.count()) ?? 0;
  }

  /// Delete old field audit logs (maintenance)
  Future<int> deleteOldFieldAuditLogs(DateTime beforeDate) {
    return (delete(fieldAuditLogs)
          ..where((t) => t.createdAt.isSmallerThan(Variable(beforeDate))))
        .go();
  }
}

/// Represents a single field change for batch operations
class FieldChange {
  final String fieldName;
  final String fieldKey;
  final String? oldValue;
  final String? newValue;

  const FieldChange({
    required this.fieldName,
    required this.fieldKey,
    this.oldValue,
    this.newValue,
  });
}
