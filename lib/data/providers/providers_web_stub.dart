// Web stub for native providers (empty stubs for web platform)
// These providers are not available on web

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../database/database_stub.dart';

/// Stub database provider for web (throws if used)
final nativeDatabaseProvider = Provider<AppDatabase>((ref) {
  throw UnsupportedError(
    'Native database not available on web. Use Supabase instead.',
  );
});

/// Stub excel service provider for web
final nativeExcelServiceProvider = Provider<Object?>((ref) {
  return null; // Excel not available on web
});
