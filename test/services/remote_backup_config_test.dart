import 'package:picpos_erp/services/backup/remote_backup_config.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('RemoteBackupConfig', () {
    test('defaults are disabled and sensible', () async {
      final cfg = await RemoteBackupConfig.load();
      expect(cfg.enabled, isFalse);
      expect(cfg.kind, RemoteBackupKind.ftp);
      expect(cfg.port, 21);
      expect(cfg.remoteDir, '/backups');
      expect(cfg.retentionDays, 30);
    });

    test('save then load round-trips all non-secret fields', () async {
      const original = RemoteBackupConfig(
        enabled: true,
        kind: RemoteBackupKind.sftp,
        host: 'backup.example.com',
        port: 2222,
        username: 'uralcash',
        remoteDir: '/uralcash/backups/client-42',
        retentionDays: 14,
      );
      await original.save();

      final loaded = await RemoteBackupConfig.load();
      expect(loaded.enabled, isTrue);
      expect(loaded.kind, RemoteBackupKind.sftp);
      expect(loaded.host, 'backup.example.com');
      expect(loaded.port, 2222);
      expect(loaded.username, 'uralcash');
      expect(loaded.remoteDir, '/uralcash/backups/client-42');
      expect(loaded.retentionDays, 14);
    });

    test('copyWith overrides only specified fields', () {
      const base = RemoteBackupConfig(
        enabled: false,
        kind: RemoteBackupKind.ftp,
        host: 'old.host',
        port: 21,
        username: 'u',
        remoteDir: '/backups',
        retentionDays: 30,
      );
      final updated = base.copyWith(host: 'new.host', port: 990);
      expect(updated.host, 'new.host');
      expect(updated.port, 990);
      expect(updated.username, 'u');
      expect(updated.kind, RemoteBackupKind.ftp);
    });
  });
}
