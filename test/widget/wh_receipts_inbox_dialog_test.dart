// WH-002: the accountant's receipts dialog (AR/EN, light/dark). It reads from the
// SOURCE the provider gives it (on a client: the main), shows each waiting
// receipt with its lines, converts once, and speaks the refusal in the user's
// words. No database here: the source is a fake with the real contract.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/core/i18n/tr.dart';
import 'package:picpos_erp/data/database/database.dart' as db;
import 'package:picpos_erp/data/providers/providers.dart';
import 'package:picpos_erp/data/providers/wh_receipts_inbox_provider.dart';
import 'package:picpos_erp/presentation/purchases_picpos/screens/wh_receipts_inbox_dialog.dart';
import 'package:picpos_erp/services/api/m1_wh/wh_http.dart';
import 'package:picpos_erp/services/api/m1_wh/wh_receipts_source.dart';

class _SignedIn extends AuthNotifier {
  @override
  AuthState build() => AuthState(
        isAuthenticated: true,
        userWithRole: db.UserWithRole(
          user: db.User(
            id: 7, username: 'acct', passwordHash: '', passwordSalt: '', displayName: 'Acct', defaultScreen: '0',
            isLocked: false, isActive: true, discountLimitIsPercent: true, forcePasswordChange: false,
            createdAt: DateTime(2026, 1, 1), rowVersion: 1,
          ),
        ),
      );
}

class _Source implements WhReceiptsSource {
  _Source(this.waiting, {this.convertError});
  final List<Map<String, Object?>> waiting;
  final WhError? convertError;
  final converted = <String>[];
  int? listedFor;

  @override
  Future<List<Map<String, Object?>>> list(int userId) async {
    listedFor = userId;
    return List.of(waiting);
  }

  @override
  Future<Map<String, Object?>> convert(String gid, int userId) async {
    if (convertError != null) throw convertError!;
    converted.add(gid);
    waiting.removeWhere((r) => r['globalId'] == gid);
    return {'invoiceId': 1};
  }
}

Map<String, Object?> _receipt() => {
      'globalId': 'rcpt-1',
      'orderNumber': 'PO-00042',
      'supplier': 'Acme',
      'warehouse': 'Main',
      'createdBy': 'Clerk',
      'lines': [
        {'productId': 1, 'name': 'Rice', 'quantity': '6', 'condition': 'ok'},
        {'productId': 1, 'name': 'Rice', 'quantity': '2', 'condition': 'damaged'},
      ],
    };

void main() {
  setUpAll(() async {
    final en = jsonDecode(File('assets/i18n/en.json').readAsStringSync()) as Map<String, dynamic>;
    I18nCatalog.setCatalog(en.map((k, v) => MapEntry(k, '$v')));
  });
  tearDown(() => I18nCatalog.setLocale(const Locale('ar', 'EG')));

  for (final (locale, mode, convertLabel, emptyText) in [
    (const Locale('en'), ThemeMode.light, 'Convert to invoice', 'No receipts are waiting to be converted.'),
    (const Locale('ar', 'EG'), ThemeMode.dark, 'تحويل لفاتورة', 'لا توجد استلامات بانتظار التحويل.'),
  ]) {
    Future<_Source> pump(WidgetTester tester, _Source source) async {
      I18nCatalog.setLocale(locale);
      tester.view.physicalSize = const Size(1000, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(ProviderScope(
        overrides: [
          authProvider.overrideWith(_SignedIn.new),
          whReceiptsInboxProvider.overrideWithValue(source),
        ],
        child: MaterialApp(
          locale: Locale(locale.languageCode),
          themeMode: mode,
          theme: ThemeData(brightness: Brightness.light),
          darkTheme: ThemeData(brightness: Brightness.dark),
          supportedLocales: const [Locale('en'), Locale('ar')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          home: Scaffold(body: Builder(builder: (c) => TextButton(onPressed: () => showWhReceiptsInboxDialog(c), child: const Text('open')))),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      return source;
    }

    testWidgets('${locale.languageCode}/${mode.name}: lists the waiting receipt with its lines and converts it once', (tester) async {
      final source = await pump(tester, _Source([_receipt()]));
      expect(source.listedFor, 7, reason: 'asked as the signed-in user');
      expect(find.byKey(const Key('whInbox.rcpt-1')), findsOneWidget);
      expect(find.text('Rice'), findsNWidgets(2));
      expect(find.text(convertLabel), findsOneWidget);

      await tester.tap(find.byKey(const Key('whInbox.convert.rcpt-1')));
      await tester.pumpAndSettle();
      expect(source.converted, ['rcpt-1']);
      expect(find.byKey(const Key('whInbox.rcpt-1')), findsNothing, reason: 'the list refreshed');
      expect(find.text(emptyText), findsOneWidget);
      await tester.pump(const Duration(seconds: 4)); // the success toast
    });

    testWidgets('${locale.languageCode}/${mode.name}: a refusal from the main is shown and nothing is marked converted', (tester) async {
      final source = await pump(tester, _Source([_receipt()], convertError: WhError('period_closed', 409)));
      await tester.tap(find.byKey(const Key('whInbox.convert.rcpt-1')));
      await tester.pumpAndSettle();
      expect(source.converted, isEmpty);
      expect(find.byKey(const Key('whInbox.rcpt-1')), findsOneWidget, reason: 'still waiting');
      await tester.pump(const Duration(seconds: 4)); // the error toast
    });
  }
}
