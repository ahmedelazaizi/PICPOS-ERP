// SEC-006 settings UI: the owner sees who still uses the legacy shared key
// (device / user-agent / last seen / accepted vs refused) and can switch it
// off; the switch is enforced by the real service.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/presentation/widgets/settings/legacy_token_section.dart';
import 'package:picpos_erp/services/api/lan_pairing_service.dart';

import '../helpers/lan_host_harness.dart';

void main() {
  testWidgets('shows telemetry and the toggle really switches the key off',
      (tester) async {
    late LanHost host;
    await tester.runAsync(() async {
      host = await LanHost.start(legacyToken: true);
      LegacyTokenTelemetry.instance.reset();
      await host.pairing.recordLegacyDevice(
          deviceId: 'old-tablet', name: 'Old tablet', ip: '10.0.0.7');
      host.pairing.noteLegacyAttempt(
          deviceId: 'old-tablet',
          name: 'Old tablet',
          ip: '10.0.0.7',
          userAgent: 'Dalvik/2.1',
          refused: false);
    });
    addTearDown(() async => tester.runAsync(host.close));

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: LegacyTokenSection(service: host.pairing, actorUserId: 1),
        ),
      ),
    ));
    await tester.runAsync(() => Future<void>.delayed(
        const Duration(milliseconds: 300)));
    await tester.pump();

    expect(find.byKey(const Key('legacy_attempt_old-tablet')), findsOneWidget);
    expect(find.textContaining('Dalvik/2.1'), findsOneWidget);
    expect(find.byKey(const Key('legacy_token_warning')), findsOneWidget);

    await tester.tap(find.byKey(const Key('legacy_token_toggle')));
    await tester.runAsync(() => Future<void>.delayed(
        const Duration(milliseconds: 300)));
    await tester.pump();
    await tester.runAsync(() => Future<void>.delayed(
        const Duration(milliseconds: 500)));
    await tester.pump();

    final enabled =
        await tester.runAsync(() => host.pairing.legacyTokenEnabled());
    expect(enabled, isFalse);
    expect(find.byKey(const Key('legacy_token_warning')), findsNothing);
    await tester.pump(const Duration(seconds: 10)); // toast timers
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 10));
  });
}
