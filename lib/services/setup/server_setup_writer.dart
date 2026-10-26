// كتابةُ بيانات إعداد المقرّ في قاعدة PostgreSQL (P5 · C.5): نواةٌ ذرّيّة
// (إعدادات · فروع · طاولات · سنة ماليّة) ثم المسؤول والمستخدمون ثم
// `setup_completed` في معاملةٍ أخيرة (انظر `apply` لسبب فصل المستخدمين).
//
// بعد إعادة التشغيل يقرأ التطبيقُ من PostgreSQL، فكلُّ ما جمعه المعالجُ (المنشأة،
// الفروع، كلمةُ المسؤول، المستخدمون ونطاقُهم، سياسةُ الدخول دون اتصال) يجب أن
// يكون هناك. و`setup_completed`/`network_mode` آخرُ ما يُكتَب.
//
// ⚠️ **idempotent**: الفرعُ بالرمز، والمستخدمُ باسم الدخول (موجودٌ ⇒ يُحدَّث دورُه
// ونطاقُه ولا يُنشأ)، والقسمُ والطاولاتُ بالاسم، والسنةُ الماليّةُ بالاسم،
// و`company_global_id` يُولَّد مرّةً واحدة. تشغيلتان ⇒ النتيجةُ نفسُها.
// ⚠️ كلمةُ المسؤول تُحدَّث بـ`updateUserPassword` فلا يبقى `admin/admin` على الخادم.
library;

import 'package:drift/drift.dart' show Value, Variable;

import '../../core/config/app_config.dart';
import '../../core/utils/uuid_v7.dart';
import '../../data/database/database_barrel.dart';
import '../../data/database/connection.dart' show openPostgresConnection;
import '../../data/database/pg_config.dart';
import '../deployment/provisioning_record.dart';
import '../network_service.dart' show NetworkMode;
import '../security_service.dart';

/// مستخدمٌ من جدول المقرّ — كلمةُ مروره الأوليّة (يُجبَر على تغييرها).
class ServerSetupUser {
  const ServerSetupUser({
    required this.name,
    required this.username,
    required this.password,
    this.roleId,
    this.roleName,
    this.scope = 'HQ',
    this.forcePasswordChange = true,
  });

  final String name;
  final String username;
  final String password;
  final int? roleId;

  /// الدورُ يُحلّ بالاسم في قاعدة الخادم أوّلاً ثم بالرقم.
  final String? roleName;

  /// `HQ` (الفرع الرئيسي) · `ALL` (كلُّ الفروع) · رمزُ فرع.
  final String scope;

  /// يُلزم بتغيير الكلمة الأوّليّة عند أوّل دخول (يُطبَّق عند الإنشاء فقط).
  final bool forcePasswordChange;
}

class ServerSetupBranch {
  const ServerSetupBranch({required this.code, required this.name});
  final String code;
  final String name;
}

class ServerSetupInput {
  const ServerSetupInput({
    required this.companyName,
    required this.currency,
    required this.businessProfile,
    required this.businessType,
    required this.vatEnabled,
    required this.vatRate,
    required this.fiscalYear,
    required this.branchName,
    required this.warehouseName,
    required this.adminPassword,
    required this.developerPassword,
    this.companyNameEn = '',
    this.companyPhone = '',
    this.companyAddress = '',
    this.taxNumber = '',
    this.commercialRegister = '',
    this.pricesIncludeTax = true,
    this.eInvoice = 'none',
    this.branchCode = '',
    this.branchAddress = '',
    this.branches = const [],
    this.users = const [],
    this.offlineDays = 7,
    this.tablesEnabled,
    this.deliveryEnabled,
    this.tableSection,
    this.tableNames = const [],
    this.serverPort = 8080,
  });

  final String companyName;
  final String companyNameEn;
  final String companyPhone;
  final String companyAddress;
  final String taxNumber;
  final String commercialRegister;
  final String currency;
  final String businessProfile;
  final String businessType;
  final bool vatEnabled;
  final double vatRate;
  final bool pricesIncludeTax;

  /// `jordan` · `egypt` · `none`.
  final String eInvoice;
  final int fiscalYear;
  final String branchName;
  final String branchCode;
  final String branchAddress;
  final String warehouseName;
  final List<ServerSetupBranch> branches;
  final String adminPassword;
  final String developerPassword;
  final List<ServerSetupUser> users;
  final int offlineDays;

