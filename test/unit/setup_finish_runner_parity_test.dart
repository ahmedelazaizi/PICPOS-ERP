// test/unit/setup_finish_runner_parity_test.dart
//
// **تكافؤُ الكتابة** بين المعالج القديم والمشغّل الجديد (‏بندُ المالك ٦).
//
// ═══ لماذا ═══
//
// إعادةُ هيكلة المعالج نقلت `_finishSetup()` من الشاشة إلى
// `SetupFinishRunner`. وشرطُ المالك: «لا يضيع إعدادٌ واحدٌ ممّا يكتبه القديم».
// فالمتوقَّعُ أدناه **منسوخٌ نداءً نداءً من `_finishSetup()` القديم** (‏16917df7،
// `setup_wizard_screen.dart:1396–1792`) — مفاتيحُ الإعدادات بقيمها، والفرعُ
// والمخزنُ، والمنتجاتُ، والمستخدمون، والضريبةُ، ونمطُ التشغيل، والسنةُ
// الماليّة، وسجلُّ التدقيق — ويُقارَن بما يكتبه المشغّلُ لمدخلٍ مكافئ.
//
// ⚠️ **المقارنةُ بالتسلسل الكامل لا بمجموعة مفاتيح**: الترتيبُ جزءٌ من الأمان
//    (‏`setup_completed` آخرُ ما يُكتَب)، ونقلُ سطرٍ قبله يمرّ بفحص مجموعة.
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/core/config/app_config.dart';
import 'package:ural_erp/data/providers/providers.dart';
import 'package:ural_erp/presentation/screens/setup_wizard/setup_finish_runner.dart';
import 'package:ural_erp/services/network_service.dart';

/// منفذٌ يسجّل كلَّ نداءٍ نصّاً — ويحاكي صفوفَ القاعدة المزروعة.
class RecordingPersistence implements SetupPersistence {
  RecordingPersistence({
    List<Branche>? branches,
    List<Warehouse>? warehouses,
    this.commitFailure,
    this.throwOn,
    Map<String, SafeData>? safes,
  })  : branches = branches ?? [_seededBranch()],
        warehouses = warehouses ?? [_seededWarehouse()],
        safes = safes ?? {};

  final List<Branche> branches;
  final List<Warehouse> warehouses;
  final Map<String, SafeData> safes;
  String? commitFailure;

  /// اسمُ نداءٍ يرمي عند بلوغه — لمحاكاة فشلٍ في المنتصف.
  String? throwOn;
  final calls = <String>[];

  void _log(String c) {
    if (throwOn != null && c.startsWith(throwOn!)) {
      throw StateError('simulated failure at $c');
    }
    calls.add(c);
  }

  @override
  Future<void> saveSetting(String key, String value) async =>
      _log('save:$key=$value');
  @override
  Future<void> saveCachedSetting(String key, String value) async =>
      _log('cache:$key=$value');
  @override
  Future<void> setDeveloperPassword(String password) async =>
      _log('devpwd:$password');
  @override
  Future<void> setCurrency(String code) async => _log('currency:$code');
  @override
  Future<List<Branche>> getAllBranches() async {
    _log('getAllBranches');
    return branches;
  }

  @override
  Future<void> updateBranch(Branche b) async {
    _log('updateBranch:${b.id}:${b.name}:${b.code}:${b.address}');
    final i = branches.indexWhere((x) => x.id == b.id);
    branches[i] = b;
  }

  @override
  Future<int> createBranch(String name) async {
    _log('createBranch:$name');
    return 99;
  }

  @override
  Future<List<Warehouse>> getWarehousesByBranch(int branchId) async {
    _log('getWarehouses:$branchId');
    return warehouses.where((w) => w.branchId == branchId).toList();
  }

