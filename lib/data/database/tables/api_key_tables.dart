part of '../database.dart';

// ═══════════════════════════════════════════════════════════════════════════
// API KEY — مفاتيح API للتكامل الخارجي (Phase C1)
// ═══════════════════════════════════════════════════════════════════════════

/// API keys for external integrations
@DataClassName('ApiKeyData')
@TableIndex(name: 'idx_api_key_hash', columns: {#keyHash})
class ApiKeys extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()(); // اسم المفتاح (وصفي)
  TextColumn get keyHash => text()(); // SHA-256 hash of the key
  TextColumn get keyPrefix => text()(); // First 8 chars for identification

  IntColumn get userId => integer().nullable().references(Users, #id)();

  /// JSON array of allowed endpoints/permissions: ["read:products","write:orders"]
  TextColumn get permissions => text().nullable()();

  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  DateTimeColumn get lastUsedAt => dateTime().nullable()();
  DateTimeColumn get expiresAt => dateTime().nullable()();
  IntColumn get requestCount => integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}