  /// `null` ⇒ لا تُكتب علامةُ الميزة (باقةٌ بلا طاولات).
  final bool? tablesEnabled;
  final bool? deliveryEnabled;
  final String? tableSection;
  final List<String> tableNames;

  /// The HTTP port this main serves on (recorded in the device record).
  final int serverPort;
}

class ServerSetupReport {
  const ServerSetupReport({
    required this.branchIds,
    required this.createdUsers,
    required this.updatedUsers,
  });

  /// رمزُ الفرع (كبيرًا) → رقمُه. `HQ` للفرع الرئيسي.
  final Map<String, int> branchIds;
  final int createdUsers;
  final int updatedUsers;
}

class ServerSetupWriter {
  ServerSetupWriter({AppDatabase Function(PostgresConfig cfg)? openDatabase})
      : _open = openDatabase ??
            ((cfg) => AppDatabase.withExecutor(
                  openPostgresConnection(cfg),
                  isPostgres: true,
                ));

  final AppDatabase Function(PostgresConfig cfg) _open;

  /// يفتح قاعدةَ الخادم ويكتب ثم يغلقها.
  Future<ServerSetupReport> write(PostgresConfig cfg, ServerSetupInput input) async {
    final db = _open(cfg);
    try {
      return await apply(db, input);
    } finally {
      try {
        await db.close();
      } catch (_) {}
    }
  }

  /// الكتابةُ على [db] داخل معاملة (‏تُختبر على SQLite في الذاكرة).
  Future<ServerSetupReport> apply(AppDatabase db, ServerSetupInput i) async {
    // التجزئةُ خارج المعاملة: Argon2id ثقيلةٌ فلا تُبقي المعاملةَ مفتوحة.
    final devHash = i.developerPassword.trim().isEmpty
        ? null
        : await SecurityService.hashPasswordArgon2(i.developerPassword.trim());
    // (1) النواةُ ذرّيّة: الإعدادات + الفروع + الطاولات + السنة الماليّة.
    final branchIds = await db.transaction(() async {
      await _settings(db, i, devHash);
      final ids = await _branches(db, i);
      await _tables(db, i);
      await _fiscalYear(db, i.fiscalYear);
      return ids;
    });
    // (2) كلمةُ المسؤول والمستخدمون خارج المعاملة عمداً: createUser و
    //     updateUserPassword يطلقان فاحصَ تصادم كلمات المرور بلا انتظار داخل
    //     منطقة المعاملة، فيسقط بعد إغلاقها (transaction used after being
    //     closed). كلٌّ منهما idempotent فتُعاد المحاولة بلا تكرار.
    await _admin(db, i.adminPassword);
    final counts = await _users(db, i, branchIds);
    // (3) آخرُ كتابة — فأيُّ فشلٍ قبلها يُبقي المعالجَ ظاهراً عند الإقلاع التالي.
    await db.transaction(() async {
      // نمط قاعدة الخادم الجديدة يُكتب بـSQL كما كانت تفعل تهيئة الخادم القديمة
      // (قاعدةُ PostgreSQL المزروعة حديثاً، لا قاعدةُ هذا الجهاز) — فلا يمرّ
      // بمالك النمط المحلي (DeploymentModeCommitter).
      await _putRaw(db, 'network_mode', 'server');
      await _writeDeviceRecord(db, i.serverPort);
      await db.setSetting('setup_completed', 'true');
    });
    return ServerSetupReport(
      branchIds: branchIds,
      createdUsers: counts.$1,
      updatedUsers: counts.$2,
    );
  }

  /// A1 adoption contract for the main server: the SAME record and derived keys
  /// the committer writes for the other modes, but INTO this (PostgreSQL)
  /// database - the one the app reads after the restart. Without it the first
  /// boot got an ADOPT-BACKFILL and no self-check. `setup_completed` is
  /// written after it by [apply]; a re-run keeps the first completion stamp.
  Future<void> _writeDeviceRecord(AppDatabase db, int port) async {
    final previous = await ProvisioningStore.read(db);
    final now = DateTime.now().toUtc();
    final record = ProvisioningRecord(
      mode: NetworkMode.server.name,
      deviceKind: NetworkMode.server.name,
      serverPort: port,
      appVersion: AppConfig.version,
      setupCompletedAt: previous?.setupCompletedAt ?? now,
      selfCheckPending: true,
      pgConfigured: true,
    );
    await ProvisioningStore.write(db, record);
    for (final e in record.derivedSettings.entries) {
      if (e.key == 'setup_completed') continue; // the very last write
      await _putRaw(db, e.key, e.value);
    }
  }

