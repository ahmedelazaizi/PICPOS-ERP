// الإعدادات › الأمان › «الأجهزة المرتبطة» — شكوى المالك: «التطبيق ليس به
// ربط أجهزة خارجية في إعدادات المستخدمون والأمان».
//
// يُقاس هنا: القسمُ ظاهرٌ في PicPos تحت مجموعة «الأمان» بعد «المستخدمون
// والأمان»، والبحثُ بكلماتِ الربط يجده، وقائمةُ أجهزة الشبكة تُعرَض
// وإلغاءُ الربط يصل إلى الخدمة، وبطاقةُ السحابة بحالتَيها، والحارسُ، ولا
// فيضانَ في RTL/LTR × فاتح/داكن على 1366×768.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/core/i18n/tr.dart';
import 'package:ural_erp/core/theme/app_theme.dart';
import 'package:ural_erp/data/providers/providers.dart';
import 'package:ural_erp/domain/models/hr_employee_file.dart';
import 'package:ural_erp/presentation/hr_picpos/hr_picpos_providers.dart';
import 'package:ural_erp/presentation/settings_picpos/screens/linked_devices_section.dart';
import 'package:ural_erp/presentation/settings_picpos/screens/settings_picpos_screen.dart';
import 'package:ural_erp/presentation/settings_picpos/widgets/settings_nav_rail.dart';
import 'package:ural_erp/services/api/lan_paired_devices_provider.dart';
import 'package:ural_erp/services/api/lan_pairing_service.dart';
import 'package:ural_erp/services/cloud_sync/cloud_link_controller.dart';

class _FakeLan implements LanPairingService {
  _FakeLan(this.devices);
  final List<LanPairingDevice> devices;
  final revoked = <String>[];

  @override
  Future<List<LanPairingDevice>> listDevices() async => devices;

