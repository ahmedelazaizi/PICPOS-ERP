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
import 'package:picpos_erp/services/setup/branch_account_verifier.dart';
import 'package:picpos_erp/services/setup/client_link_service.dart';
import 'package:picpos_erp/services/setup/first_run_storage_probe.dart';
import 'package:picpos_erp/services/setup/server_provisioning_service.dart';
import 'package:picpos_erp/services/setup/server_setup_writer.dart';

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

  /// الفروع المزامَنة في «القاعدة المحلية» (‏للمسار الفرعي).
  List<Branche> branches = [];
  int? clientBranchId;
  String? deploymentFailure;

  /// خطٌّ زمنيٌّ مشتركٌ مع بقيّة المزيّفات (‏يضبطه الحاضنُ) لقياس الترتيب.
  List<String>? timeline;

  @override
  Future<void> saveSetting(String key, String value) async {
    if (key == failOnKey) throw StateError('disk full');
    calls.add('save:$key');
    timeline?.add('save:$key');
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
  Future<List<Branche>> getAllBranches() async => branches;
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
    timeline?.add('mode:${mode.name}');
    return deploymentFailure;
  }

  @override
  Future<void> saveClientBranchId(int branchId) async {
    clientBranchId = branchId;
    calls.add('clientBranch:$branchId');
  }
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

Branche testBranch(int id, String name, String code) => Branche(
      id: id,
      name: name,
      code: code,
      address: null,
      phone: null,
      isActive: true,
      costCenterId: null,
      globalId: 'g$id',
      regionId: null,
      isSystemDefault: false,
      lastModifiedAt: null,
      deletedAt: null,
      originClientId: null,
      rowVersion: 0,
    );

/// تهيئةُ PostgreSQL مزيّفة: تسجّل النداءات وتفشل عند الطلب.
class FakeProvisioning extends ServerProvisioningService {
  FakeProvisioning(this.events);
  final List<String> events;
  String? testError;
  String? provisionError;
  PostgresConfig? lastConfig;
  int armed = 0;

  @override
  Future<String?> testConnection(PostgresConfig cfg) async {
    lastConfig = cfg;
    events.add('pg-test');
    return testError;
  }

  @override
  Future<ProvisionOutcome> provision(
    PostgresConfig cfg, {
    void Function(int index, ProvisionStatus status, String? detail)? onStep,
  }) async {
    lastConfig = cfg;
    events.add('pg-provision');
    for (var i = 0; i < 6; i++) {
      onStep?.call(i, ProvisionStatus.running, null);
      if (provisionError != null && i == 1) {
        onStep?.call(i, ProvisionStatus.failed, provisionError);
        return ProvisionOutcome.failure(provisionError!);
      }
      onStep?.call(i, ProvisionStatus.ok, null);
    }
    return const ProvisionOutcome.success();
  }

  @override
  Future<void> armPostgresMode(PostgresConfig cfg) async {
    armed++;
    events.add('pg-arm');
  }
}

/// كاتبُ بيانات الخادم المزيّف: يحفظ آخر مدخل ويفشل عند الطلب.
class FakeServerWriter extends ServerSetupWriter {
  FakeServerWriter(this.events);
  final List<String> events;
  ServerSetupInput? lastInput;
  PostgresConfig? lastConfig;
  Object? failWith;
  int writes = 0;

  @override
  Future<ServerSetupReport> write(PostgresConfig cfg, ServerSetupInput input) async {
    events.add('server-write');
    if (failWith != null) throw failWith!;
    writes++;
    lastInput = input;
    lastConfig = cfg;
    return const ServerSetupReport(branchIds: {}, createdUsers: 0, updatedUsers: 0);
  }
}

/// ربطُ الفرع المزيّف: الإقران والمزامنة بنتائج قابلة للضبط.
class FakeLink implements ClientLinkPort {
  FakeLink(this.events);
  final List<String> events;
  bool pairOk = true;
  bool online = true;
  bool syncOk = true;
  List<Branche> branches = [testBranch(7, 'فرع عمّان', 'AMM')];
  String? lastCode;
  String? lastAddress;
  String? lastDeviceName;
  int syncCalls = 0;
  String? mirrorAdmin;

