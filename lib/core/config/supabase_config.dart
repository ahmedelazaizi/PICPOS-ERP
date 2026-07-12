import 'package:flutter/foundation.dart';

/// Supabase configuration
/// Used for web platform database
///
/// Values are injected at build time via --dart-define:
///   flutter run --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...
///
/// For development, see .env.example for required variables.
class SupabaseConfig {
  /// Supabase project URL (injected via --dart-define=SUPABASE_URL=...)
  static const String supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: '',
  );

  /// Supabase anon/public key (injected via --dart-define=SUPABASE_ANON_KEY=...)
  static const String supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: '',
  );

  /// Whether Supabase is properly configured (non-empty and not a placeholder)
  static bool get isConfigured =>
      supabaseUrl.isNotEmpty &&
      supabaseAnonKey.isNotEmpty &&
      !_isPlaceholder(supabaseUrl) &&
      !_isPlaceholder(supabaseAnonKey);

  /// Check if running on web platform
  static bool get isWeb => kIsWeb;

  /// Check if should use Supabase (only on web and when configured)
  static bool get useSupabase => kIsWeb && isConfigured;

  static bool _isPlaceholder(String v) {
    final lower = v.toLowerCase();
    return lower.contains('your-') ||
        lower.contains('your_') ||
        lower.contains('example') ||
        lower.contains('xxxx');
  }

  /// Throws a descriptive error if misconfigured. Call at app bootstrap on web.
  static void assertConfigured() {
    if (!isConfigured) {
      throw StateError(
        'Supabase is not configured. Pass --dart-define=SUPABASE_URL=... '
        'and --dart-define=SUPABASE_ANON_KEY=... at build/run time. '
        'See .env.example and docs/SUPABASE_RLS_CHECKLIST.md.',
      );
    }
  }
}