  @override
  Future<void> updateWarehouse(Warehouse w) async =>
      _log('updateWarehouse:${w.id}:${w.name}');
  @override
  Future<int> createWarehouseForBranch({
    required String name,
    required int branchId,
  }) async {
    _log('createWarehouse:$name@$branchId');
    return 77;
  }

  @override
  Future<SafeData?> getDefaultSafeByType(String type) async {
    _log('getSafe:$type');
    return safes[type];
  }

  @override
  Future<void> updateSafeDetails(
    SafeData safe, {
    required String name,
    String? bankName,
    String? accountNumber,
  }) async =>
      _log('updateSafe:${safe.id}:$name:$bankName:$accountNumber:'
          '${safe.branchId}:${safe.linkedAccountId}');
  @override
  Future<void> insertProduct(ProductsCompanion p) async => _log(
      'insertProduct:${p.code.value}:${p.name.value}:${p.salePrice.value}:'
      '${p.costPrice.value}');
  @override
  Future<int?> findUserId(String username) async {
    _log('findUser:$username');
    return username == 'admin' ? 1 : null;
  }

  @override
  Future<void> updateUserPassword(int userId, String password) async =>
      _log('userPassword:$userId:$password');
  @override
  Future<void> createUser({
    required String username,
    required String password,
    required String displayName,
    int? roleId,
  }) async =>
      _log('createUser:$username:$password:$displayName:$roleId');
  @override
  Future<String?> commitDeploymentMode(NetworkMode mode, int port) async {
    _log('commit:${mode.name}:$port');
    return commitFailure;
  }

  @override
  Future<void> saveClientBranchId(int id) async => _log('clientBranch:$id');
  @override
  Future<int> createFiscalYear(String name, DateTime s, DateTime e) async {
    _log('fiscalYear:$name:${s.toIso8601String()}:${e.toIso8601String()}');
    return 5;
  }

  @override
  Future<void> generatePeriodsForYear(int id, DateTime s, DateTime e) async =>
      _log('periods:$id');
  @override
  Future<void> recordAudit(String event, Map<String, dynamic> payload) async =>
      _log('audit:$event:${payload['profile']}:${payload['mode']}:'
          '${payload['business_type']}');
  @override
  Future<bool> rehydrateRuntimeConfigCache() async {
    _log('rehydrate');
    return true;
  }
}

Branche _seededBranch({String name = 'الفرع الرئيسي', String? code}) =>
    Branche(
      id: 1,
      name: name,
      code: code,
      isActive: true,
      isSystemDefault: true,
      rowVersion: 1,
    );

Warehouse _seededWarehouse({int branchId = 1}) => Warehouse(
      id: 1,
      name: 'المخزن الرئيسي',
      branchId: branchId,
      type: 'main',
      isDefault: true,
      isActive: true,
      isSystemDefault: true,
      rowVersion: 1,
    );

final _clock = DateTime(2026, 10, 2, 9, 30);

/// مدخلٌ **مكافئٌ للمعالج القديم** — الحقولُ الجديدةُ كلُّها على افتراضها.
SetupDraft _legacyDraft({
  NetworkMode mode = NetworkMode.standalone,
  int? clientBranchId,
  List<Branche> synced = const [],
}) =>
    SetupDraft(
      profile: BusinessProfile.lite,
      developerPassword: ' 1234 ',
      companyName: ' شركة النيل ',
      companyPhone: '0790000000',
      companyAddress: 'عمّان',
      businessType: 'retail',
      currency: 'JOD',
      branchName: 'الفرع الرئيسي',
      warehouseName: 'مخزن الصالة',
      products: [
        {'name': 'شاي', 'price': '1.5', 'cost': '1'},
      ],
      users: [
        {
          'displayName': 'سارة',
          'username': 'sara',
          'password': 'pw-sara',
          'roleId': 2,
          'roleName': 'كاشير',
        },
      ],
      enableTax: true,
      taxRate: 16.0,
      networkMode: mode,
      serverPortText: '8080',
      selectedClientBranchId: clientBranchId,
      syncedBranches: synced,
    );

