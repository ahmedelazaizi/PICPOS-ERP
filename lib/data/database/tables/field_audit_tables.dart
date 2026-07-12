part of '../database.dart';

// ═══════════════════════════════════════════════════════════════════════════
// FIELD-LEVEL AUDIT LOGGING — سجل التغييرات على مستوى الحقول (Phase C7)
// ═══════════════════════════════════════════════════════════════════════════

/// Tracks individual field changes on sensitive entities.
/// Groups related changes via [transactionId] for atomic operations.
@DataClassName('FieldAuditLog')
@TableIndex(name: 'idx_field_audit_entity', columns: {#entityType, #entityId})
@TableIndex(name: 'idx_field_audit_date', columns: {#createdAt})
@TableIndex(name: 'idx_field_audit_user', columns: {#changedBy})
@TableIndex(name: 'idx_field_audit_txn', columns: {#transactionId})
class FieldAuditLogs extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// Entity type: product, party, sales_invoice, purchase_invoice, journal_entry
  TextColumn get entityType => text()();

  /// ID of the entity that was changed
  IntColumn get entityId => integer()();

  /// Human-readable field name (e.g. 'السعر', 'الاسم', 'الكمية')
  TextColumn get fieldName => text()();

  /// Machine-readable field key (e.g. 'price', 'name', 'quantity')
  TextColumn get fieldKey => text()();

  /// Previous value (as string), null for new records
  TextColumn get oldValue => text().nullable()();

  /// New value (as string), null for deletions
  TextColumn get newValue => text().nullable()();

  /// User who made the change
  IntColumn get changedBy => integer().references(Users, #id)();

  /// Display name of the user (denormalized for fast reads)
  TextColumn get changedByName => text()();

  /// Optional reason for the change
  TextColumn get changeReason => text().nullable()();

  /// Groups multiple field changes that happened in the same operation
  TextColumn get transactionId => text().nullable()();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}
