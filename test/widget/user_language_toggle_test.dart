import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:picpos_erp/core/enums/app_screen.dart';
import 'package:picpos_erp/core/i18n/locale_provider.dart';
import 'package:picpos_erp/core/i18n/tr.dart';
import 'package:picpos_erp/core/permissions/permission_codes.dart';
import 'package:picpos_erp/core/theme/app_theme.dart';
import 'package:picpos_erp/data/providers/providers.dart';
import 'package:picpos_erp/domain/repositories/settings_repository.dart';
import 'package:picpos_erp/presentation/pos/providers/cfd_controller.dart';
import 'package:picpos_erp/presentation/screens/login_screen.dart';
import 'package:picpos_erp/presentation/shell/app_shell.dart';
import 'package:picpos_erp/presentation/shell/screen_tabs_bar.dart';
import 'package:picpos_erp/presentation/widgets/user_language_selector.dart';
import 'package:picpos_erp/presentation/widgets/notifications/providers/notification_provider.dart';

class _MemorySettingsRepository implements ISettingsRepository {
  final values = <String, String>{};

  @override
  Future<List<String>> getAvailableBackups() async => [];

  @override
  Future<String?> createBackup() async => null;

  @override
  Future<bool> deleteBackup(String path) async => false;

  @override
  Future<bool> exportBackup(String destinationFolder) async => false;

  @override
  Future<Map<String, dynamic>> getBackupStats() async => {};

  @override
  Future<Map<String, String>> getAllSettings() async => values;

  @override
  Future<String?> getSetting(String key) async => values[key];

  @override
  Future<Map<String, dynamic>> getReceiptSettings() async => {};

  @override
  Future<bool> restoreBackup(String path) async => false;

  @override
  Future<void> saveCompanyInfo({
    required String name,
    String? phone,
    String? address,
    String? taxId,
  }) async {}

  @override
  Future<void> saveReceiptSettings({
    String? companyName,
    String? companyAddress,
    String? companyPhone,
    String? companyPhone2,
    String? companyEmail,
    String? taxNumber,
    String? headerText,
    String? footerText,
    String? termsText,
    dynamic logoImage,
    bool? showLogo,
    bool? showQrCode,
    bool? showBarcode,
    bool? showTaxDetails,
    bool? showItemCode,
    bool? showSalesperson,
    bool? showCustomerInfo,
    int? headerFontSize,
    int? bodyFontSize,
    int? footerFontSize,
    int? paperWidth,
    String? currencySymbol,
  }) async {}

  @override
  Future<void> saveSetting(String key, String value) async {
    values[key] = value;
  }

  @override
  Stream<dynamic> watchReceiptSettings() => const Stream.empty();

  @override
  Stream<String?> watchSettingValue(String key) => Stream.value(values[key]);
}

const _testUserId = 42;

class _SignedInAuth extends AuthNotifier {
  @override
  AuthState build() => AuthState(
        isAuthenticated: true,
        userWithRole: UserWithRole(
          user: User(
            id: _testUserId,
            username: 'language-test',
            passwordHash: '',
            passwordSalt: '',
            displayName: 'Language Tester',
            defaultScreen: '0',
            isLocked: false,
            isActive: true,
            discountLimitIsPercent: true,
            forcePasswordChange: false,
            createdAt: DateTime(2026, 1, 1),
            rowVersion: 1,
          ),
        ),
      );
}

class _SignedOutAuth extends AuthNotifier {
  @override
  AuthState build() => const AuthState();
}

class _TestCfdController extends CfdController {
  @override
  void build() {}
}

