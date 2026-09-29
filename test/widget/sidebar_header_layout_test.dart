import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:ural_erp/core/enums/app_screen.dart';
import 'package:ural_erp/core/i18n/locale_provider.dart';
import 'package:ural_erp/core/i18n/tr.dart';
import 'package:ural_erp/core/permissions/permission_codes.dart';
import 'package:ural_erp/core/theme/app_theme.dart';
import 'package:ural_erp/data/providers/providers.dart';
import 'package:ural_erp/presentation/pos/providers/cfd_controller.dart';
import 'package:ural_erp/presentation/shell/app_shell.dart';
import 'package:ural_erp/presentation/shell/screen_tabs_bar.dart';

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
  _TestLocaleNotifier(this.initialLocale);

  final Locale initialLocale;

  @override
  Locale build() {
    I18nCatalog.setLocale(initialLocale);
    return initialLocale;
  }

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
    ];

Widget _shellApp({
  required Locale locale,
  required void Function(int) onNavigate,
}) {
  return ProviderScope(
    overrides: [
      userLocaleProvider.overrideWith(
        () => _TestLocaleNotifier(locale),
      ),
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
      locale: locale,
      supportedLocales: const [defaultUserLocale, englishUserLocale],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: AppShell(
        currentIndex: AppScreen.settings.value,
        onNavigate: onNavigate,
        tabs: const [
          ScreenTabView(
            index: 12,
            label: 'الإعدادات',
            icon: PhosphorIconsBold.gear,
          ),
        ],
        onSelectTab: (_) {},
        onCloseTab: (_) {},
        child: const SizedBox.shrink(),
      ),
    ),
  );
}

Future<void> _pumpShell(
  WidgetTester tester, {
  required double width,
  required Locale locale,
  required void Function(int) onNavigate,
}) async {
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    _shellApp(locale: locale, onNavigate: onNavigate),
  );
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  setUp(() {
    I18nCatalog.setCatalog({
      'المبيعات': 'Sales',
      'المشتريات': 'Purchases',
      'الإعدادات': 'Settings',
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
  });

  tearDown(() {
    I18nCatalog.setCatalog(const {});
    I18nCatalog.setLocale(defaultUserLocale);
  });

  for (final locale in [defaultUserLocale, englishUserLocale]) {
    for (final width in [240.0, 300.0]) {
      testWidgets(
        'sidebar header stays separated and navigates at '
        '${locale.languageCode} and ${width.toInt()}px',
        (tester) async {
          int? navigatedTo;
          await _pumpShell(
            tester,
            width: width,
            locale: locale,
            onNavigate: (index) => navigatedTo = index,
          );

          final brand = tester.getRect(
            find.byKey(const ValueKey('picposSidebarBrand')),
          );
          final shortcut = tester.getRect(
            find.byKey(const ValueKey('picposSidebarPosShortcut')),
          );
          expect(brand.overlaps(shortcut), isFalse);
          if (locale.languageCode == 'ar') {
            expect(shortcut.right, lessThanOrEqualTo(brand.left));
          } else {
            expect(shortcut.left, greaterThanOrEqualTo(brand.right));
          }

          await tester.tap(
            find.byKey(const ValueKey('picposSidebarPosShortcut')),
          );
          await tester.pump();
          expect(navigatedTo, AppScreen.pos.value);
        },
      );
    }
  }
}
