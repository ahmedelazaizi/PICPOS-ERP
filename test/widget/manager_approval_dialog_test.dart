// P5 (plan 2026-10-24): the four-eyes approval dialog (PicPosDialog) in Arabic
// (RTL) and English (LTR), light and dark - request summary, approve action and
// every refusal sentence, including the offline-critical refusal.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:picpos_erp/core/i18n/tr.dart';
import 'package:picpos_erp/core/permissions/permission_codes.dart';
import 'package:picpos_erp/core/theme/app_theme.dart';
import 'package:picpos_erp/data/database/database.dart' as db;
import 'package:picpos_erp/data/providers/manager_approval_provider.dart';
import 'package:picpos_erp/data/providers/providers.dart';
import 'package:picpos_erp/presentation/widgets/manager_approval_dialog.dart';
import 'package:picpos_erp/services/approval/approval_proof_carrier.dart';
import 'package:picpos_erp/services/approval/manager_approval_flow.dart';
import 'package:picpos_erp/services/login_rate_limiter.dart';
import 'package:picpos_erp/services/manager_approval_cache.dart';

db.User _user(int id, String name) => db.User(
      id: id,
      username: name,
      passwordHash: '',
      passwordSalt: '',
      displayName: name,
      defaultScreen: '0',
      isLocked: false,
      isActive: true,
      discountLimitIsPercent: true,
      forcePasswordChange: false,
      createdAt: DateTime(2026, 1, 1),
      rowVersion: 1,
    );

class _Cashier extends AuthNotifier {
  @override
  AuthState build() => AuthState(
        isAuthenticated: true,
        userWithRole: db.UserWithRole(user: _user(10, 'Cashier Sam')),
      );
}

class _Wire implements ApprovalWirePort {
  _Wire(this.reply);
  Object Function() reply;
  @override
  Future<ApprovalWireResult> grant(Map<String, dynamic> body) async {
    final r = reply();
    if (r is ApprovalWireResult) return r;
    throw r;
  }
}

class _NoLocal implements LocalApproverPort {
  @override
  Future<LocalApprover?> authenticate(String input) async => null;
}

