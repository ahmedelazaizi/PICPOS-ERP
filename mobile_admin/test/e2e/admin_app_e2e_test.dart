// E2E تطبيق الإدارة (PicPos إدارة): `AdminSession` الحقيقي + `CloudManageClient`
// + `HttpApiTransport` (HTTP فعلي) ↔ خادم السحابة الحقيقي (عملية فرعية + Postgres)،
// بدور مكتب (E2eDesktop) يوقّع لقطاته بـ Ed25519 حقيقي، وتخزين أسرار في الذاكرة.
// القسم الثاني يقود واجهة التطبيق (PicPosAdminApp) فوق الخادم الحقيقي.
//
// يُشغَّل: `flutter test test/e2e` من مجلد mobile_admin. انظر docs/testing/E2E.md.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_admin/admin_session.dart';
import 'package:picpos_admin/app.dart';
import 'package:picpos_api_client/picpos_api_client.dart';
import 'package:picpos_device/picpos_device.dart';
import 'package:picpos_ui/picpos_ui.dart';

import '../support.dart';
import 'support/e2e_cloud.dart';
import 'support/e2e_desktop.dart';

void main() {
  late E2eCloud cloud;
  late E2eDesktop desk;
  const owner = 'e2e-owner';

  setUpAll(() async {
    HttpOverrides.global = null; // flutter_test يحجب HTTP افتراضيًا
    await loadTestFonts();
    cloud = await E2eCloud.start(pairLimit: 100);
    desk = await E2eDesktop.link(cloud);
    final r = await desk.pushUsers([
      await desk.userJson(owner, 'owner'),
      await desk.userJson('e2e-lock', 'locked'),
      await desk.userJson('e2e-ui', 'uiuser'),
    ]);
    expect(r.status, 200, reason: '$r');
  });
  tearDownAll(() => cloud.stop());

  setUp(() => HttpOverrides.global = null); // flutter_test يحجب HTTP افتراضيًا

  Future<PairingOffer> offer(String userGid, {String? key}) async => PairingOffer(
        cloudUrl: Uri.parse(cloud.url),
        code: await desk.adminPairingCode(userGid),
        desktopSigningKey: key ?? desk.publicKey,
      );

  group('AdminSession على خادم حقيقي', () {
    test('اقتران ← دخول موقَّع ← لوحة المؤشرات والموافقات ← تحديث من المكتب ← الأسرار محفوظة', () async {
      final secrets = MemorySecretStore();
      final session = AdminSession(secrets);
      await session.pair(await offer(owner));
      expect(session.paired, isTrue);
      expect(session.loggedIn, isFalse);
      expect(secrets.values['admin.signingKey'], desk.publicKey);
      expect(session.username, 'owner');

      await desk.pushSnapshots([
        await desk.signed(SnapshotKinds.kpiToday, {'netSales': '51.000', 'invoiceCount': 2}),
        await desk.signed(SnapshotKinds.approvalsSalesReturns, {
          'items': [
            {'ref': 'SR-7', 'summary': 'مرتجع بيع', 'amount': '4.500'},
            {'ref': 'SR-8', 'summary': 'مرتجع بيع', 'amount': '9.000'},
          ],
        }),
      ]);

      await session.login('owner', E2eDesktop.defaultPassword);
      expect(session.loggedIn, isTrue);
      expect(secrets.values['admin.sessionToken'], isNotEmpty);
      final snaps = session.snapshots!;
      expect(snaps.rejected, 0);
      expect((snaps.find(SnapshotKinds.kpiToday)!.payload as Map)['netSales'], '51.000');
      final items = (snaps.find(SnapshotKinds.approvalsSalesReturns)!.payload as Map)['items'] as List;
      expect(items.map((e) => (e as Map)['ref']), ['SR-7', 'SR-8']);

      // المكتب يوافق على SR-7 فيُحدّث اللقطة؛ التطبيق يرى الأحدث بعد refresh.
      await desk.pushSnapshots([
        await desk.signed(SnapshotKinds.approvalsSalesReturns, {
          'items': [
            {'ref': 'SR-8', 'summary': 'مرتجع بيع', 'amount': '9.000'},
          ],
        }, asOf: DateTime.now().toUtc().add(const Duration(seconds: 3))),
      ]);
      await session.refresh();
      final after = (session.snapshots!.find(SnapshotKinds.approvalsSalesReturns)!.payload as Map)['items'] as List;
      expect(after.map((e) => (e as Map)['ref']), ['SR-8']);

      // إعادة تشغيل التطبيق: restore() من الأسرار يعيد نفس الجلسة العاملة.
      final restarted = AdminSession(secrets);
      await restarted.restore();
      expect(restarted.paired && restarted.loggedIn, isTrue);
      await restarted.refresh();
      expect(restarted.snapshots!.rejected, 0);
    });

    test('مفتاح التوقيع في QR يخالف مفتاح الخادم ← desktop_signing_key_mismatch ولا يُحفظ شيء', () async {
      final secrets = MemorySecretStore();
      final session = AdminSession(secrets);
      final wrong = base64.encode(List<int>.filled(32, 9));
      await expectLater(session.pair(await offer(owner, key: wrong)), throwsA(isA<FormatException>()));
      expect(session.paired, isFalse);
      expect(secrets.values['admin.signingKey'], isNull);
    });

    test('لقطة مزوّرة من وسيط السحابة لا تُعرض (تُحتسب مرفوضة)', () async {
      final session = AdminSession(MemorySecretStore());
      await session.pair(await offer(owner));
      final rogue = await PayloadSigner.fromSeed(List<int>.filled(32, 66));
      final forged = await buildSignedSnapshot(rogue,
          kind: SnapshotKinds.profitToday, scope: 'all', asOf: DateTime.now().toUtc(), data: {'grossProfit': '1000000.000'});
      expect((await desk.pushSnapshots([forged])).status, 200);
      await session.login('owner', E2eDesktop.defaultPassword);
      expect(session.snapshots!.find(SnapshotKinds.profitToday), isNull);
      expect(session.snapshots!.rejected, greaterThanOrEqualTo(1));
    });

    test('كلمة مرور خاطئة ← ApiError unauthorized؛ الجلسة لا تُحفظ؛ 5 فشل ← قفل', () async {
      final secrets = MemorySecretStore();
      final session = AdminSession(secrets);
      await session.pair(await offer('e2e-lock'));
      for (var i = 0; i < 5; i++) {
        await expectLater(session.login('locked', 'wrong-pass-$i'),
            throwsA(isA<ApiError>().having((e) => e.kind, 'kind', ApiErrorKind.unauthorized)));
      }
      expect(secrets.values['admin.sessionToken'], isNull);
      await expectLater(session.login('locked', E2eDesktop.defaultPassword),
          throwsA(isA<ApiError>().having((e) => e.kind, 'kind', ApiErrorKind.rateLimited)));
      expect(session.loggedIn, isFalse);
    });

    test('إلغاء الاقتران: unpairAndWipe يُبطل الجهاز على الخادم ويمسح الأسرار', () async {
      final secrets = MemorySecretStore();
      final session = AdminSession(secrets);
      await session.pair(await offer(owner));
      await session.login('owner', E2eDesktop.defaultPassword);
      final id = secrets.values['admin.deviceId']!;
      expect(await session.unpairAndWipe(), isTrue);
      expect(secrets.values, isEmpty);
      final row = (await desk.adminDevices()).firstWhere((d) => d['deviceId'] == id);
      expect(row['revoked'], true);
    });

    test('إبطال من المكتب ← أول refresh يُسقط ApiError(deviceRevoked) ويمسح الأسرار', () async {
      final secrets = MemorySecretStore();
      final session = AdminSession(secrets);
      await session.pair(await offer(owner));
      await session.login('owner', E2eDesktop.defaultPassword);
      expect((await desk.revokeAdminDevice(secrets.values['admin.deviceId']!)).status, 200);
      await expectLater(session.refresh(),
          throwsA(isA<ApiError>().having((e) => e.kind, 'kind', ApiErrorKind.deviceRevoked)));
      expect(session.paired, isFalse);
      expect(secrets.values, isEmpty);
    });

    test('تسجيل الخروج يبقي الاقتران ويمسح الجلسة محليًا ثم دخول جديد ينجح (إبطال الرمز على الخادم: انظر security_cross_tenant_e2e_test)', () async {
      final secrets = MemorySecretStore();
      final session = AdminSession(secrets);
      await session.pair(await offer(owner));
      await session.login('owner', E2eDesktop.defaultPassword);
      await session.logout();
      expect(session.paired, isTrue);
      expect(session.loggedIn, isFalse);
      expect(secrets.values['admin.sessionToken'], isNull);
      expect(secrets.values['admin.deviceToken'], isNotEmpty);
      await session.login('owner', E2eDesktop.defaultPassword);
      expect(session.loggedIn, isTrue);
    });
  });

  group('واجهة التطبيق فوق الخادم الحقيقي', () {
    /// ننتظر ردود الشبكة الحقيقية داخل runAsync ثم نرسم الإطار.
    Future<void> until(WidgetTester tester, Finder f, {int tries = 80}) async {
      for (var i = 0; i < tries && f.evaluate().isEmpty; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(f, findsWidgets);
    }

    testWidgets('اقتران من النموذج ← دخول ← لوحة 51.000 ← الموافقات ← فك الربط', (tester) async {
      setSurface(tester, kPhone);
      final qr = jsonEncode(PairingOffer(
              cloudUrl: Uri.parse(cloud.url), code: (await tester.runAsync(() => desk.adminPairingCode('e2e-ui')))!, desktopSigningKey: desk.publicKey)
          .toQrJson());
      await tester.runAsync(() async => desk.pushSnapshots([
            await desk.signed(SnapshotKinds.kpiToday, {'netSales': '51.000', 'invoiceCount': 2}),
            await desk.signed(SnapshotKinds.approvalsSalesReturns, {
              'items': [
                {'ref': 'SR-UI-1', 'summary': 'مرتجع واجهة', 'amount': '6.250'},
              ],
            }, asOf: DateTime.now().toUtc().add(const Duration(minutes: 5))), // يتفوّق على لقطات الاختبارات السابقة (الأحدث يفوز)
          ]));
      final secrets = MemorySecretStore();
      final session = AdminSession(secrets);
      await tester.pumpWidget(PicPosAdminApp(settings: PicPosAppSettings(), session: session));
      await tester.enterText(find.byKey(const Key('admin.offer')), qr);
      await tester.ensureVisible(find.byKey(const Key('admin.pair')));
      await tester.tap(find.byKey(const Key('admin.pair')));
      await until(tester, find.byKey(const Key('admin.login')));
      expect(secrets.values['admin.deviceToken'], isNotEmpty);

      await tester.enterText(find.byKey(const Key('admin.username')), 'uiuser');
      await tester.enterText(find.byKey(const Key('admin.password')), E2eDesktop.defaultPassword);
      await tester.tap(find.byKey(const Key('admin.login')));
       await until(tester, find.byKey(const Key('admin.appPinSetup')));
       await tester.enterText(find.byKey(const Key('admin.appPinSetup')), '1234');
       await tester.enterText(find.byKey(const Key('admin.appPinConfirm')), '1234');
       await tester.tap(find.byKey(const Key('admin.appPinSave')));
       await until(tester, find.text('51.000'));

      // الموافقات (للعرض فقط): العنصر الموقَّع يظهر.
      await tester.tap(find.text('الموافقات').last);
      await tester.pumpAndSettle();
      expect(find.textContaining('SR-UI-1'), findsOneWidget);
      expect(find.text('للعرض فقط'), findsOneWidget);

      // فك الربط من الإعدادات يعيد الإقلاع (Onboarding) ويمسح الأسرار.
      await tester.tap(find.text('المزيد'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('الإعدادات').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('settings.unpair')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('فك ربط الجهاز').last);
      await until(tester, find.byKey(const Key('admin.url')));
      expect(secrets.values, isEmpty);
      // مؤقّتات keep-alive الخاملة لاتصالات HTTP (15 ث) تُستنزف كي لا تُسقط فحص flutter_test.
      await tester.pump(const Duration(seconds: 20));
    });
  });

  test('الموافقة/الرفض من التطبيق على طلب معلّق', () {}, skip: 'غير منفَّذ بعد: الموافقات في M-1 «للعرض فقط» (viewOnly)، '
      'و CloudManageClient.submitCommand يرمي not_available_in_m1 (الأوامر في M-3). '
      'فعّل الاختبار عند تنفيذ /manage/commands: موافقة ← رفض ← عدم تكرار ← step-up.');
}