  @override
  Future<void> revoke(String deviceId) async => revoked.add(deviceId);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeCloud implements CloudLinkController {
  _FakeCloud({required this.enabled, this.devices = const []});
  final bool enabled;
  final List<CloudRepDeviceView> devices;
  final revoked = <String>[];
  final issued = <String>[];

  @override
  Future<CloudLinkView> load({bool includeSecret = true}) async => CloudLinkView(
        enabled: enabled,
        url: enabled ? 'https://cloud.example.test' : '',
        linkId: enabled ? 'link-1' : '',
        hasSecret: enabled,
        intervalMinutes: 5,
        lastSyncAt: enabled ? DateTime(2026, 9, 1, 10, 30) : null,
        posted: enabled ? 7 : 0,
        conflicts: const [],
      );

  @override
  Future<List<CloudRepDeviceView>?> listRepDevices() async =>
      enabled ? devices : null;

  @override
  Future<void> revokeRepDevice(String deviceId) async => revoked.add(deviceId);

  @override
  Future<Map<String, dynamic>?> issueRepPairingCode(String employeeGlobalId,
      {String? pin}) async {
    issued.add(employeeGlobalId);
    return {'code': 'ABCDEFGH'};
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final _lanDevices = [
  LanPairingDevice(
    deviceId: 'cashier-1',
    name: 'كاشير الصالة',
    pairedAt: DateTime(2026, 8, 1, 9),
    lastSeenAt: DateTime(2026, 9, 1, 12),
    ip: '192.168.1.20',
    revoked: false,
    legacySeen: false,
  ),
  LanPairingDevice(
    deviceId: 'branch-2',
    name: 'فرع الزرقاء',
    pairedAt: DateTime(2026, 7, 1, 9),
    lastSeenAt: DateTime(2026, 8, 20, 8),
    ip: '192.168.1.30',
    revoked: true,
    legacySeen: false,
  ),
  // غيرُ مقترنٍ (مرّ بالمفتاح القديم) — ليس «جهازاً مرتبطاً».
  const LanPairingDevice(
    deviceId: 'legacy-3',
    name: 'جهاز قديم',
    pairedAt: null,
    lastSeenAt: null,
    ip: null,
    revoked: false,
    legacySeen: true,
  ),
];

final _repDevices = [
  CloudRepDeviceView(
    deviceId: 'phone-1',
    deviceName: 'Galaxy A54',
    employeeName: 'مندوب ١',
    pairedAt: DateTime(2026, 8, 10),
    lastSeenAt: DateTime(2026, 9, 1, 11),
    revoked: false,
  ),
];

const _rep = EmployeeProfile(
    id: 5, globalId: 'rep-gid', name: 'مندوب ١', roleTags: {HrRoleTag.rep});

void _setLocale(Locale locale) {
  if (locale.languageCode == 'en') {
    I18nCatalog.setCatalog(Map<String, String>.from(
        jsonDecode(File('assets/i18n/en.json').readAsStringSync()) as Map));
  }
  I18nCatalog.setLocale(locale);
  addTearDown(() => I18nCatalog.setLocale(const Locale('ar', 'EG')));
}

Widget _app(
  Widget home, {
  required List<dynamic> overrides,
  Locale locale = const Locale('ar'),
  bool dark = false,
}) =>
    ProviderScope(
      overrides: overrides.cast(),
      child: MaterialApp(
        theme: dark ? AppTheme.darkTheme : AppTheme.lightTheme,
        locale: locale,
        supportedLocales: const [Locale('ar'), Locale('en')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: home,
      ),
    );

void _desktop(WidgetTester tester) {
  tester.view.physicalSize = const Size(1366, 768);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

void main() {
  late _FakeLan lan;
  late _FakeCloud cloud;

  List<dynamic> overrides({bool admin = true}) => [
        currentUserPermissionsProvider.overrideWith(
            (ref) async => admin ? ['system_admin'] : ['pos_access']),
        lanPairedDevicesServiceProvider.overrideWithValue(lan),
        cloudLinkControllerProvider.overrideWithValue(cloud),
        hrProfilesProvider.overrideWith((ref) async => [_rep]),
      ];

  Future<void> pumpSection(
    WidgetTester tester, {
    bool admin = true,
    Locale locale = const Locale('ar'),
    bool dark = false,
  }) async {
    _desktop(tester);
    _setLocale(locale);
    await tester.pumpWidget(_app(
      Scaffold(
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: LinkedDevicesSection(onOpenNetworkMode: () {}),
        ),
      ),
      overrides: overrides(admin: admin),
      locale: locale,
      dark: dark,
    ));
    await tester.pumpAndSettle();
  }

  setUp(() {
    lan = _FakeLan(_lanDevices);
    cloud = _FakeCloud(enabled: true, devices: _repDevices);
  });

  group('settings screen', () {
    Future<void> pumpScreen(WidgetTester tester) async {
      _desktop(tester);
      _setLocale(const Locale('ar'));
      // Drift opens lazily: open it on the real clock first (as the English
      // sweep does), then let each query complete outside fake async.
      final db = AppDatabase.forTesting();
      await tester.runAsync(() => db.getBranches());
      await tester.pumpWidget(_app(
        const SettingsPicposScreen(),
        overrides: [databaseProvider.overrideWithValue(db), ...overrides()],
      ));
      for (var i = 0; i < 20; i++) {
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 50)));
        await tester.pump(const Duration(milliseconds: 100));
        if (find.byType(SettingsNavRail).evaluate().isNotEmpty) break;
      }
      expect(find.byType(SettingsNavRail), findsOneWidget);
    }

    // Unmount, then drain the screen's timers (drift stream teardown,
    // activity logger, toasts) before the binding checks for pending ones.
    Future<void> disposeScreen(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox.shrink());
      for (var i = 0; i < 5; i++) {
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 50)));
        await tester.pump(const Duration(seconds: 2));
      }
    }

    Finder navText(String text) =>
        find.descendant(of: find.byType(SettingsNavRail), matching: find.text(text));

    testWidgets('section sits in the security group right after users',
        (tester) async {
      await pumpScreen(tester);
      final users = tester.getTopLeft(navText('المستخدمون والأمان'));
      final devices = tester.getTopLeft(navText('الأجهزة المرتبطة'));
      final guards = tester.getTopLeft(navText('حماية الأقسام'));
      expect(devices.dy, greaterThan(users.dy));
      expect(devices.dy, lessThan(guards.dy));

      await tester.tap(navText('الأجهزة المرتبطة'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(LinkedDevicesSection), findsOneWidget);
      await disposeScreen(tester);
    }, timeout: const Timeout(Duration(minutes: 3)));

    testWidgets('search by linking words finds the section', (tester) async {
      await pumpScreen(tester);
      final search = find.descendant(
          of: find.byType(SettingsNavRail), matching: find.byType(TextField));
      for (final word in const [
        'ربط',
        'أجهزة',
        'اقتران',
        'موبايل',
        'تابلت',
        'مندوب',
        'كاشير',
        'سحابة',
      ]) {
        await tester.enterText(search, word);
        await tester.pump();
        expect(
            find.descendant(
                of: find.byType(ListTile), matching: find.text('الأجهزة المرتبطة')),
            findsOneWidget,
            reason: 'search «$word»');
      }
      await disposeScreen(tester);
    }, timeout: const Timeout(Duration(minutes: 3)));
  });

  testWidgets('LAN list shows paired devices and revoke reaches the service',
      (tester) async {
    await pumpSection(tester);
    expect(find.byKey(const Key('ld_lan_cashier-1')), findsOneWidget);
    expect(find.byKey(const Key('ld_lan_branch-2')), findsOneWidget);
    expect(find.byKey(const Key('ld_lan_legacy-3')), findsNothing,
        reason: 'unpaired legacy devices are not linked devices');
    expect(find.text('كاشير الصالة'), findsOneWidget);
    expect(find.textContaining('آخر ظهور: 2026-09-01 12:00'), findsOneWidget);
    expect(find.textContaining('اقترن: 2026-08-01 09:00'), findsOneWidget);
    expect(find.byKey(const Key('ld_lan_revoke_branch-2')), findsNothing,
        reason: 'an already revoked device shows its state, not a button');
    expect(find.text('ملغى'), findsOneWidget);

    await tester.ensureVisible(find.byKey(const Key('ld_lan_revoke_cashier-1')));
    await tester.tap(find.byKey(const Key('ld_lan_revoke_cashier-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(ElevatedButton).last);
    await tester.pumpAndSettle();
    expect(lan.revoked, ['cashier-1']);
    await tester.pump(const Duration(seconds: 6)); // toast timer
  });

  testWidgets('cancelling the confirmation does not revoke', (tester) async {
    await pumpSection(tester);
    await tester.ensureVisible(find.byKey(const Key('ld_lan_revoke_cashier-1')));
    await tester.tap(find.byKey(const Key('ld_lan_revoke_cashier-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('إلغاء').last);
    await tester.pumpAndSettle();
    expect(lan.revoked, isEmpty);
  });

  testWidgets('cloud enabled: status, sync counts, rep devices and revoke',
      (tester) async {
    await pumpSection(tester);
    expect(find.text('مفعّل'), findsOneWidget);
    expect(find.text('https://cloud.example.test'), findsOneWidget);
    expect(find.text('مُرحَّلة: 7 · تعارضات: 0'), findsOneWidget);
    expect(find.byKey(const Key('ld_cloud_phone-1')), findsOneWidget);
    expect(find.text('مندوب ١ · Galaxy A54'), findsOneWidget);
    final issue = tester.widget<FilledButton>(find.byKey(const Key('ld_rep_issue')));
    expect(issue.onPressed, isNotNull);

    await tester.ensureVisible(find.byKey(const Key('ld_cloud_revoke_phone-1')));
    await tester.tap(find.byKey(const Key('ld_cloud_revoke_phone-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(ElevatedButton).last);
    await tester.pumpAndSettle();
    expect(cloud.revoked, ['phone-1']);
    await tester.pump(const Duration(seconds: 6)); // toast timer
  });

  testWidgets('cloud enabled: issuing a rep code reuses the HR pairing flow',
      (tester) async {
    await pumpSection(tester);
    await tester.ensureVisible(find.byKey(const Key('ld_rep_issue')));
    await tester.tap(find.byKey(const Key('ld_rep_issue')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('ld_rep_picker')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('مندوب ١').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(ElevatedButton).last);
    await tester.pumpAndSettle();
    // حوارُ لوحة المندوب نفسُه (مفاتيحُ `ef_rep_*`).
    await tester.tap(find.byKey(const Key('ef_rep_keep_pin')));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(ElevatedButton).last);
    await tester.pumpAndSettle();
    expect(cloud.issued, ['rep-gid']);
    expect(find.byKey(const Key('ef_rep_pairing_code')), findsOneWidget);
  });

  testWidgets('cloud disabled: says so and cannot issue codes', (tester) async {
    cloud = _FakeCloud(enabled: false);
    await pumpSection(tester);
    expect(find.text('غير مفعّل'), findsOneWidget);
    expect(find.text('فعّل الربط السحابي لإدارة هواتف المناديب'), findsOneWidget);
    expect(find.byKey(const Key('ld_cloud_sync')), findsNothing);
    final issue = tester.widget<FilledButton>(find.byKey(const Key('ld_rep_issue')));
    expect(issue.onPressed, isNull);
    expect(find.byKey(const Key('ld_cloud_settings')), findsOneWidget);
  });

  testWidgets('non-admin sees a read-only notice only', (tester) async {
    await pumpSection(tester, admin: false);
    expect(find.byKey(const Key('ld_read_only')), findsOneWidget);
    expect(find.byKey(const Key('ld_lan_mode')), findsNothing);
    expect(find.byKey(const Key('ld_rep_issue')), findsNothing);
  });

  testWidgets('coming-soon card has no actions', (tester) async {
    await pumpSection(tester);
    final card = find.byKey(const Key('ld_coming_soon'));
    expect(card, findsOneWidget);
    expect(find.descendant(of: card, matching: find.byType(ButtonStyleButton)),
        findsNothing);
  });

  for (final locale in const [Locale('ar'), Locale('en')]) {
    for (final dark in [false, true]) {
      testWidgets(
          'fits 1366x768 ${locale.languageCode}/${dark ? 'dark' : 'light'}',
          (tester) async {
        await pumpSection(tester, locale: locale, dark: dark);
        expect(tester.takeException(), isNull);
        expect(find.byType(LinkedDevicesSection), findsOneWidget);
        if (locale.languageCode == 'en') {
          expect(find.text('Local network devices (cashier/branches)'),
              findsOneWidget);
          expect(find.text('Unlink'), findsWidgets);
        }
      });
    }
  }
}
