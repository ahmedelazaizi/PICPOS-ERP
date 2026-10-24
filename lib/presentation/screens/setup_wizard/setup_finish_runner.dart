// تشغيلُ «إنهاء الإعداد» — **ما يُكتَب** عند البدء، مفصولاً عن الشاشة.
//
// ═══ لماذا خرج من `setup_wizard_screen.dart` ═══
//
// بندُ المالك ٦ أعاد ترتيبَ الخطوات كلَّها، وشرطُه الصريح: «لا يضيع إعدادٌ
// واحدٌ ممّا يكتبه المعالجُ القديم». و`_finishSetup()` كان دالّةً من ٤٠٠ سطرٍ
// داخلَ `State` لا تُقاس إلّا بتركيب الشاشة كاملةً مع الشبكة والمرآة والمزامنة
// (‏راجع ترويسةَ `spec_b3_setup_wizard_cache_hardening_test.dart`).
//
// فالكتاباتُ هنا **بالترتيب نفسه** وعبر منفذٍ واحد (`SetupPersistence`) يُنفَّذ
// في الإنتاج بالمستودعات الحقيقيّة (`setup_persistence_riverpod.dart`)، وفي
// الاختبار بمسجّلٍ يقارن التسلسلَ بتسلسل المعالج القديم حرفاً
// (`test/unit/setup_finish_runner_parity_test.dart`).
//
// ═══ ⚠️ ما يبقى من سلوك الأمان ═══
//
// • `setup_completed=true` **آخرُ** ما يُكتَب — فأيُّ فشلٍ قبله يترك المعالجَ
//   ظاهراً عند الإقلاع التالي ولا يدخل المستخدمُ على قاعدةٍ نصفِ مهيّأة.
// • فشلُ اعتماد نمط التشغيل (`CommitFailed`) يوقف التشغيلَ كما كان.
// • الإعادةُ تبدأ من الأوّل (‏قرارُ المالك)، والكتاباتُ كلُّها قابلةٌ للتكرار:
//   الفرعُ والمخزنُ يُعاد استعمالُهما، والمنتجاتُ والمستخدمون الذين نجحوا في
//   محاولةٍ سابقةٍ لا يُكرَّرون (‏يتذكّرهم هذا الكائن).
library;

import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;

import '../../../core/config/app_config.dart';
import '../../../core/config/runtime_config_snapshot.dart';
import '../../../core/i18n/tr.dart';
import '../../../data/providers/providers.dart';
import '../../../services/network_service.dart';
import 'setup_client_branch.dart';

/// بلدُ الفوترة الإلكترونيّة — يقرّر أيَّ منصّةٍ تظهر في شاشاتها.
enum SetupEInvoiceCountry { jordan, egypt, none }

/// كلُّ ما جمعه المعالج — مدخلُ [SetupFinishRunner.run].
///
/// ⚠️ **الحقولُ القديمةُ بمعناها القديم حرفاً** (‏نصوصٌ خامٌ تُقَصّ هنا كما
/// كان `_finishSetup` يقصّها). والجديدةُ `null`/فارغةٌ ⇒ لا كتابةَ إطلاقاً،
/// فمدخلٌ «مكافئٌ للقديم» يُنتج تسلسلَ الكتابات القديمَ نفسَه.
class SetupDraft {
  SetupDraft({
    required this.profile,
    required this.developerPassword,
    required this.companyName,
    required this.companyPhone,
    required this.companyAddress,
    required this.businessType,
    required this.currency,
    required this.branchName,
    required this.warehouseName,
    required this.products,
    required this.users,
    required this.enableTax,
    required this.taxRate,
    required this.networkMode,
    required this.serverPortText,
    this.selectedClientBranchId,
    this.syncedBranches = const [],
    this.companyNameEn = '',
    this.taxNumber = '',
    this.commercialRegister = '',
    this.logo,
    this.branchCode = '',
    this.branchAddress = '',
    this.pricesIncludeTax,
    this.eInvoiceCountry,
    this.cashBoxName,
    this.bankSafeName,
    this.bankName,
    this.bankAccountNumber,
    this.cliqSafeName,
    this.adminPassword,
    this.fiscalYear,
    this.extraStage,
  });

