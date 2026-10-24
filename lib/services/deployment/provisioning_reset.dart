import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/database/database.dart';
import '../mirror_state.dart';
import '../server_proxy.dart';
import 'settings_keys.dart';

/// Device-provisioning keys cleared by [resetProvisioning] (DB `settings`).
/// Business data (products, invoices, users…) is NOT touched.
const List<String> kProvisioningDbKeys = <String>[
  ...DeploymentSettingsKeys.ownedKeys,
  'deployment_mode',
  'setup_completed',
  'setup_in_progress',
  'setup_draft_v2',
  'setup_progress_v2',
  'mirror_cache_integrity_v1_applied',
];

/// Device-local SharedPreferences keys cleared by [resetProvisioning].
const List<String> kProvisioningPrefKeys = <String>[
  'network_server_address',
  'network_server_port',
  'network_api_token',
  'client_branch_id',
];

/// A0 (ADP-009): the single way out of the "inconsistent provisioning" Fatal
/// screen. Forgets the mode, the pairing and the first-run flags so the next
/// launch starts the first-run setup from scratch — no developer options.
///
/// Unlike `NetworkService.resetToStandalone` this never deletes
/// `pg_config.json` (a server device must keep its database connection).
/// The caller must ask the user to restart the app afterwards.
Future<void> resetProvisioning(AppDatabase db) async {
  for (final key in kProvisioningDbKeys) {
    await db.customStatement('DELETE FROM settings WHERE key = ?', [key]);
  }
  final prefs = await SharedPreferences.getInstance();
  for (final key in kProvisioningPrefKeys) {
    await prefs.remove(key);
  }
  // network_mode lives in prefs too (legacy copy): an explicit standalone
  // prevents a stale `mirror`/`client` from being re-read at the next boot.
  await prefs.setString(DeploymentSettingsKeys.networkMode, 'standalone');
  await MirrorState.instance.clear();
  try {
    ServerProxy.instance.setApiToken('');
  } catch (e) {
    debugPrint('[ProvisioningReset] token clear: $e');
  }
  debugPrint('[ProvisioningReset] provisioning cleared — restart required');
}
