import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/core/i18n/tr.dart';
import 'package:picpos_erp/core/theme/app_theme.dart';
import 'package:picpos_erp/data/providers/providers.dart';
import 'package:picpos_erp/domain/models/hr_employee_file.dart';
import 'package:picpos_erp/presentation/hr_picpos/hr_picpos_providers.dart';
import 'package:picpos_erp/presentation/hr_picpos/screens/ef_rep_panel.dart';
import 'package:picpos_erp/services/cloud_sync/cloud_link_controller.dart';

class _PairingController implements CloudLinkController {
  final issuedPins = <String?>[];
  final issuedIds = <String>[];

  @override
  Future<Map<String, dynamic>?> issueRepPairingCode(String employeeGlobalId,
      {String? pin}) async {
    issuedIds.add(employeeGlobalId);
    issuedPins.add(pin);
    return {'code': 'ABCDEFGH'};
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  const assets = HrRepAssets(
    routes: [],
    allRoutes: [],
    resources: null,
    books: [],
    allBooks: [],
    warehouses: [],
    safes: [],
  );
  const profile = EmployeeProfile(id: 1, globalId: 'rep-global', name: 'Rep');
  late _PairingController controller;

  Future<void> pumpPanel(WidgetTester tester,
      {Locale locale = const Locale('ar'), bool dark = false}) async {
    tester.view.physicalSize = const Size(1366, 768);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    if (locale.languageCode == 'en') {
      I18nCatalog.setCatalog(Map<String, String>.from(
          jsonDecode(File('assets/i18n/en.json').readAsStringSync()) as Map));
      I18nCatalog.setLocale(locale);
      addTearDown(() => I18nCatalog.setLocale(const Locale('ar', 'EG')));
    } else {
      I18nCatalog.setLocale(locale);
    }
    controller = _PairingController();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        hrRepAssetsProvider(1).overrideWith((ref) async => assets),
        hasPermissionProvider.overrideWith((ref, code) async => false),
        cloudLinkControllerProvider.overrideWithValue(controller),
      ],
      child: MaterialApp(
        theme: dark ? AppTheme.darkTheme : AppTheme.lightTheme,
        locale: locale,
        supportedLocales: const [Locale('ar'), Locale('en')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: const Scaffold(body: EfRepPanel(profile: profile, canManage: true)),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('ef_rep_pairing')));
    await tester.pumpAndSettle();
  }

  Future<void> issue(WidgetTester tester) async {
    await tester.tap(find.byType(ElevatedButton).last);
    await tester.pumpAndSettle();
  }

  testWidgets('invalid PIN length and mismatch prevent issuing', (tester) async {
    await pumpPanel(tester);
    await tester.enterText(find.byKey(const Key('ef_rep_pin')), '123');
    await tester.enterText(find.byKey(const Key('ef_rep_pin_confirmation')), '123');
    await issue(tester);
    expect(controller.issuedPins, isEmpty);
    expect(find.text('الرمز السري يجب أن يتكون من 4 إلى 8 أرقام'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('ef_rep_pin')), '1234');
    await issue(tester);
    expect(controller.issuedPins, isEmpty);
    expect(find.text('الرمزان غير متطابقين'), findsOneWidget);
  });

  testWidgets('non-digits cannot become the issued PIN', (tester) async {
    await pumpPanel(tester);
    await tester.enterText(find.byKey(const Key('ef_rep_pin')), 'ab12');
    await tester.enterText(find.byKey(const Key('ef_rep_pin_confirmation')), '12');
    expect(tester.widget<EditableText>(find.descendant(
      of: find.byKey(const Key('ef_rep_pin')),
      matching: find.byType(EditableText),
    )).controller.text, '12');
    await issue(tester);
    expect(controller.issuedPins, isEmpty);
  });

  testWidgets('validated PIN reaches cloud and is not shown after issue',
      (tester) async {
    await pumpPanel(tester);
    await tester.enterText(find.byKey(const Key('ef_rep_pin')), '12345678');
    await tester.enterText(find.byKey(const Key('ef_rep_pin_confirmation')), '12345678');
    await issue(tester);
    expect(controller.issuedIds, ['rep-global']);
    expect(controller.issuedPins, ['12345678']);
    expect(find.byKey(const Key('ef_rep_pairing_code')), findsOneWidget);
    expect(find.text('الرمز السري: تم ضبطه'), findsOneWidget);
    expect(find.text('رمز الاقتران صالح لمدة 10 دقائق ويُستخدم مرة واحدة.'),
        findsOneWidget);
    expect(find.text('12345678'), findsNothing);
  });

  testWidgets('keep current PIN issues without changing PIN', (tester) async {
    await pumpPanel(tester);
    await tester.tap(find.byKey(const Key('ef_rep_keep_pin')));
    await tester.pumpAndSettle();
    await issue(tester);
    expect(controller.issuedPins, [null]);
    expect(find.text('لم يتغيّر الرمز السري'), findsOneWidget);
  });

  for (final locale in const [Locale('ar'), Locale('en')]) {
    for (final dark in [false, true]) {
      testWidgets('pairing dialogs fit ${locale.languageCode}/${dark ? 'dark' : 'light'}',
          (tester) async {
        await pumpPanel(tester, locale: locale, dark: dark);
        expect(tester.takeException(), isNull);
        await tester.tap(find.byKey(const Key('ef_rep_keep_pin')));
        await tester.pumpAndSettle();
        await issue(tester);
        expect(tester.takeException(), isNull);
        expect(find.byKey(const Key('ef_rep_pairing_code')), findsOneWidget);
      });
    }
  }
}
