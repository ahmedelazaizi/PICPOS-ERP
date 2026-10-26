import 'package:flutter/material.dart';
import 'package:picpos_device/picpos_device.dart';
import 'package:picpos_ui/picpos_ui.dart';

import 'app.dart';
import 'session/pos_session.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final session = PosSession(KeystoreSecretStore());
  await session.restore();
  runApp(PicPosPosApp(settings: PicPosAppSettings(), session: session));
}
