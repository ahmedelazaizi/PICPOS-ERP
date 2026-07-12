import 'dart:io';

import 'package:ftpconnect/ftpconnect.dart';

import 'remote_backup_config.dart';

/// Result of a remote backup attempt.
class RemoteBackupResult {
  final bool success;
  final String? remotePath;
  final String? error;
  final Duration elapsed;

  const RemoteBackupResult.ok(this.remotePath, this.elapsed)
      : success = true,
        error = null;
  const RemoteBackupResult.failure(this.error, this.elapsed)
      : success = false,
        remotePath = null;
}

/// Uploads a local backup file to a remote destination (FTP today; SFTP
/// tomorrow). Does NOT create the backup itself — pass in an existing file.
class RemoteBackupService {
  RemoteBackupService._();
  static final instance = RemoteBackupService._();

  /// Upload [localFile] using the saved config. If config is disabled or
  /// invalid, returns a failure result without throwing.
  Future<RemoteBackupResult> upload(File localFile) async {
    final sw = Stopwatch()..start();
    if (!await localFile.exists()) {
      return RemoteBackupResult.failure('Local file does not exist',
          sw.elapsed);
    }

    final cfg = await RemoteBackupConfig.load();
    if (!cfg.enabled) {
      return RemoteBackupResult.failure('Remote backup disabled', sw.elapsed);
    }
    if (cfg.host.isEmpty || cfg.username.isEmpty) {
      return RemoteBackupResult.failure('Incomplete config', sw.elapsed);
    }
    final password = await RemoteBackupConfig.loadPassword();
    if (password == null || password.isEmpty) {
      return RemoteBackupResult.failure('Missing password', sw.elapsed);
    }

    switch (cfg.kind) {
      case RemoteBackupKind.ftp:
        return _uploadFtp(localFile, cfg, password, sw);
      case RemoteBackupKind.sftp:
        // SFTP is deferred: ftpconnect only supports plain FTP/FTPS.
        // When we add SFTP, plug `dartssh2` here.
        return RemoteBackupResult.failure(
            'SFTP not implemented yet', sw.elapsed);
    }
  }

  Future<RemoteBackupResult> _uploadFtp(
    File file,
    RemoteBackupConfig cfg,
    String password,
    Stopwatch sw,
  ) async {
    final ftp = FTPConnect(
      cfg.host,
      user: cfg.username,
      pass: password,
      port: cfg.port,
    );
    try {
      await ftp.connect();
      // Ensure remote dir exists and cd into it.
      await _ensureRemoteDir(ftp, cfg.remoteDir);
      final remoteName = _timestampedName(file);
      final ok = await ftp.uploadFile(file, sRemoteName: remoteName);
      if (!ok) {
        return RemoteBackupResult.failure('Upload returned false', sw.elapsed);
      }
      return RemoteBackupResult.ok('${cfg.remoteDir}/$remoteName', sw.elapsed);
    } catch (e) {
      return RemoteBackupResult.failure('FTP error: $e', sw.elapsed);
    } finally {
      try {
        await ftp.disconnect();
      } catch (_) {}
    }
  }

  Future<void> _ensureRemoteDir(FTPConnect ftp, String dir) async {
    if (dir.isEmpty || dir == '/') return;
    try {
      await ftp.changeDirectory(dir);
    } catch (_) {
      // Directory missing — create recursively.
      final parts = dir.split('/').where((p) => p.isNotEmpty).toList();
      await ftp.changeDirectory('/');
      for (final p in parts) {
        try {
          await ftp.changeDirectory(p);
        } catch (_) {
          await ftp.makeDirectory(p);
          await ftp.changeDirectory(p);
        }
      }
    }
  }

  String _timestampedName(File f) {
    final base = f.uri.pathSegments.last;
    final ts = DateTime.now()
        .toUtc()
        .toIso8601String()
        .replaceAll(':', '-')
        .split('.')
        .first;
    return '${ts}_$base';
  }

  /// Connectivity check. Returns null on success, error message on failure.
  Future<String?> testConnection() async {
    final cfg = await RemoteBackupConfig.load();
    if (cfg.host.isEmpty) return 'Host not set';
    final password = await RemoteBackupConfig.loadPassword();
    if (password == null || password.isEmpty) return 'Password not set';
    if (cfg.kind == RemoteBackupKind.sftp) return 'SFTP not implemented yet';

    final ftp = FTPConnect(
      cfg.host,
      user: cfg.username,
      pass: password,
      port: cfg.port,
    );
    try {
      final connected = await ftp.connect();
      if (!connected) return 'Connect returned false';
      await ftp.disconnect();
      return null;
    } catch (e) {
      return 'FTP error: $e';
    }
  }
}
