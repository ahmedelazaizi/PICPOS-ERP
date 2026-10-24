// Local PIN gate: setup on first sign-in, lock after idle / background, wrong
// PIN refused.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_api_client/picpos_api_client.dart';
import 'package:picpos_device/picpos_device.dart';
import 'package:picpos_ui/picpos_ui.dart';
import 'package:picpos_warehouse/session/app_lock.dart';

import 'fakes.dart';
import 'support.dart';

void main() {
  setUpAll(loadTestFonts);

  testWidgets('first run asks for a PIN, then the content; idle timeout locks; wrong PIN refused', (tester) async {
    setSurface(tester, kPhone);
    final desktop = FakeDesktop();
    final session = desktop.session(MemorySecretStore());
    await session.restore();
    await session.pair(PairingPayload.parse(desktop.qr()));
    await tester.pumpWidget(PicPosMaterialApp(
      settings: PicPosAppSettings(locale: const Locale('en')),
      title: (_) => 't',
      home: AppLockGate(
        session: session,
        idleDuration: const Duration(seconds: 30),
        child: const Scaffold(body: Text('SECRET CONTENT')),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Create an app lock PIN'), findsOneWidget);
    expect(find.text('SECRET CONTENT'), findsNothing);

    await tester.enterText(find.byKey(const Key('wh.appPinSetup')), '1234');
    await tester.enterText(find.byKey(const Key('wh.appPinConfirm')), '9999');
    await tester.tap(find.byKey(const Key('wh.appPinSave')));
    await tester.pumpAndSettle();
    expect(find.text('The PINs do not match.'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('wh.appPinConfirm')), '1234');
    await tester.tap(find.byKey(const Key('wh.appPinSave')));
    await tester.pumpAndSettle();
    expect(find.text('SECRET CONTENT'), findsOneWidget);

    await tester.pump(const Duration(seconds: 31));
    await tester.pumpAndSettle();
    expect(find.text('App locked'), findsOneWidget);
    expect(find.text('SECRET CONTENT'), findsNothing);

    await tester.enterText(find.byKey(const Key('wh.appPinUnlock')), '0000');
    await tester.tap(find.byKey(const Key('wh.appPinUnlockSubmit')));
    await tester.pumpAndSettle();
    expect(find.text('Incorrect PIN.'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('wh.appPinUnlock')), '1234');
    await tester.tap(find.byKey(const Key('wh.appPinUnlockSubmit')));
    await tester.pumpAndSettle();
    expect(find.text('SECRET CONTENT'), findsOneWidget);
  });
}
