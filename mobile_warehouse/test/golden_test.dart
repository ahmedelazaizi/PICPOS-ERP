// Golden screenshots of the signed-in home: AR/EN x light/dark x
// phone/handheld/tablet (plan W0: 12 images). Platform-sensitive: generated on
// the Windows dev machine; regenerate deliberately with
// `flutter test --update-goldens test/golden_test.dart`.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_api_client/picpos_api_client.dart';
import 'package:picpos_device/picpos_device.dart';
import 'package:picpos_ui/picpos_ui.dart';
import 'package:picpos_warehouse/app.dart';
import 'package:picpos_warehouse/store/wh_local_store.dart';

import 'fakes.dart';
import 'support.dart';

void main() {
  setUpAll(loadTestFonts);

  for (final lang in ['ar', 'en']) {
    for (final mode in [ThemeMode.light, ThemeMode.dark]) {
      for (final MapEntry(key: sizeName, value: size) in kSizes.entries) {
        testWidgets('golden home $lang ${mode.name} $sizeName', (tester) async {
          setSurface(tester, size);
          final desktop = FakeDesktop()..supervisor = true;
          final session = desktop.session(MemorySecretStore());
          await session.restore();
          await session.pair(PairingPayload.parse(desktop.qr()));
          await session.login('ali', 'pw');
          await tester.pumpWidget(PicPosWarehouseApp(
            settings: PicPosAppSettings(locale: Locale(lang), themeMode: mode),
            session: session,
            store: WhLocalStore.memory(),
            lockEnabled: false,
          ));
          await tester.pumpAndSettle();
          await expectLater(
            find.byType(MaterialApp),
            matchesGoldenFile('goldens/home_${lang}_${mode.name}_$sizeName.png'),
          );
        });
      }
    }
  }
}
