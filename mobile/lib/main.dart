import 'package:flutter/material.dart';

import 'app.dart';
import 'data/cloud_api.dart';
import 'data/sqflite_store.dart';
import 'state/app_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final controller = AppController(store: await SqfliteLocalStore.open(), api: HttpCloudApi());
  await controller.init();
  runApp(PicposVanApp(controller: controller));
}
