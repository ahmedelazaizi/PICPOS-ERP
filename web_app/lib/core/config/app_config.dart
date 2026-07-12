/// Application configuration
/// Use --dart-define=IS_DEMO=true to build demo version
class AppConfig {
  /// Check if running in demo mode
  static const bool isDemo = bool.fromEnvironment('IS_DEMO', defaultValue: false);
  
  /// Maximum products allowed in demo mode
  static const int maxDemoProducts = 50;
  
  /// App version
  static const String version = '1.0.0';
}
