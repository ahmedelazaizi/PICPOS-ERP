// إنهاءُ المسارات المرتبطة بخادمٍ: المقرّ (‏hq) والفرع والمرآة.
//
// • المقرّ: (1) كتابةُ البيانات في PostgreSQL بمعاملةٍ واحدة (‏`ServerSetupWriter`)،
//   (2) تسليحُ بوّابة الإقلاع (‏`armPostgresMode`) بعد نجاح الكتابة فقط، (3) الذيلُ
//   المحلّيّ المشترك. لا `exit(0)` هنا: صفحةُ النجاح تعرض «إعادة التشغيل الآن».
// • الفرع: لا كتابةَ شركةٍ ولا فروعٍ ولا مستخدمين — الربطُ والمزامنةُ جرَيا بالفعل؛
//   يبقى فرعُ الجهاز وبادئاتُ الترقيم والذيل.
// • المرآة: الذيلُ فقط (‏المصافحةُ جرت في خطوة الربط).
//
// كلُّها idempotent بمفاتيح الكاتب، وكلُّها تنتهي بـ`setup_completed`.
library;

import '../../../core/config/business_profile.dart';
import '../../../core/config/feature_key.dart';
import '../../../core/i18n/tr.dart';
import '../../../domain/models/first_run/first_run_draft.dart';
import '../../../domain/models/first_run/first_run_currency.dart';
import '../../../domain/models/first_run/first_run_path.dart';
import '../../../services/network_service.dart';
import '../../../services/setup/server_provisioning_service.dart';
import '../../../services/setup/server_setup_writer.dart';
import '../setup_wizard/setup_client_branch.dart';
import '../setup_wizard/setup_finish_runner.dart';
import 'first_run_finish.dart';
import 'first_run_finish_tail.dart';
import 'first_run_ops.dart' show pgConfigOf;

/// ما يُكتب في قاعدة الخادم من مسودّة المقرّ.
ServerSetupInput buildServerSetupInput(FirstRunDraft d, FirstRunSecrets s) {
  final profile = BusinessProfile.values.byName(d.pack.profileName);
  final tableCount = int.tryParse(d.tablesCount.trim()) ?? 0;
  final withTables = d.pack.hasTables && d.serviceType.tables && tableCount > 0;
  return ServerSetupInput(
    companyName: d.companyName,
    companyNameEn: d.companyNameEn,
    companyPhone: d.companyPhone,
    companyAddress: d.companyAddress,
    taxNumber: d.taxNumber,
    commercialRegister: d.commercialRegister,
    currency: d.currency,
    businessProfile: profile.name,
    businessType: profile.defaultBusinessType,
    vatEnabled: d.vatEnabled,
    vatRate: d.vatRate,
    pricesIncludeTax: d.pricesIncludeTax,
    eInvoice: switch (d.eInvoice) {
      FirstRunEInvoice.jordan => 'jordan',
      FirstRunEInvoice.egypt => 'egypt',
      _ => 'none',
    },
    fiscalYear: d.fiscalYear,
    branchName: d.branchName,
    branchCode: d.branchCode,
    branchAddress: d.branchAddress,
    warehouseName: d.warehouseName,
    branches: [
      for (final b in d.branches)
        ServerSetupBranch(code: b.code.trim(), name: b.name),
    ],
    adminPassword: s.adminPassword,
    developerPassword: s.developerPassword,
    users: [
      for (final u in d.hqUsers)
        ServerSetupUser(
          name: u.name,
          username: u.username,
          password: s.userPasswords[u.rowId] ?? '',
          roleId: u.roleId,
          roleName: u.roleName,
          scope: u.scope,
          forcePasswordChange: u.forceChange,
        ),
    ],
    offlineDays: d.offlineDays,
    tablesEnabled: d.pack.hasTables ? d.serviceType.tables : null,
    deliveryEnabled: d.pack.hasTables ? d.serviceType.delivery : null,
    tableSection: withTables ? tr('القاعة الرئيسية') : null,
    tableNames: withTables
        ? [for (var n = 1; n <= tableCount; n++) tr('طاولة {p0}', {'p0': n})]
        : const [],
  );
}

