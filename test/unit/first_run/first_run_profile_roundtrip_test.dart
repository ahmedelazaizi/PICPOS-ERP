// بند 8 (دراسة 2026-10-30): اختيارُ «النظام الكامل» (‏full ⇒ unified) في معالج
// الإعداد الأول يجب أن يُقرأ «شاملاً» بعد الإقلاع التالي في كل المسارات الأربعة.
//
// الاختبارُ يمرّ بالمنفّذ الحقيقيّ (‏`defaultFinisher`) والمنفذ الحقيقيّ
// (‏`RiverpodSetupPersistence`) والمُعتمِد الحقيقيّ (‏`ModeActivator`) على قاعدة
// SQLite في الذاكرة، ثم «يُقلع» كما يفعل `main.dart`: ذاكرةُ إعداداتٍ جديدة
// تُحمَّل مسبقاً ثم `ProviderContainer` جديد يقرأ `businessProfileProvider`.
//
// المستثنى عمداً: اعتمادُ نمط الخادم (‏`NetworkService.setMode(server)` يفتح منفذ
// HTTP) فيُستبدل في مسار المقرّ بلا أثر؛ والمقرُّ يُكتب في «قاعدة خادم» ثانية
// (‏SQLite في الذاكرة بدل PostgreSQL، وهي نفسُ `ServerSetupWriter.apply`).
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:picpos_erp/core/config/business_profile.dart';
import 'package:picpos_erp/core/config/business_profile_provider.dart';
import 'package:picpos_erp/core/config/feature_key.dart';
import 'package:picpos_erp/core/i18n/tr.dart';
import 'package:picpos_erp/core/logging/diagnostic_logger.dart';
import 'package:picpos_erp/data/database/pg_config.dart';
import 'package:picpos_erp/data/providers/providers.dart';
import 'package:picpos_erp/data/repositories/settings_repository_cached.dart';
import 'package:picpos_erp/domain/models/first_run/first_run_currency.dart';
import 'package:picpos_erp/domain/models/first_run/first_run_draft.dart';
import 'package:picpos_erp/domain/models/first_run/first_run_packs.dart';
import 'package:picpos_erp/domain/models/first_run/first_run_path.dart';
import 'package:picpos_erp/presentation/screens/first_run/first_run_finish.dart';
import 'package:picpos_erp/presentation/screens/setup_wizard/setup_persistence_riverpod.dart';
import 'package:picpos_erp/services/deployment/provisioning_applier.dart';
import 'package:picpos_erp/services/mirror_heartbeat_service.dart';
import 'package:picpos_erp/services/mirror_state.dart';
import 'package:picpos_erp/services/network_service.dart';
import 'package:picpos_erp/services/setup/server_setup_writer.dart';
import 'package:picpos_erp/services/sync/strategies/setting_sync_strategy.dart';

import '../../widget/first_run/first_run_test_kit.dart';

/// المنفذُ الحقيقيّ، عدا اعتماد نمط الخادم (يفتح منفذ HTTP).
class _Persistence extends RiverpodSetupPersistence {
  _Persistence(super.ref);

  @override
  Future<String?> commitDeploymentMode(NetworkMode mode, int serverPort) async =>
      mode == NetworkMode.server ? null : super.commitDeploymentMode(mode, serverPort);
}

/// «قاعدةُ الخادم»: نفسُ كاتب الخادم الحقيقيّ على قاعدة ثانية في الذاكرة.
class _WriterToDb extends ServerSetupWriter {
  _WriterToDb(this.target);
  final AppDatabase target;

  @override
  Future<ServerSetupReport> write(PostgresConfig cfg, ServerSetupInput input) =>
      apply(target, input);
}

const _secrets = FirstRunSecrets(
  adminPassword: 'S3cretPass',
  adminPasswordConfirm: 'S3cretPass',
  developerPassword: 'dev1',
  developerPasswordConfirm: 'dev1',
);

