// من مسودّة الإعداد الأول إلى التشغيل — محوّلٌ إلى `SetupDraft` ونداءُ
// `SetupFinishRunner` الموجود (‏لا كتابةٌ مباشرةٌ لأعلام الأنماط ولا نسخةٌ ثانية
// من منطق الإنهاء). `setup_completed` آخرُ كتابة (‏عقدُ المشغّل)، والكتاباتُ
// الإضافيّةُ (طاولات · overrides · تفضيلات الجهاز) تجري قبله في مرحلة `extras`.
//
// ⚠️ **idempotent**: الفرعُ والمخزنُ المزروعان يُعاد استعمالُهما، والمدير يُحدَّث
// ولا يُنشأ، والطاولاتُ بالاسم داخل القسم، والسنةُ الماليّةُ تتحمّل الوجود —
// فتشغيلتان بنفس المسودّة لا تكرّران شيئاً.
library;

import '../../../core/config/business_profile.dart';
import '../../../core/config/feature_key.dart';
import '../../../core/i18n/tr.dart';
import '../../../domain/models/first_run/first_run_currency.dart';
import '../../../domain/models/first_run/first_run_draft.dart';
import '../../../domain/models/first_run/first_run_path.dart';
import '../../../services/network_service.dart';
import '../../../services/setup/server_provisioning_service.dart';
import '../../../services/setup/server_setup_writer.dart';
import '../setup_wizard/setup_finish_runner.dart';
import 'first_run_finish_server.dart';

/// واجهةُ التشغيل — تُحقن في الاختبار.
typedef FirstRunFinisher = Future<SetupRunResult> Function(
  FirstRunDraft draft,
  FirstRunSecrets secrets,
  SetupPersistence persistence, {
  void Function(SetupRunStage stage)? onStage,
});

SetupEInvoiceCountry _eInvoice(FirstRunEInvoice? e) => switch (e) {
      FirstRunEInvoice.jordan => SetupEInvoiceCountry.jordan,
      FirstRunEInvoice.egypt => SetupEInvoiceCountry.egypt,
      _ => SetupEInvoiceCountry.none,
    };

/// المسار المستقلّ (‏P3) — مدخلُ SetupFinishRunner.
SetupDraft toSetupDraft(FirstRunDraft d, FirstRunSecrets s) {
  final profile = BusinessProfile.values.byName(d.pack.profileName);
  return SetupDraft(
    profile: profile,
    developerPassword: s.developerPassword,
    companyName: d.companyName,
    companyPhone: d.companyPhone,
    companyAddress: d.companyAddress,
    businessType: profile.defaultBusinessType,
    currency: d.currency,
    branchName: d.branchName,
    warehouseName: d.warehouseName,
    products: const [],
    users: const [],
    enableTax: d.vatEnabled,
    taxRate: d.vatRate,
    networkMode: NetworkMode.standalone,
    serverPortText: '8080',
    companyNameEn: d.companyNameEn,
    taxNumber: d.taxNumber,
    commercialRegister: d.commercialRegister,
    branchCode: d.branchCode,
    branchAddress: d.branchAddress,
    pricesIncludeTax: d.pricesIncludeTax,
    eInvoiceCountry: _eInvoice(d.eInvoice),
    cashBoxName: d.cashBoxName.trim().isEmpty ? null : d.cashBoxName,
    adminPassword: s.adminPassword,
    fiscalYear: d.fiscalYear,
    extraStage: (p) => runExtras(d, p),
  );
}

/// طاولاتٌ وoverrides وتفضيلاتُ الجهاز — قبل `setup_completed`.
///
/// الكتابةُ بالإعدادات مباشرةً كما يفعل المعالجُ مع `business_profile` (لأنّ
/// `ConfigService.setOverride` يتطلّب `_assertUnlocked`)، وتُقرأ عند
/// `rehydrateRuntimeConfigCache` التي تعيد تحميل مفاتيح `FeatureKey` كلّها.
Future<void> runExtras(FirstRunDraft d, SetupPersistence p) async {
  if (d.pack.hasTables) {
    await p.saveCachedSetting(
      FeatureKey.posTables.settingKey,
      d.serviceType.tables.toString(),
    );
    await p.saveCachedSetting(
      FeatureKey.posDelivery.settingKey,
      d.serviceType.delivery.toString(),
    );
    final count = int.tryParse(d.tablesCount.trim()) ?? 0;
    if (d.serviceType.tables && count > 0) {
      if (p is! SetupTablesPort) {
        throw UnsupportedError('SetupTablesPort');
      }
      await (p as SetupTablesPort).ensureTables(
        sectionName: tr('القاعة الرئيسية'),
        count: count,
        tableName: (n) => tr('طاولة {p0}', {'p0': n}),
      );
    }
  }
  if (d.touchMode) {
    await p.saveCachedSetting('touchMode', 'true');
  }
}

/// عميلٌ/مرآة: تفضيلُ الجهاز وحده - حالةُ المؤسسة مِلكُ السيرفر (ADP-006).
Future<void> runDeviceExtras(FirstRunDraft d, SetupPersistence p) async {
  if (d.touchMode) await p.saveCachedSetting('touchMode', 'true');
}

/// المنفِّذ الافتراضيّ: المستقلّ بمشغّلٍ واحدٍ يعيش بين المحاولات ليتذكّر ما
/// نجح، والمقرّ/الفرع/المرآة بالمنفّذ المرتبط بخادم (‏serverBoundFinisher).
FirstRunFinisher defaultFinisher({
  required ServerSetupWriter writer,
  required ServerProvisioningService provisioning,
}) {
  final runner = SetupFinishRunner();
  final serverBound =
      serverBoundFinisher(writer: writer, provisioning: provisioning);
  return (draft, secrets, persistence, {onStage}) {
    if (draft.path == FirstRunPath.standalone) {
      return runner.run(toSetupDraft(draft, secrets), persistence,
          onStage: onStage);
    }
    return serverBound(draft, secrets, persistence, onStage: onStage);
  };
}