  // ── حقولُ المعالج القديم ──
  final BusinessProfile profile;
  final String developerPassword;
  final String companyName;
  final String companyPhone;
  final String companyAddress;
  final String businessType;
  final String currency;
  final String branchName;
  final String warehouseName;
  final List<Map<String, String>> products;
  final List<Map<String, dynamic>> users;
  final bool enableTax;
  final double taxRate;
  final NetworkMode networkMode;
  final String serverPortText;
  final int? selectedClientBranchId;
  final List<Branche> syncedBranches;

  // ── بندُ المالك ٦ — جديدة ──
  final String companyNameEn;
  final String taxNumber;
  final String commercialRegister;
  final Uint8List? logo;
  final String branchCode;
  final String branchAddress;
  final bool? pricesIncludeTax;
  final SetupEInvoiceCountry? eInvoiceCountry;
  final String? cashBoxName;
  final String? bankSafeName;
  final String? bankName;
  final String? bankAccountNumber;
  final String? cliqSafeName;

  /// `null` ⇒ لا تُلمَس كلمةُ مرور المدير (‏العميلُ والخادمُ والمرآة).
  final String? adminPassword;

  // ── المعالج v2 (‏P3) — اختياريّتان: `null` ⇒ سلوكٌ مطابقٌ للقديم ──

  /// سنةٌ ماليّةٌ محدَّدة؛ `null` ⇒ سنةُ الساعة الجارية.
  final int? fiscalYear;

  /// كتاباتٌ إضافيّةٌ (‏طاولات · overrides · تفضيلات) تجري **قبل** `finalize`
  /// فتبقى `setup_completed` آخرَ ما يُكتَب.
  final Future<void> Function(SetupPersistence p)? extraStage;
}

/// منفذُ الكتابة — كلُّ نداءٍ كان `_finishSetup` يجريه، بلا زيادة.
abstract class SetupPersistence {
  Future<void> saveSetting(String key, String value);

  /// عبر `SettingsRepositoryCached` الحيّ (‏Spec B3).
  Future<void> saveCachedSetting(String key, String value);
  Future<void> setDeveloperPassword(String password);
  Future<void> setCurrency(String code);

  Future<List<Branche>> getAllBranches();
  Future<void> updateBranch(Branche branch);
  Future<int> createBranch(String name);
  Future<List<Warehouse>> getWarehousesByBranch(int branchId);
  Future<void> updateWarehouse(Warehouse warehouse);
  Future<int> createWarehouseForBranch({
    required String name,
    required int branchId,
  });

  Future<SafeData?> getDefaultSafeByType(String type);
  Future<void> updateSafeDetails(
    SafeData safe, {
    required String name,
    String? bankName,
    String? accountNumber,
  });

  Future<void> insertProduct(ProductsCompanion product);
  Future<int?> findUserId(String username);
  Future<void> updateUserPassword(int userId, String password);
  Future<void> createUser({
    required String username,
    required String password,
    required String displayName,
    int? roleId,
  });

  /// يُرجع سببَ الفشل بالعربيّة أو `null` عند النجاح.
  Future<String?> commitDeploymentMode(NetworkMode mode, int serverPort);
  Future<void> saveClientBranchId(int branchId);
  Future<int> createFiscalYear(String name, DateTime start, DateTime end);
  Future<void> generatePeriodsForYear(int yearId, DateTime start, DateTime end);
  Future<void> recordAudit(String event, Map<String, dynamic> payload);
  Future<bool> rehydrateRuntimeConfigCache();

}

/// منفذٌ إضافيٌّ للمعالج v2 (‏P3): قسمٌ للطاولات و[count] طاولةً **بلا تكرار**
/// (‏بالاسم داخل القسم) — تشغيلتان ⇒ العددُ نفسُه. منفصلٌ عن [SetupPersistence]
/// كي لا تنكسر مسجّلاتُ الاختبار القديمة التي implements الأصل.
abstract interface class SetupTablesPort {
  Future<int> ensureTables({
    required String sectionName,
    required int count,
    required String Function(int n) tableName,
  });
}

