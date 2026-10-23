import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/app_main_screen.dart';
import 'package:picpos_erp/core/config/app_config.dart';
import 'package:picpos_erp/core/config/brand.dart';
import 'package:picpos_erp/core/config/business_profile_provider.dart';
import 'package:picpos_erp/core/enums/app_screen.dart';
import 'package:picpos_erp/core/i18n/locale_provider.dart';
import 'package:picpos_erp/core/i18n/tr.dart';
import 'package:picpos_erp/data/providers/guest_order_requests_provider.dart';
import 'package:picpos_erp/data/providers/providers.dart';
import 'package:picpos_erp/data/providers/screen_navigation_provider.dart';
import 'package:picpos_erp/domain/models/picpos_booking_view.dart';
import 'package:picpos_erp/l10n/app_localizations.dart';
import 'package:picpos_erp/presentation/pos/providers/cfd_controller.dart';
import 'package:picpos_erp/presentation/bookings_picpos/widgets/bookings_destination_tabs.dart';
import 'package:picpos_erp/presentation/picpos_shell/picpos_report_tabs.dart';
import 'package:picpos_erp/presentation/settings_picpos/widgets/settings_nav_rail.dart';
import 'package:picpos_erp/presentation/treasury_picpos/widgets/treasury_tab_bar_picpos.dart';
import 'package:picpos_erp/core/theme/app_theme.dart';

final _arabicLetters = RegExp(r'[\u0600-\u06FF]');

/// The language picker intentionally keeps this source-language option visible.
const _documentedArabicAllowlist = {'العربية'};

class _SweepLocaleNotifier extends UserLocaleNotifier {
  @override
  Locale build() => englishUserLocale;

  @override
  Future<void> setLocale(Locale locale) async {
    final normalized = localeForCode(locale.languageCode);
    state = normalized;
    I18nCatalog.setLocale(normalized);
  }
}

class _SweepThemeModeNotifier extends ThemeModeNotifier {
  @override
  ThemeMode build() => ThemeMode.light;
}

class _SweepCfdController extends CfdController {
  @override
  void build() {}
}

class _SweepBusinessProfileNotifier extends BusinessProfileNotifier {
  @override
  BusinessProfile build() => BusinessProfile.unified;
}

class _SweepAuthNotifier extends AuthNotifier {
  @override
  AuthState build() {
    final now = DateTime.now();
    final role = Role(
      id: 1,
      name: 'مدير النظام',
      isSystemRole: true,
      createdAt: now,
      rowVersion: 1,
    );
    final user = User(
      id: 1,
      username: 'admin',
      passwordHash: '',
      passwordSalt: '',
      displayName: 'مدير النظام',
      roleId: role.id,
      defaultScreen: '0',
      isLocked: false,
      isActive: true,
      discountLimitIsPercent: true,
      forcePasswordChange: false,
      createdAt: now,
      rowVersion: 1,
    );
    return AuthState(
      userWithRole: UserWithRole(user: user, role: role),
      isAuthenticated: true,
      loginTime: now,
      lastActivity: now,
    );
  }
}

const _fixtureArabicText = <String>{
  'حسابي الخاص',
  'منتج تجريبي',
};

Future<void> _insertUserDataFixture(AppDatabase db) async {
  await db.into(db.accounts).insert(
        AccountsCompanion.insert(
          code: '999999',
          name: 'حسابي الخاص',
          accountType: 'asset',
        ),
      );
  await db.into(db.products).insert(
        ProductsCompanion.insert(
          code: 'I18N-USER-1',
          name: 'منتج تجريبي',
        ),
      );
}

