import 'package:ural_erp/core/permissions/permission_codes.dart';
import 'package:ural_erp/data/database/database.dart';
import 'package:picpos_api_client/picpos_api_client.dart';

import '../cloud_sync/cloud_link_api.dart';

/// Mobile credential settings never contain a desktop login hash.
class AdminUserMirror {
  AdminUserMirror(this.db);

  final AppDatabase db;

  static String _settingKey(String globalId) => 'mobile_admin_user_$globalId';

  Future<void> setMobilePassword(String globalId, String password) async {
    final normalized = normalizeCredential(password);
    if (normalized.length < kMobilePasswordMinLength) {
      throw ArgumentError('Mobile password must contain at least 8 characters');
    }
    await db.saveSettings({_settingKey(globalId): await hashMobilePassword(normalized)});
  }

  Future<void> disableMobile(String globalId) =>
      db.saveSettings({_settingKey(globalId): ''});

  /// Includes inactive and soft-deleted users so the cloud can revoke them.
  Future<List<Map<String, Object?>>> buildUsers() async {
    final settings = {
      for (final setting in await db.getSettingsByPrefix('mobile_admin_user_'))
        setting.key: setting.value ?? '',
    };
    final rows = await db.customSelect('''
      SELECT id, global_id, username, display_name, is_active, is_locked,
             deleted_at, row_version FROM users WHERE global_id IS NOT NULL
    ''').get();
    final users = <Map<String, Object?>>[];
    for (final row in rows) {
      final fields = row.data;
      final id = fields['id'] as int;
      final globalId = fields['global_id'] as String;
      final hash = settings[_settingKey(globalId)] ?? '';
      final permissions = await db.getUserPermissionCodes(id);
      final allowed = await db.userHasPermission(id, PermissionCodes.mobileAdminAccess) &&
          await db.userHasPermission(id, PermissionCodes.dashboardAccess);
      final active = fields['is_active'] == 1 || fields['is_active'] == true;
      final locked = fields['is_locked'] == 1 || fields['is_locked'] == true;
      users.add({
        'globalId': globalId,
        'username': fields['username'] as String,
        'displayName': fields['display_name'] as String,
        'mobileEnabled': hash.isNotEmpty && allowed && active && !locked && fields['deleted_at'] == null,
        if (hash.isNotEmpty) 'mobilePasswordHash': hash,
        'permissions': permissions,
        'branchScope': await db.getUserAccessibleBranchIds(id),
        'require2fa': false,
        'version': fields['row_version'] as int,
      });
    }
    return users;
  }

  Future<void> push(CloudLinkApi api) async {
    final users = await buildUsers();
    for (var start = 0; start < users.length; start += 1000) {
      await api.pushAdminUsers(users.skip(start).take(1000).toList());
    }
  }
}