/// المقرّ فقط: نسخةُ الإقلاع المحلّيّة لمفاتيح الباقة/الأنشطة التي يكتبها
/// `ServerSetupWriter` في الخادم وحده (أعلامُ `feature.*` ونوعُ النشاط وإظهارُ
/// منصّتَي الفوترة). لا تُكتب في الفرع/المرآة: تُزامَن من الخادم فيطمسها الافتراضيّ.
Future<void> writeHqLocalBootSettings(
    SetupPersistence p, ServerSetupInput i) async {
  await p.saveSetting('business_type', i.businessType);
  await p.saveSetting(
      'show_jofotara_einvoice', i.eInvoice == 'jordan' ? 'true' : 'false');
  await p.saveSetting('show_eta_einvoice', i.eInvoice == 'egypt' ? 'true' : 'false');
  if (i.tablesEnabled != null) {
    await p.saveCachedSetting(
        FeatureKey.posTables.settingKey, i.tablesEnabled.toString());
  }
  if (i.deliveryEnabled != null) {
    await p.saveCachedSetting(
        FeatureKey.posDelivery.settingKey, i.deliveryEnabled.toString());
  }
}

/// A1: the network mode a path COMMITS - one explicit mapping, so the mode the
/// owner chose in the first step is the mode that is committed (never client
/// for a mirror, as the old wizard's logs showed).
NetworkMode networkModeForPath(FirstRunPath path) => switch (path) {
      FirstRunPath.standalone => NetworkMode.standalone,
      FirstRunPath.hq => NetworkMode.server,
      FirstRunPath.branch => NetworkMode.client,
      FirstRunPath.mirror => NetworkMode.mirror,
    };

/// المنفّذُ المناسب لمسار [path].
FirstRunFinisher serverBoundFinisher({
  required ServerSetupWriter writer,
  required ServerProvisioningService provisioning,
}) {
  return (draft, secrets, p, {onStage}) async {
    var stage = SetupRunStage.settings;
    void enter(SetupRunStage s) {
      stage = s;
      onStage?.call(s);
    }

    try {
      enter(SetupRunStage.settings);
      await p.saveSetting('setup_in_progress', 'true');
      final audit = <String, dynamic>{
        'profile': draft.pack.profileName,
        'mode': draft.path.name,
      };
      switch (draft.path) {
        case FirstRunPath.hq:
          enter(SetupRunStage.serverData);
          final cfg = pgConfigOf(draft, secrets);
          final input = buildServerSetupInput(draft, secrets);
          await writer.write(cfg, input);
          await provisioning.armPostgresMode(cfg);
          enter(SetupRunStage.settings);
          // نسخةُ الإقلاع المحلّيّة: اسمُ الشركة وملفُّ النشاط (‏يقرأ التطبيقُ من
          // الخادم بعد الإعادة، لكنّه يرجع إلى SQLite المحلية إن تعذّر PG —
          // main.dart — فبلا `business_profile` هنا يسقط «شامل» إلى الافتراضيّ).
          if (draft.companyName.trim().isNotEmpty) {
            await p.saveSetting('company_name', draft.companyName.trim());
          }
          await p.saveCachedSetting('business_profile', draft.pack.profileName);
          await writeHqLocalBootSettings(p, input);
          return runFinishTail(
            p: p,
            mode: networkModeForPath(draft.path),
            serverPort: 8080,
            auditPayload: audit,
            enter: enter,
            extras: () async {
              if (draft.touchMode) await p.saveCachedSetting('touchMode', 'true');
            },
          );
        case FirstRunPath.branch:
          final branchId = draft.selectedBranchId;
          if (branchId == null) {
            throw StateError(tr('اختر فرع هذا الجهاز أولًا.'));
          }
          return runFinishTail(
            p: p,
            mode: networkModeForPath(draft.path),
            serverPort: int.tryParse(draft.port.trim()) ?? 8080,
            auditPayload: {...audit, 'branch_id': branchId},
            enter: enter,
            afterCommit: () async => writeClientBranchSettings(
              p,
              branchId: branchId,
              syncedBranches: await p.getAllBranches(),
            ),
            extras: () => runDeviceExtras(draft, p),
          );
        case FirstRunPath.mirror:
          return runFinishTail(
            p: p,
            mode: networkModeForPath(draft.path),
            serverPort: int.tryParse(draft.port.trim()) ?? 8080,
            auditPayload: audit,
            enter: enter,
            extras: () => runDeviceExtras(draft, p),
          );
        case FirstRunPath.standalone:
          throw StateError('standalone uses SetupFinishRunner');
      }
    } catch (e) {
      return SetupRunResult(ok: false, failedStage: stage, error: '$e');
    }
  };
}
