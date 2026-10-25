// عملياتُ الشبكة والخادم في المعالج (P5/P6) — منفصلةٌ عن متحكّم الخطوات كي يبقى
// كلٌّ منهما صغيراً: اختبارُ PostgreSQL وتهيئتُه، إقرانُ الفرع وربطُه، المزامنةُ
// الأولى، التحقّقُ من الحساب. النتائجُ تعود إلى المسودّة **أعلامَ تحقّقٍ** فقط
// (`checks`)، وتبقى الرسائلُ هنا.
//
// ⚠️ لا نجاحَ مزيّفاً: كلُّ علمٍ يُرفع بنتيجةٍ حقيقيةٍ من الخدمة المحقونة، وفشلُ
// الاتصال يُترجَم إلى سببٍ مقروءٍ ولا يُقدّم الخطوة.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/tr.dart';
import '../../../data/providers/providers.dart' show Branche;
import '../../../domain/models/first_run/first_run_draft.dart';
import '../../../domain/models/first_run/first_run_invalidation.dart';
import '../../../domain/models/first_run/first_run_path.dart';
import '../../../services/setup/branch_account_verifier.dart';
import '../../../services/setup/client_link_service.dart';
import '../../../services/setup/server_provisioning_service.dart';
import '../setup_wizard/setup_persistence_riverpod.dart';
import 'first_run_controller.dart';
import 'first_run_providers.dart';

/// صفُّ تقدّم تهيئة الخادم (‏يطابق خطواتِ `ServerProvisioningService.provision`).
class ProvisionRow {
  const ProvisionRow(this.label, this.status, [this.detail]);
  final String label;
  final ProvisionStatus status;
  final String? detail;
}

List<String> provisionLabels() => [
      tr('اختبار الاتصال بالسيرفر'),
      tr('إنشاء جداول قاعدة البيانات'),
      tr('زرع البيانات الأساسية (أدوار، فرع، مخزن، خزائن…)'),
      tr('زرع شجرة الحسابات'),
      tr('إنشاء السنة المالية الحالية'),
      tr('التحقق من اكتمال البيانات'),
    ];

/// إعدادُ PostgreSQL من المسودّة والأسرار.
PostgresConfig pgConfigOf(FirstRunDraft d, FirstRunSecrets s) =>
    buildPostgresConfig(
      host: d.pgHost,
      port: d.pgPort,
      database: d.pgDatabase,
      username: d.pgUser,
      password: s.pgPassword,
    );

class FirstRunOpsState {
  const FirstRunOpsState({
    this.pgBusy = false,
    this.pgMessage,
    this.pgMessageOk = false,
    this.provisionRows = const [],
    this.provisionError,
    this.linkBusy = false,
    this.linkMessage,
    this.linkMessageOk = false,
    this.syncBusy = false,
    this.syncMessage,
    this.syncOffline = false,
    this.branches = const [],
    this.accountBusy = false,
    this.account,
  });

  final bool pgBusy;
  final String? pgMessage;
  final bool pgMessageOk;
  final List<ProvisionRow> provisionRows;
  final String? provisionError;
  final bool linkBusy;
  final String? linkMessage;
  final bool linkMessageOk;
  final bool syncBusy;
  final String? syncMessage;

  /// فشلت المزامنةُ لأنّ الخادم غيرُ قابلٍ للوصول — تشرحه الواجهةُ بعبارةٍ ثابتة.
  final bool syncOffline;

  /// الفروعُ المزامَنة المعروضةُ للاختيار.
  final List<Branche> branches;
  final bool accountBusy;
  final AccountVerification? account;

  bool get anyBusy => pgBusy || linkBusy || syncBusy || accountBusy;

