import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../database/supabase_database.dart';

/// Provider for Supabase client (only available on web)
final supabaseClientProvider = Provider<SupabaseClient?>((ref) {
  if (kIsWeb) {
    return Supabase.instance.client;
  }
  return null;
});

/// Provider for Supabase database service (only available on web)
final supabaseDatabaseProvider = Provider<SupabaseDatabase?>((ref) {
  final client = ref.watch(supabaseClientProvider);
  if (client != null) {
    return SupabaseDatabase(client);
  }
  return null;
});

/// Check if using Supabase (web platform)
final isUsingSupabaseProvider = Provider<bool>((ref) => kIsWeb);
