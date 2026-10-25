// مسودّةُ الإعداد الأول — نموذجٌ immutable يُحفَظ في إعدادٍ واحدٍ للجهاز.
//
// ═══ لا أسرارَ في المسودّة، بنيويّاً ═══
// كلماتُ المرور ورمزُ الربط ومفاتيحُ الترخيص في [FirstRunSecrets] — صنفٌ منفصلٌ
// لا يملك `toJson` أصلاً. و[FirstRunChecks] (‏أعلامُ التحقّق) لا تُسلسَل أيضاً:
// تُشتقّ من حقائق النظام عند الاستئناف (‏C.3) فلا تخدعها مسودّةٌ معدَّلة.
library;

import 'first_run_currency.dart';
import 'first_run_packs.dart';
import 'first_run_path.dart';
import 'first_run_steps.dart';

/// إصدارُ صيغة JSON — مسودّةٌ بإصدارٍ آخر تُتجاهَل.
const int kFirstRunDraftVersion = 1;

/// سطرُ فرعٍ في جدول فروع المقرّ (‏hq).
class FirstRunBranchRow {
  const FirstRunBranchRow({required this.code, required this.name});

  final String code;
  final String name;

  Map<String, Object?> toJson() => {'code': code, 'name': name};

  factory FirstRunBranchRow.fromJson(Map<String, Object?> j) =>
      FirstRunBranchRow(
        code: (j['code'] as String?) ?? '',
        name: (j['name'] as String?) ?? '',
      );
}

/// سطرُ مستخدمٍ في جدول مستخدمي الفروع (‏hq). **بلا كلمة مرور.**
/// [scope]: `HQ` أو `ALL` أو رمزُ فرع.
class FirstRunUserRow {
  const FirstRunUserRow({
    required this.name,
    required this.username,
    this.roleId,
    this.scope = 'HQ',
    this.rowId = 0,
    this.roleName,
    this.forceChange = true,
  });

  final String name;
  final String username;
  final int? roleId;
  final String scope;

  /// مفتاحُ السطر الثابت — تُربط به كلمةُ المرور الأوليّة في [FirstRunSecrets].
  final int rowId;

  /// اسمُ الدور وقتَ الاختيار: الخادمُ يحلّ الدورَ بالاسم لا برقمٍ محلّيّ.
  final String? roleName;

  /// يُلزم بتغيير كلمته الأوّليّة عند أوّل دخول (الافتراضيّ). الخادمُ لا يمنح جلسةً
  /// لحسابٍ ملزَمٍ بالتغيير، فإيقافه يتيح لجهاز الفرع اعتمادَ الحساب في الإعداد.
  final bool forceChange;

  FirstRunUserRow copyWith({
    String? name,
    String? username,
    int? roleId,
    String? scope,
    String? roleName,
    bool? forceChange,
  }) =>
      FirstRunUserRow(
        name: name ?? this.name,
        username: username ?? this.username,
        roleId: roleId ?? this.roleId,
        scope: scope ?? this.scope,
        rowId: rowId,
        roleName: roleName ?? this.roleName,
        forceChange: forceChange ?? this.forceChange,
      );

  Map<String, Object?> toJson() => {
        'name': name,
        'username': username,
        'roleId': roleId,
        'scope': scope,
        'rowId': rowId,
        'roleName': roleName,
        'forceChange': forceChange,
      };

  factory FirstRunUserRow.fromJson(Map<String, Object?> j) => FirstRunUserRow(
        name: (j['name'] as String?) ?? '',
        username: (j['username'] as String?) ?? '',
        roleId: j['roleId'] as int?,
        scope: (j['scope'] as String?) ?? 'HQ',
        rowId: (j['rowId'] as int?) ?? 0,
        roleName: j['roleName'] as String?,
        forceChange: j['forceChange'] is bool ? j['forceChange'] as bool : true,
      );
}

/// الأسرارُ — في الذاكرة فقط، ولا تُسلسَل أبداً.
class FirstRunSecrets {
  const FirstRunSecrets({
    this.adminPassword = '',
    this.adminPasswordConfirm = '',
    this.developerPassword = '',
    this.developerPasswordConfirm = '',
    this.pairingCode = '',
    this.pgPassword = '',
    this.accountPassword = '',
    this.accountNewPassword = '',
    this.userPasswords = const {},
  });