  Future<void> _settings(AppDatabase db, ServerSetupInput i, String? devHash) async {
    Future<void> put(String k, String v) => db.setSetting(k, v);
    Future<void> putIf(String k, String v) async {
      if (v.trim().isNotEmpty) await put(k, v.trim());
    }

    await put('company_name', i.companyName.trim());
    await putIf('company_name_en', i.companyNameEn);
    await putIf('company_phone', i.companyPhone);
    await putIf('company_address', i.companyAddress);
    await putIf('company_tax_id', i.taxNumber);
    await putIf('company_cr_number', i.commercialRegister);
    await put('business_type', i.businessType);
    await put('business_profile', i.businessProfile);
    await put('system_currency', i.currency);
    await put('tax_enabled', i.vatEnabled ? 'true' : 'false');
    await put('tax_rate', i.vatRate.toString());
    await put('pos_default_tax_rate',
        (i.vatEnabled ? i.vatRate / 100.0 : 0.0).toString());
    await put('prices_include_tax', i.pricesIncludeTax ? 'true' : 'false');
    await put('show_jofotara_einvoice', i.eInvoice == 'jordan' ? 'true' : 'false');
    await put('show_eta_einvoice', i.eInvoice == 'egypt' ? 'true' : 'false');
    await put('offline_login_grace_days', i.offlineDays.toString());
    if (devHash != null) {
      await put('developer_password_hash', devHash);
      await db.customStatement(
          "DELETE FROM settings WHERE key = 'developer_password_salt'");
    }
    final gid = await db.getSettingValue('company_global_id');
    if (gid == null || gid.isEmpty) {
      await put('company_global_id', UuidV7.generate());
    }
    if (i.tablesEnabled != null) {
      await put('feature.pos.tables', i.tablesEnabled.toString());
    }
    if (i.deliveryEnabled != null) {
      await put('feature.pos.delivery', i.deliveryEnabled.toString());
    }
  }

  /// الفرعُ الرئيسيّ المزروع يُعاد استعمالُه (‏ويُعاد تسميتُه)، والفروعُ الأخرى
  /// بالرمز. المفتاح `HQ` للرئيسيّ ورمزُ كلِّ فرعٍ كبيراً.
  Future<Map<String, int>> _branches(AppDatabase db, ServerSetupInput i) async {
    final all = await db.select(db.branches).get();
    final name = i.branchName.trim();
    final code = i.branchCode.trim();
    final address = i.branchAddress.trim();
    Branche? main = all.where((b) => b.isSystemDefault).firstOrNull ??
        all.where((b) => b.name.trim() == name).firstOrNull;
    int mainId;
    if (main == null) {
      mainId = await db.createBranch(
        name: name,
        code: code.isEmpty ? null : code,
        address: address.isEmpty ? null : address,
      );
    } else {
      mainId = main.id;
      await db.updateBranch(main.copyWith(
        name: name,
        code: code.isEmpty ? Value(main.code) : Value(code),
        address: address.isEmpty ? Value(main.address) : Value(address),
      ));
    }
    await _warehouse(db, mainId, i.warehouseName.trim());

    final ids = <String, int>{'HQ': mainId};
    if (code.isNotEmpty) ids[code.toUpperCase()] = mainId;
    for (final row in i.branches) {
      final rc = row.code.trim();
      final key = rc.toUpperCase();
      if (ids.containsKey(key)) continue; // نفسُ رمز الفرع الرئيسي
      final existing = all
          .where((b) => (b.code ?? '').trim().toUpperCase() == key)
          .firstOrNull;
      if (existing != null) {
        ids[key] = existing.id;
        if (existing.name.trim() != row.name.trim()) {
          await db.updateBranch(existing.copyWith(name: row.name.trim()));
        }
      } else {
        ids[key] = await db.createBranch(name: row.name.trim(), code: rc);
      }
    }
    return ids;
  }

