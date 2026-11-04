// Integration review 2026-11-04, round 2 — INT-09: CFD settings at start-up.
//
// Before: `CfdService.loadSettings` ran only from the CFD settings cards, so
// after a restart the network display (SSE) used the DEFAULT display config —
// fields the owner had hidden came back — and an enabled serial/USB/HDMI
// display stayed disconnected until someone opened the settings screen.
// After: `restoreAtStartup` (called by `initPlatform`) always loads the saved
// settings; it re-connects the saved transport only when the owner opted in
// (`cfd_auto_connect_on_startup`, OFF by default) because HDMI launches a
// browser window and serial/USB opens a COM port. The wiring itself is
// checked by test/structural/cfd_startup_restore_wired_test.dart.
//
// Only the `network` transport is connected here: it opens nothing (it marks
// itself connected and serves SSE through the API server).
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/services/cfd/cfd_network_transport.dart';
import 'package:picpos_erp/services/cfd/cfd_transport.dart';
import 'package:picpos_erp/services/cfd_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final cfd = CfdService.instance;

  Future<void> prefs(Map<String, Object> values) async {
    await cfd.disconnectTransport();
    SharedPreferences.setMockInitialValues(values);
  }

  final hiddenCustomer = jsonEncode(
    const CfdDisplayConfig(showCustomerName: false, showTax: false).toJson(),
  );

  test('the saved display config is in force after start-up, without opening '
      'the settings screen; nothing connects by default', () async {
    await prefs({
      'cfd_enabled': true,
      'cfd_connection_type': 'network',
      'cfd_display_config': hiddenCustomer,
    });
    final connected = await cfd.restoreAtStartup();
    expect(cfd.displayConfig.showCustomerName, isFalse);
    expect(cfd.displayConfig.showTax, isFalse);
    expect(cfd.enabled, isTrue);
    expect(cfd.autoConnectOnStartup, isFalse, reason: 'opt-in, off by default');
    expect(connected, isFalse);
    expect(cfd.activeTransport, isNull,
        reason: 'no transport may open on its own unless the owner opted in');
  });

  test('opted in and enabled: the saved transport is re-connected', () async {
    await prefs({
      'cfd_enabled': true,
      'cfd_connection_type': 'network',
      'cfd_auto_connect_on_startup': true,
    });
    expect(await cfd.restoreAtStartup(), isTrue);
    expect(cfd.activeTransport, isA<CfdNetworkTransport>());
    expect(cfd.isConnected, isTrue);
  });

  test('opted in but the display is disabled: nothing connects', () async {
    await prefs({
      'cfd_enabled': false,
      'cfd_connection_type': 'network',
      'cfd_auto_connect_on_startup': true,
    });
    expect(await cfd.restoreAtStartup(), isFalse);
    expect(cfd.activeTransport, isNull);
  });

  test('the switch persists the opt-in', () async {
    await prefs({});
    await cfd.setAutoConnectOnStartup(true);
    final p = await SharedPreferences.getInstance();
    expect(p.getBool('cfd_auto_connect_on_startup'), isTrue);
    await cfd.setAutoConnectOnStartup(false);
    expect(p.getBool('cfd_auto_connect_on_startup'), isFalse);
  });
}
