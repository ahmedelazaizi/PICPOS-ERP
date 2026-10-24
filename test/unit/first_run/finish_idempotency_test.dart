// الإنهاء idempotent على قاعدة SQLite حقيقية (في الذاكرة): تشغيلتان بنفس المسودة
// لا تكرّران فرعاً ولا مخزناً ولا قسمَ طاولات ولا طاولات، والمديرُ يُحدَّث
// ولا يُنشأ، و`setup_completed` يُكتب.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/core/i18n/tr.dart';
import 'package:picpos_erp/data/providers/providers.dart';
import 'package:picpos_erp/domain/models/first_run/first_run_draft.dart';
import 'package:picpos_erp/domain/models/first_run/first_run_packs.dart';
import 'package:picpos_erp/presentation/screens/first_run/first_run_finish.dart';
import 'package:picpos_erp/presentation/screens/setup_wizard/setup_finish_runner.dart';
import 'package:picpos_erp/presentation/screens/setup_wizard/setup_persistence_riverpod.dart';
import 'package:picpos_erp/services/network_service.dart';

/// كتابات القاعدة كلها حقيقية؛ ما يمسّ الشبكة/التفضيلات/الإعدادات المؤقتة
/// يُستبدل بلا أثر (‏يُقاس في اختبارات المشغّل والمعالج الأخرى).
class _DbPersistence extends RiverpodSetupPersistence {
  _DbPersistence(super.ref);

  @override
  Future<String?> commitDeploymentMode(NetworkMode mode, int serverPort) async =>
      null;

  @override
  Future<void> recordAudit(String event, Map<String, dynamic> payload) async {}

  @override
  Future<bool> rehydrateRuntimeConfigCache() async => true;

  @override
  Future<void> saveCachedSetting(String key, String value) =>
      saveSetting(key, value);

  @override
  Future<void> setDeveloperPassword(String password) async {}

  @override
  Future<void> setCurrency(String code) => saveSetting('system_currency', code);
}

void main() {
  setUpAll(() => I18nCatalog.setCatalog(const {}));

  test('تشغيلان بنفس المسودة على قاعدة حقيقية لا يكرران شيئاً', () async {
    final db = AppDatabase.forTesting();
    // updateUserPassword يطلق فاحصَ تصادم كلمات المرور بلا انتظار؛ يُترك ينتهي
    // قبل إغلاق القاعدة وإلا سقط بـ«Can't re-open a database after closing».
    addTearDown(() async {
      await Future<void>.delayed(const Duration(milliseconds: 600));
      await db.close();
    });
    await db.getBranches();
    final container = ProviderContainer(overrides: [
      databaseProvider.overrideWithValue(db),
      setupPersistenceProvider.overrideWith((ref) => _DbPersistence(ref)),
    ]);
    addTearDown(container.dispose);

    final draft = const FirstRunDraft(draftId: 'idem-1').copyWith(
      pack: FirstRunPack.restaurant,
      companyName: 'مطعم الياسمين',
      currency: 'JOD',
      vatRate: 16,
      branchName: 'فرع الياسمين',
      warehouseName: 'مخزن الياسمين',
      fiscalYear: 2026,
      tablesCount: '6',
    );
    const secrets = FirstRunSecrets(
      adminPassword: 'S3cretPass',
      adminPasswordConfirm: 'S3cretPass',
      developerPassword: 'dev1',
      developerPasswordConfirm: 'dev1',
    );
    final persistence = container.read(setupPersistenceProvider);

    Future<SetupRunResult> run() => SetupFinishRunner()
        .run(toSetupDraft(draft, secrets), persistence);

    final first = await run();
    expect(first.ok, isTrue, reason: '${first.error} @ ${first.failedStage}');

    Future<(int, int, int, int, int)> counts() async => (
          (await db.getBranches()).length,
          (await container.read(branchRepositoryProvider).getWarehousesByBranch(
                  (await db.getBranches()).first.id))
              .length,
          (await container.read(restaurantRepositoryProvider).getAllSections())
              .length,
          (await container.read(restaurantRepositoryProvider).getAllTables())
              .length,
          (await db.getSettingValue('setup_completed')) == 'true' ? 1 : 0,
        );

    final a = await counts();
    expect(a.$3, 1);
    expect(a.$4, 6);
    expect(a.$5, 1);

    final second = await run();
    expect(second.ok, isTrue, reason: '${second.error} @ ${second.failedStage}');
    final b = await counts();
    expect(b, a, reason: 'تشغيل ثانٍ بنفس المسودة غيّر العدّادات');
    expect(await db.getSettingValue('company_name'), 'مطعم الياسمين');
    expect(await db.getSettingValue('business_profile'), 'restaurant');
  });
}
