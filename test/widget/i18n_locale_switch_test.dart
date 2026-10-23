import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:picpos_erp/core/i18n/locale_provider.dart';
import 'package:picpos_erp/core/i18n/tr.dart';
import 'package:picpos_erp/core/permissions/permission_codes.dart';
import 'package:picpos_erp/core/theme/app_theme.dart';
import 'package:picpos_erp/data/providers/providers.dart';
import 'package:picpos_erp/presentation/pos/providers/cfd_controller.dart';
import 'package:picpos_erp/presentation/shell/app_shell.dart';
import 'package:picpos_erp/presentation/shell/screen_tabs_bar.dart';
import 'package:picpos_erp/presentation/widgets/user_language_selector.dart';

class _LocaleHarness extends ConsumerWidget {
  const _LocaleHarness();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(userLocaleProvider);
    return MaterialApp(
      locale: locale,
      supportedLocales: const [defaultUserLocale, englishUserLocale],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: const Scaffold(body: _NavHome()),
    );
  }
}

class _NavHome extends ConsumerWidget {
  const _NavHome();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(userLocaleProvider);
    return Column(
      children: [
        Text(tr('البيع السريع')),
        const UserLanguageSelector(),
      ],
    );
  }
}

class _TestAuthNotifier extends AuthNotifier {
  @override
  AuthState build() => const AuthState(isAuthenticated: true);
}

class _TestCfdController extends CfdController {
  @override
  void build() {}
}

class _TestThemeModeNotifier extends ThemeModeNotifier {
  @override
  ThemeMode build() => ThemeMode.light;
}

class _TestLocaleNotifier extends UserLocaleNotifier {
  @override
  Locale build() => defaultUserLocale;

  @override
  Future<void> setLocale(Locale locale) async {
    final normalized = localeForCode(locale.languageCode);
    state = normalized;
    I18nCatalog.setLocale(normalized);
  }
}

List<NavItemDef> _testNavItems() => const [
      NavItemDef(
        icon: PhosphorIconsBold.shoppingCart,
        label: 'المبيعات',
        index: 0,
        group: 'sales',
      ),
      NavItemDef(
        icon: PhosphorIconsBold.receipt,
        label: 'المشتريات',
        index: 1,
        group: 'purchases',
      ),
      NavItemDef(
        icon: PhosphorIconsBold.gear,
        label: 'اعداد النظام',
        index: 13,
        group: 'system',
      ),
    ];

