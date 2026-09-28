// دفعة ١٠ — الإعدادات والنظام: معلومات الشركة، عملة النظام، إعدادات البيع
// السريع، نسبة الضريبة الافتراضية، قاعدة البيانات، تفعيل الترخيص.
//
// الستة كانوا أكواد بلا إنفاذ: أي حد يقدر يفتح شاشة الإعدادات كان يقدر
// يبدّل محرك قاعدة البيانات (وبيانات اتصالها بكلمة سر بنص صريح)، ويغيّر
// عملة النظام، ويفعّل الترخيص.
//
// ── ليه مش شاشة الإعدادات كاملة ───────────────────────────────────────────
// `SettingsScreen` بتجرّ عشرات الـproviders وقاعدة بيانات حقيقية. التايلات
// اتلمّت في `widgets/settings/settings_permission_tiles.dart` — ملف مشترك
// بين البراندين والإنتاج بينادي نفس الدوال دي في الفوركين، فالاختبار بيثبت
// التوصيلة مش نسخة موازية.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/core/permissions/permission_codes.dart';
import 'package:ural_erp/data/providers/providers.dart';
import 'package:ural_erp/presentation/widgets/permission_guard.dart';
import 'package:ural_erp/presentation/widgets/settings/settings_permission_tiles.dart';

void main() {
  Future<void> pump(
    WidgetTester tester,
    Widget guarded,
    List<String> perms,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentUserPermissionsProvider.overrideWith((ref) async => perms),
        ],
        child: MaterialApp(home: Scaffold(body: guarded)),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  PermissionGuard guardOf(WidgetTester tester) =>
      tester.widget<PermissionGuard>(find.byType(PermissionGuard).first);

  /// كل تايل بيفتح ديالوج: نفس الشكل بالظبط (تجاوز مدير + `onGranted`).
  final openers = <String, ({String code, Widget Function({required VoidCallback onOpen}) build, String tapTarget})>{
    'settings_company': (
      code: PermissionCodes.settingsCompany,
      build: buildCompanyInfoTileGuarded,
      tapTarget: 'معلومات الشركة',
    ),
    'settings_pos_edit': (
      code: PermissionCodes.settingsPosEdit,
      build: buildPosSettingsTileGuarded,
      tapTarget: 'إعدادات البيع السريع الرئيسية',
    ),
    'system_database': (
      code: PermissionCodes.systemDatabase,
      build: buildDatabaseSettingsTileGuarded,
      tapTarget: 'قاعدة البيانات',
    ),
    'system_license': (
      code: PermissionCodes.systemLicense,
      build: buildLicenseActivateButtonGuarded,
      tapTarget: 'تفعيل الآن',
    ),
  };

  openers.forEach((name, spec) {
    group('$name — الفتح', () {
      testWidgets('بالصلاحية: الضغطة بتفتح على طول', (tester) async {
        var opened = 0;
        await pump(tester, spec.build(onOpen: () => opened++), [spec.code]);

        final guard = guardOf(tester);
        expect(guard.permission, spec.code);
        expect(guard.allowManagerOverride, isTrue);
        // درس f8d3fa9 — من غير onGranted الحارس بيفكّ القفل وبس.
        expect(guard.onGranted, isNotNull);

        await tester.tap(find.text(spec.tapTarget));
        await tester.pump();
        expect(opened, 1);
      });

      testWidgets('بدون الصلاحية: ما بيفتحش من غير موافقة مدير',
          (tester) async {
        var opened = 0;
        await pump(tester, spec.build(onOpen: () => opened++), const []);

        await tester.tap(find.text(spec.tapTarget), warnIfMissed: false);
        await tester.pump();
        expect(opened, 0);
      });
    });
  });

  group('settings_currency — عملة النظام', () {
    testWidgets('بالصلاحية: بيفتح المُنتقي', (tester) async {
      var opened = 0;
      await pump(
        tester,
        buildCurrencyTileGuarded(
          subtitle: 'جنيه مصري (EGP)',
          onOpen: () => opened++,
        ),
        [PermissionCodes.settingsCurrency],
      );

      expect(guardOf(tester).permission, PermissionCodes.settingsCurrency);
      await tester.tap(find.text('عملة النظام'));
      await tester.pump();
      expect(opened, 1);
    });

    testWidgets('بدون الصلاحية: ما بيفتحش', (tester) async {
      var opened = 0;
      await pump(
        tester,
        buildCurrencyTileGuarded(
          subtitle: 'جنيه مصري (EGP)',
          onOpen: () => opened++,
        ),
        const [],
      );

      await tester.tap(find.text('عملة النظام'), warnIfMissed: false);
      await tester.pump();
      expect(opened, 0);
    });
  });

  group('settings_tax — نسبة الضريبة الافتراضية', () {
    testWidgets('بالصلاحية: الحقل قابل للكتابة', (tester) async {
      var typed = '';
      await pump(
        tester,
        buildDefaultTaxRateTileGuarded(
          field: TextFormField(onChanged: (v) => typed = v),
        ),
        [PermissionCodes.settingsTax],
      );

      final guard = guardOf(tester);
      expect(guard.permission, PermissionCodes.settingsTax);
      expect(guard.allowManagerOverride, isTrue);
      // حقل نص حر مالوش «فعل واحد» — الموافقة بتفكّ القفل، فمفيش onGranted
      // عن قصد (نفس قرار pos_note_add في دفعة ٧).
      expect(guard.onGranted, isNull);

      await tester.enterText(find.byType(TextFormField), '14');
      expect(typed, '14');
    });

    testWidgets('بدون الصلاحية: الحقل متقفّل (AbsorbPointer)', (tester) async {
      await pump(
        tester,
        buildDefaultTaxRateTileGuarded(field: TextFormField()),
        const [],
      );

      // الحقل لسه ظاهر — الإخفاء كان هيمنع أي تعديل نهائياً بدل ما يطلب
      // موافقة مدير — لكنه جوه AbsorbPointer فالضغط بيروح للحارس.
      expect(find.byType(TextFormField), findsOneWidget);
      expect(find.byType(AbsorbPointer), findsWidgets);
    });
  });

  group('party balance repair — نفس صلاحية DAO', () {
    testWidgets('يظهر ويحرس إجراء الإصلاح بصلاحية الأستاذ', (tester) async {
      var opened = 0;
      await pump(
        tester,
        buildPartyBalanceRepairTileGuarded(onOpen: () => opened++),
        [PermissionCodes.accountingJournal],
      );

      expect(guardOf(tester).permission, PermissionCodes.accountingJournal);
      await tester.tap(find.text('تدقيق أرصدة الأطراف'));
      await tester.pump();
      expect(opened, 1);
    });

    testWidgets('بدون صلاحية الأستاذ لا يفتح الإصلاح', (tester) async {
      var opened = 0;
      await pump(
        tester,
        buildPartyBalanceRepairTileGuarded(onOpen: () => opened++),
        const [],
      );

      await tester.tap(find.text('تدقيق أرصدة الأطراف'), warnIfMissed: false);
      await tester.pump();
      expect(opened, 0);
    });
  });
}