const _op = 'pos_expense';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final critical = PermissionCodes.criticalFinancialOps.first;
  late ApprovalProofCarrier carrier;

  setUpAll(() async => I18nCatalog.load());
  setUp(() {
    carrier = ApprovalProofCarrier.instance..debugReset();
    ManagerApprovalCache.instance.clear();
    LoginRateLimiter.reset();
  });
  tearDown(() {
    carrier.debugReset();
    I18nCatalog.setLocale(const Locale('ar', 'EG'));
  });

  Future<bool?> open(
    WidgetTester tester, {
    required _Wire wire,
    required Locale locale,
    required ThemeMode mode,
    String permission = _op,
    bool mirror = false,
  }) async {
    I18nCatalog.setLocale(locale);
    bool? result;
    await tester.binding.setSurfaceSize(const Size(900, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authProvider.overrideWith(_Cashier.new),
          managerApprovalFlowProvider.overrideWithValue(ManagerApprovalFlow(
            wire: wire,
            local: _NoLocal(),
            requesterId: () => 10,
            isClientMode: () => true,
            isMirror: () => mirror,
            carrier: carrier,
          )),
        ],
        child: MaterialApp(
          locale: locale,
          supportedLocales: const [Locale('ar', 'EG'), Locale('en')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: mode,
          home: Scaffold(
            body: Builder(
              builder: (ctx) => TextButton(
                onPressed: () async => result = await showDialog<bool>(
                  context: ctx,
                  builder: (_) => ManagerApprovalDialog(
                    permission: permission,
                    actionName: locale.languageCode == 'en' ? 'Void invoice' : 'إلغاء فاتورة',
                  ),
                ),
                child: const Text('go'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pump(const Duration(milliseconds: 400));
    return result;
  }

  Future<void> submit(WidgetTester tester, String pw) async {
    await tester.enterText(
        find.byKey(const ValueKey('managerApprovalPassword')), pw);
    await tester.tap(find.text(
        I18nCatalog.activeLocale.languageCode == 'en' ? 'Confirm' : 'تأكيد'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  const locales = {'ar': Locale('ar', 'EG'), 'en': Locale('en')};
  const modes = {'light': ThemeMode.light, 'dark': ThemeMode.dark};

  for (final l in locales.entries) {
    for (final m in modes.entries) {
      final en = l.key == 'en';
      group('${l.key} / ${m.key}', () {
        testWidgets('request summary: who asks, for what, how critical',
            (tester) async {
          await open(tester,
              wire: _Wire(() => throw StateError('unused')),
              locale: l.value,
              mode: m.value,
              permission: critical);
          expect(tester.takeException(), isNull);
          expect(find.text(en ? 'Admin authorization required' : 'تصريح المسؤول مطلوب'),
              findsOneWidget);
          expect(find.text('Cashier Sam'), findsOneWidget);
          expect(find.text(en ? 'Critical operation' : 'عملية حرجة'), findsOneWidget);
          expect(find.text(critical), findsOneWidget);
          expect(
              Directionality.of(tester.element(find.byType(ManagerApprovalDialog))),
              en ? TextDirection.ltr : TextDirection.rtl);
          expect(Theme.of(tester.element(find.byType(ManagerApprovalDialog))).brightness,
              m.key == 'dark' ? Brightness.dark : Brightness.light);
        });

        testWidgets('a different manager approved by the main: dialog closes, '
            'the proof is held and the single-use cache granted',
            (tester) async {
          final wire = _Wire(() => const ApprovalWireResult(
              200, {'proof': 'P.sig', 'approverId': 12, 'approverName': 'Boss'}));
          await open(tester, wire: wire, locale: l.value, mode: m.value);
          await submit(tester, 'boss-pw');
          expect(find.byType(ManagerApprovalDialog), findsNothing);
          expect(carrier.proof, 'P.sig');
          expect(ManagerApprovalCache.instance.consume(_op), isTrue);
        });

        testWidgets('the requester approving himself is refused with its own '
            'sentence', (tester) async {
          final wire = _Wire(() => const ApprovalWireResult(
              403, {'code': 'self_approval'}));
          await open(tester, wire: wire, locale: l.value, mode: m.value);
          await submit(tester, 'mine');
          expect(find.byType(ManagerApprovalDialog), findsOneWidget);
          expect(
              find.text(en
                  ? 'You cannot approve an action you requested yourself — another manager is required'
                  : 'لا يمكنك الموافقة على إجراءٍ طلبتَه بنفسك — يلزم مسؤولٌ آخر'),
              findsOneWidget);
          expect(carrier.proof, isNull);
          expect(ManagerApprovalCache.instance.consume(_op), isFalse);
        });

        testWidgets('offline + CRITICAL: refused with the main-system sentence, '
            'nothing granted', (tester) async {
          final wire = _Wire(() => const SocketException('down'));
          await open(tester,
              wire: wire, locale: l.value, mode: m.value, permission: critical);
          await submit(tester, 'boss-pw');
          expect(find.byType(ManagerApprovalDialog), findsOneWidget);
          expect(
              find.text(en
                  ? 'Critical financial operation: it needs approval through the main system and is not accepted offline.'
                  : 'عملية مالية حرجة: تتطلب موافقة عبر النظام الرئيسي ولا تُقبل دون اتصال.'),
              findsOneWidget);
          expect(ManagerApprovalCache.instance.consume(critical), isFalse);
        });

        testWidgets('a console offline never approves', (tester) async {
          final wire = _Wire(() => const SocketException('down'));
          await open(tester,
              wire: wire, locale: l.value, mode: m.value, mirror: true);
          await submit(tester, 'boss-pw');
          expect(
              find.text(en
                  ? 'The console is read-only offline — no approval without the main system.'
                  : 'المرآة للقراءة فقط دون اتصال — لا موافقة بلا النظام الرئيسي.'),
              findsOneWidget);
        });
      });
    }
  }

  test('every refusal kind has a non-empty sentence', () {
    for (final k in ManagerApprovalKind.values) {
      final s = managerApprovalMessage(ManagerApprovalDecision(k));
      expect(s.isEmpty, k == ManagerApprovalKind.approved, reason: '$k');
    }
  });
}
