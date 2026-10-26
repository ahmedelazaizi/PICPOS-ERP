import 'package:flutter/material.dart';
import 'package:picpos_device/picpos_device.dart';
import 'package:picpos_ui/picpos_ui.dart';

import 'app.dart';
import 'printing/label_printer.dart';
import 'session/wh_session.dart';
import 'store/wh_local_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final secrets = KeystoreSecretStore();
  final store = await WhLocalStore.open(secrets);
  final session = WhSession(secrets, onWipe: store.wipe);
  await session.restore();
  // Labels: Bluetooth SPP or network ESC/POS. Nothing is selected until the
  // user chooses a printer in Settings (until then the app says "no printer").
  final printService = PrintService(
    store: store.store,
    transports: [BluetoothThermalTransport(permissions: MethodChannelBluetoothPermissionGate()), NetworkPrinterTransport()],
  );
  await printService.init();
  runApp(PicPosWarehouseApp(
    settings: PicPosAppSettings(),
    session: session,
    store: store,
    printer: ServiceLabelPrinter(printService),
  ));
}
