// test/widget/setup_wizard_flow_test.dart
//
// معالجُ البدء بعد إعادة الهيكلة — بندُ المالك ٦ (المرحلة ح).
//
// ═══ ما يحرسه ═══
//
// • **كلُّ خطوةٍ** تُرسَم بلا فيضٍ على ١٣٦٦×٧٦٨ — RTL/LTR × فاتح/داكن — وفي
//   الإنجليزيّة بلا مفتاحٍ ناقصٍ في الكتالوج.
// • **التحقّق**: «التالي» مقفولٌ على الحقول الإلزاميّة، والعمودُ الجانبيُّ لا
//   يقفز فوقها، وEnter يتقدّم حين تصحّ الخطوة.
// • **الاختياريّ يُتخطّى**: المنتجاتُ والصناديقُ والدليل.
// • **المراجعة** تعرض الاختيارات، و«تعديل» يفتح الخطوةَ ويعود إليها.
// • **الفشل**: المرحلةُ وسببُها، والإعادةُ تبدأ من الأوّل، ولا `setup_completed`.
//
// ⚠️ والكتاباتُ نفسُها (‏مفاتيحُ وصفوفٌ بالترتيب) مقيسةٌ على المشغّل مباشرةً في
//    `test/unit/setup_finish_runner_parity_test.dart` مقابلَ المعالج القديم.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/core/i18n/locale_provider.dart';
import 'package:picpos_erp/core/i18n/tr.dart';
import 'package:picpos_erp/core/theme/app_theme.dart';
import 'package:picpos_erp/data/providers/providers.dart';
import 'package:picpos_erp/domain/models/setup_step_order.dart';
import 'package:picpos_erp/presentation/screens/setup_wizard/setup_finish_runner.dart';
import 'package:picpos_erp/presentation/screens/setup_wizard/setup_persistence_riverpod.dart';
import 'package:picpos_erp/presentation/screens/setup_wizard/setup_step_meta.dart';
import 'package:picpos_erp/presentation/screens/setup_wizard_screen.dart';
import 'package:picpos_erp/services/network_service.dart';

class _LocaleNotifier extends UserLocaleNotifier {
  @override
  Locale build() => I18nCatalog.activeLocale;

  @override
  Future<void> setLocale(Locale locale) async {
    final normalized = localeForCode(locale.languageCode);
    state = normalized;
    I18nCatalog.setLocale(normalized);
  }
}

class _ThemeNotifier extends ThemeModeNotifier {
  _ThemeNotifier(this.mode);
  final ThemeMode mode;
  @override
  ThemeMode build() => mode;
}

/// منفذٌ يفشل دائماً عند الضريبة — ويعدّ المحاولات.
class _FailingPersistence implements SetupPersistence {
  int runs = 0;
  final keys = <String>[];

  @override
  Future<void> saveSetting(String key, String value) async {
    if (key == 'setup_in_progress' && value == 'true') runs++;
    if (key == 'tax_enabled') throw StateError('disk full');
    keys.add(key);
  }

  @override
  Future<void> saveCachedSetting(String key, String value) async {}
  @override
  Future<void> setDeveloperPassword(String password) async {}
  @override
  Future<void> setCurrency(String code) async {}
  @override
  Future<List<Branche>> getAllBranches() async => const [];
  @override
  Future<void> updateBranch(Branche branch) async {}
  @override
  Future<int> createBranch(String name) async => 1;
  @override
  Future<List<Warehouse>> getWarehousesByBranch(int branchId) async =>
      const [];
  @override
  Future<void> updateWarehouse(Warehouse warehouse) async {}
  @override
  Future<int> createWarehouseForBranch({
    required String name,
    required int branchId,
  }) async =>
      1;
  @override
  Future<SafeData?> getDefaultSafeByType(String type) async => null;
  @override
  Future<void> updateSafeDetails(
    SafeData safe, {
    required String name,
    String? bankName,
    String? accountNumber,
  }) async {}
  @override
  Future<void> insertProduct(ProductsCompanion product) async {}
  @override
  Future<int?> findUserId(String username) async => 1;
  @override
  Future<void> updateUserPassword(int userId, String password) async {}
  @override
  Future<void> createUser({
    required String username,
    required String password,
    required String displayName,
    int? roleId,
  }) async {}
  @override
  Future<String?> commitDeploymentMode(NetworkMode mode, int port) async =>
      null;
  @override
  Future<void> saveClientBranchId(int branchId) async {}
  @override
  Future<int> createFiscalYear(String n, DateTime s, DateTime e) async => 1;
  @override
  Future<void> generatePeriodsForYear(int id, DateTime s, DateTime e) async {}
  @override
  Future<void> recordAudit(String e, Map<String, dynamic> p) async {}
  @override
  Future<bool> rehydrateRuntimeConfigCache() async => true;
}

