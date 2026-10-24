// أدواتٌ مشتركةٌ لاختبارات الإعداد الأول (v2): مخزنٌ ومجسٌّ ومنفذُ كتابةٍ مسجِّل،
// ودالّةُ تركيبٍ بالعربيّة/الإنجليزيّة والفاتح/الداكن.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/core/i18n/locale_provider.dart';
import 'package:picpos_erp/core/i18n/tr.dart';
import 'package:picpos_erp/core/theme/app_theme.dart';
import 'package:picpos_erp/data/providers/providers.dart';
import 'package:picpos_erp/presentation/screens/first_run/first_run_draft_store.dart';
import 'package:picpos_erp/presentation/screens/first_run/first_run_providers.dart';
import 'package:picpos_erp/presentation/screens/first_run/first_run_setup_screen.dart';
import 'package:picpos_erp/presentation/screens/setup_wizard/setup_finish_runner.dart';
import 'package:picpos_erp/presentation/screens/setup_wizard/setup_persistence_riverpod.dart';
import 'package:picpos_erp/services/network_service.dart';
import 'package:picpos_erp/services/setup/first_run_storage_probe.dart';

class FakeLocaleNotifier extends UserLocaleNotifier {
  @override
  Locale build() => I18nCatalog.activeLocale;

  @override
  Future<void> setLocale(Locale locale) async {
    final normalized = localeForCode(locale.languageCode);
    state = normalized;
    I18nCatalog.setLocale(normalized);
  }
}

/// مخزنُ إعداداتٍ في الذاكرة (المفتاح → القيمة) يحاكي `settings`.
class MemorySettings {
  final Map<String, String> values = {};
  Future<String?> read(String k) async => values[k];
  Future<void> write(String k, String v) async => values[k] = v;
}

class FakeProbe extends FirstRunStorageProbe {
  FakeProbe({this.writable = true, this.prior = false});
  bool writable;
  bool prior;

  @override
  Future<StorageProbeResult> probe() async => StorageProbeResult(
        path: r'C:\Users\x\Documents\picpos_lite.db',
        writable: writable,
        hasPriorData: prior,
        error: writable ? null : 'denied',
      );
}

/// منفذُ كتابةٍ مسجِّل: يحفظ التسلسلَ، ويتذكّر الطاولات (idempotent بالاسم)،
/// ويفشل عند مفتاحٍ معيَّن عند الطلب.
class RecordingPersistence implements SetupPersistence, SetupTablesPort {
  final calls = <String>[];
  final settings = <String, String>{};
  final tableNames = <String>{};
  String? failOnKey;
  int ensureTablesCalls = 0;
  String? adminPassword;
  String? developerPassword;
  String? currency;

  @override
  Future<void> saveSetting(String key, String value) async {
    if (key == failOnKey) throw StateError('disk full');
    calls.add('save:$key');
    settings[key] = value;
  }

  @override
  Future<void> saveCachedSetting(String key, String value) async {
    calls.add('cached:$key');
    settings[key] = value;
  }

  @override
  Future<void> setDeveloperPassword(String password) async {
    developerPassword = password;
    calls.add('devpw');
  }

  @override
  Future<void> setCurrency(String code) async {
    currency = code;
    calls.add('currency:$code');
  }

  @override
  Future<List<Branche>> getAllBranches() async => const [];
  @override
  Future<void> updateBranch(Branche branch) async {}
  @override
  Future<int> createBranch(String name) async {
    calls.add('createBranch');
    return 1;
  }

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
  Future<void> updateUserPassword(int userId, String password) async {
    adminPassword = password;
    calls.add('adminpw');
  }

  @override
  Future<void> createUser({
    required String username,
    required String password,
    required String displayName,
    int? roleId,
  }) async {}
  @override
  Future<String?> commitDeploymentMode(NetworkMode mode, int port) async {
    calls.add('mode:${mode.name}');
    return null;
  }

  @override
  Future<void> saveClientBranchId(int branchId) async {}
  @override
  Future<int> createFiscalYear(String n, DateTime s, DateTime e) async {
    calls.add('fiscal:$n');
    return 1;
  }

  @override
  Future<void> generatePeriodsForYear(int id, DateTime s, DateTime e) async {}
  @override
  Future<void> recordAudit(String e, Map<String, dynamic> p) async {
    calls.add('audit');
  }

