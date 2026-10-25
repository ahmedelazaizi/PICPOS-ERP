// منفذُ الكتابة الحقيقيّ لمشغّل الإعداد — **النداءاتُ نفسُها** التي كان
// `_finishSetup()` يجريها على المستودعات، كلٌّ في دالّة.
//
// ⚠️ لا منطقَ هنا: الترتيبُ والشروطُ في `setup_finish_runner.dart` وحده، وهذا
// الملفُّ ترجمةٌ حرفيّةٌ لكلّ نداءٍ إلى مزوّده. فالمقارنةُ في اختبار التكافؤ
// تقيس السلوكَ كلَّه لا نصفَه.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/config/business_profile_provider.dart';
import '../../../data/providers/providers.dart';
import '../../../services/audit_log.dart';
import '../../../services/deployment/commit_result.dart';
import '../../../services/deployment/mode_activator.dart';
import '../../../services/developer_auth_service.dart';
import '../../../services/network_service.dart';
import 'setup_finish_runner.dart';

/// المنفذُ المستعمَل في الإنتاج — والاختبارُ يستبدله بمسجّل.
final setupPersistenceProvider = Provider<SetupPersistence>(
  RiverpodSetupPersistence.new,
);

class RiverpodSetupPersistence implements SetupPersistence, SetupTablesPort {
  RiverpodSetupPersistence(this._ref);

  final Ref _ref;

  @override
  Future<void> saveSetting(String key, String value) =>
      _ref.read(settingsRepositoryProvider).saveSetting(key, value);

  // Spec B3: `business_profile` و`deployment_mode` وكلمةُ المطوّر عبر نفس
  // نسخة `SettingsRepositoryCached` الحيّة التي تقرأ منها «أدوات المطوّر».
  @override
  Future<void> saveCachedSetting(String key, String value) =>
      _ref.read(settingsRepositoryCachedProvider).save(key, value);

  @override
  Future<void> setDeveloperPassword(String password) =>
      DeveloperAuthService(_ref.read(settingsRepositoryCachedProvider))
          .setPassword(password);

  @override
  Future<void> setCurrency(String code) =>
      _ref.read(systemCurrencyProvider.notifier).setCurrency(code);

  @override
  Future<List<Branche>> getAllBranches() =>
      _ref.read(branchRepositoryProvider).getAllBranches();

  @override
  Future<void> updateBranch(Branche branch) =>
      _ref.read(branchRepositoryProvider).updateBranch(branch);

  @override
  Future<int> createBranch(String name) =>
      _ref.read(branchRepositoryProvider).createBranch(name: name);

  @override
  Future<List<Warehouse>> getWarehousesByBranch(int branchId) =>
      _ref.read(branchRepositoryProvider).getWarehousesByBranch(branchId);

  @override
  Future<void> updateWarehouse(Warehouse warehouse) =>
      _ref.read(branchRepositoryProvider).updateWarehouse(warehouse);

  @override
  Future<int> createWarehouseForBranch({
    required String name,
    required int branchId,
  }) =>
      _ref.read(branchRepositoryProvider).createWarehouseForBranch(
            name: name,
            branchId: branchId,
            isDefault: true,
          );

  @override
  Future<SafeData?> getDefaultSafeByType(String type) =>
      _ref.read(treasuryRepositoryProvider).getDefaultSafeByType(type);

  // ⚠️ `updateSafeDetails` يكتب كلَّ الأعمدة — فالمركزُ والفرعُ والحسابُ
  //    المرتبطُ تُمرَّر من الصفّ الحاليّ وإلّا صُفِّرت. وإعادةُ التسمية تنتقل
  //    إلى الحساب المرتبط ذرّيّاً (Feature 004 · FR-006).
  @override
  Future<void> updateSafeDetails(
    SafeData safe, {
    required String name,
    String? bankName,
    String? accountNumber,
  }) =>
      _ref.read(treasuryRepositoryProvider).updateSafeDetails(
            safeId: safe.id,
            name: name,
            bankName: bankName,
            accountNumber: accountNumber,
            costCenterId: safe.costCenterId,
            branchId: safe.branchId,
            linkedAccountId: safe.linkedAccountId,
          );

  @override
  Future<void> insertProduct(ProductsCompanion product) =>
      _ref.read(productRepositoryProvider).insertProduct(product);

  @override
  Future<int?> findUserId(String username) async =>
      (await _ref.read(authRepositoryProvider).getUserByUsername(username))
          ?.user
          .id;

  @override
  Future<void> updateUserPassword(int userId, String password) => _ref
      .read(authRepositoryProvider)
      .updateUserPassword(userId: userId, newPassword: password);

  @override
  Future<void> createUser({
    required String username,
    required String password,
    required String displayName,
    int? roleId,
  }) =>
      _ref.read(authRepositoryProvider).createUser(
            username: username,
            password: password,
            displayName: displayName,
            roleId: roleId,
            forcePasswordChange: true,
          );

  // Spec 125 (US1): اعتمادٌ ذرّيٌّ لنمط التشغيل عبر المالك الوحيد لـ
  // `network_mode`.
  @override
  Future<String?> commitDeploymentMode(NetworkMode mode, int serverPort) async {
    // A1: the ModeActivator is the single committer; the mode is the CHOSEN one.
    final result = await ModeActivator(db: _ref.read(databaseProvider)).commit(
      ActivationPlan(
        mode: mode,
        port: serverPort,
        host: NetworkService.instance.serverAddress,
      ),
    );
    return result is CommitFailed ? result.reasonAr : null;
  }

  // ADP-011: the branch lives in the DB (the device record) AND the prefs cache.
  @override
  Future<void> saveClientBranchId(int branchId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('client_branch_id', branchId);
    await _ref
        .read(settingsRepositoryProvider)
        .saveSetting('client_branch_id', '$branchId');
  }

  @override
  Future<int> createFiscalYear(String name, DateTime start, DateTime end) =>
      _ref
          .read(accountingRepositoryProvider)
          .createFiscalYear(name: name, startDate: start, endDate: end);

  @override
  Future<void> generatePeriodsForYear(
    int yearId,
    DateTime start,
    DateTime end,
  ) =>
      _ref
          .read(accountingRepositoryProvider)
          .generatePeriodsForYear(yearId, start, end);

  @override
  Future<void> recordAudit(String event, Map<String, dynamic> payload) =>
      AuditLog.record(event, level: AuditLevel.critical, payload: payload);

  @override
  Future<bool> rehydrateRuntimeConfigCache() => _ref
      .read(configServiceProvider)
      .rehydrateRuntimeConfigCache(exitPath: 'finish');

  // المعالج v2: قسمٌ + طاولات، idempotent بالاسم.
  @override
  Future<int> ensureTables({
    required String sectionName,
    required int count,
    required String Function(int n) tableName,
  }) async {
    final repo = _ref.read(restaurantRepositoryProvider);
    final sections = await repo.getAllSections();
    final section = sections.where((s) => s.name.trim() == sectionName).firstOrNull;
    final sectionId = section?.id ?? await repo.createSection(sectionName);
    final existing = (await repo.getAllTables())
        .where((t) => t.sectionId == sectionId)
        .map((t) => t.name.trim())
        .toSet();
    var created = 0;
    for (var n = 1; n <= count; n++) {
      final name = tableName(n);
      if (existing.contains(name)) continue;
      await repo.createTable(name: name, capacity: 4, sectionId: sectionId);
      created++;
    }
    return created;
  }
}
