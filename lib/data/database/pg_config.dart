import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/config/brand.dart';

/// Database connection mode
enum DatabaseMode {
  /// Local SQLite database (standalone, offline)
  sqlite,

  /// Remote PostgreSQL server (multi-branch, real-time)
  postgres;

  String get displayName {
    switch (this) {
      case DatabaseMode.sqlite:
        return 'قاعدة بيانات محلية (SQLite)';
      case DatabaseMode.postgres:
        return 'سيرفر PostgreSQL (متعدد الفروع)';
    }
  }
}

/// PostgreSQL connection configuration
class PostgresConfig {
  final String host;
  final int port;
  final String database;
  final String username;
  final String password;
  final bool useSsl;

  const PostgresConfig({
    this.host = 'localhost',
    this.port = 5432,
    this.database = Brand.pgIdentifier,
    this.username = Brand.pgIdentifier,
    this.password = '',
    this.useSsl = false,
  });

  /// Create from JSON map
  factory PostgresConfig.fromJson(Map<String, dynamic> json) {
    return PostgresConfig(
      host: json['host'] as String? ?? 'localhost',
      port: json['port'] as int? ?? 5432,
      database: json['database'] as String? ?? Brand.pgIdentifier,
      username: json['username'] as String? ?? Brand.pgIdentifier,
      password: json['password'] as String? ?? '',
      useSsl: json['useSsl'] as bool? ?? false,
    );
  }

  /// Serialize to JSON map
  Map<String, dynamic> toJson() => {
        'host': host,
        'port': port,
        'database': database,
        'username': username,
        'password': password,
        'useSsl': useSsl,
      };

  /// Create a copy with modified fields
  PostgresConfig copyWith({
    String? host,
    int? port,
    String? database,
    String? username,
    String? password,
    bool? useSsl,
  }) {
    return PostgresConfig(
      host: host ?? this.host,
      port: port ?? this.port,
      database: database ?? this.database,
      username: username ?? this.username,
      password: password ?? this.password,
      useSsl: useSsl ?? this.useSsl,
    );
  }

  /// Human-readable connection string (no password)
  String get displayString => '$username@$host:$port/$database';

  // ─── Runtime offline fallback flag ────────────────────────────────
  /// True when PostgreSQL was configured but the server was unreachable at
  /// startup, so the app fell back to the local SQLite database.
  static bool _isOfflineFallback = false;
  static bool get isOfflineFallback => _isOfflineFallback;

  /// Timestamp when offline fallback started (persisted across restarts)
  static DateTime? _offlineFallbackStart;
  static DateTime? get offlineFallbackStart => _offlineFallbackStart;

  static const _offlineStartKey = 'pg_offline_start';

  /// Set offline fallback mode. When entering offline mode, records the
  /// timestamp so the sync service knows which records to copy back.
  static Future<void> setOfflineFallback(bool value) async {
    _isOfflineFallback = value;
    final prefs = await SharedPreferences.getInstance();
    if (value) {
      // Only set the start time if not already set (preserves across restarts)
      if (_offlineFallbackStart == null) {
        _offlineFallbackStart = DateTime.now();
        await prefs.setString(
          _offlineStartKey,
          _offlineFallbackStart!.toIso8601String(),
        );
      }
    } else {
      _offlineFallbackStart = null;
      await prefs.remove(_offlineStartKey);
    }
  }

  /// Load the offline fallback start timestamp from SharedPreferences.
  /// Called at startup to restore state after an app restart during offline.
  static Future<void> loadOfflineFallbackState() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_offlineStartKey);
    if (stored != null) {
      _offlineFallbackStart = DateTime.tryParse(stored);
      _isOfflineFallback = _offlineFallbackStart != null;
    }
  }

  // ─── Persistence ────────────────────────────────────────────────────

  static const _modeKey = 'db_mode';
  static const _configKey = 'pg_config';

  /// Save database mode to SharedPreferences
  static Future<void> saveMode(DatabaseMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_modeKey, mode.name);
  }

  /// Load database mode from SharedPreferences
  static Future<DatabaseMode> loadMode() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString(_modeKey);
    if (value == 'postgres') return DatabaseMode.postgres;
    return DatabaseMode.sqlite; // default
  }

  /// Save PostgreSQL config to SharedPreferences
  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_configKey, jsonEncode(toJson()));
  }

  /// Load PostgreSQL config from SharedPreferences
  static Future<PostgresConfig> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_configKey);
    if (raw == null) return const PostgresConfig();
    try {
      return PostgresConfig.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
    } catch (_) {
      return const PostgresConfig();
    }
  }
}