  /// كلمةُ المرور الجديدة حين يُلزم الرئيسيُّ بتغيير المؤقتة (‏في الذاكرة فقط).
  final String accountNewPassword;

  /// كلمةُ مرور PostgreSQL وكلمةُ حساب الفرع/مدير المرآة وكلماتُ مستخدمي
  /// المقرّ الأوليّة (بمفتاح rowId) — كلُّها في الذاكرة فقط.
  final String pgPassword;
  final String accountPassword;
  final Map<int, String> userPasswords;

  final String adminPassword;
  final String adminPasswordConfirm;
  final String developerPassword;
  final String developerPasswordConfirm;
  final String pairingCode;

  FirstRunSecrets copyWith({
    String? adminPassword,
    String? adminPasswordConfirm,
    String? developerPassword,
    String? developerPasswordConfirm,
    String? pairingCode,
    String? pgPassword,
    String? accountPassword,
    String? accountNewPassword,
    Map<int, String>? userPasswords,
  }) =>
      FirstRunSecrets(
        pgPassword: pgPassword ?? this.pgPassword,
        accountPassword: accountPassword ?? this.accountPassword,
        accountNewPassword: accountNewPassword ?? this.accountNewPassword,
        userPasswords: userPasswords ?? this.userPasswords,
        adminPassword: adminPassword ?? this.adminPassword,
        adminPasswordConfirm: adminPasswordConfirm ?? this.adminPasswordConfirm,
        developerPassword: developerPassword ?? this.developerPassword,
        developerPasswordConfirm:
            developerPasswordConfirm ?? this.developerPasswordConfirm,
        pairingCode: pairingCode ?? this.pairingCode,
      );
}

/// أعلامُ التحقّق — تُصفَّر عند تغيّر مدخلاتها وتُشتقّ من الحقائق عند الاستئناف.
class FirstRunChecks {
  const FirstRunChecks({
    this.storageChecked = false,
    this.linked = false,
    this.provisioned = false,
    this.firstSyncDone = false,
    this.accountVerified = false,
  });

  final bool storageChecked;
  final bool linked;
  final bool provisioned;
  final bool firstSyncDone;
  final bool accountVerified;

  FirstRunChecks copyWith({
    bool? storageChecked,
    bool? linked,
    bool? provisioned,
    bool? firstSyncDone,
    bool? accountVerified,
  }) =>
      FirstRunChecks(
        storageChecked: storageChecked ?? this.storageChecked,
        linked: linked ?? this.linked,
        provisioned: provisioned ?? this.provisioned,
        firstSyncDone: firstSyncDone ?? this.firstSyncDone,
        accountVerified: accountVerified ?? this.accountVerified,
      );
}

class FirstRunDraft {
  const FirstRunDraft({
    required this.draftId,
    this.path = FirstRunPath.standalone,
    this.step = 0,
    this.maxStep = 0,
    this.pack = FirstRunPack.pos,
    this.companyName = '',
    this.companyNameEn = '',
    this.companyPhone = '',
    this.companyAddress = '',
    this.taxNumber = '',
    this.commercialRegister = '',
    this.currency = '',
    this.vatEnabled = true,
    this.vatRate = 0,
    this.vatRateTouched = false,
    this.pricesIncludeTax = true,
    this.eInvoice,
    this.eInvoiceTouched = false,
    this.fiscalYear = 2026,
    this.branchName = '',
    this.branchCode = '',
    this.branchAddress = '',
    this.warehouseName = '',
    this.cashBoxName = '',
    this.tablesCount = '12',
    this.serviceType = FirstRunServiceType.all,
    this.touchMode = false,
    this.endpoint = '',
    this.port = '8080',
    this.deviceName = '',
    this.branchRole = BranchDeviceRole.first,
    this.pgHost = 'localhost',
    this.pgPort = '5432',
    this.pgDatabase = 'picpos',
    this.pgUser = 'postgres',
    this.selectedBranchId,
    this.selectedBranchName = '',
    this.selectedBranchCode = '',
    this.accountUsername = '',
    this.branches = const [],
    this.hqUsers = const [],
    this.offlineDays = 7,
    this.checks = const FirstRunChecks(),
  });

