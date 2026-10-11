import 'secure_storage_service.dart';

/// مخزنُ أسرارٍ بسيط يُحقَن في الخدمات كي تُختبَر بلا تخزينٍ آمنٍ حقيقي.
///
/// نفسُ شكل `SecureStorageService.read/write/delete`، لكنه واجهةٌ مجرّدة.
abstract class SecretStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

/// التنفيذُ الإنتاجيّ: يلفّ [SecureStorageService] (flutter_secure_storage).
class SecureStorageSecretStore implements SecretStore {
  SecureStorageSecretStore([SecureStorageService? storage])
      : _storage = storage ?? SecureStorageService();

  final SecureStorageService _storage;

  @override
  Future<String?> read(String key) => _storage.read(key);

  @override
  Future<void> write(String key, String value) => _storage.write(key, value);

  @override
  Future<void> delete(String key) => _storage.delete(key);
}

/// مخزنٌ في الذاكرة للاختبارات.
class MemorySecretStore implements SecretStore {
  MemorySecretStore([Map<String, String>? initial])
      : values = Map<String, String>.of(initial ?? const {});

  final Map<String, String> values;

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;

  @override
  Future<void> delete(String key) async => values.remove(key);
}
