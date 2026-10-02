import 'package:flutter/material.dart';

import 'app.dart';
import 'data/cloud_api.dart';
import 'data/db_key.dart';
import 'data/sqflite_store.dart';
import 'printing/print_service.dart';
import 'printing/printer_transport.dart';
import 'state/app_controller.dart';
import 'sync/sync_scheduler.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final key = await DatabaseKey(KeystoreSecretStore()).obtain();
  final controller = AppController(store: await SqfliteLocalStore.open(password: key), api: HttpCloudApi());
  await controller.init();
  // Bluetooth ESC/POS printing (I-4): print-on-save runs in the background
  // and queues on failure — it never blocks a sale.
  final printing = PrintService(controller: controller, transport: BluetoothThermalTransport());
  await printing.init();
  printing.attach();
  final scheduler = SyncScheduler(
    sync: controller.syncNow,
    connectivity: PlusConnectivity(),
    onStatus: controller.setAutoSyncStatus,
  );
  BackgroundSync(controller, scheduler);
  // Coming back to the foreground pushes/pulls right away.
  AppLifecycleListener(onResume: scheduler.trigger);
  runApp(PicposVanApp(controller: controller, printService: printing));
}
