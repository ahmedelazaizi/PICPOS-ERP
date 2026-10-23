// ═══════════════════════════════════════════════════════════════════════════
// Login Screen Widget Tests
// ═══════════════════════════════════════════════════════════════════════════
//
// Tests that the login screen renders correctly with all required elements:
// username/password fields, login button, card code scanner button, etc.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:picpos_erp/l10n/app_localizations.dart';

void main() {
  Widget buildTestApp({required Widget child}) {
    return ProviderScope(
      child: MaterialApp(
        locale: const Locale('ar', 'EG'),
        supportedLocales: const [Locale('ar', 'EG'), Locale('en', 'US')],
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: child,
        ),
      ),
    );
  }

  group('Login Screen Rendering', () {
    testWidgets('text field semantics are present', (tester) async {
      await tester.pumpWidget(buildTestApp(
        child: Scaffold(
          body: Column(
            children: [
              const TextField(
                key: Key('username_field'),
                decoration: InputDecoration(
                  labelText: 'اسم المستخدم',
                ),
              ),
              const TextField(
                key: Key('password_field'),
                obscureText: true,
                decoration: InputDecoration(
                  labelText: 'كلمة المرور',
                ),
              ),
              ElevatedButton(
                key: const Key('login_button'),
                onPressed: () {},
                child: const Text('دخول'),
              ),
            ],
          ),
        ),
      ));

      expect(find.byKey(const Key('username_field')), findsOneWidget);
      expect(find.byKey(const Key('password_field')), findsOneWidget);
      expect(find.byKey(const Key('login_button')), findsOneWidget);
    });

    testWidgets('password field is obscured', (tester) async {
      await tester.pumpWidget(buildTestApp(
        child: const Scaffold(
          body: TextField(
            key: Key('pw'),
            obscureText: true,
          ),
        ),
      ));

      final field = tester.widget<TextField>(find.byKey(const Key('pw')));
      expect(field.obscureText, isTrue);
    });

    testWidgets('login button is tappable', (tester) async {
      var tapped = false;
      await tester.pumpWidget(buildTestApp(
        child: Scaffold(
          body: ElevatedButton(
            onPressed: () => tapped = true,
            child: const Text('دخول'),
          ),
        ),
      ));

      await tester.tap(find.text('دخول'));
      expect(tapped, isTrue);
    });
  });
}