/// مراحلُ التشغيل كما تعرضها المراجعة.
enum SetupRunStage {
  /// المقرّ: كتابةُ بيانات الإعداد في قاعدة PostgreSQL (‏معاملة واحدة).
  serverData,
  settings,
  branch,
  cashBanks,
  people,
  tax,
  mode,
  fiscalYear,
  extras,
  finalize,
}

extension SetupRunStageLabel on SetupRunStage {
  String get label => switch (this) {
        SetupRunStage.serverData => tr('بيانات الشركة والفروع والمستخدمين على الخادم'),
        SetupRunStage.settings => tr('حفظ بيانات الشركة والإعدادات الأساسية'),
        SetupRunStage.branch => tr('الفرع والمخزن الرئيسيان'),
        SetupRunStage.cashBanks => tr('الصناديق والحسابات البنكية'),
        SetupRunStage.people => tr('المستخدمون والمنتجات الأولى'),
        SetupRunStage.tax => tr('الضريبة والفوترة الإلكترونية'),
        SetupRunStage.mode => tr('اعتماد وضع التشغيل'),
        SetupRunStage.fiscalYear => tr('السنة المالية الحالية'),
        SetupRunStage.extras => tr('الطاولات وإعدادات الأقسام وتفضيلات الجهاز'),
        SetupRunStage.finalize => tr('إنهاء الإعداد'),
      };
}

/// نتيجةُ محاولةٍ واحدة.
class SetupRunResult {
  const SetupRunResult({
    required this.ok,
    this.failedStage,
    this.error,
    this.warnings = const [],
    this.failedUsers = const [],
  });

  final bool ok;
  final SetupRunStage? failedStage;
  final String? error;

  /// تحذيراتٌ غيرُ قاتلة — تُعرَض في إشعارٍ واحدٍ بعد النجاح.
  final List<String> warnings;

  /// مستخدمون تعذّر إنشاؤهم — `username: سبب`.
  final List<String> failedUsers;
}

/// مشغّلُ الإعداد — كائنٌ واحدٌ يعيش مع الشاشة ليتذكّر ما نجح بين المحاولات.
class SetupFinishRunner {
  SetupFinishRunner({DateTime Function()? clock})
      : _clock = clock ?? DateTime.now;

  final DateTime Function() _clock;

  /// منتجاتٌ ومستخدمون كُتبوا في محاولةٍ سابقة — لا يُكرَّرون عند الإعادة.
  bool _productsWritten = false;
  final Set<String> _createdUsernames = {};