  @override
  Future<ClientLinkResult> pairDevice({
    required String address,
    required int port,
    required String code,
    String? deviceName,
  }) async {
    events.add('pair');
    lastCode = code;
    lastAddress = '$address:$port';
    lastDeviceName = deviceName;
    return pairOk
        ? const ClientLinkResult(ClientLinkOutcome.devicePaired, message: 'paired')
        : const ClientLinkResult(ClientLinkOutcome.pairFailed, message: 'bad code');
  }

  @override
  Future<ClientLinkResult> connectAndSync({
    required String address,
    required int port,
    required Future<bool> Function() confirmRePair,
    void Function(String message)? onProgress,
    bool mirror = false,
  }) async {
    events.add(mirror ? 'sync-mirror' : 'sync');
    syncCalls++;
    if (!online) {
      return const ClientLinkResult(ClientLinkOutcome.connectFailed,
          message: 'no route to host');
    }
    if (!syncOk) {
      return const ClientLinkResult(ClientLinkOutcome.syncFailed,
          message: 'sync failed');
    }
    return ClientLinkResult(ClientLinkOutcome.connected,
        branches: branches, message: 'synced');
  }

  @override
  Future<ClientLinkResult> pairMirrorWithCode({
    required String host,
    required int port,
    required String code,
    String? deviceName,
  }) async {
    events.add('pair-mirror');
    lastCode = code;
    lastAddress = '$host:$port';
    lastDeviceName = deviceName;
    return pairOk
        ? const ClientLinkResult(ClientLinkOutcome.paired, message: 'mirror ok')
        : const ClientLinkResult(ClientLinkOutcome.pairFailed, message: 'bad code');
  }
}

/// التحقّق من الحساب المزيّف: كلمة `Good#Pass1` وحدها تنجح.
class FakeVerifier implements BranchAccountVerifierPort {
  FakeVerifier(this.events);
  final List<String> events;
  int? lastBranchId;
  String? lastUser;
  String? newPasswordSeen;
  bool serverSession = true;

  @override
  Future<AccountVerification> verify({
    required String username,
    required String password,
    int? branchId,
    String? newPassword,
  }) async {
    events.add('verify');
    newPasswordSeen = newPassword;
    if (password == 'Temp#Pass1' && (newPassword ?? '').isEmpty) {
      return const AccountVerification.passwordChangeRequired('change it');
    }
    lastBranchId = branchId;
    lastUser = username;
    if (password != 'Good#Pass1' && password != 'Temp#Pass1') {
      return const AccountVerification.failure('wrong password');
    }
    if (!serverSession) {
      return const AccountVerification.failure('no server session');
    }
    return const AccountVerification.success(
      userId: 12,
      displayName: 'كاشير عمّان',
      roleName: 'كاشير',
      permissionCount: 14,
      topPermissions: ['pos_access', 'pos_save', 'pos_print'],
    );
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
        probe = probe ?? FakeProbe() {
    provisioning = FakeProvisioning(events);
    writer = FakeServerWriter(events);
    link = FakeLink(events);
    verifier = FakeVerifier(events);
    this.persistence.timeline = events;
  }

  final MemorySettings settings;
  final RecordingPersistence persistence;
  final FakeProbe probe;
  final List<String> events = [];
  late final FakeProvisioning provisioning;
  late final FakeServerWriter writer;
  late final FakeLink link;
  late final FakeVerifier verifier;
  bool started = false;
  bool restarted = false;
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
        serverProvisioningServiceProvider.overrideWithValue(provisioning),
        serverSetupWriterProvider.overrideWithValue(writer),
        clientLinkPortProvider.overrideWithValue(link),
        branchAccountVerifierProvider.overrideWithValue(verifier),
        firstRunRolesProvider.overrideWith((ref) async => const [
              FirstRunRoleOption(2, 'كاشير'),
              FirstRunRoleOption(7, 'مدير فرع'),
            ]),
        firstRunLocalAddressesProvider
            .overrideWith((ref) async => const ['192.168.1.20']),
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
          home: FirstRunSetupScreen(
            onStart: () => started = true,
            onRestart: () => restarted = true,
          ),
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
