// «أمان الخادم» في قسم الأجهزة المرتبطة: تدوير مفاتيح الخادم (تأكيد مزدوج)
// وإيقاف قبول رموز الطاولات القديمة. المحاكيات تحلّ محلّ ServerSecrets
// والقاعدة، فيُقاس ما تفعله الواجهة لا ما تفعله الخدمات.
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/core/theme/app_theme.dart';
import 'package:picpos_erp/data/providers/auth_providers.dart';
import 'package:picpos_erp/presentation/settings_picpos/screens/linked_devices_section.dart';
import 'package:picpos_erp/presentation/settings_picpos/widgets/database_encryption_block.dart';
import 'package:picpos_erp/presentation/settings_picpos/widgets/server_security_block.dart';
import 'package:picpos_erp/services/api/lan_paired_devices_provider.dart';
import 'package:picpos_erp/services/api/lan_pairing_service.dart';
import 'package:picpos_erp/services/cloud_sync/cloud_link_controller.dart';

class _FakeLan implements LanPairingService {
  @override
  Future<List<LanPairingDevice>> listDevices() async => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeCloud implements CloudLinkController {
  @override
  Future<CloudLinkView> load({bool includeSecret = true}) async =>
      const CloudLinkView(
        enabled: false,
        url: '',
        linkId: '',
        hasSecret: false,
        intervalMinutes: 5,
        lastSyncAt: null,
        posted: 0,
        conflicts: [],
      );

  @override
  Future<List<CloudRepDeviceView>?> listRepDevices() async => null;

  @override
  Future<List<({String globalId, String name})>> adminUsers() async => [];

  @override
  Future<List<Map<String, dynamic>>> listAdminDevices() async => [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Calls {
  int rotate = 0;
  int disable = 0;
  bool legacyAccepted = true;
  bool rotateFails = false;
  final audits = <String>[];

  ServerSecurityActions get actions => ServerSecurityActions(
        rotateSessionSecret: () async {
          if (rotateFails) throw StateError('boom');
          rotate++;
        },
        isLegacyAccepted: () async => legacyAccepted,
        disableLegacy: () async {
          disable++;
          legacyAccepted = false;
        },
        audit: (action, description) async => audits.add(action),
      );
}

void main() {
  late _Calls calls;

  setUp(() => calls = _Calls());

  Future<void> pump(WidgetTester tester,
      {bool admin = true, Size size = const Size(1366, 768)}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        currentUserPermissionsProvider.overrideWith(
            (ref) async => admin ? ['system_admin'] : ['pos_access']),
        lanPairedDevicesServiceProvider.overrideWithValue(_FakeLan()),
        cloudLinkControllerProvider.overrideWithValue(_FakeCloud()),
        serverSecurityActionsProvider.overrideWithValue(calls.actions),
        dbEncryptionSupportedProvider.overrideWithValue(false),
      ],
      child: MaterialApp(
        theme: AppTheme.lightTheme,
        locale: const Locale('ar'),
        supportedLocales: const [Locale('ar'), Locale('en')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: LinkedDevicesSection(onOpenNetworkMode: () async {}),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  Finder rotateButton() => find.descendant(
      of: find.byKey(const Key('ld_rotate_row')),
      matching: find.byType(OutlinedButton));
  Finder legacyButton() => find.descendant(
      of: find.byKey(const Key('ld_legacy_row')),
      matching: find.byType(OutlinedButton));

  Future<void> tapRotate(WidgetTester tester) async {
    await tester.ensureVisible(rotateButton());
    await tester.tap(rotateButton());
    await tester.pumpAndSettle();
  }

  testWidgets('admin sees both actions and the current legacy status',
      (tester) async {
    await pump(tester);
    expect(find.byKey(const Key('ld_server_security')), findsOneWidget);
    expect(rotateButton(), findsOneWidget);
    expect(legacyButton(), findsOneWidget);
    expect(
        find.descendant(
            of: find.byKey(const Key('ld_legacy_status')),
            matching: find.text('مقبولة')),
        findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('non-admin sees neither action', (tester) async {
    await pump(tester, admin: false);
    expect(find.byKey(const Key('ld_server_security')), findsNothing);
    expect(find.byKey(const Key('ld_rotate_row')), findsNothing);
    expect(find.byKey(const Key('ld_legacy_row')), findsNothing);
  });

  testWidgets('rotate: confirm stays disabled until the word is typed',
      (tester) async {
    await pump(tester);
    await tapRotate(tester);
    expect(find.textContaining('تحذير: سيُبطل هذا كل جلسات'), findsOneWidget);

    final confirm = find.widgetWithText(ElevatedButton, 'تدوير المفاتيح');
    expect(tester.widget<ElevatedButton>(confirm).onPressed, isNull);

    await tester.enterText(
        find.byKey(const Key('ld_rotate_confirm_field')), 'خطأ');
    await tester.pump();
    expect(tester.widget<ElevatedButton>(confirm).onPressed, isNull);
    expect(calls.rotate, 0);

    await tester.enterText(
        find.byKey(const Key('ld_rotate_confirm_field')), 'تدوير');
    await tester.pump();
    expect(tester.widget<ElevatedButton>(confirm).onPressed, isNotNull);
    expect(calls.rotate, 0, reason: 'typing alone must not rotate');
  });

  testWidgets('rotate: cancelling the dialog never calls the service',
      (tester) async {
    await pump(tester);
    await tapRotate(tester);
    await tester.tap(find.text('إلغاء').last);
    await tester.pumpAndSettle();
    expect(calls.rotate, 0);
    expect(calls.audits, isEmpty);
  });

  testWidgets('rotate: calls the service and audits after confirmation',
      (tester) async {
    await pump(tester);
    await tapRotate(tester);
    await tester.enterText(
        find.byKey(const Key('ld_rotate_confirm_field')), 'تدوير');
    await tester.pump();
    await tester.tap(find.widgetWithText(ElevatedButton, 'تدوير المفاتيح'));
    await tester.pumpAndSettle();
    expect(calls.rotate, 1);
    expect(calls.audits, ['rotate_server_secrets']);
    expect(find.text('تم تدوير مفاتيح الخادم — أُبطلت الجلسات'), findsOneWidget);
    await tester.pump(const Duration(seconds: 6)); // toast timer
  });

  testWidgets('rotate: failure is reported, not swallowed', (tester) async {
    calls.rotateFails = true;
    await pump(tester);
    await tapRotate(tester);
    await tester.enterText(
        find.byKey(const Key('ld_rotate_confirm_field')), 'تدوير');
    await tester.pump();
    await tester.tap(find.widgetWithText(ElevatedButton, 'تدوير المفاتيح'));
    await tester.pumpAndSettle();
    expect(calls.rotate, 0);
    expect(calls.audits, ['rotate_server_secrets_failed']);
    expect(find.textContaining('تعذّر تدوير مفاتيح الخادم'), findsOneWidget);
    await tester.pump(const Duration(seconds: 6));
  });

  testWidgets('legacy: cancel does nothing; confirm disables and flips status',
      (tester) async {
    await pump(tester);
    await tester.ensureVisible(legacyButton());
    await tester.tap(legacyButton());
    await tester.pumpAndSettle();
    expect(find.textContaining('ستتوقف رموز QR المطبوعة القديمة'),
        findsOneWidget);

    await tester.tap(find.text('إلغاء').last);
    await tester.pumpAndSettle();
    expect(calls.disable, 0);

    await tester.tap(legacyButton());
    await tester.pumpAndSettle();
    await tester.tap(find.byType(ElevatedButton).last);
    await tester.pumpAndSettle();
    expect(calls.disable, 1);
    expect(calls.audits, ['disable_legacy_table_qr']);
    expect(
        find.descendant(
            of: find.byKey(const Key('ld_legacy_status')),
            matching: find.text('موقوفة')),
        findsOneWidget);
    expect(legacyButton(), findsNothing,
        reason: 'nothing left to disable once codes are already stopped');
    await tester.pump(const Duration(seconds: 6));
  });

  testWidgets('legacy already disabled: shows state without the action',
      (tester) async {
    calls.legacyAccepted = false;
    await pump(tester);
    expect(
        find.descendant(
            of: find.byKey(const Key('ld_legacy_status')),
            matching: find.text('موقوفة')),
        findsOneWidget);
    expect(find.byKey(const Key('ld_legacy_row')), findsNothing);
  });
}