late Map<String, String> _englishCatalog;

void _useLocale({required bool english}) {
  I18nCatalog.setCatalog(_englishCatalog);
  I18nCatalog.setLocale(english ? englishUserLocale : defaultUserLocale);
}

Future<void> _pump(
  WidgetTester tester, {
  int? step,
  NetworkMode? mode,
  bool dark = false,
  SetupPersistence? persistence,
}) async {
  tester.view.physicalSize = const Size(1366, 768);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final db = AppDatabase.forTesting();
  await tester.runAsync(() => db.getBranches());
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        userLocaleProvider.overrideWith(_LocaleNotifier.new),
        themeModeProvider.overrideWith(
          () => _ThemeNotifier(dark ? ThemeMode.dark : ThemeMode.light),
        ),
        allRolesProvider.overrideWith((ref) => Stream.value(const <Role>[])),
        if (persistence != null)
          setupPersistenceProvider.overrideWithValue(persistence),
      ],
      child: MaterialApp(
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        themeMode: dark ? ThemeMode.dark : ThemeMode.light,
        home: SetupWizardScreen(initialStep: step, initialMode: mode),
      ),
    ),
  );
  // قراءاتُ القاعدة (‏الصناديق · الدليل) تحتاج وقتاً حقيقيّاً لا وهميّاً.
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
  await tester.pump();
  await tester.pump();
}

Future<void> _teardown(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 1));
}

ElevatedButton _next(WidgetTester tester) =>
    tester.widget<ElevatedButton>(find.byKey(const Key('setup_next')));

