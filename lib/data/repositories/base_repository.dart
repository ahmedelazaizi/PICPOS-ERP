import '../database/database.dart';

/// Base repository interface for common CRUD operations
abstract class BaseRepository<T> {
  final AppDatabase db;

  BaseRepository(this.db);

  /// Get all items as a stream for reactive UI
  Stream<List<T>> watchAll();

  /// Get item by ID
  Future<T?> getById(int id);
}

/// Repository result wrapper for error handling
class RepositoryResult<T> {
  final T? data;
  final String? error;
  final bool success;

  RepositoryResult.success(this.data) : success = true, error = null;

  RepositoryResult.failure(this.error) : success = false, data = null;
}