  Future<SetupRunResult> run(
    SetupDraft d,
    SetupPersistence p, {
    void Function(SetupRunStage stage)? onStage,
  }) async {
    final warnings = <String>[];
    final failedUsers = <String>[];
    var stage = SetupRunStage.settings;
    void enter(SetupRunStage s) {
      stage = s;
      onStage?.call(s);
    }

    try {
      enter(SetupRunStage.settings);
      // Phase B: breadcrumb للاستئناف بعد انهيارٍ في المنتصف.
      await p.saveSetting('setup_in_progress', 'true');
      await p.saveCachedSetting('business_profile', d.profile.name);
      try {
        await p.setDeveloperPassword(d.developerPassword.trim());
      } catch (_) {
        warnings.add(tr('لم يُحفَظ كلمة مرور المطوّر'));
      }

      final companyName = d.companyName.trim();
      if (companyName.isNotEmpty) {
        await p.saveSetting('company_name', companyName);
      }
      if (d.companyPhone.trim().isNotEmpty) {
        await p.saveSetting('company_phone', d.companyPhone.trim());
      }
      if (d.companyAddress.trim().isNotEmpty) {
        await p.saveSetting('company_address', d.companyAddress.trim());
      }
      await p.saveSetting('business_type', d.businessType);

      // ── بندُ المالك ٦: هويّةُ الشركة الكاملة — بمفاتيحِ شاشة «معلومات
      //    الشركة» نفسِها (`company_tax_id` · `company_logo`) كي يقرأها
      //    القالبُ والطباعةُ بلا ربطٍ جديد.
      if (d.companyNameEn.trim().isNotEmpty) {
        await p.saveSetting('company_name_en', d.companyNameEn.trim());
      }
      if (d.taxNumber.trim().isNotEmpty) {
        await p.saveSetting('company_tax_id', d.taxNumber.trim());
      }
      if (d.commercialRegister.trim().isNotEmpty) {
        await p.saveSetting('company_cr_number', d.commercialRegister.trim());
      }
      if (d.logo != null && d.logo!.isNotEmpty) {
        // نفسُ ترميز `company_info_widget_io.dart` — بايتاتٌ خامٌ لا base64.
        await p.saveSetting('company_logo', String.fromCharCodes(d.logo!));
      }

      await p.setCurrency(d.currency);

      enter(SetupRunStage.branch);
      final (branchId, warehouseId) = await _branchAndWarehouse(d, p);
      if (branchId != null && warehouseId != null) {
        await p.saveSetting(
          'pos_default_warehouse_branch_$branchId',
          warehouseId.toString(),
        );
        await p.saveSetting('pos_default_warehouse_id', warehouseId.toString());
      }

      enter(SetupRunStage.cashBanks);
      if (d.networkMode == NetworkMode.standalone) {
        await _renameSafe(p, 'cash', d.cashBoxName);
        await _renameSafe(
          p,
          'bank',
          d.bankSafeName,
          bankName: d.bankName,
          accountNumber: d.bankAccountNumber,
        );
        await _renameSafe(p, 'click', d.cliqSafeName);
      }

      enter(SetupRunStage.people);
      if (!_productsWritten) {
        for (var i = 0; i < d.products.length; i++) {
          final prod = d.products[i];
          try {
            final code = 'SETUP-${_clock().millisecondsSinceEpoch}-$i';
            await p.insertProduct(
              ProductsCompanion.insert(
                code: code,
                name: prod['name']!,
                salePrice: Value(double.tryParse(prod['price'] ?? '0') ?? 0),
                costPrice: Value(double.tryParse(prod['cost'] ?? '0') ?? 0),
              ),
            );
          } catch (_) {}
        }
        _productsWritten = true;
      }

      final adminPassword = d.adminPassword;
      if (adminPassword != null &&
          adminPassword.isNotEmpty &&
          d.networkMode == NetworkMode.standalone) {
        // ⚠️ قاتلٌ لا تحذير: مديرٌ يظنّ أنّه غيّر كلمتَه وهي لم تتغيّر يُقفَل
        //    خارجَ نظامه — أو يتركه مفتوحاً بالافتراضيّة.
        final adminId = await p.findUserId('admin');
        if (adminId == null) {
          throw StateError(tr('حساب المدير غير موجود في قاعدة البيانات'));
        }
        await p.updateUserPassword(adminId, adminPassword);
      }

      for (final u in d.users) {
        final username = u['username'] as String;
        if (_createdUsernames.contains(username)) continue;
        try {
          await p.createUser(
            username: username,
            password: u['password'] as String,
            displayName: u['displayName'] as String,
            roleId: u['roleId'] as int?,
          );
          _createdUsernames.add(username);
        } catch (e) {
          failedUsers.add('$username: $e');
        }
      }

      enter(SetupRunStage.tax);
      await p.saveSetting('tax_enabled', d.enableTax ? 'true' : 'false');
      await p.saveSetting('tax_rate', d.taxRate.toString());
      // POS reads tax as decimal (e.g. 0.14 for 14%).
      final taxDecimal = d.enableTax ? (d.taxRate / 100.0) : 0.0;
      await p.saveSetting('pos_default_tax_rate', taxDecimal.toString());
      if (d.pricesIncludeTax != null) {
        await p.saveSetting(
          'prices_include_tax',
          d.pricesIncludeTax! ? 'true' : 'false',
        );
      }
      if (d.eInvoiceCountry != null) {
        // نفسُ المفتاحَين اللذين تكتبهما شاشةُ الإعدادات — `'false'` يُخفي
        // المنصّة، وما سواه (‏ومنه الغياب) يُظهرها.
        final c = d.eInvoiceCountry!;
        await p.saveSetting(
          'show_jofotara_einvoice',
          c == SetupEInvoiceCountry.jordan ? 'true' : 'false',
        );
        await p.saveSetting(
          'show_eta_einvoice',
          c == SetupEInvoiceCountry.egypt ? 'true' : 'false',
        );
      }

      enter(SetupRunStage.mode);
      final failure = await p.commitDeploymentMode(
        d.networkMode,
        int.tryParse(d.serverPortText) ?? 8080,
      );
      if (failure != null) {
        // BUG 5 + 7 + 1 (Spec 125): لا حالةَ جزئيّةً — يقف ولا يكمل.
        return SetupRunResult(
          ok: false,
          failedStage: stage,
          error: failure,
          warnings: warnings,
          failedUsers: failedUsers,
        );
      }
      await p.saveCachedSetting(
        'deployment_mode',
        switch (d.networkMode) {
          NetworkMode.standalone => DeploymentMode.standalone,
          NetworkMode.server => DeploymentMode.server,
          NetworkMode.client => DeploymentMode.client,
          NetworkMode.mirror => DeploymentMode.mirror,
        }.key,
      );
      await _clientBranch(d, p);

      enter(SetupRunStage.fiscalYear);
      // العميلُ يأخذ سنتَه الماليّة من الخادم بالمزامنة (‏Spec 001).
      if (d.networkMode != NetworkMode.client) {
        try {
          final now = _clock();
          final year = d.fiscalYear ?? now.year;
          final fyStart = DateTime(year, 1, 1);
          final fyEnd = DateTime(year, 12, 31);
          final fyId = await p.createFiscalYear('$year', fyStart, fyEnd);
          await p.generatePeriodsForYear(fyId, fyStart, fyEnd);
        } catch (_) {
          // Fiscal year may already exist — silently continue
        }
      }

      if (d.extraStage != null) {
        enter(SetupRunStage.extras);
        await d.extraStage!(p);
      }

      enter(SetupRunStage.finalize);
      await p.saveSetting('setup_completed', 'true');
      await p.saveSetting('setup_in_progress', '');
      await p.recordAudit('setup_completed', {
        'profile': d.profile.name,
        'mode': d.networkMode.name,
        'business_type': d.businessType,
      });
      if (!await p.rehydrateRuntimeConfigCache()) {
        warnings.add(tr('تعذّر تحديث ذاكرة الإعدادات المؤقتة'));
      }
      return SetupRunResult(
        ok: true,
        warnings: warnings,
        failedUsers: failedUsers,
      );
    } catch (e) {
      return SetupRunResult(
        ok: false,
        failedStage: stage,
        error: '$e',
        warnings: warnings,
        failedUsers: failedUsers,
      );
    }
  }