  /// معرّفٌ ثابتٌ للمحاولة — يُنسب إليه ما يُكتَب فيُعاد بلا تكرار.
  final String draftId;

  final FirstRunPath path;

  /// فهرسُ الخطوة الحاليّة في [stepsFor] وأبعدُ ما بلغه المستخدم.
  final int step;
  final int maxStep;

  final FirstRunPack pack;

  // ── الشركة ──
  final String companyName;
  final String companyNameEn;
  final String companyPhone;
  final String companyAddress;
  final String taxNumber;
  final String commercialRegister;

  /// `''` = لم تُختَر بعد (‏UX-004: بلا اختيار مسبق).
  final String currency;
  final bool vatEnabled;
  final double vatRate;
  final bool vatRateTouched;
  final bool pricesIncludeTax;
  final FirstRunEInvoice? eInvoice;
  final bool eInvoiceTouched;
  final int fiscalYear;

  // ── الفرع والمخزن ──
  final String branchName;
  final String branchCode;
  final String branchAddress;
  final String warehouseName;

  // ── التجهيز ──
  final String cashBoxName;
  final String tablesCount;
  final FirstRunServiceType serviceType;
  final bool touchMode;

  // ── مسار الفرع (‏P6) ──
  final String endpoint;
  final String port;
  final String deviceName;
  final BranchDeviceRole branchRole;

  /// الفرعُ المختار من الفروع المزامَنة (‏يظهر بعد المزامنة الأولى).
  final int? selectedBranchId;
  final String selectedBranchName;
  final String selectedBranchCode;

  /// اسمُ المستخدم المعتمد للتحقّق (‏الفرع) أو مديرُ المرآة. **لا كلمةَ مرور.**
  final String accountUsername;

  // ── مسار المقرّ (‏P5): اتصالُ PostgreSQL — كلمةُ المرور في الأسرار ──
  final String pgHost;
  final String pgPort;
  final String pgDatabase;
  final String pgUser;
  final List<FirstRunBranchRow> branches;
  final List<FirstRunUserRow> hqUsers;
  final int offlineDays;

  final FirstRunChecks checks;

  FirstRunStep get currentStep {
    final steps = stepsFor(path);
    return steps[step.clamp(0, steps.length - 1)];
  }