/// تسلسلُ `_finishSetup()` القديم لنفس المدخل — منسوخٌ من الكود القديم.
List<String> _legacyStandaloneCalls() => [
      'save:setup_in_progress=true',
      'cache:business_profile=lite',
      'devpwd:1234',
      'save:company_name=شركة النيل',
      'save:company_phone=0790000000',
      'save:company_address=عمّان',
      'save:business_type=retail',
      'currency:JOD',
      // BUG 5a: يُعاد استعمالُ الفرع المزروع (‏الاسمُ نفسُه ⇒ لا تحديث)…
      'getAllBranches',
      // …والمخزنُ المزروعُ يُعاد تسميتُه بدل إنشاء صفٍّ ثانٍ.
      'getWarehouses:1',
      'updateWarehouse:1:مخزن الصالة',
      'save:pos_default_warehouse_branch_1=1',
      'save:pos_default_warehouse_id=1',
      'insertProduct:SETUP-${_clock.millisecondsSinceEpoch}-0:شاي:1.5:1.0',
      'createUser:sara:pw-sara:سارة:2',
      'save:tax_enabled=true',
      'save:tax_rate=16.0',
      'save:pos_default_tax_rate=0.16',
      'commit:standalone:8080',
      'cache:deployment_mode=standalone',
      'fiscalYear:2026:2026-01-01T00:00:00.000:2026-12-31T00:00:00.000',
      'periods:5',
      'save:setup_completed=true',
      'save:setup_in_progress=',
      'audit:setup_completed:lite:standalone:retail',
      'rehydrate',
    ];