  /// UPDATE ثم INSERT-إن-صفر: بلا ON CONFLICT (يعمل على أي لهجة وأي مخطط قديم).
  Future<void> _putRaw(AppDatabase db, String key, String value) async {
    await db.customStatement(
      'UPDATE settings SET value = ? WHERE key = ?',
      [value, key],
    );
    final rows = await db
        .customSelect('SELECT 1 AS x FROM settings WHERE key = ?',
            variables: [Variable<String>(key)])
        .get();
    if (rows.isEmpty) {
      await db.customStatement(
        'INSERT INTO settings (key, value) VALUES (?, ?)',
        [key, value],
      );
    }
  }

  Future<void> _warehouse(AppDatabase db, int branchId, String name) async {
    if (name.isEmpty) return;
    final existing = await db.getWarehousesByBranch(branchId);
    final seeded = existing.where((w) => w.isSystemDefault).firstOrNull ??
        existing.where((w) => w.name.trim() == name).firstOrNull;
    if (seeded == null) {
      await db.createWarehouseForBranch(
          name: name, branchId: branchId, isDefault: true);
    } else if (seeded.name.trim() != name) {
      await db.update(db.warehouses).replace(seeded.copyWith(name: name));
    }
  }

  Future<void> _admin(AppDatabase db, String password) async {
    final admin = await db.getUserByUsername('admin');
    if (admin == null) {
      throw StateError('حساب المدير غير موجود في قاعدة بيانات الخادم');
    }
    await db.updateUserPassword(userId: admin.user.id, newPassword: password);
  }

  Future<(int, int)> _users(
    AppDatabase db,
    ServerSetupInput i,
    Map<String, int> branchIds,
  ) async {
    final roles = await db.getAllRoles();
    int? roleOf(ServerSetupUser u) {
      final byName = roles.where((r) => r.name == u.roleName).firstOrNull;
      if (byName != null) return byName.id;
      return roles.where((r) => r.id == u.roleId).firstOrNull?.id;
    }

    var created = 0;
    var updated = 0;
    for (final u in i.users) {
      final username = u.username.trim();
      final roleId = roleOf(u);
      final found = await db.getUserByUsername(username);
      final int userId;
      if (found != null) {
        userId = found.user.id;
        await db.updateUserInfo(
          userId: userId,
          displayName: u.name.trim(),
          roleId: roleId,
        );
        updated++;
      } else {
        userId = await db.createUser(
          username: username,
          password: u.password,
          displayName: u.name.trim(),
          roleId: roleId,
          forcePasswordChange: u.forcePasswordChange,
        );
        created++;
      }
      final scope = u.scope.trim().toUpperCase();
      final branchesFor = switch (scope) {
        'ALL' => branchIds.values.toSet().toList(),
        'HQ' => [branchIds['HQ']!],
        _ => [branchIds[scope] ?? branchIds['HQ']!],
      };
      await db.setUserBranchAccess(userId, branchesFor);
    }
    return (created, updated);
  }

  Future<void> _tables(AppDatabase db, ServerSetupInput i) async {
    if (i.tableNames.isEmpty || i.tableSection == null) return;
    final sections = await db.getAllSections();
    final sectionId = sections
            .where((s) => s.name.trim() == i.tableSection)
            .firstOrNull
            ?.id ??
        await db.createSection(i.tableSection!);
    final existing = (await db.select(db.restaurantTables).get())
        .where((t) => t.sectionId == sectionId)
        .map((t) => t.name.trim())
        .toSet();
    for (final n in i.tableNames) {
      if (existing.contains(n)) continue;
      await db.createTable(name: n, capacity: 4, sectionId: sectionId);
    }
  }

  Future<void> _fiscalYear(AppDatabase db, int year) async {
    final years = await db.getFiscalYears();
    if (years.any((y) => y.name.trim() == '$year')) return;
    final start = DateTime(year, 1, 1);
    final end = DateTime(year, 12, 31);
    final id =
        await db.createFiscalYear(name: '$year', startDate: start, endDate: end);
    await db.generatePeriodsForYear(id, start, end);
  }
}