Widget _realShellTestApp() {
  const description =
      'الطرقُ المؤشَّرة وحدَها تظهر للكاشير عند إتمام الدفع — والصلاحياتُ تضيّق عليها ولا توسّعها.';
  return ProviderScope(
    overrides: [
      userLocaleProvider.overrideWith(_TestLocaleNotifier.new),
      cfdControllerProvider.overrideWith(_TestCfdController.new),
      authProvider.overrideWith(_TestAuthNotifier.new),
      userNavItemsProvider.overrideWith((ref) async => _testNavItems()),
      currentUserPermissionsProvider.overrideWith(
        (ref) async => [PermissionCodes.posAccess],
      ),
      userRoleProvider.overrideWith((ref) async => null),
      showTopBarProvider.overrideWith((ref) async => true),
      themeModeProvider.overrideWith(_TestThemeModeNotifier.new),
    ],
    child: MaterialApp(
      theme: AppTheme.lightTheme,
      locale: defaultUserLocale,
      supportedLocales: const [defaultUserLocale, englishUserLocale],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: AppShell(
        currentIndex: 13,
        onNavigate: (_) {},
        tabs: const [
          ScreenTabView(
            index: 13,
            label: 'الإعدادات',
            icon: PhosphorIconsBold.gear,
          ),
        ],
        onSelectTab: (_) {},
        onCloseTab: (_) {},
        child: Center(
          child: Consumer(
            builder: (context, ref, _) {
              ref.watch(userLocaleProvider);
              return Text(tr(description));
            },
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('switching a user to English renders nav text LTR',
      (tester) async {
    I18nCatalog.setCatalog({
      'البيع السريع': 'Quick Sale',
      'لغة الواجهة': 'Interface language',
      'تُحفظ لكل مستخدم وتغيّر اتجاه الشاشة تلقائياً':
          'Saved per user and changes screen direction automatically',
      'العربية': 'Arabic',
    });
    I18nCatalog.setLocale(defaultUserLocale);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [userLocaleProvider.overrideWith(_TestLocaleNotifier.new)],
        child: const _LocaleHarness(),
      ),
    );

    final container = ProviderScope.containerOf(
      tester.element(find.byType(_LocaleHarness)),
    );
    await container
        .read(userLocaleProvider.notifier)
        .setLocale(englishUserLocale);
    await tester.pump();

    expect(find.text('Quick Sale'), findsOneWidget);
    final directionality = tester.widget<Directionality>(
      find.ancestor(
        of: find.text('Quick Sale'),
        matching: find.byType(Directionality),
      ).first,
    );
    expect(directionality.textDirection, TextDirection.ltr);
  });

  testWidgets('English locale translates the real shell and keeps it LTR',
      (tester) async {
    I18nCatalog.setCatalog({
      'العربية': 'Arabic',
      'المبيعات': 'Sales',
      'المشتريات': 'Purchases',
      'اعداد النظام': 'System Settings',
      'الفروع والمخازن': 'Branches & Warehouses',
      'الإعدادات': 'Settings',
      'الطرقُ المؤشَّرة وحدَها تظهر للكاشير عند إتمام الدفع — والصلاحياتُ تضيّق عليها ولا توسّعها.':
          'Only selected payment methods appear to cashiers at checkout — permissions can narrow this list, not expand it.',
      'English': 'English',
      'البيع السريع': 'Quick Sale',
      'الشاشة الأولى': 'Home',
      'ابحث عن شاشة أو ما بداخلها…': 'Search screens or their content…',
      'مسح البحث': 'Clear search',
      'الوضع الداكن': 'Dark Mode',
      'الوضع الفاتح': 'Light Mode',
      'إخفاء': 'Hide',
      'إغلاق': 'Close',
      'تسجيل الخروج': 'Log out',
      'خروج': 'Exit',
      'الذهاب إلى البيع السريع': 'Go to Quick Sale',
    });
    I18nCatalog.setLocale(defaultUserLocale);
    await tester.pumpWidget(_realShellTestApp());
    await tester.pump(const Duration(milliseconds: 300));

    final shellDirection = tester.widget<Directionality>(
      find.descendant(
        of: find.byType(AppShell),
        matching: find.byType(Directionality),
      ).first,
    );
    expect(shellDirection.textDirection, TextDirection.rtl);

    final brand = tester.getRect(find.byKey(const ValueKey('picposSidebarBrand')));
    final pos =
        tester.getRect(find.byKey(const ValueKey('picposSidebarPosShortcut')));
    expect(brand.overlaps(pos), isFalse);

    await tester.tap(find.text('English'));
    await tester.pump(const Duration(milliseconds: 300));

    expect(I18nCatalog.activeLocale, englishUserLocale);
    expect(find.text('Sales'), findsWidgets);
    expect(find.text('Purchases'), findsWidgets);
    expect(find.text('System Settings'), findsWidgets);
    expect(find.text('Branches & Warehouses'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);
    expect(find.textContaining('Only selected payment methods'), findsOneWidget);
    final ltrDirection = tester.widget<Directionality>(
      find.descendant(
        of: find.byType(AppShell),
        matching: find.byType(Directionality),
      ).first,
    );
    expect(ltrDirection.textDirection, TextDirection.ltr);

    expect(find.text('المبيعات'), findsNothing);
    expect(find.text('المشتريات'), findsNothing);
    expect(find.text('اعداد النظام'), findsNothing);
    expect(find.textContaining('الطرقُ المؤشَّرة'), findsNothing);
    expect(find.text('Arabic'), findsOneWidget);
  });
}