void _collectArabicStrings(
  Element root,
  Set<String> result,
  Set<String> dataAllowlist,
) {
  void add(String? value) {
    if (value == null || value.isEmpty || !_arabicLetters.hasMatch(value)) {
      return;
    }
    if (!dataAllowlist.contains(value) &&
        !_documentedArabicAllowlist.contains(value)) {
      result.add(value);
    }
  }

  void visit(Element element) {
    final widget = element.widget;
    if (widget is Offstage && widget.offstage) return;
    if (widget is IndexedStack) {
      var childIndex = 0;
      element.visitChildElements((child) {
        if (childIndex++ == widget.index) visit(child);
      });
      return;
    }

    if (widget is Text) {
      add(widget.data);
      add(widget.textSpan?.toPlainText());
    } else if (widget is RichText) {
      add(widget.text.toPlainText());
    } else if (widget is EditableText) {
      add(widget.controller.text);
    } else if (widget is InputDecorator) {
      add(widget.decoration.labelText);
      add(widget.decoration.hintText);
      add(widget.decoration.helperText);
      add(widget.decoration.errorText);
      add(widget.decoration.prefixText);
      add(widget.decoration.suffixText);
    } else if (widget is Tooltip) {
      add(widget.message);
    }
    element.visitChildElements(visit);
  }

  visit(root);
}

String _screenName(AppScreen screen) => screen.name;

void _writeSweepReport({
  required Map<String, int> initialCounts,
  required Map<String, Set<String>> findings,
  required int screenCount,
  required int dialogCount,
  List<String> skippedSurfaces = const [],
}) async {
  final buffer = StringBuffer()
    ..writeln('English i18n sweep report')
    ..writeln('Brand: ${Brand.id}')
    ..writeln('Screens covered: $screenCount')
    ..writeln('Dialogs/forms covered: $dialogCount')
    ..writeln('Optional surfaces not reachable: ${skippedSurfaces.length}'
        '${skippedSurfaces.isEmpty ? '' : ' (${skippedSurfaces.join(', ')})'}')
    ..writeln('Initial offending counts per screen:');
  for (final screen in AppScreen.values) {
    final name = _screenName(screen);
    buffer.writeln('  $name: ${initialCounts[name] ?? 0}');
  }
  buffer.writeln('Final findings (screen/form → offending strings):');
  final names = <String>{
    ...AppScreen.values.map(_screenName),
    ...findings.keys,
  }.toList()..sort();
  for (final name in names) {
    final values = findings[name] ?? const <String>{};
    buffer.writeln('$name:');
    for (final value in values.toList()..sort()) {
      buffer.writeln('  - $value');
    }
  }
  final report = File('build/i18n_sweep_report.txt');
  report.parent.createSync(recursive: true);
  report.writeAsStringSync(buffer.toString());
}

void _drainExpectedLayoutErrors(WidgetTester tester) {
  Object? exception;
  while ((exception = tester.takeException()) != null) {
    final text = '$exception';
    if (!text.contains('overflow') &&
        !text.contains('RenderFlex') &&
        !text.contains('was not laid out') &&
        !text.contains('_needsLayout') &&
        !text.contains('Multiple exceptions')) {
      throw TestFailure('Unexpected widget exception: $text');
    }
  }
}

Future<bool> _tapIfPresent(WidgetTester tester, Finder finder) async {
  if (finder.evaluate().isEmpty) return false;
  final target = finder.last;
  // A surface whose layout failed (reported by the layout suites) cannot be
  // hit-tested; its text was still scanned through the element tree.
  final renderObject = tester.renderObject(target);
  if (renderObject is RenderBox && !renderObject.hasSize) return false;
  await tester.ensureVisible(target);
  await tester.tap(target, warnIfMissed: false);
  await tester.pump();
  _drainExpectedLayoutErrors(tester);
  return true;
}

Future<Set<String>> _scanMaterialApp(
  WidgetTester tester,
  Set<String> seededText,
) async {
  final app = find.byType(MaterialApp, skipOffstage: false);
  if (app.evaluate().isEmpty) return <String>{};
  await tester.pump();
  _drainExpectedLayoutErrors(tester);
  final result = <String>{};
  _collectArabicStrings(tester.element(app.first), result, seededText);
  return result;
}