  @override
  Future<bool> rehydrateRuntimeConfigCache() async {
    calls.add('rehydrate');
    return true;
  }

  @override
  Future<int> ensureTables({
    required String sectionName,
    required int count,
    required String Function(int n) tableName,
  }) async {
    ensureTablesCalls++;
    var created = 0;
    for (var n = 1; n <= count; n++) {
      if (tableNames.add('$sectionName/${tableName(n)}')) created++;
    }
    calls.add('tables:$count');
    return created;
  }
}

late Map<String, String> englishCatalog;

void loadEnglishCatalog() {
  final decoded = jsonDecode(File('assets/i18n/en.json').readAsStringSync())
      as Map<String, dynamic>;
  englishCatalog = {
    for (final e in decoded.entries)
      if (e.value is String) e.key: e.value as String,
  };
}

void useLocale({required bool english}) {
  I18nCatalog.setCatalog(englishCatalog);
  I18nCatalog.setLocale(english ? englishUserLocale : defaultUserLocale);
}

class FirstRunHarness {
  FirstRunHarness({
    MemorySettings? settings,
    RecordingPersistence? persistence,
    FakeProbe? probe,
  })  : settings = settings ?? MemorySettings(),
        persistence = persistence ?? RecordingPersistence(),
        probe = probe ?? FakeProbe();

  final MemorySettings settings;
  final RecordingPersistence persistence;
  final FakeProbe probe;
  bool started = false;
  late ProviderContainer container;

  FirstRunDraftStore makeStore() => FirstRunDraftStore(
        read: settings.read,
        write: settings.write,
        debounce: const Duration(milliseconds: 20),
        newId: () => 'draft-test-id',
      );

  List<Override> get overrides => [
        firstRunDraftStoreProvider.overrideWith((ref) {
          final s = makeStore();
          ref.onDispose(s.dispose);
          return s;
        }),
        firstRunStorageProbeProvider.overrideWithValue(probe),
        userLocaleProvider.overrideWith(FakeLocaleNotifier.new),
        setupPersistenceProvider.overrideWithValue(persistence),
      ];

  Future<void> pump(
    WidgetTester tester, {
    bool dark = false,
    Size size = const Size(1366, 768),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: overrides,
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: dark ? ThemeMode.dark : ThemeMode.light,
          home: FirstRunSetupScreen(onStart: () => started = true),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    container = ProviderScope.containerOf(
      tester.element(find.byType(FirstRunSetupScreen)),
    );
  }

  /// يترك مؤقّتَ الحفظ يمرّ ثمّ يفكّ الشجرة (‏لا مؤقّتات معلَّقة).
  Future<void> teardown(WidgetTester tester) async {
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> tapKey(WidgetTester tester, String key) async {
  final f = find.byKey(Key(key));
  await tester.ensureVisible(f);
  await tester.tap(f);
  await tester.pump();
}

Future<void> enterKey(WidgetTester tester, String key, String text) async {
  final f = find.descendant(
    of: find.byKey(Key(key)),
    matching: find.byType(TextField),
  );
  await tester.ensureVisible(f);
  await tester.enterText(f, text);
  await tester.pump();
}

/// يُكمل الخطوات الستّ للمسار المستقلّ حتى المراجعة.
Future<void> fillStandaloneUntilReview(
  WidgetTester tester, {
  String company = 'شركة الأمل',
  String currency = 'JOD',
  String pack = 'pos',
  String password = 'S3cretPass',
}) async {
  await tapKey(tester, 'first_run_next'); // mode → company
  await tapKey(tester, 'first_run_pack_$pack');
  await enterKey(tester, 'first_run_company_name', company);
  await tapKey(tester, 'first_run_currency_$currency');
  await tapKey(tester, 'first_run_next'); // company → storage
  await tapKey(tester, 'first_run_next'); // storage → users
  await enterKey(tester, 'first_run_admin_password', password);
  await enterKey(tester, 'first_run_admin_password_confirm', password);
  await enterKey(tester, 'first_run_dev_password', 'dev123');
  await enterKey(tester, 'first_run_dev_password_confirm', 'dev123');
  await tapKey(tester, 'first_run_next'); // users → prep
  await tapKey(tester, 'first_run_next'); // prep → review
}