class _TestThemeModeNotifier extends ThemeModeNotifier {
  @override
  ThemeMode build() => ThemeMode.light;
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

ProviderScope _shellScope(_MemorySettingsRepository repository) {
  return ProviderScope(
    overrides: [
      settingsRepositoryProvider.overrideWithValue(repository),
      unreadNotificationsCountProvider.overrideWith(
        (ref) => Stream.value(0),
      ),
      authProvider.overrideWith(_SignedInAuth.new),
      cfdControllerProvider.overrideWith(_TestCfdController.new),
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
        currentIndex: AppScreen.settings.value,
        onNavigate: (_) {},
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
  WidgetTester tester,
  _MemorySettingsRepository repository,
) async {
  I18nCatalog.setLocale(defaultUserLocale);
  await tester.pumpWidget(_shellScope(repository));
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  setUp(() {
    I18nCatalog.setCatalog({
      'المبيعات': 'Sales',
      'المشتريات': 'Purchases',
      'الإعدادات': 'Settings',
      'العربية': 'Arabic',
      'English': 'English',
      'لغة الواجهة': 'Interface language',
      'تُحفظ لكل مستخدم وتغيّر اتجاه الشاشة تلقائياً':
          'Saved per user and changes screen direction automatically',
      'تسجيل الدخول': 'Log in',
      'أدخل كلمة المرور للمتابعة': 'Enter password to continue',
      'كلمة المرور': 'Password',
      'لوحة المفاتيح': 'Keyboard',
      'إغلاق البرنامج': 'Close application',
      'تطوير: Ural Technology': 'Developed by Ural Technology',
    });
  });

  tearDown(() {
    I18nCatalog.setCatalog(const {});
    I18nCatalog.setLocale(defaultUserLocale);
  });

  testWidgets('sidebar language toggle changes labels and saves per-user locale',
      (tester) async {
    final repository = _MemorySettingsRepository();
    await _pumpShell(tester, repository);

    expect(find.text('المبيعات'), findsWidgets);
    expect(find.text('المشتريات'), findsWidgets);

    await tester.tap(
      find.descendant(
        of: find.byType(UserLanguageToggle),
        matching: find.text('English'),
      ),
    );
    await tester.pump();

    expect(I18nCatalog.activeLocale, englishUserLocale);
    expect(repository.values[userLocaleSettingKey(_testUserId)], 'en');
    expect(find.text('Sales'), findsWidgets);
    expect(find.text('Purchases'), findsWidgets);
    expect(find.text('المبيعات'), findsNothing);

    await tester.tap(
      find.descendant(
        of: find.byType(UserLanguageToggle),
        matching: find.text('Arabic'),
      ),
    );
    await tester.pump();

    expect(I18nCatalog.activeLocale, defaultUserLocale);
    expect(repository.values[userLocaleSettingKey(_testUserId)], 'ar');
    expect(find.text('المبيعات'), findsWidgets);
    expect(find.text('المشتريات'), findsWidgets);
  });

  testWidgets('login language toggle saves device locale before authentication',
      (tester) async {
    final repository = _MemorySettingsRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsRepositoryProvider.overrideWithValue(repository),
          authProvider.overrideWith(_SignedOutAuth.new),
        ],
        child: const MaterialApp(
          locale: defaultUserLocale,
          supportedLocales: [defaultUserLocale, englishUserLocale],
          localizationsDelegates: [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: LoginScreen(),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('تسجيل الدخول'), findsWidgets);
    final loginDirection = tester.widget<Directionality>(
      find.descendant(
        of: find.byType(LoginScreen),
        matching: find.byType(Directionality),
      ),
    );
    expect(loginDirection.textDirection, TextDirection.rtl);

    await tester.tap(
      find.descendant(
        of: find.byType(UserLanguageToggle),
        matching: find.text('English'),
      ),
    );
    await tester.pump();

    expect(repository.values[deviceLocaleSettingKey], 'en');
    expect(I18nCatalog.activeLocale, englishUserLocale);
    expect(find.text('Log in'), findsWidgets);
    final englishDirection = tester.widget<Directionality>(
      find.descendant(
        of: find.byType(LoginScreen),
        matching: find.byType(Directionality),
      ),
    );
    expect(englishDirection.textDirection, TextDirection.ltr);
  });
}
