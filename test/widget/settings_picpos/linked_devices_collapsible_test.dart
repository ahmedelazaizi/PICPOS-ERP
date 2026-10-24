import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/data/providers/auth_providers.dart';
import 'package:picpos_erp/presentation/settings_picpos/screens/linked_devices_section.dart';
import 'package:picpos_erp/services/api/lan_paired_devices_provider.dart';
import 'package:picpos_erp/services/api/lan_pairing_service.dart';
import 'package:picpos_erp/services/cloud_sync/cloud_link_controller.dart';

class _LanFake implements LanPairingService {
  @override
  Future<List<LanPairingDevice>> listDevices() async => [];
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _CloudFake implements CloudLinkController {
  _CloudFake({this.extraDevices = const []});
  final List<CloudRepDeviceView> extraDevices;
  final revoked = <String>[];
  @override
  Future<CloudLinkView> load({bool includeSecret = true}) async =>
      const CloudLinkView(enabled: true, url: 'https://example.test', linkId: 'link',
          hasSecret: true, intervalMinutes: 5, posted: 0, conflicts: []);
  @override
  Future<List<CloudRepDeviceView>?> listRepDevices() async => [
    CloudRepDeviceView(deviceId: 'rep-1', employeeName: 'أحمد',
        deviceName: 'Galaxy', lastSeenAt: DateTime(2026, 1, 2), revoked: false),
    CloudRepDeviceView(deviceId: 'rep-2', employeeName: 'سليم',
        lastSeenAt: DateTime(2026, 1, 1), revoked: true),
    ...extraDevices,
  ];
  @override
  Future<void> revokeRepDevice(String deviceId) async => revoked.add(deviceId);
  @override
  Future<List<({String globalId, String name})>> adminUsers() async => [];
  @override
  Future<List<Map<String, dynamic>>> listAdminDevices() async => [
    {'deviceId': 'admin-1', 'deviceName': 'Admin phone', 'revoked': false},
  ];
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('rep and admin phones start collapsed and rep revoke reaches controller',
      (tester) async {
    tester.view.physicalSize = const Size(1366, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final cloud = _CloudFake();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        currentUserPermissionsProvider.overrideWith((ref) async => ['system_admin']),
        cloudLinkControllerProvider.overrideWithValue(cloud),
        lanPairedDevicesServiceProvider.overrideWithValue(_LanFake()),
      ],
      child: MaterialApp(home: Scaffold(body: SingleChildScrollView(
        child: LinkedDevicesSection(onOpenNetworkMode: () async {}),
      ))),
    ));
    await tester.pumpAndSettle();
    for (final title in const [
      'الاتصال بالسحابة', 'الشبكة المحلية', 'التطبيقات',
      'PicPos Van — تطبيق المندوب', 'PicPos إدارة — تطبيق الإدارة',
      'PicPos كاشير', 'PicPos مخازن',
    ]) {
      expect(find.text(title), findsOneWidget);
    }
    expect(find.text('قريباً'), findsOneWidget); // cashier only; warehouse has its pairing card
    expect(find.text('هواتف المناديب المقترنة (2)'), findsOneWidget);
    expect(find.text('نشط: 1 · ملغى: 1'), findsOneWidget);
    expect(find.text('هواتف الإدارة المقترنة (1)'), findsOneWidget);
    expect(find.byKey(const Key('ld_cloud_rep-1')), findsNothing);
    expect(find.byKey(const Key('ld_admin_revoke_admin-1')), findsNothing);

    await tester.ensureVisible(find.byKey(const Key('ld_rep_devices')));
    await tester.tap(find.byKey(const Key('ld_rep_devices')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('ld_cloud_rep-1')), findsOneWidget);
    expect(find.byKey(const Key('ld_cloud_rep-2')), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('ld_cloud_revoke_rep-1')));
    await tester.tap(find.byKey(const Key('ld_cloud_revoke_rep-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(ElevatedButton).last);
    await tester.pumpAndSettle();
    expect(cloud.revoked, ['rep-1']);
    await tester.pump(const Duration(seconds: 6));
  });

  testWidgets('more than eight rep phones open searchable full list',
      (tester) async {
    tester.view.physicalSize = const Size(1366, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final cloud = _CloudFake(extraDevices: [
      for (var i = 0; i < 8; i++)
        CloudRepDeviceView(deviceId: 'extra-$i', employeeName: 'مندوب $i',
            revoked: false),
    ]);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        currentUserPermissionsProvider.overrideWith((ref) async => ['system_admin']),
        cloudLinkControllerProvider.overrideWithValue(cloud),
        lanPairedDevicesServiceProvider.overrideWithValue(_LanFake()),
      ],
      child: MaterialApp(home: Scaffold(body: SingleChildScrollView(
        child: LinkedDevicesSection(onOpenNetworkMode: () async {}),
      ))),
    ));
    await tester.pumpAndSettle();
    expect(find.text('هواتف المناديب المقترنة (10)'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('ld_rep_devices')));
    await tester.tap(find.byKey(const Key('ld_rep_devices')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('ld_rep_show_all')));
    await tester.tap(find.byKey(const Key('ld_rep_show_all')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'Galaxy');
    await tester.pumpAndSettle();
    expect(find.text('أحمد · Galaxy'), findsOneWidget);
    expect(find.text('سليم'), findsNothing);
  });
}