Future<void> _dismissOpenedSurface(WidgetTester tester) async {
  final cancel = find.text(tr('إلغاء'));
  if (cancel.evaluate().isNotEmpty) {
    await tester.tap(cancel.last);
    await tester.pump();
    _drainExpectedLayoutErrors(tester);
    return;
  }
  if (tester.binding.focusManager.primaryFocus != null) {
    tester.binding.focusManager.primaryFocus!.unfocus();
  }
  final navigator = find.byType(Navigator);
  if (navigator.evaluate().isEmpty) return;
  final state = tester.state<NavigatorState>(navigator.last);
  if (state.canPop()) {
    await state.maybePop();
    await tester.pump();
    _drainExpectedLayoutErrors(tester);
  }
}

void main() {
  testWidgets('English renders every registered screen without Arabic UI text',
      (tester) async {
    // Desktop window size: the POS and report layouts target Windows desktops.
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final db = AppDatabase.forTesting();
    await tester.runAsync(() => db.getBranches());
    await tester.runAsync(() => _insertUserDataFixture(db));
    const seededText = _fixtureArabicText;
    final allScreenIndexes = [
      for (final screen in AppScreen.values) screen.value,
    ];
    final allPermissions = <String>['system_admin'];

    AppConfig.updateProfile(BusinessProfile.unified);
    AppConfig.updateFeatures(FeaturePolicy.fromProfile(BusinessProfile.unified));
    I18nCatalog.setLocale(englishUserLocale);
    final catalog = jsonDecode(
      File('assets/i18n/en.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    I18nCatalog.setCatalog({
      for (final entry in catalog.entries)
        if (entry.value is String) entry.key: entry.value as String,
    });

    final findings = <String, Set<String>>{};
    final initialCounts = <String, int>{};
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          authProvider.overrideWith(_SweepAuthNotifier.new),
          userLocaleProvider.overrideWith(_SweepLocaleNotifier.new),
          themeModeProvider.overrideWith(_SweepThemeModeNotifier.new),
          cfdControllerProvider.overrideWith(_SweepCfdController.new),
          businessProfileProvider
              .overrideWith(_SweepBusinessProfileNotifier.new),
          userAllowedScreensProvider
              .overrideWith((ref) async => allScreenIndexes),
          userNavItemsProvider
              .overrideWith((ref) async => kAllNavItemDefs),
          currentUserPermissionsProvider
              .overrideWith((ref) async => allPermissions),
          userRoleProvider.overrideWith((ref) async => null),
          // No server in widget tests: the client poller would keep a timer.
          guestOrderRequestsProvider.overrideWith(
            (ref) => Stream.value(const []),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          locale: englishUserLocale,
          supportedLocales: const [defaultUserLocale, englishUserLocale],
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: const MainScreen(),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));
    // Resolve the shell once: onstage finders walk viewports, and a screen with
    // a (separately covered) layout failure leaves slivers without geometry.
    final mainScreenElement = tester.element(find.byType(MainScreen));
    final container = ProviderScope.containerOf(mainScreenElement);

    final initialDashboardFindings = <String>{};
    _collectArabicStrings(
      mainScreenElement,
      initialDashboardFindings,
      seededText,
    );
    initialCounts['dashboard'] = initialDashboardFindings.length;
    findings['dashboard'] = initialDashboardFindings;
    _drainExpectedLayoutErrors(tester);

    for (final screen in AppScreen.values.skip(1)) {
      final name = _screenName(screen);
      container.read(screenNavigationProvider.notifier).open(screen.value);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      final screenFindings = <String>{};
      _collectArabicStrings(
        mainScreenElement,
        screenFindings,
        seededText,
      );
      initialCounts[name] = screenFindings.length;
      findings[name] = screenFindings;
      _drainExpectedLayoutErrors(tester);
      _writeSweepReport(
        initialCounts: initialCounts,
        findings: findings,
        screenCount: AppScreen.values.length,
        dialogCount: 0,
      );
    }

    var dialogCount = 0;
    final skippedSurfaces = <String>[];
    Future<void> scanSurface(String name) async {
      findings[name] = await _scanMaterialApp(tester, seededText);
      dialogCount++;
      _writeSweepReport(
        initialCounts: initialCounts,
        findings: findings,
        screenCount: AppScreen.values.length,
        dialogCount: dialogCount,
        skippedSurfaces: skippedSurfaces,
      );
    }

    Future<void> openScreen(AppScreen screen) async {
      container.read(screenNavigationProvider.notifier).open(screen.value);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      _drainExpectedLayoutErrors(tester);
    }

    Future<void> scanButtonSurface(String name, Finder finder) async {
      if (!await _tapIfPresent(tester, finder)) {
        skippedSurfaces.add(name);
        return;
      }
      await scanSurface(name);
      await _dismissOpenedSurface(tester);
    }

    Future<void> scanRequiredSurface(String name, Finder finder) async {
      expect(finder, findsWidgets, reason: 'Required sweep surface: $name');
      expect(await _tapIfPresent(tester, finder), isTrue);
      await scanSurface(name);
      await _dismissOpenedSurface(tester);
    }

    if (Brand.isPicPos) {
      await openScreen(AppScreen.treasury);
      final treasuryTabs = find.byType(TreasuryTabBarPicpos);
      expect(treasuryTabs, findsOneWidget);
      final treasuryTabBar = tester.widget<TreasuryTabBarPicpos>(treasuryTabs);
      treasuryTabBar.controller.animateTo(3);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(treasuryTabBar.controller.index, 3);
      await scanSurface('treasury daily closing tab');
      final treasurySearch = find.descendant(
        of: treasuryTabs,
        matching: find.byType(TextField),
      );
      expect(treasurySearch, findsOneWidget);
      await tester.enterText(treasurySearch, 'cash');
      await tester.pump();
      await scanSurface('treasury daily closing search');
    }

    await openScreen(AppScreen.commercialPapers);
    final incomingTab = find.text(tr('الواردة'));
    expect(incomingTab, findsWidgets);
    expect(await _tapIfPresent(tester, incomingTab), isTrue);
    await scanSurface('cheques incoming tab');

    await openScreen(AppScreen.fiscalYear);
    await scanSurface('fiscal years list');

    await openScreen(AppScreen.chartOfAccounts);
    final expandAll = find.text(tr('توسيع الكل'));
    expect(expandAll, findsOneWidget);
    expect(await _tapIfPresent(tester, expandAll), isTrue);
    await tester.pump();
    expect(find.text('حسابي الخاص'), findsOneWidget,
        reason: 'User-entered Arabic account names must remain unchanged');
    await scanSurface('chart of accounts expanded');

    await openScreen(AppScreen.trialBalance);
    await scanSurface('trial balance');

    await openScreen(AppScreen.templateResolution);
    await scanSurface('template resolution');

    // Report cards live in lazily built, category-scoped panes; the report
    // search lists every entry regardless of category or scroll position.
    Future<void> scanReport(String name, String arabicTitle) async {
      await openScreen(AppScreen.reports);
      final search = find.byWidgetPredicate(
        (widget) =>
            widget is TextField &&
            widget.decoration?.hintText == tr('بحث في جميع التقارير...'),
      );
      expect(search, findsOneWidget, reason: 'Reports search field');
      await tester.enterText(search, tr(arabicTitle));
      await tester.pump();
      _drainExpectedLayoutErrors(tester);
      await scanRequiredSurface(name, find.text(tr(arabicTitle)));
      await openScreen(AppScreen.reports);
      if (search.evaluate().isNotEmpty) {
        await tester.enterText(search, '');
        await tester.pump();
        _drainExpectedLayoutErrors(tester);
      }
    }

    await scanReport('tables report', 'تقرير الطاولات');
    await scanReport(
      'inventory reconciliation dialog',
      'تسوية المخزون مع الأستاذ العام',
    );
    await scanReport('VAT settlement report', 'تسوية ضريبة القيمة المضافة');

    await openScreen(AppScreen.salesInvoices);
    await scanButtonSurface('new sales invoice', find.text(tr('فاتورة جديدة')));
    await openScreen(AppScreen.purchases);
    await scanButtonSurface('new purchase invoice', find.text(tr('فاتورة جديدة')));
    await openScreen(AppScreen.importPurchases);
    await scanButtonSurface('import purchase', find.byKey(const Key('import_new_invoice')));
    await openScreen(AppScreen.salesReturns);
    // J2: في PicPos المدخلُ سجلُّ المرتجعات و«جديد» يفتح الاستمارة (حوارُ
    // «سجل المرتجعات» حُذف)؛ وذراعُ UralCash على حوارها كما هو.
    await scanButtonSurface(
      Brand.isPicPos ? 'new sales return' : 'sales return history dialog',
      Brand.isPicPos
          ? find.byKey(const Key('return_records_new'))
          : find.text(tr('سجل المرتجعات')),
    );
    await openScreen(AppScreen.pos);
    await scanButtonSurface('sales return form', find.text(tr('مرتجع سريع')));
    await openScreen(AppScreen.purchaseReturns);
    await scanButtonSurface('new purchase return', find.byKey(const Key('return_records_new')));
    await openScreen(AppScreen.receiptVoucher);
    await scanButtonSurface('receipt voucher form', find.byKey(const Key('voucher_records_new')));
    await openScreen(AppScreen.paymentVoucher);
    await scanButtonSurface('payment voucher form', find.byKey(const Key('voucher_records_new')));

    await openScreen(AppScreen.bookings);
    final bookingTabs = find.byType(BookingsDestinationTabs);
    for (final destination in BookingsDestination.values) {
      final tab = find.descendant(
        of: bookingTabs,
        matching: find.text(tr(destination.label)),
      );
      if (await _tapIfPresent(tester, tab)) {
        await scanSurface('bookings ${destination.name} tab');
      }
    }

    await openScreen(AppScreen.settings);
    final settingsNav = find.byType(SettingsNavRail);
    for (final title in const [
      'النظام والمظهر',
      'الأجهزة والطباعة',
      'البيع السريع',
      'المستخدمون والأمان',
      'الأجهزة المرتبطة',
      'ربط التطبيقات والأجهزة',
      'حماية الأقسام',
      'المالية والمحاسبة',
      'شؤون الموظفين',
      'إدارة البيانات',
      'التكاملات والخدمات',
      'عن البرنامج',
    ]) {
      final navItem = find.descendant(
        of: settingsNav,
        matching: find.text(tr(title)),
      );
      final opened = await _tapIfPresent(tester, navItem);
      if (Brand.isPicPos &&
          const {
            'ربط التطبيقات والأجهزة',
            'المالية والمحاسبة',
            'التكاملات والخدمات',
            'عن البرنامج',
          }.contains(title)) {
        expect(opened, isTrue, reason: 'Required settings section: $title');
      }
      if (opened) await scanSurface('settings $title');
    }

    await openScreen(AppScreen.manufacturing);
    final manufacturingTabs = find.byType(PicPosReportTabs);
    for (final title in const [
      'قوائم المكوّنات',
      'أوامر الإنتاج',
      'التشفية',
      'التكاليف الإضافية',
      'التقارير',
    ]) {
      final tab = find.descendant(
        of: manufacturingTabs,
        matching: find.text(tr(title)),
      );
      if (await _tapIfPresent(tester, tab)) {
        await scanSurface('manufacturing $title');
      }
    }

    await openScreen(AppScreen.parties);
    await scanButtonSurface('party add dialog', find.text(tr('إضافة')));
    await openScreen(AppScreen.products);
    await scanButtonSurface('product add dialog', find.text(tr('إضافة صنف')));

    _writeSweepReport(
      initialCounts: initialCounts,
      findings: findings,
      screenCount: AppScreen.values.length,
      dialogCount: dialogCount,
      skippedSurfaces: skippedSurfaces,
    );

    // Layout exceptions are reported by the existing widget/structural suites;
    // this sweep asserts only the localization contract across every screen.
    final offending = findings.values.expand((values) => values).toSet();
    // Flush deferred startup timers before the widget-test invariant check.
    await tester.pump(const Duration(seconds: 2));
    _drainExpectedLayoutErrors(tester);
    await tester.pumpWidget(const SizedBox.shrink());
    // Provider disposal schedules its own short timers; let them run out.
    await tester.pump(const Duration(minutes: 2));
    _drainExpectedLayoutErrors(tester);
    expect(offending, isEmpty,
        reason: 'See build/i18n_sweep_report.txt for screen → offending strings');
  });
}