void main() {
  setUpAll(() {
    final decoded = jsonDecode(
      File('assets/i18n/en.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    _englishCatalog = {
      for (final e in decoded.entries)
        if (e.value is String) e.key: e.value as String,
    };
  });

  tearDown(() => _useLocale(english: false));

  // ── كلُّ خطوةٍ × الاتجاهين × الوضعين على ١٣٦٦×٧٦٨ ──
  final cases = <(NetworkMode, int)>[
    for (final s in setupStepOrderFor(SetupDeploymentMode.standalone))
      (NetworkMode.standalone, s),
    (NetworkMode.server, SetupStepIds.users),
    (NetworkMode.server, SetupStepIds.postgres),
    (NetworkMode.server, SetupStepIds.provisioning),
    (NetworkMode.client, SetupStepIds.company),
    (NetworkMode.client, SetupStepIds.branchAndMode),
    (NetworkMode.mirror, SetupStepIds.branchAndMode),
  ];
  for (final english in [false, true]) {
    for (final dark in [false, true]) {
      final tag = '${english ? 'LTR' : 'RTL'} · ${dark ? 'داكن' : 'فاتح'}';
      group(tag, () {
        for (final (mode, step) in cases) {
          testWidgets('الخطوة $step (${mode.name}) بلا فيضٍ على ١٣٦٦×٧٦٨',
              (tester) async {
            _useLocale(english: english);
            await _pump(tester, step: step, mode: mode, dark: dark);

            final err = tester.takeException();
            expect(err, isNull, reason: '$err');
            // عنوانُ الخطوة الصحيحة فوق جسمها.
            expect(find.text(kSetupSteps[step]!.title), findsWidgets);
            final dir = tester.widget<Directionality>(find
                .ancestor(
                  of: find.byType(Scaffold),
                  matching: find.byType(Directionality),
                )
                .first);
            expect(dir.textDirection,
                english ? TextDirection.ltr : TextDirection.rtl);
            if (english) {
              expect(I18nCatalog.missingKeys, isEmpty,
                  reason: 'مفاتيحُ بلا ترجمة: ${I18nCatalog.missingKeys}');
            }
            await _teardown(tester);
          });
        }
      });
    }
  }

  group('التحقّق والتنقّل', () {
    testWidgets('اسمُ الشركة الفارغ يقفل «التالي» — وEnter يتقدّم بعد ملئه',
        (tester) async {
      await _pump(tester, step: SetupStepIds.company);
      expect(_next(tester).onPressed, isNull,
          reason: 'اسمُ الشركة إلزاميّ في المستقلّ');

      await tester.enterText(
          find.byKey(const Key('setup_company_name')), 'شركة النيل');
      await tester.pump();
      expect(_next(tester).onPressed, isNotNull);

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(find.text(kSetupSteps[SetupStepIds.currencyTax]!.title),
          findsWidgets,
          reason: 'Enter = التالي');
      await _teardown(tester);
    });

    testWidgets('العمودُ الجانبيُّ لا يقفز فوق خطوةٍ ناقصة', (tester) async {
      await _pump(tester, step: SetupStepIds.company);
      // «المراجعة والبدء» في العمود — والشركةُ بلا اسم.
      await tester.tap(find.text(kSetupSteps[SetupStepIds.review]!.label).first);
      await tester.pump();
      expect(find.text(kSetupSteps[SetupStepIds.company]!.title), findsWidgets);
      await tester.pump(const Duration(seconds: 5));
      await _teardown(tester);
    });

    testWidgets('كلمتا المرور تقفلان «المستخدمين» حتّى تصحّا', (tester) async {
      await _pump(tester, step: SetupStepIds.users);
      expect(_next(tester).onPressed, isNull);

      await tester.enterText(
          find.byKey(const Key('setup_admin_password')), 'Strong-123');
      await tester.enterText(
          find.byKey(const Key('setup_admin_password_confirm')), 'Strong-123');
      await tester.pump();
      expect(_next(tester).onPressed, isNull, reason: 'كلمةُ المطوّر ناقصة');

      await tester.enterText(find.byKey(const Key('setup_dev_password')), 'dev1');
      await tester.enterText(
          find.byKey(const Key('setup_dev_password_confirm')), 'dev2');
      await tester.pump();
      expect(_next(tester).onPressed, isNull, reason: 'التأكيدُ لا يطابق');

      await tester.enterText(
          find.byKey(const Key('setup_dev_password_confirm')), 'dev1');
      await tester.pump();
      expect(_next(tester).onPressed, isNotNull);
      expect(find.byKey(const Key('setup_admin_strength')), findsOneWidget);
      await _teardown(tester);
    });

    testWidgets('الخطواتُ الاختياريّةُ تُتخطّى — الصناديقُ ثمّ الدليلُ ثمّ المنتجات',
        (tester) async {
      await _pump(tester, step: SetupStepIds.cashBanks);
      for (final expected in [
        SetupStepIds.chartOfAccounts,
        SetupStepIds.users,
      ]) {
        await tester.tap(find.byKey(const Key('setup_skip_step')));
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)));
        await tester.pump();
        expect(find.text(kSetupSteps[expected]!.title), findsWidgets);
      }
      await _teardown(tester);

      await _pump(tester, step: SetupStepIds.products);
      await tester.tap(find.byKey(const Key('setup_skip_step')));
      await tester.pump();
      expect(find.text(kSetupSteps[SetupStepIds.review]!.title), findsWidgets);
      await _teardown(tester);
    });
  });

  group('المراجعة والتشغيل', () {
    /// يملأ الإلزاميَّ كلَّه ماشياً خطوةً خطوةً حتّى المراجعة.
    Future<void> walkToReview(WidgetTester tester) async {
      await tester.enterText(
          find.byKey(const Key('setup_company_name')), 'شركة النيل');
      await tester.enterText(find.byKey(const Key('setup_tax_number')), '998877');
      await tester.pump();
      Future<void> next() async {
        await tester.tap(find.byKey(const Key('setup_next')));
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)));
        await tester.pump();
      }

      await next(); // ← العملة والضريبة
      await tester.tap(find.byKey(const Key('setup_currency_JOD')));
      await tester.pump();
      await next(); // ← الفرع
      await tester.enterText(find.byKey(const Key('setup_branch_code')), 'AMM');
      await next(); // ← الصناديق
      await next(); // ← الدليل
      await next(); // ← المستخدمون
      await tester.enterText(
          find.byKey(const Key('setup_admin_password')), 'Strong-123');
      await tester.enterText(
          find.byKey(const Key('setup_admin_password_confirm')), 'Strong-123');
      await tester.enterText(find.byKey(const Key('setup_dev_password')), 'dev1');
      await tester.enterText(
          find.byKey(const Key('setup_dev_password_confirm')), 'dev1');
      await tester.pump();
      await next(); // ← المنتجات
      await next(); // ← المراجعة
      expect(find.text(kSetupSteps[SetupStepIds.review]!.title), findsWidgets);
    }

    testWidgets('الملخّصُ يعرض الاختيارات و«تعديل» يفتح الخطوةَ ويعود',
        (tester) async {
      await _pump(tester, step: SetupStepIds.company);
      await walkToReview(tester);

      for (final s in setupStepOrderFor(SetupDeploymentMode.standalone)) {
        if (s == SetupStepIds.review) continue;
        expect(find.byKey(Key('setup_review_card_$s')), findsOneWidget,
            reason: 'بطاقةُ الخطوة $s غائبة');
      }
      expect(find.text('شركة النيل'), findsOneWidget);
      expect(find.text('998877'), findsOneWidget);
      expect(find.text('JOD'), findsOneWidget);
      // العملةُ تضبط النسبةَ افتراضيّاً: JOD ⇒ ١٦٪.
      expect(find.text('16%'), findsOneWidget);
      expect(find.text('AMM'), findsOneWidget);
      expect(tester.takeException(), isNull);

      // «تعديل» على الفرع ⇒ خطوةُ الفرع، وزرُّ العودة إلى المراجعة.
      const editBranch =
          Key('setup_review_edit_${SetupStepIds.branchAndMode}');
      await tester.ensureVisible(find.byKey(editBranch));
      await tester.tap(find.byKey(editBranch));
      await tester.pump();
      expect(find.text(kSetupSteps[SetupStepIds.branchAndMode]!.title),
          findsWidgets);
      expect(find.text('العودة إلى المراجعة'), findsOneWidget);

      await tester.enterText(find.byKey(const Key('setup_branch_code')), 'IRB');
      await tester.tap(find.byKey(const Key('setup_next')));
      await tester.pump();
      expect(find.text(kSetupSteps[SetupStepIds.review]!.title), findsWidgets);
      expect(find.text('IRB'), findsOneWidget);
      await _teardown(tester);
    });

    testWidgets('الفشلُ يعرض المرحلةَ وسببَها — والإعادةُ تبدأ من الأوّل',
        (tester) async {
      final fake = _FailingPersistence();
      await _pump(tester, step: SetupStepIds.company, persistence: fake);
      await walkToReview(tester);

      await tester.tap(find.byKey(const Key('setup_finish')));
      await tester.pump();
      await tester.pump();
      expect(fake.runs, 1);
      expect(find.byKey(const Key('setup_run_error')), findsOneWidget);
      // السببُ قابلٌ للنسخ (`SelectableText`) — يُلصَق في بلاغ الدعم.
      expect(
        find.byWidgetPredicate(
            (w) => w is SelectableText && (w.data ?? '').contains('disk full')),
        findsOneWidget,
      );
      expect(
        find.text(tr('فشلت مرحلة: {p0}', {'p0': SetupRunStage.tax.label})),
        findsOneWidget,
      );
      // لا علامةَ اكتمال — الإعدادُ لم يُعلَّم مكتملاً.
      expect(fake.keys, isNot(contains('setup_completed')));

      await tester.ensureVisible(find.byKey(const Key('setup_retry')));
      await tester.tap(find.byKey(const Key('setup_retry')));
      await tester.pump();
      await tester.pump();
      expect(fake.runs, 2, reason: 'الإعادةُ تبدأ من الأوّل');
      expect(find.byType(SetupWizardScreen), findsOneWidget,
          reason: 'لا دخولَ إلى النظام على قاعدةٍ نصفِ مهيّأة');
      await tester.pump(const Duration(seconds: 5));
      await _teardown(tester);
    });
  });
}
