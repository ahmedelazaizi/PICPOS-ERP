import 'package:flutter/material.dart';

import 'app.dart';
import 'data/cloud_api.dart';
import 'data/db_key.dart';
import 'data/sqflite_store.dart';
import 'state/app_controller.dart';
import 'sync/sync_scheduler.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final key = await DatabaseKey(KeystoreSecretStore()).obtain();
  final controller = AppController(store: await SqfliteLocalStore.open(password: key), api: HttpCloudApi());
  await controller.init();
  final scheduler = SyncScheduler(
    sync: controller.syncNow,
    connectivity: PlusConnectivity(),
    onStatus: controller.setAutoSyncStatus,
  );
  BackgroundSync(controller, scheduler);
  // Coming back to the foreground pushes/pulls right away.
  AppLifecycleListener(onResume: scheduler.trigger);
  runApp(PicposVanApp(controller: controller));
}