  FirstRunDraft copyWith({
    FirstRunPath? path,
    int? step,
    int? maxStep,
    FirstRunPack? pack,
    String? companyName,
    String? companyNameEn,
    String? companyPhone,
    String? companyAddress,
    String? taxNumber,
    String? commercialRegister,
    String? currency,
    bool? vatEnabled,
    double? vatRate,
    bool? vatRateTouched,
    bool? pricesIncludeTax,
    FirstRunEInvoice? eInvoice,
    bool? eInvoiceTouched,
    int? fiscalYear,
    String? branchName,
    String? branchCode,
    String? branchAddress,
    String? warehouseName,
    String? cashBoxName,
    String? tablesCount,
    FirstRunServiceType? serviceType,
    bool? touchMode,
    String? endpoint,
    String? port,
    String? deviceName,
    BranchDeviceRole? branchRole,
    String? pgHost,
    String? pgPort,
    String? pgDatabase,
    String? pgUser,
    int? selectedBranchId,
    bool clearSelectedBranch = false,
    String? selectedBranchName,
    String? selectedBranchCode,
    String? accountUsername,
    List<FirstRunBranchRow>? branches,
    List<FirstRunUserRow>? hqUsers,
    int? offlineDays,
    FirstRunChecks? checks,
  }) =>
      FirstRunDraft(
        draftId: draftId,
        path: path ?? this.path,
        step: step ?? this.step,
        maxStep: maxStep ?? this.maxStep,
        pack: pack ?? this.pack,
        companyName: companyName ?? this.companyName,
        companyNameEn: companyNameEn ?? this.companyNameEn,
        companyPhone: companyPhone ?? this.companyPhone,
        companyAddress: companyAddress ?? this.companyAddress,
        taxNumber: taxNumber ?? this.taxNumber,
        commercialRegister: commercialRegister ?? this.commercialRegister,
        currency: currency ?? this.currency,
        vatEnabled: vatEnabled ?? this.vatEnabled,
        vatRate: vatRate ?? this.vatRate,
        vatRateTouched: vatRateTouched ?? this.vatRateTouched,
        pricesIncludeTax: pricesIncludeTax ?? this.pricesIncludeTax,
        eInvoice: eInvoice ?? this.eInvoice,
        eInvoiceTouched: eInvoiceTouched ?? this.eInvoiceTouched,
        fiscalYear: fiscalYear ?? this.fiscalYear,
        branchName: branchName ?? this.branchName,
        branchCode: branchCode ?? this.branchCode,
        branchAddress: branchAddress ?? this.branchAddress,
        warehouseName: warehouseName ?? this.warehouseName,
        cashBoxName: cashBoxName ?? this.cashBoxName,
        tablesCount: tablesCount ?? this.tablesCount,
        serviceType: serviceType ?? this.serviceType,
        touchMode: touchMode ?? this.touchMode,
        endpoint: endpoint ?? this.endpoint,
        port: port ?? this.port,
        deviceName: deviceName ?? this.deviceName,
        branchRole: branchRole ?? this.branchRole,
        pgHost: pgHost ?? this.pgHost,
        pgPort: pgPort ?? this.pgPort,
        pgDatabase: pgDatabase ?? this.pgDatabase,
        pgUser: pgUser ?? this.pgUser,
        selectedBranchId: clearSelectedBranch
            ? null
            : (selectedBranchId ?? this.selectedBranchId),
        selectedBranchName: selectedBranchName ?? this.selectedBranchName,
        selectedBranchCode: selectedBranchCode ?? this.selectedBranchCode,
        accountUsername: accountUsername ?? this.accountUsername,
        branches: branches ?? this.branches,
        hqUsers: hqUsers ?? this.hqUsers,
        offlineDays: offlineDays ?? this.offlineDays,
        checks: checks ?? this.checks,
      );

  /// JSON للحفظ — **لا يحوي** [FirstRunSecrets] ولا [checks].
  Map<String, Object?> toJson() => {
        'version': kFirstRunDraftVersion,
        'draftId': draftId,
        'path': path.name,
        'step': step,
        'maxStep': maxStep,
        'pack': pack.name,
        'companyName': companyName,
        'companyNameEn': companyNameEn,
        'companyPhone': companyPhone,
        'companyAddress': companyAddress,
        'taxNumber': taxNumber,
        'commercialRegister': commercialRegister,
        'currency': currency,
        'vatEnabled': vatEnabled,
        'vatRate': vatRate,
        'vatRateTouched': vatRateTouched,
        'pricesIncludeTax': pricesIncludeTax,
        'eInvoice': eInvoice?.name,
        'eInvoiceTouched': eInvoiceTouched,
        'fiscalYear': fiscalYear,
        'branchName': branchName,
        'branchCode': branchCode,
        'branchAddress': branchAddress,
        'warehouseName': warehouseName,
        'cashBoxName': cashBoxName,
        'tablesCount': tablesCount,
        'serviceType': serviceType.name,
        'touchMode': touchMode,
        'endpoint': endpoint,
        'port': port,
        'deviceName': deviceName,
        'branchRole': branchRole.name,
        'pgHost': pgHost,
        'pgPort': pgPort,
        'pgDatabase': pgDatabase,
        'pgUser': pgUser,
        'selectedBranchId': selectedBranchId,
        'selectedBranchName': selectedBranchName,
        'selectedBranchCode': selectedBranchCode,
        'accountUsername': accountUsername,
        'branches': [for (final b in branches) b.toJson()],
        'hqUsers': [for (final u in hqUsers) u.toJson()],
        'offlineDays': offlineDays,
      };

