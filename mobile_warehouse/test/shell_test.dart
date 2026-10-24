// App screens: AR/EN x light/dark x phone/handheld/tablet, no overflow, right
// direction and brightness; onboarding -> login -> role-aware home -> lookup;
// honest "not available" states; settings; unpair.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_api_client/picpos_api_client.dart';
import 'package:picpos_device/picpos_device.dart';
import 'package:picpos_ui/picpos_ui.dart';
import 'package:picpos_warehouse/app.dart';
import 'package:picpos_warehouse/l10n/strings.dart';
import 'package:picpos_warehouse/screens/login_page.dart';
import 'package:picpos_warehouse/screens/onboarding_page.dart';
import 'package:picpos_warehouse/session/wh_session.dart';
import 'package:picpos_warehouse/shell/warehouse_shell.dart';
import 'package:picpos_warehouse/store/wh_local_store.dart';

import 'fakes.dart';
import 'support.dart';

Future<WhSession> _signedIn(FakeDesktop d, {MemorySecretStore? secrets}) async {
  final s = d.session(secrets ?? MemorySecretStore());
  await s.restore();
  await s.pair(PairingPayload.parse(d.qr()));
  await s.login('ali', 'pw');
  return s;
}

void main() {
  setUpAll(loadTestFonts);

  Widget app(WhSession s, PicPosAppSettings settings, {int dest = 0}) => PicPosWarehouseApp(
        key: UniqueKey(),
        settings: settings,
        session: s,
        store: WhLocalStore.memory(),
        initialDestination: dest,
        lockEnabled: false,
      );

  group('AR/EN x light/dark x phone/handheld/tablet: every destination, no overflow', () {
    for (final lang in ['ar', 'en']) {
      for (final mode in [ThemeMode.light, ThemeMode.dark]) {
        for (final MapEntry(key: sizeName, value: size) in kSizes.entries) {
          testWidgets('$lang ${mode.name} $sizeName', (tester) async {
            setSurface(tester, size);
            final desktop = FakeDesktop();
            final settings = PicPosAppSettings(locale: Locale(lang), themeMode: mode);

            final fresh = desktop.session(MemorySecretStore());
            await fresh.restore();
            await tester.pumpWidget(app(fresh, settings));
            await tester.pumpAndSettle();
            expect(find.byType(OnboardingPage), findsOneWidget);
            expect(tester.takeException(), isNull);

            final signedIn = await _signedIn(desktop);
            for (var i = 0; i < WarehouseShell.destinationCount; i++) {
              await tester.pumpWidget(app(signedIn, settings, dest: i));
              await tester.pumpAndSettle();
              expect(tester.takeException(), isNull, reason: 'destination $i');
              final ctx = tester.element(find.byType(WarehouseShell));
              expect(Directionality.of(ctx), lang == 'ar' ? TextDirection.rtl : TextDirection.ltr);
              expect(Theme.of(ctx).brightness, mode == ThemeMode.dark ? Brightness.dark : Brightness.light);
              if (size == kTablet) {
                expect(find.byType(NavigationRail), findsOneWidget);
              } else {
                expect(find.byType(NavigationBar), findsOneWidget);
                expect(find.byType(NavigationDestination), findsNWidgets(5));
              }
            }

            final loggedOut = desktop.session(MemorySecretStore());
            await loggedOut.restore();
            await loggedOut.pair(PairingPayload.parse(desktop.qr()));
            await tester.pumpWidget(app(loggedOut, settings));
            await tester.pumpAndSettle();
            expect(find.byType(LoginPage), findsOneWidget);
            expect(tester.takeException(), isNull);
          });
        }
      }
    }
  });

  testWidgets('home: clerk sees no transfer/approval capabilities; supervisor does; unbuilt features say so', (tester) async {
    setSurface(tester, kPhone);
    final desktop = FakeDesktop();
    final settings = PicPosAppSettings(locale: const Locale('en'));
    await tester.pumpWidget(app(await _signedIn(desktop), settings));
    await tester.pumpAndSettle();
    expect(find.text('Hello Ali Hassan'), findsOneWidget);
    expect(find.text('Main store'), findsOneWidget);
    expect(find.text('Warehouse clerk / keeper'), findsOneWidget);
    expect(find.text('Transfer between warehouses'), findsNothing);
    expect(find.text('Not available yet'), findsWidgets, reason: 'receive/count are not built: the UI must say so');

    desktop.supervisor = true;
    await tester.pumpWidget(app(await _signedIn(desktop), settings));
    await tester.pumpAndSettle();
    expect(find.text('Supervisor / stock manager'), findsOneWidget);
    expect(find.text('Transfer between warehouses'), findsOneWidget);
    expect(find.text('Approve counts and variances'), findsOneWidget);
  });

  testWidgets('home: a branch with no allowed warehouse says so', (tester) async {
    setSurface(tester, kPhone);
    final desktop = FakeDesktop()..warehouses = const [];
    await tester.pumpWidget(app(await _signedIn(desktop), PicPosAppSettings(locale: const Locale('en'))));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('home.noWarehouses')), findsOneWidget);
  });

  testWidgets('documents and outbox are honest placeholders (nothing simulated)', (tester) async {
    setSurface(tester, kPhone);
    final desktop = FakeDesktop();
    final settings = PicPosAppSettings(locale: const Locale('en'));
    await tester.pumpWidget(app(await _signedIn(desktop), settings, dest: 2));
    await tester.pumpAndSettle();
    expect(find.textContaining('not implemented in this version'), findsOneWidget);
    await tester.pumpWidget(app(await _signedIn(desktop), settings, dest: 3));
    await tester.pumpAndSettle();
    expect(find.text('Nothing is waiting to be sent.'), findsOneWidget);
    expect(find.textContaining('not enabled yet'), findsOneWidget);
  });

  testWidgets('lookup: barcode -> stock in scope; unknown -> empty message; unreachable -> error', (tester) async {
    setSurface(tester, kPhone);
    final desktop = FakeDesktop();
    await tester.pumpWidget(app(await _signedIn(desktop), PicPosAppSettings(locale: const Locale('en')), dest: 1));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('lookup.field')), '6221234567890');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    expect(find.text('Milk 1L'), findsOneWidget);
    expect(find.text('12.0'), findsOneWidget);
    expect(find.text('Stock in Main store'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('lookup.field')), '000000000');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    expect(find.text('No item matches this barcode or name.'), findsOneWidget);

    desktop.transports.last.failWith = ApiError.network('offline');
    await tester.enterText(find.byKey(const Key('lookup.field')), '6221234567890');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('lookup.error')), findsOneWidget);
    expect(find.text('Milk 1L'), findsNothing, reason: 'no stale numbers shown as if live');
  });

  testWidgets('onboarding: QR scan pairs; a TLS-less / wrong-kind / bad QR shows the reason', (tester) async {
    setSurface(tester, kPhone);
    final desktop = FakeDesktop();
    final secrets = MemorySecretStore();
    final s = desktop.session(secrets);
    await s.restore();
    var qr = desktop.qr(kind: 'pos');
    await tester.pumpWidget(PicPosMaterialApp(
      settings: PicPosAppSettings(locale: const Locale('en')),
      title: (_) => 't',
      home: OnboardingPage(session: s, scanner: (c, {bool qr = true}) async => qrHolder.value),
    ));
    qrHolder.value = qr;
    await tester.tap(find.byKey(const Key('onboarding.scan')));
    await tester.pumpAndSettle();
    expect(find.text('This code is not for the Warehouse app.'), findsOneWidget);
    qrHolder.value = 'garbage';
    await tester.tap(find.byKey(const Key('onboarding.scan')));
    await tester.pumpAndSettle();
    expect(find.text('The text is not a valid pairing code.'), findsOneWidget);
    qrHolder.value = desktop.qr();
    await tester.tap(find.byKey(const Key('onboarding.scan')));
    await tester.pumpAndSettle();
    expect(s.paired, isTrue);
  });

  testWidgets('onboarding manual entry needs a valid fingerprint', (tester) async {
    setSurface(tester, kPhone);
    final desktop = FakeDesktop();
    final s = desktop.session(MemorySecretStore());
    await s.restore();
    await tester.pumpWidget(PicPosMaterialApp(
      settings: PicPosAppSettings(locale: const Locale('en')),
      title: (_) => 't',
      home: OnboardingPage(session: s),
    ));
    await tester.enterText(find.byKey(const Key('onboarding.address')), '192.168.1.5:8443');
    await tester.enterText(find.byKey(const Key('onboarding.code')), 'pair1234');
    await tester.ensureVisible(find.byKey(const Key('onboarding.pair')));
    await tester.tap(find.byKey(const Key('onboarding.pair')));
    await tester.pumpAndSettle();
    expect(find.text('The server does not use TLS, so pairing was refused.'), findsOneWidget);
    expect(s.paired, isFalse);
    await tester.enterText(find.byKey(const Key('onboarding.fingerprint')), kFingerprint);
    await tester.tap(find.byKey(const Key('onboarding.pair')));
    await tester.pumpAndSettle();
    expect(s.paired, isTrue);
    expect(desktop.lastBase, Uri.parse('https://192.168.1.5:8443'));
  });

  testWidgets('login: wrong password shows an error; settings: language/theme, unpair needs confirmation', (tester) async {
    setSurface(tester, kPhone);
    final desktop = FakeDesktop();
    final s = desktop.session(MemorySecretStore());
    await s.restore();
    await s.pair(PairingPayload.parse(desktop.qr()));
    final settings = PicPosAppSettings(locale: const Locale('en'));
    await tester.pumpWidget(app(s, settings));
    await tester.pumpAndSettle();
    desktop.validPassword = false;
    await tester.enterText(find.byKey(const Key('login.user')), 'ali');
    await tester.enterText(find.byKey(const Key('login.password')), 'bad');
    await tester.tap(find.byKey(const Key('login.submit')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('login.error')), findsOneWidget);
    desktop.validPassword = true;
    await tester.tap(find.byKey(const Key('login.submit')));
    await tester.pumpAndSettle();
    expect(s.loggedIn, isTrue);

    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('العربية'));
    await tester.tap(find.text('Dark'));
    await tester.pumpAndSettle();
    expect((settings.locale, settings.themeMode), (const Locale('ar'), ThemeMode.dark));

    await tester.ensureVisible(find.byKey(const Key('settings.unpair')));
    await tester.tap(find.byKey(const Key('settings.unpair')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('unpair.cancel')));
    await tester.pumpAndSettle();
    expect(s.paired, isTrue);
    await tester.tap(find.byKey(const Key('settings.unpair')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('unpair.confirm')));
    await tester.pumpAndSettle();
    expect(s.paired, isFalse);
    expect(find.byType(OnboardingPage), findsOneWidget);
  });

  test('every string has Arabic and English', () {
    expect(S.table.coverageProblems(), isEmpty);
  });
}

final qrHolder = ValueNotifier<String?>(null);