  FirstRunOpsState copyWith({
    bool? pgBusy,
    String? pgMessage,
    bool clearPgMessage = false,
    bool? pgMessageOk,
    List<ProvisionRow>? provisionRows,
    String? provisionError,
    bool clearProvisionError = false,
    bool? linkBusy,
    String? linkMessage,
    bool clearLinkMessage = false,
    bool? linkMessageOk,
    bool? syncBusy,
    String? syncMessage,
    bool clearSyncMessage = false,
    bool? syncOffline,
    List<Branche>? branches,
    bool? accountBusy,
    AccountVerification? account,
    bool clearAccount = false,
  }) =>
      FirstRunOpsState(
        pgBusy: pgBusy ?? this.pgBusy,
        pgMessage: clearPgMessage ? null : (pgMessage ?? this.pgMessage),
        pgMessageOk: pgMessageOk ?? this.pgMessageOk,
        provisionRows: provisionRows ?? this.provisionRows,
        provisionError: clearProvisionError
            ? null
            : (provisionError ?? this.provisionError),
        linkBusy: linkBusy ?? this.linkBusy,
        linkMessage: clearLinkMessage ? null : (linkMessage ?? this.linkMessage),
        linkMessageOk: linkMessageOk ?? this.linkMessageOk,
        syncBusy: syncBusy ?? this.syncBusy,
        syncMessage: clearSyncMessage ? null : (syncMessage ?? this.syncMessage),
        syncOffline: syncOffline ?? this.syncOffline,
        branches: branches ?? this.branches,
        accountBusy: accountBusy ?? this.accountBusy,
        account: clearAccount ? null : (account ?? this.account),
      );
}

final firstRunOpsProvider =
    NotifierProvider<FirstRunOps, FirstRunOpsState>(FirstRunOps.new);

class FirstRunOps extends Notifier<FirstRunOpsState> {
  @override
  FirstRunOpsState build() => const FirstRunOpsState();

  FirstRunController get _ctl => ref.read(firstRunControllerProvider.notifier);
  FirstRunUiState get _ui => ref.read(firstRunControllerProvider);

  void _setChecks(FirstRunChecks Function(FirstRunChecks c) change) =>
      _ctl.update((d) => d.copyWith(checks: change(d.checks)));

  // ── PostgreSQL (hq) ──

  Future<void> testPostgres() async {
    if (state.anyBusy) return;
    state = state.copyWith(pgBusy: true, clearPgMessage: true);
    final err = await ref
        .read(serverProvisioningServiceProvider)
        .testConnection(pgConfigOf(_ui.draft, _ui.secrets));
    state = state.copyWith(
      pgBusy: false,
      pgMessageOk: err == null,
      pgMessage: err == null
          ? tr('✅ تم الاتصال بنجاح')
          : tr('❌ فشل الاتصال: {err}', {'err': err}),
    );
  }

  Future<void> provisionPostgres() async {
    if (state.anyBusy) return;
    final labels = provisionLabels();
    var rows = [for (final l in labels) ProvisionRow(l, ProvisionStatus.pending)];
    state = state.copyWith(
      pgBusy: true,
      provisionRows: rows,
      clearProvisionError: true,
      clearPgMessage: true,
    );
    _setChecks((c) => c.copyWith(provisioned: false));
    final outcome = await ref.read(serverProvisioningServiceProvider).provision(
      pgConfigOf(_ui.draft, _ui.secrets),
      onStep: (i, status, detail) {
        rows = [...rows];
        rows[i] = ProvisionRow(labels[i], status, detail ?? rows[i].detail);
        state = state.copyWith(provisionRows: rows);
      },
    );
    state = state.copyWith(
      pgBusy: false,
      provisionError: outcome.ok ? null : outcome.error,
    );
    if (outcome.ok) _setChecks((c) => c.copyWith(provisioned: true));
  }

  // ── الربط (branch / mirror) ──

