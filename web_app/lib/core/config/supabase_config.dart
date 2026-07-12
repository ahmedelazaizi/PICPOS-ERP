import 'package:flutter/foundation.dart';

/// Supabase configuration for web_app.
///
/// Values MUST be injected at build time via --dart-define:
///   flutter run --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...
///
/// Never hardcode keys here — they are secrets (even the anon key grants
/// access scoped only by RLS policies and must be rotated on exposure).
class SupabaseConfig {
  static const String supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: '',
  );

  static const String supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: '',
  );

  static bool get isConfigured =>
      supabaseUrl.isNotEmpty &&
      supabaseAnonKey.isNotEmpty &&
      !_isPlaceholder(supabaseUrl) &&
      !_isPlaceholder(supabaseAnonKey);

  static bool get isWeb => kIsWeb;

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
