import 'dart:ui' show DartPluginRegistrant;

import 'package:flutter/widgets.dart';
import 'package:workmanager/workmanager.dart';

import '../data/cloud_api.dart';
import '../data/db_key.dart';
import '../data/sqflite_store.dart';
import '../state/app_controller.dart';

/// Owner decision K-2 — sync while the app is closed: an Android WorkManager
/// periodic task (every 15 min, only with a network connection, exponential
/// backoff on failure) runs the same outbox push + pull as the app, on the
/// SQLCipher database whose key comes from the Android Keystore.
///
/// Never double-posts: documents keep their `globalId` and the cloud replays
/// a known one as `duplicate` (ARCHITECTURE-I §5).
const kBackgroundSyncTask = 'picpos.van.sync';

/// No pull more often than this when nothing waits in the outbox.
const kIdlePullInterval = Duration(minutes: 15);

/// Registers the periodic task (idempotent: `keep` an existing one).
Future<void> scheduleBackgroundSync() async {
  await Workmanager().initialize(backgroundSyncDispatcher);
  await Workmanager().registerPeriodicTask(
    kBackgroundSyncTask,
    kBackgroundSyncTask,
    frequency: kIdlePullInterval,
    constraints: Constraints(networkType: NetworkType.connected),
    backoffPolicy: BackoffPolicy.exponential,
    backoffPolicyDelay: const Duration(minutes: 1),
    existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
  );
}

/// WorkManager entry point (separate background isolate).
@pragma('vm:entry-point')
void backgroundSyncDispatcher() {
  Workmanager().executeTask((task, _) async {
    WidgetsFlutterBinding.ensureInitialized();
    DartPluginRegistrant.ensureInitialized();
    return runBackgroundSync(openDeviceController);
  });
}

/// The app's controller over the encrypted device database.
Future<AppController> openDeviceController() async {
  final key = await DatabaseKey(KeystoreSecretStore()).obtain();
  final c = AppController(store: await SqfliteLocalStore.open(password: key), api: HttpCloudApi());
  await c.init();
  return c;
}

/// One background run. Returns false only for a failure worth a retry
/// (WorkManager then backs off exponentially); nothing to do, no pairing or
/// an expired session (needs the rep's PIN) are successes.
Future<bool> runBackgroundSync(
  Future<AppController> Function() open, {
  DateTime Function()? clock,
  Duration idlePullInterval = kIdlePullInterval,
}) async {
  final c = await open();
  if (!c.isPaired || c.session == null) return true;
  final now = (clock ?? DateTime.now)();
  final pending = await c.pendingDocs();
  final last = c.lastSync;
  // Battery: an empty outbox only pulls, and not more than every 15 min
  // (also skips right after the open app synced).
  if (pending.isEmpty && last != null && now.difference(last) < idlePullInterval) return true;
  final ok = await c.syncNow();
  if (!ok && (c.lastSyncError == 'sessionRequired' || !c.isPaired)) return true;
  return ok;
}