  /// يقرأ مسودّةً محفوظة؛ `null` لإصدارٍ مجهولٍ أو بنيةٍ تالفة. القيمُ
  /// الناقصةُ أو الخارجةُ عن المدى تعود إلى الافتراضيّ ولا تُسقط القراءة.
  static FirstRunDraft? fromJson(Object? raw, {required String fallbackId}) {
    if (raw is! Map || raw['version'] != kFirstRunDraftVersion) return null;
    T pick<T extends Enum>(List<T> values, Object? name, T fallback) {
      for (final v in values) {
        if (v.name == name) return v;
      }
      return fallback;
    }

    String s(String k) => raw[k] is String ? raw[k] as String : '';
    bool b(String k, bool d) => raw[k] is bool ? raw[k] as bool : d;
    int i(String k, int d) => raw[k] is int ? raw[k] as int : d;

    final path = pick(FirstRunPath.values, raw['path'], FirstRunPath.standalone);
    final last = stepsFor(path).length - 1;
    final maxStep = i('maxStep', 0).clamp(0, last);
    final eInvoiceName = raw['eInvoice'];
    final base = FirstRunDraft(draftId: s('draftId').isEmpty ? fallbackId : s('draftId'));
    return base.copyWith(
      path: path,
      maxStep: maxStep,
      step: i('step', 0).clamp(0, maxStep),
      pack: pick(FirstRunPack.values, raw['pack'], FirstRunPack.pos),
      companyName: s('companyName'),
      companyNameEn: s('companyNameEn'),
      companyPhone: s('companyPhone'),
      companyAddress: s('companyAddress'),
      taxNumber: s('taxNumber'),
      commercialRegister: s('commercialRegister'),
      currency: kFirstRunCurrencies.contains(s('currency')) ? s('currency') : '',
      vatEnabled: b('vatEnabled', true),
      vatRate: raw['vatRate'] is num ? (raw['vatRate'] as num).toDouble() : 0,
      vatRateTouched: b('vatRateTouched', false),
      pricesIncludeTax: b('pricesIncludeTax', true),
      eInvoice: eInvoiceName == null
          ? null
          : pick(FirstRunEInvoice.values, eInvoiceName, FirstRunEInvoice.none),
      eInvoiceTouched: b('eInvoiceTouched', false),
      fiscalYear: i('fiscalYear', 2026),
      branchName: s('branchName'),
      branchCode: s('branchCode'),
      branchAddress: s('branchAddress'),
      warehouseName: s('warehouseName'),
      cashBoxName: s('cashBoxName'),
      tablesCount: s('tablesCount').isEmpty ? '12' : s('tablesCount'),
      serviceType: pick(FirstRunServiceType.values, raw['serviceType'],
          FirstRunServiceType.all),
      touchMode: b('touchMode', false),
      endpoint: s('endpoint'),
      port: s('port').isEmpty ? '8080' : s('port'),
      deviceName: s('deviceName'),
      branchRole:
          pick(BranchDeviceRole.values, raw['branchRole'], BranchDeviceRole.first),
      pgHost: s('pgHost').isEmpty ? 'localhost' : s('pgHost'),
      pgPort: s('pgPort').isEmpty ? '5432' : s('pgPort'),
      pgDatabase: s('pgDatabase').isEmpty ? 'picpos' : s('pgDatabase'),
      pgUser: s('pgUser').isEmpty ? 'postgres' : s('pgUser'),
      selectedBranchId: raw['selectedBranchId'] is int
          ? raw['selectedBranchId'] as int
          : null,
      selectedBranchName: s('selectedBranchName'),
      selectedBranchCode: s('selectedBranchCode'),
      accountUsername: s('accountUsername'),
      branches: [
        if (raw['branches'] is List)
          for (final e in raw['branches'] as List)
            if (e is Map<String, Object?>) FirstRunBranchRow.fromJson(e),
      ],
      hqUsers: [
        if (raw['hqUsers'] is List)
          for (final e in raw['hqUsers'] as List)
            if (e is Map<String, Object?>) FirstRunUserRow.fromJson(e),
      ],
      offlineDays: i('offlineDays', 7),
    );
  }
}
