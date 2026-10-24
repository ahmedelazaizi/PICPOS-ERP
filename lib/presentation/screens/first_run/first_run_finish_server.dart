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
          await writer.write(cfg, buildServerSetupInput(draft, secrets));
          await provisioning.armPostgresMode(cfg);
          enter(SetupRunStage.settings);
          // نسخةُ الإقلاع المحلّيّة: اسمُ الشركة فقط (‏يقرأ التطبيقُ من الخادم بعد الإعادة).
          if (draft.companyName.trim().isNotEmpty) {
            await p.saveSetting('company_name', draft.companyName.trim());
          }
          return runFinishTail(
            p: p,
            mode: NetworkMode.server,
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
            mode: NetworkMode.client,
            serverPort: int.tryParse(draft.port.trim()) ?? 8080,
            auditPayload: {...audit, 'branch_id': branchId},
            enter: enter,
            afterCommit: () async => writeClientBranchSettings(
              p,
              branchId: branchId,
              syncedBranches: await p.getAllBranches(),
            ),
            extras: () => runExtras(draft, p),
          );
        case FirstRunPath.mirror:
          return runFinishTail(
            p: p,
            mode: NetworkMode.mirror,
            serverPort: int.tryParse(draft.port.trim()) ?? 8080,
            auditPayload: audit,
            enter: enter,
            extras: () => runExtras(draft, p),
          );
        case FirstRunPath.standalone:
          throw StateError('standalone uses SetupFinishRunner');
      }
    } catch (e) {
      return SetupRunResult(ok: false, failedStage: stage, error: '$e');
    }
  };
}