  Future<void> pairDevice() async {
    if (state.anyBusy) return;
    final d = _ui.draft;
    final code = _ui.secrets.pairingCode.trim().toUpperCase();
    if (code.isEmpty) {
      state = state.copyWith(
          linkMessageOk: false,
          linkMessage: tr('أدخل رمز الإقران الذي أصدره السيرفر الرئيسي.'));
      return;
    }
    state = state.copyWith(linkBusy: true, clearLinkMessage: true);
    final link = ref.read(clientLinkPortProvider);
    final address = d.endpoint.trim();
    final port = int.tryParse(d.port.trim()) ?? 8080;
    // A1: the PATH decides the device kind (a mirror pairs only with a mirror
    // code; a branch only with a client / pos code) - never the other way.
    final r = d.path == FirstRunPath.mirror
        ? await link.pairMirrorWithCode(
            host: address, port: port, code: code, deviceName: d.deviceName.trim())
        : await link.pairDevice(
            address: address, port: port, code: code, deviceName: d.deviceName.trim());
    state = state.copyWith(
      linkBusy: false,
      linkMessageOk: r.ok,
      linkMessage: r.message,
    );
    if (r.ok) {
      _ctl.updateSecrets((s) => s.copyWith(pairingCode: ''));
      _setChecks((c) => c.copyWith(linked: true));
    }
  }

  // ── المزامنة الأولى ──

  Future<void> loadSyncedBranches() async {
    if (state.branches.isNotEmpty) return;
    try {
      final all = await ref.read(setupPersistenceProvider).getAllBranches();
      if (all.isNotEmpty) state = state.copyWith(branches: all);
    } catch (_) {}
  }

  Future<void> startFirstSync() async {
    if (state.anyBusy) return;
    final d = _ui.draft;
    state = state.copyWith(
      syncBusy: true,
      syncOffline: false,
      clearSyncMessage: true,
    );
    final r = await ref.read(clientLinkPortProvider).connectAndSync(
          address: d.endpoint.trim(),
          port: int.tryParse(d.port.trim()) ?? 8080,
          // الإعدادُ لم يكتمل بعد: لا بياناتَ عملٍ محليّةً تُفقَد بإعادة الربط.
          confirmRePair: () async => true,
          onProgress: (m) => state = state.copyWith(syncMessage: m),
          mirror: d.path == FirstRunPath.mirror,
        );
    state = state.copyWith(
      syncBusy: false,
      syncMessage: r.message,
      syncOffline: r.outcome == ClientLinkOutcome.connectFailed ||
          r.outcome == ClientLinkOutcome.error,
      branches: r.ok ? r.branches : state.branches,
    );
    if (!r.ok) return;
    _setChecks((c) => c.copyWith(firstSyncDone: true));
    if (d.path == FirstRunPath.branch && r.branches.length == 1) {
      await selectBranch(r.branches.single);
    }
  }

  Future<void> selectBranch(Branche b) async {
    await ref.read(setupPersistenceProvider).saveClientBranchId(b.id);
    state = state.copyWith(clearAccount: true);
    _ctl.update((d) => invalidate(
          d.copyWith(
            selectedBranchId: b.id,
            selectedBranchName: b.name,
            selectedBranchCode: b.code ?? '',
          ),
          FirstRunField.branchSelection,
        ));
  }

  // ── حساب الفرع ──

  Future<void> verifyAccount() async {
    if (state.anyBusy) return;
    final d = _ui.draft;
    final branchId = d.selectedBranchId;
    final mirror = d.path == FirstRunPath.mirror;
    if (branchId == null && !mirror) return;
    state = state.copyWith(accountBusy: true, clearAccount: true);
    final r = await ref.read(branchAccountVerifierProvider).verify(
          username: d.accountUsername,
          password: _ui.secrets.accountPassword,
          branchId: mirror ? null : branchId,
          newPassword: _ui.secrets.accountNewPassword,
        );
    state = state.copyWith(accountBusy: false, account: r);
    // A temporary password stays in memory for the NEXT call only (the change
    // is made on the main); otherwise no password survives the attempt.
    _ctl.updateSecrets((s) => r.needsPasswordChange
        ? s.copyWith(accountNewPassword: '')
        : s.copyWith(accountPassword: '', accountNewPassword: ''));
    _setChecks((c) => c.copyWith(accountVerified: r.ok));
  }

  void clearAccountResult() => state = state.copyWith(clearAccount: true);
}
