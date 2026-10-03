import 'package:flutter/material.dart';

import 'app.dart';
import 'data/cloud_api.dart';
import 'data/db_key.dart';
import 'data/sqflite_store.dart';
import 'geo/geo_capture.dart';
import 'printing/print_service.dart';
import 'printing/printer_transport.dart';
import 'state/app_controller.dart';
import 'sync/background_worker.dart';
import 'sync/sync_scheduler.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final key = await DatabaseKey(KeystoreSecretStore()).obtain();
  final controller = AppController(
    store: await SqfliteLocalStore.open(password: key),
    api: HttpCloudApi(),
    // K-3: GPS stamp on visits and documents (permission asked on the route).
    geo: GeoCapture(DeviceGeoProvider()),
  );
  await controller.init();
  // Bluetooth ESC/POS printing (I-4): print-on-save runs in the background
  // and queues on failure — it never blocks a sale.
  final printing = PrintService(controller: controller, transport: BluetoothThermalTransport());
  await printing.init();
  printing.attach();
  // K-2: while the app is open — on start, on every queued document, when
  // connectivity returns and on resume; the idle pull is every 15 min.
  final scheduler = SyncScheduler(
    sync: controller.syncNow,
    connectivity: PlusConnectivity(),
    onStatus: controller.setAutoSyncStatus,
    interval: kIdlePullInterval,
  );
  BackgroundSync(controller, scheduler);
  // Coming back to the foreground pushes/pulls right away.
  AppLifecycleListener(onResume: scheduler.trigger);
  // …and with the app closed: WorkManager whenever there is a network.
  try {
    await scheduleBackgroundSync();
  } catch (e) {
    debugPrint('background sync not scheduled: $e');
  }
  runApp(PicposVanApp(controller: controller, printService: printing));
}
