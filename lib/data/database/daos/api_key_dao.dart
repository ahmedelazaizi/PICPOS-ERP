part of '../database.dart';

// ═══════════════════════════════════════════════════════════════════════════
// API KEY DAO — إدارة مفاتيح API (Phase C1)
// ═══════════════════════════════════════════════════════════════════════════

extension ApiKeyDao on AppDatabase {

  /// Create a new API key (returns the raw key — only shown once)
  Future<Map<String, dynamic>> createApiKey({
    required String name,
    int? userId,
    List<String>? permissions,
    DateTime? expiresAt,
  }) async {
    // Generate a random key
    final rawKey = _generateApiKey();
    final hash = SecurityService.hashApiKey(rawKey);
    final prefix = rawKey.substring(0, 8);

    final id = await into(apiKeys).insert(
      ApiKeysCompanion.insert(
        name: name,
        keyHash: hash,
        keyPrefix: prefix,
        userId: Value(userId),
        permissions: Value(permissions?.join(',') ?? 'read:*'),
        expiresAt: Value(expiresAt),
      ),
    );

    return {
      'id': id,
      'key': rawKey, // Only returned once
      'prefix': prefix,
      'name': name,
    };
  }

  /// Validate an API key and return the key data if valid
  Future<ApiKeyData?> validateApiKey(String rawKey) async {
    final hash = SecurityService.hashApiKey(rawKey);
    final keyData = await (select(apiKeys)
          ..where((k) => k.keyHash.equals(hash))
          ..where((k) => k.isActive.equals(true)))
        .getSingleOrNull();

    if (keyData == null) return null;

    // Check expiration
    if (keyData.expiresAt != null && keyData.expiresAt!.isBefore(DateTime.now())) {
      return null;
    }

    // Update last used
    await (update(apiKeys)..where((k) => k.id.equals(keyData.id)))
        .write(ApiKeysCompanion(
      lastUsedAt: Value(DateTime.now()),
      requestCount: Value(keyData.requestCount + 1),
    ));

    return keyData;
  }

  /// Get all API keys (without the actual key hash)
  Future<List<ApiKeyData>> getApiKeys() {
    return (select(apiKeys)
          ..orderBy([(k) => OrderingTerm.desc(k.createdAt)]))
        .get();
  }

  /// Revoke an API key
  Future<void> revokeApiKey(int keyId) async {
    await (update(apiKeys)..where((k) => k.id.equals(keyId)))
        .write(const ApiKeysCompanion(isActive: Value(false)));
  }

  /// Delete an API key permanently
  Future<void> deleteApiKey(int keyId) async {
    await (delete(apiKeys)..where((k) => k.id.equals(keyId))).go();
  }

  /// Check if a key has permission for a specific scope
  bool hasApiPermission(ApiKeyData key, String requiredScope) {
    if (key.permissions == null || key.permissions!.isEmpty) return false;
    final perms = key.permissions!.split(',');
    // Check wildcard and exact match
    return perms.contains('*') ||
        perms.contains(requiredScope) ||
        perms.any((p) => p.endsWith(':*') &&
            requiredScope.startsWith(p.replaceAll(':*', ':')));
  }

  String _generateApiKey() {
    final random = DateTime.now().microsecondsSinceEpoch;
    final key = SecurityService.generateSalt() +
        random.toRadixString(36) +
        SecurityService.generateSalt();
    return 'ural_${key.substring(0, 40)}';
  }
}