FirstRunDraft _draft(FirstRunPath path, {FirstRunPack pack = FirstRunPack.full}) =>
    FirstRunDraft(draftId: 'rt-${path.name}', path: path).copyWith(
      pack: pack,
      companyName: 'شركة الأمل',
      currency: 'JOD',
      branchName: 'الرئيسي',
      warehouseName: 'المخزن',
      fiscalYear: 2026,
      tablesCount: '0',
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
          const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
          (call) async => null);

  late AppDatabase db; // قاعدةُ هذا الجهاز
  late AppDatabase serverDb; // قاعدةُ الخادم (PostgreSQL في الإنتاج)
  late ProviderContainer container;

  setUp(() async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    I18nCatalog.setCatalog(const {});
    SharedPreferences.setMockInitialValues({});
    DiagnosticLogger.enableTestMode();
    NetworkService.instance.debugSetModeForTests(NetworkMode.standalone);
    MirrorState.instance.debugSetForTests();
    db = AppDatabase.forTesting();
    serverDb = AppDatabase.forTesting();
    await db.getBranches();
    await serverDb.getBranches();
    container = ProviderContainer(overrides: [
      databaseProvider.overrideWithValue(db),
      setupPersistenceProvider.overrideWith((ref) => _Persistence(ref)),
    ]);
  });

  tearDown(() async {
    container.dispose();
    MirrorHeartbeatService.stop();
    NetworkService.instance.debugSetModeForTests(NetworkMode.standalone);
    MirrorState.instance.debugSetForTests();
    await Future<void>.delayed(const Duration(milliseconds: 600));
    await db.close();
    await serverDb.close();
  });

  Future<void> finish(FirstRunDraft d, {FirstRunSecrets s = _secrets}) async {
    final events = <String>[];
    final fin = defaultFinisher(
      writer: _WriterToDb(serverDb),
      provisioning: FakeProvisioning(events),
    );
    final r = await fin(d, s, container.read(setupPersistenceProvider));
    expect(r.ok, isTrue, reason: '${r.error} @ ${r.failedStage}');
  }

  /// إقلاعٌ بارد كما في `main.dart`: ذاكرةٌ جديدة + `preload` + نطاقٌ جديد.
  Future<BusinessProfile> bootRead(AppDatabase from) async {
    final cache = SettingsRepositoryCached(from);
    await cache.preload([
      'setup_completed',
      'business_profile',
      'deployment_mode',
      ...FeatureKey.values.map((k) => k.settingKey),
    ]);
    final boot = ProviderContainer(overrides: [
      databaseProvider.overrideWithValue(from),
      settingsRepositoryCachedProvider.overrideWithValue(cache),
    ]);
    addTearDown(boot.dispose);
    return boot.read(businessProfileProvider);
  }

  /// المزامنةُ الأولى لفرعٍ/مرآة: `GET /api/settings` من الخادم ⇒
  /// `SettingSyncStrategy.syncFromJson` (‏تتخطّى مفاتيحَ الجهاز فقط).
  Future<void> firstSyncSettingsFromServer() async {
    final rows = await serverDb.select(serverDb.settings).get();
    await SettingSyncStrategy(db).syncFromJson({
      'settings': {for (final r in rows) r.key: r.value},
    });
  }

  // ملاحظة: بلا --dart-define=APP_BRAND=picpos يكون احتياطيّ غياب المفتاح
  // unified فلا تُثبت قراءةُ المزوّد وحدها شيئاً؛ لذا تُقاس القاعدةُ مباشرةً
  // في كل اختبار، ويُشغَّل الملف بالبناءين.

  test('مستقل: full ⇒ unified في القاعدة وبعد الإقلاع', () async {
    await finish(_draft(FirstRunPath.standalone));

    expect((await db.getSettingValue('business_profile'))?.trim(), 'unified');
    await ProvisioningApplier.ensure(db);
    expect(await bootRead(db), BusinessProfile.unified);
  });

  test('مقر: القاعدتان (الخادم والمحلية) تحملان unified ويُقرآن شاملاً', () async {
    await finish(_draft(FirstRunPath.hq));

    expect((await serverDb.getSettingValue('business_profile'))?.trim(),
        'unified');
    expect(await bootRead(serverDb), BusinessProfile.unified);
    // الإقلاع على القاعدة المحلية يحدث فعلاً حين يتعذّر PostgreSQL (main.dart
    // :236-240 يرجع إلى SQLite المحلية) ⇒ يجب ألا يسقط إلى الافتراضيّ.
    expect((await db.getSettingValue('business_profile'))?.trim(), 'unified',
        reason: 'نسخةُ الإقلاع المحلية لم تحمل ملف النشاط (‏lite عند سقوط PG)');
    expect(await bootRead(db), BusinessProfile.unified);
  });

  test('فرع: قيمةُ الخادم المزامَنة تبقى unified بعد الإنهاء (لا تُطمس)',
      () async {
    await finish(_draft(FirstRunPath.hq));
    await firstSyncSettingsFromServer();
    await db.setSetting('client_first_sync_completed', 'true');
    final branchId = (await db.getBranches()).first.id;

    // المعالج لا يعرض اختيار الباقة في الفرع (لا خطوة company) ⇒ الباقة
    // الافتراضية pos في المسودة؛ لا يجوز أن تطغى على قيمة الخادم.
    await finish(_draft(FirstRunPath.branch, pack: FirstRunPack.pos)
        .copyWith(selectedBranchId: branchId));

    expect((await db.getSettingValue('business_profile'))?.trim(), 'unified');
    expect(await bootRead(db), BusinessProfile.unified);
  });

  test('مرآة: قيمةُ الخادم المزامَنة تبقى unified بعد الإنهاء (لا تُطمس)',
      () async {
    await finish(_draft(FirstRunPath.hq));
    await firstSyncSettingsFromServer();
    await db.setSetting('mirror_first_sync_completed', 'true');
    await MirrorState.instance
        .setPaired(serverDisplayName: 'hq:8080', adminUserId: 1);

    await finish(_draft(FirstRunPath.mirror, pack: FirstRunPack.pos));

    expect((await db.getSettingValue('business_profile'))?.trim(), 'unified');
    expect(await bootRead(db), BusinessProfile.unified);
  });

  // مفاتيحُ الباقة/الأنشطة التي يكتبها ServerSetupWriter في الخادم وحده.
  const keys = [
    'business_type',
    'feature.pos.tables',
    'feature.pos.delivery',
    'show_jofotara_einvoice',
    'show_eta_einvoice',
  ];

  /// قراءةٌ متزامنة بعد إقلاعٍ بارد (ذاكرةٌ جديدة + preload) كما في main.dart.
  Future<Map<String, String?>> bootKeys(AppDatabase from) async {
    final cache = SettingsRepositoryCached(from);
    await cache.preload(keys);
    return {for (final k in keys) k: cache.get(k)};
  }

  FirstRunDraft hqDraft() => _draft(FirstRunPath.hq, pack: FirstRunPack.restaurant)
      .copyWith(
          serviceType: FirstRunServiceType.tablesOnly,
          eInvoice: FirstRunEInvoice.jordan);

  const expected = {
    'business_type': 'restaurant',
    'feature.pos.tables': 'true',
    'feature.pos.delivery': 'false',
    'show_jofotara_einvoice': 'true',
    'show_eta_einvoice': 'false',
  };

  test('مقر: مفاتيحُ الباقة تُقرأ محلياً بعد الإقلاع كما في الخادم', () async {
    await finish(hqDraft());
    final server = await bootKeys(serverDb);
    final local = await bootKeys(db);
    expect(server['feature.pos.tables'], expected['feature.pos.tables']);
    expect(server['feature.pos.delivery'], expected['feature.pos.delivery']);
    expect(server['show_jofotara_einvoice'], 'true');
    expect(local['feature.pos.tables'], 'true');
    expect(local['feature.pos.delivery'], 'false');
    expect(local['show_jofotara_einvoice'], 'true');
    expect(local['show_eta_einvoice'], 'false');
    expect(local['business_type'], server['business_type']);
    expect(local['business_type'], isNotEmpty);
  });

  for (final path in [FirstRunPath.branch, FirstRunPath.mirror]) {
    test('${path.name}: مفاتيحُ الباقة المزامَنة لا تُطمس بالافتراضي', () async {
      await finish(hqDraft());
      // نبدأ من جهازٍ نظيف يحمل ما زامنه الخادم فقط.
      final rows = await serverDb.select(serverDb.settings).get();
      for (final k in keys) {
        await db.customStatement('DELETE FROM settings WHERE key = ?', [k]);
      }
      await firstSyncSettingsFromServer();
      final before = await bootKeys(db);
      expect(before['feature.pos.tables'], 'true');
      expect(before['feature.pos.delivery'], 'false');
      expect(rows, isNotEmpty);

      if (path == FirstRunPath.branch) {
        await db.setSetting('client_first_sync_completed', 'true');
      } else {
        await db.setSetting('mirror_first_sync_completed', 'true');
        await MirrorState.instance
            .setPaired(serverDisplayName: 'hq:8080', adminUserId: 1);
      }
      final branchId = (await db.getBranches()).first.id;
      // مسودةٌ بقيمٍ افتراضيةٍ مختلفة تماماً (باقة pos، فوترة مصر، توصيل).
      await finish(_draft(path, pack: FirstRunPack.pos).copyWith(
        selectedBranchId: branchId,
        serviceType: FirstRunServiceType.takeawayDelivery,
        eInvoice: FirstRunEInvoice.egypt,
      ));

      expect(await bootKeys(db), before);
    });
  }

  test('مقر: باقةٌ غير شاملة تبقى كما اختيرت (لا تعميم unified)', () async {
    await finish(_draft(FirstRunPath.hq, pack: FirstRunPack.business));
    expect((await db.getSettingValue('business_profile'))?.trim(),
        'supermarket');
    expect((await serverDb.getSettingValue('business_profile'))?.trim(),
        'supermarket');
  });
}
