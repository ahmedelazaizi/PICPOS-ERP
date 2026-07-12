import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Remote backup transport kind.
enum RemoteBackupKind { ftp, sftp }

/// Persistent configuration for remote backup.
///
/// Non-secret fields live in SharedPreferences; the password is stored
/// separately in [FlutterSecureStorage] so it is encrypted at rest.
class RemoteBackupConfig {
  final bool enabled;
  final RemoteBackupKind kind;
  final String host;
  final int port;
  final String username;
  final String remoteDir;
  final int retentionDays;

  const RemoteBackupConfig({
    required this.enabled,
    required this.kind,
    required this.host,
    required this.port,
    required this.username,
    required this.remoteDir,
    required this.retentionDays,
  });

  factory RemoteBackupConfig.disabled() => const RemoteBackupConfig(
        enabled: false,
        kind: RemoteBackupKind.ftp,
        host: '',
        port: 21,
        username: '',
        remoteDir: '/backups',
        retentionDays: 30,
      );

  RemoteBackupConfig copyWith({
    bool? enabled,
    RemoteBackupKind? kind,
    String? host,
    int? port,
    String? username,
    String? remoteDir,
    int? retentionDays,
  }) =>
      RemoteBackupConfig(
        enabled: enabled ?? this.enabled,
        kind: kind ?? this.kind,
        host: host ?? this.host,
        port: port ?? this.port,
        username: username ?? this.username,
        remoteDir: remoteDir ?? this.remoteDir,
        retentionDays: retentionDays ?? this.retentionDays,
      );

  // ── persistence ─────────────────────────────────────────────────────────
  static const _prefEnabled = 'remote_backup_enabled';
  static const _prefKind = 'remote_backup_kind';
  static const _prefHost = 'remote_backup_host';
  static const _prefPort = 'remote_backup_port';
  static const _prefUsername = 'remote_backup_username';
  static const _prefDir = 'remote_backup_dir';
  static const _prefRetention = 'remote_backup_retention';
  static const _secretKey = 'remote_backup_password';

  static const _secure = FlutterSecureStorage();

  static Future<RemoteBackupConfig> load() async {
    final prefs = await SharedPreferences.getInstance();
    final kindName = prefs.getString(_prefKind) ?? 'ftp';
    return RemoteBackupConfig(
      enabled: prefs.getBool(_prefEnabled) ?? false,
      kind: RemoteBackupKind.values
          .firstWhere((k) => k.name == kindName, orElse: () => RemoteBackupKind.ftp),
      host: prefs.getString(_prefHost) ?? '',
      port: prefs.getInt(_prefPort) ?? 21,
      username: prefs.getString(_prefUsername) ?? '',
      remoteDir: prefs.getString(_prefDir) ?? '/backups',
      retentionDays: prefs.getInt(_prefRetention) ?? 30,
    );
  }

  Future<void> save({String? password}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefEnabled, enabled);
    await prefs.setString(_prefKind, kind.name);
    await prefs.setString(_prefHost, host);
    await prefs.setInt(_prefPort, port);
    await prefs.setString(_prefUsername, username);
    await prefs.setString(_prefDir, remoteDir);
    await prefs.setInt(_prefRetention, retentionDays);
    if (password != null) {
      await _secure.write(key: _secretKey, value: password);
    }
  }

  static Future<String?> loadPassword() => _secure.read(key: _secretKey);

  static Future<void> clearPassword() => _secure.delete(key: _secretKey);
}