  /// BUG 5a: الفرعُ والمخزنُ المزروعان يُعاد استعمالُهما (‏ويُعاد تسميتُهما)
  /// بدل إنشاء صفٍّ ثانٍ بجوارهما — حرفاً كما كان في `_finishSetup`.
  Future<(int?, int?)> _branchAndWarehouse(
    SetupDraft d,
    SetupPersistence p,
  ) async {
    final branchName = d.branchName.trim();
    final code = d.branchCode.trim();
    final address = d.branchAddress.trim();
    int? branchId;
    if (branchName.isNotEmpty) {
      try {
        final existing = await p.getAllBranches();
        final seeded = existing.where((b) => b.isSystemDefault).firstOrNull ??
            existing.where((b) => b.name.trim() == branchName).firstOrNull;
        if (seeded != null) {
          branchId = seeded.id;
          if (seeded.name.trim() != branchName) {
            await p.updateBranch(seeded.copyWith(
              name: branchName,
              lastModifiedAt: Value(_clock()),
            ));
          }
        } else {
          branchId = await p.createBranch(branchName);
        }
      } catch (_) {
        final existing = await p.getAllBranches();
        branchId = existing
            .where((b) => b.name.trim() == branchName)
            .map((b) => b.id)
            .firstOrNull;
      }
      // بندُ المالك ٦: رمزُ الفرع وعنوانُه — رمزُ الفرع بادئةُ أرقام الفواتير.
      if (branchId != null && (code.isNotEmpty || address.isNotEmpty)) {
        // ⚠️ `firstOrNull` لا `first`: صفٌّ لم يُقرأ بعد إنشائه (‏قراءةٌ
        //    متأخّرةٌ في العميل) يُترَك بلا رمزٍ ولا يُسقط التشغيلَ كلَّه.
        final current = (await p.getAllBranches())
            .where((b) => b.id == branchId)
            .firstOrNull;
        if (current != null) {
          await p.updateBranch(current.copyWith(
            code: code.isNotEmpty ? Value(code) : Value(current.code),
            address:
                address.isNotEmpty ? Value(address) : Value(current.address),
            lastModifiedAt: Value(_clock()),
          ));
        }
      }
    }

    final warehouseName = d.warehouseName.trim();
    int? warehouseId;
    if (warehouseName.isNotEmpty && branchId != null) {
      try {
        final existing = await p.getWarehousesByBranch(branchId);
        final seeded = existing.where((w) => w.isSystemDefault).firstOrNull ??
            existing.where((w) => w.name.trim() == warehouseName).firstOrNull;
        if (seeded != null) {
          warehouseId = seeded.id;
          if (seeded.name.trim() != warehouseName) {
            await p.updateWarehouse(seeded.copyWith(
              name: warehouseName,
              lastModifiedAt: Value(_clock()),
            ));
          }
        } else {
          warehouseId = await p.createWarehouseForBranch(
            name: warehouseName,
            branchId: branchId,
          );
        }
      } catch (_) {
        final existing = await p.getWarehousesByBranch(branchId);
        warehouseId = existing
            .where((w) => w.name.trim() == warehouseName)
            .map((w) => w.id)
            .firstOrNull;
      }
    }
    return (branchId, warehouseId);
  }