void main() {
  group('تكافؤٌ مع `_finishSetup()` القديم', () {
    test('المستقلّ: التسلسلُ حرفاً لمدخلٍ مكافئ', () async {
      final p = RecordingPersistence();
      final r = await SetupFinishRunner(clock: () => _clock)
          .run(_legacyDraft(), p);
      expect(r.ok, isTrue, reason: r.error);
      expect(p.calls, _legacyStandaloneCalls());
    });

    test('العميل: فرعُ الجهاز ومخزنُه وبادئاتُ الترقيم — بلا سنةٍ ماليّة', () async {
      // العميلُ لا يُزرَع فرعُه محلّيّاً — فيُنشئه المعالجُ القديمُ بالاسم.
      final synced = [_seededBranch(code: 'AMM')];
      final p = RecordingPersistence(branches: [], warehouses: [
        _seededWarehouse(branchId: 7),
        const Warehouse(
          id: 8,
          name: 'w',
          branchId: 7,
          type: 'main',
          isDefault: true,
          isActive: true,
          isSystemDefault: false,
          rowVersion: 1,
        ),
      ]);
      final r = await SetupFinishRunner(clock: () => _clock).run(
        _legacyDraft(
          mode: NetworkMode.client,
          clientBranchId: 7,
          synced: [synced.first.copyWith(id: 7)],
        ),
        p,
      );
      expect(r.ok, isTrue, reason: r.error);
      final i = p.calls.indexOf('commit:client:8080');
      expect(p.calls.sublist(i), [
        'commit:client:8080',
        'cache:deployment_mode=client',
        'clientBranch:7',
        'getWarehouses:7',
        // `isDefault` أوّلاً — كـ`_resolveDefaultWarehouseForBranch`.
        'save:pos_default_warehouse_branch_7=1',
        'save:pos_default_warehouse_id=1',
        'save:invoice_code_prefix=AMM-POS',
        'save:prefix_sales_pos=AMM-POS',
        'save:prefix_sales_manual=AMM-SINV',
        'save:prefix_sales_return=AMM-SRET',
        'save:prefix_purchase=AMM-PINV',
        'save:prefix_purchase_return=AMM-PRET',
        'save:prefix_receipt_voucher=AMM-RCPT',
        'save:prefix_payment_voucher=AMM-PMT',
        'save:prefix_quotation=AMM-QUOT',
        // لا `fiscalYear` — السنةُ تصل من الخادم بالمزامنة (‏Spec 001).
        'save:setup_completed=true',
        'save:setup_in_progress=',
        'audit:setup_completed:lite:client:retail',
        'rehydrate',
      ]);
      expect(p.calls, contains('createBranch:الفرع الرئيسي'));
    });

    test('فشلُ اعتماد النمط يوقف قبل `setup_completed` (‏Spec 125)', () async {
      final p = RecordingPersistence(commitFailure: 'تعذّر الاتصال');
      final r = await SetupFinishRunner(clock: () => _clock)
          .run(_legacyDraft(), p);
      expect(r.ok, isFalse);
      expect(r.failedStage, SetupRunStage.mode);
      expect(r.error, 'تعذّر الاتصال');
      expect(p.calls.last, 'commit:standalone:8080');
      expect(p.calls, isNot(contains('save:setup_completed=true')));
    });
  });

  group('بندُ المالك ٦ — الإضافاتُ الجديدة', () {
    test('الهويّةُ والضريبةُ والفوترةُ والفرعُ والصناديقُ والمدير', () async {
      final p = RecordingPersistence(safes: {
        'cash': const SafeData(
          id: 11,
          name: 'صندوق الكاشير',
          safeType: 'cash',
          balance: 0,
          isDefault: true,
          isActive: true,
          branchId: 1,
          linkedAccountId: 501,
        ),
        'bank': const SafeData(
          id: 12,
          name: 'الحساب البنكي',
          safeType: 'bank',
          balance: 0,
          isDefault: true,
          isActive: true,
        ),
        'click': const SafeData(
          id: 13,
          name: 'صندوق تحويل كليك',
          safeType: 'click',
          balance: 0,
          isDefault: true,
          isActive: true,
        ),
      });
      final legacy = _legacyDraft();
      final d = SetupDraft(
        profile: legacy.profile,
        developerPassword: legacy.developerPassword,
        companyName: legacy.companyName,
        companyPhone: legacy.companyPhone,
        companyAddress: legacy.companyAddress,
        businessType: legacy.businessType,
        currency: legacy.currency,
        branchName: legacy.branchName,
        warehouseName: legacy.warehouseName,
        products: legacy.products,
        users: legacy.users,
        enableTax: legacy.enableTax,
        taxRate: legacy.taxRate,
        networkMode: legacy.networkMode,
        serverPortText: legacy.serverPortText,
        companyNameEn: 'Nile Co',
        taxNumber: '123456',
        commercialRegister: 'CR-9',
        branchCode: 'AMM',
        branchAddress: 'Abdali',
        pricesIncludeTax: true,
        eInvoiceCountry: SetupEInvoiceCountry.jordan,
        cashBoxName: 'كاشير ١',
        bankSafeName: 'الحساب البنكي',
        bankName: 'بنك الإسكان',
        bankAccountNumber: 'JO00',
        // لم يتغيّر ⇒ لا كتابة.
        cliqSafeName: 'صندوق تحويل كليك',
        adminPassword: 'S3cure-pass',
      );
      final r = await SetupFinishRunner(clock: () => _clock).run(d, p);
      expect(r.ok, isTrue, reason: r.error);

      // كلُّ نداءٍ قديمٍ باقٍ بترتيبه — الجديدُ إضافاتٌ بينها لا بدائل.
      final legacyCalls = _legacyStandaloneCalls();
      var at = 0;
      for (final c in p.calls) {
        if (at < legacyCalls.length && c == legacyCalls[at]) at++;
      }
      expect(at, legacyCalls.length,
          reason: at < legacyCalls.length
              ? 'نداءٌ قديمٌ سقط أو تبدّل ترتيبه: ${legacyCalls[at]}'
              : null);

      expect(p.calls, containsAllInOrder([
        'save:business_type=retail',
        'save:company_name_en=Nile Co',
        'save:company_tax_id=123456',
        'save:company_cr_number=CR-9',
        'currency:JOD',
      ]));
      expect(p.calls, contains('updateBranch:1:الفرع الرئيسي:AMM:Abdali'));
      // المركزُ والفرعُ والحسابُ المرتبطُ تُمرَّر من الصفّ — لا تُصفَّر.
      expect(p.calls, contains('updateSafe:11:كاشير ١:null:null:1:501'));
      expect(p.calls,
          contains('updateSafe:12:الحساب البنكي:بنك الإسكان:JO00:null:null'));
      expect(p.calls.where((c) => c.startsWith('updateSafe:13')), isEmpty);
      expect(p.calls, containsAllInOrder([
        'findUser:admin',
        'userPassword:1:S3cure-pass',
        'createUser:sara:pw-sara:سارة:2',
      ]));
      expect(p.calls, containsAllInOrder([
        'save:pos_default_tax_rate=0.16',
        'save:prices_include_tax=true',
        'save:show_jofotara_einvoice=true',
        'save:show_eta_einvoice=false',
        'commit:standalone:8080',
      ]));
      expect(p.calls.last, 'rehydrate');
    });

    test('كلمةُ المدير والصناديق لا تُلمَس خارجَ المستقلّ', () async {
      final p = RecordingPersistence();
      final legacy = _legacyDraft(mode: NetworkMode.mirror);
      final d = SetupDraft(
        profile: legacy.profile,
        developerPassword: legacy.developerPassword,
        companyName: legacy.companyName,
        companyPhone: legacy.companyPhone,
        companyAddress: legacy.companyAddress,
        businessType: legacy.businessType,
        currency: legacy.currency,
        branchName: legacy.branchName,
        warehouseName: legacy.warehouseName,
        products: legacy.products,
        users: legacy.users,
        enableTax: legacy.enableTax,
        taxRate: legacy.taxRate,
        networkMode: legacy.networkMode,
        serverPortText: legacy.serverPortText,
        cashBoxName: 'x',
        adminPassword: 'S3cure-pass',
      );
      await SetupFinishRunner(clock: () => _clock).run(d, p);
      expect(p.calls.where((c) => c.startsWith('getSafe')), isEmpty);
      expect(p.calls.where((c) => c.startsWith('userPassword')), isEmpty);
    });
  });

  group('الفشلُ والإعادة', () {
    test('فشلٌ في المنتصف ⇒ مرحلتُه وسببُه ولا `setup_completed`', () async {
      final p = RecordingPersistence(throwOn: 'save:tax_enabled');
      final r = await SetupFinishRunner(clock: () => _clock)
          .run(_legacyDraft(), p);
      expect(r.ok, isFalse);
      expect(r.failedStage, SetupRunStage.tax);
      expect(r.error, contains('simulated failure'));
      expect(p.calls, isNot(contains('save:setup_completed=true')));
    });

    test('الإعادةُ من البداية لا تكرّر منتجاً ولا مستخدماً نجحا', () async {
      final runner = SetupFinishRunner(clock: () => _clock);
      final p = RecordingPersistence(throwOn: 'save:tax_enabled');
      expect((await runner.run(_legacyDraft(), p)).ok, isFalse);
      p
        ..throwOn = null
        ..calls.clear();
      final r = await runner.run(_legacyDraft(), p);
      expect(r.ok, isTrue, reason: r.error);
      expect(p.calls.first, 'save:setup_in_progress=true',
          reason: 'الإعادةُ تبدأ من الأوّل');
      expect(p.calls.where((c) => c.startsWith('insertProduct')), isEmpty);
      expect(p.calls.where((c) => c.startsWith('createUser')), isEmpty);
      expect(p.calls, contains('save:setup_completed=true'));
    });
  });
}