  /// يعيد تسميةَ صندوقٍ مزروعٍ بنوعه — ولا يلمسه إن لم يتغيّر شيء.
  Future<void> _renameSafe(
    SetupPersistence p,
    String type,
    String? name, {
    String? bankName,
    String? accountNumber,
  }) async {
    final trimmed = name?.trim() ?? '';
    final bank = bankName?.trim() ?? '';
    final account = accountNumber?.trim() ?? '';
    if (trimmed.isEmpty && bank.isEmpty && account.isEmpty) return;
    final safe = await p.getDefaultSafeByType(type);
    if (safe == null) return;
    final newName = trimmed.isEmpty ? safe.name : trimmed;
    final newBank = bank.isEmpty ? safe.bankName : bank;
    final newAccount = account.isEmpty ? safe.accountNumber : account;
    if (newName == safe.name &&
        newBank == safe.bankName &&
        newAccount == safe.accountNumber) {
      return;
    }
    await p.updateSafeDetails(
      safe,
      name: newName,
      bankName: newBank,
      accountNumber: newAccount,
    );
  }

  /// العميل: فرعُ الجهاز ومخزنُه الافتراضيّ وبادئاتُ الترقيم من رمز الفرع.
  Future<void> _clientBranch(SetupDraft d, SetupPersistence p) async {
    final branchId = d.selectedClientBranchId;
    if (d.networkMode != NetworkMode.client || branchId == null) return;
    await writeClientBranchSettings(
      p,
      branchId: branchId,
      syncedBranches: d.syncedBranches,
    );
  }
}
