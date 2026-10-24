// متحكّمُ الإعداد الأول — `Notifier` واحدٌ فوق الآلة الخالصة (`first_run_machine`).
//
// • كلُّ تعديلٍ يمرّ بـ[update] فيُحفَظ في المسودّة (debounce) ويمسح الخطأ.
// • الأسرارُ في [FirstRunUiState.secrets] — الذاكرةُ فقط، تُمسح عند تبديل
//   المسار وعند نجاح الإنهاء، ولا تصل المخزنَ أبداً.
// • الاستئنافُ: تُحمَّل المسودّةُ ثمّ تُشتقّ أعلامُ التحقّق من **الحقائق**.
// • الإنهاءُ idempotent: حارسُ إعادة الدخول `committing`، والفشلُ يبقى على
//   المراجعة بمرحلته وسببه، ويُمسح `setup_progress_v2` و`setup_draft_v2` عند
//   النجاح فقط.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/tr.dart';
import '../../../domain/models/first_run/first_run_draft.dart';
import '../../../domain/models/first_run/first_run_invalidation.dart';
import '../../../domain/models/first_run/first_run_machine.dart' as machine;
import '../../../domain/models/first_run/first_run_path.dart';
import '../../../domain/models/first_run/first_run_steps.dart';
import '../../../domain/models/first_run/first_run_validation.dart';
import '../../../services/setup/first_run_storage_probe.dart';
import '../../touch_keyboard/providers/touch_mode_provider.dart';
import '../setup_wizard/setup_finish_runner.dart';
import '../setup_wizard/setup_persistence_riverpod.dart';
import 'first_run_draft_store.dart';
import 'first_run_facts.dart';
import 'first_run_providers.dart';

class FirstRunUiState {
  const FirstRunUiState({
    required this.draft,
    this.secrets = const FirstRunSecrets(),
    this.phase = machine.FirstRunPhase.editing,
    this.loading = true,
    this.error,
    this.runStage,
    this.failedStage,
    this.failureMessage,
    this.resumedIncomplete = false,
    this.storage,
    this.warnings = const [],
  });

  final FirstRunDraft draft;
  final FirstRunSecrets secrets;
  final machine.FirstRunPhase phase;

  /// تُحمَّل المسودّةُ المحفوظة بعد.
  final bool loading;

  /// آخرُ سببِ منعٍ — يُعلَن في منطقة الخطأ.
  final FirstRunStepIssue? error;

  /// المرحلةُ الجاريةُ أثناء `committing`.
  final SetupRunStage? runStage;
  final SetupRunStage? failedStage;
  final String? failureMessage;

  /// بانر «إعداد غير مكتمل — أكمل».
  final bool resumedIncomplete;
  final StorageProbeResult? storage;
  final List<String> warnings;

  bool get busy => phase == machine.FirstRunPhase.committing;
  bool get committed => phase == machine.FirstRunPhase.committed;

  FirstRunUiState copyWith({
    FirstRunDraft? draft,
    FirstRunSecrets? secrets,
    machine.FirstRunPhase? phase,
    bool? loading,
    FirstRunStepIssue? error,
    bool clearError = false,
    SetupRunStage? runStage,
    bool clearRunStage = false,
    SetupRunStage? failedStage,
    String? failureMessage,
    bool clearFailure = false,
    bool? resumedIncomplete,
    StorageProbeResult? storage,
    List<String>? warnings,
  }) =>
      FirstRunUiState(
        draft: draft ?? this.draft,
        secrets: secrets ?? this.secrets,
        phase: phase ?? this.phase,
        loading: loading ?? this.loading,
        error: clearError ? null : (error ?? this.error),
        runStage: clearRunStage ? null : (runStage ?? this.runStage),
        failedStage: clearFailure ? null : (failedStage ?? this.failedStage),
        failureMessage:
            clearFailure ? null : (failureMessage ?? this.failureMessage),
        resumedIncomplete: resumedIncomplete ?? this.resumedIncomplete,
        storage: storage ?? this.storage,
        warnings: warnings ?? this.warnings,
      );
}

final firstRunControllerProvider =
    NotifierProvider<FirstRunController, FirstRunUiState>(
  FirstRunController.new,
);

class FirstRunController extends Notifier<FirstRunUiState> {
  late final FirstRunDraftStore _store;

  @override
  FirstRunUiState build() {
    _store = ref.read(firstRunDraftStoreProvider);
    unawaited(Future<void>.microtask(_init));
    return FirstRunUiState(draft: _store.fresh());
  }

  Future<void> _init() async {
    final saved = await _store.load();
    final probe = ref.read(firstRunStorageProbeProvider);
    final facts = await loadFacts(
      read: _store.readSetting,
      probe: probe,
      wasCommitting: await _store.wasCommitting(),
    );
    var draft = applyFacts(saved ?? state.draft, facts);
    // افتراضاتٌ بلغة الواجهة الحاليّة للحقول الفارغة.
    if (draft.branchName.trim().isEmpty) {
      draft = draft.copyWith(branchName: tr('الفرع الرئيسي'));
    }
    if (draft.warehouseName.trim().isEmpty) {
      draft = draft.copyWith(warehouseName: tr('المخزن الرئيسي'));
    }
    // انقطاعٌ أثناء التشغيل ⇒ يُستأنف من المراجعة (‏C.3) بإنهاءٍ idempotent.
    if (facts.wasCommitting) {
      final last = stepsFor(draft.path).length - 1;
      draft = draft.copyWith(step: last, maxStep: last);
    }
    state = state.copyWith(
      draft: draft,
      loading: false,
      resumedIncomplete: facts.incomplete,
      storage: facts.storage,
    );
  }

  // ── تعديلات ──

  void update(FirstRunDraft Function(FirstRunDraft d) change) {
    final next = change(state.draft);
    state = state.copyWith(draft: next, clearError: true);
    _store.scheduleSave(next);
  }

  void updateSecrets(FirstRunSecrets Function(FirstRunSecrets s) change) {
    state = state.copyWith(secrets: change(state.secrets), clearError: true);
  }

  void selectPathTo(FirstRunPath path) {
    if (state.draft.path == path) return;
    state = state.copyWith(secrets: const FirstRunSecrets(), clearFailure: true);
    // تصفيرُ التحقّقات يشمل فحصَ المجلد — يُعاد من آخر نتيجةٍ للفحص.
    update((d) => selectPath(d, path).copyWith(
          checks: FirstRunChecks(
            storageChecked: state.storage?.writable ?? false,
          ),
        ));
  }

  void setCurrency(String code) => update((d) => selectCurrency(d, code));

  /// إعادةُ فحص مجلد البيانات (‏زرّ «إعادة الفحص»).
  Future<void> recheckStorage() async {
    final r = await ref.read(firstRunStorageProbeProvider).probe();
    state = state.copyWith(
      storage: r,
      draft: state.draft.copyWith(
        checks: state.draft.checks.copyWith(storageChecked: r.writable),
      ),
    );
  }

  // ── تنقّل ──

  void next() {
    final move = machine.advance(state.draft, state.secrets);
    state = state.copyWith(
      draft: move.draft,
      error: move.blocked,
      clearError: move.ok,
    );
    _store.scheduleSave(move.draft);
  }

  void back() => update(machine.back);

  void jumpToStep(int index) => update((d) => machine.jumpTo(d, index));

  // ── الإنهاء ──

  Future<void> finish() async {
    if (state.busy || state.committed) return;
    final move = machine.beginFinish(state.draft, state.secrets);
    if (!move.ok) {
      state = state.copyWith(draft: move.draft, error: move.blocked);
      _store.scheduleSave(move.draft);
      return;
    }
    state = state.copyWith(
      phase: machine.FirstRunPhase.committing,
      clearError: true,
      clearFailure: true,
      clearRunStage: true,
    );
    await _store.markCommitting();
    final result = await ref.read(firstRunFinisherProvider)(
      state.draft,
      state.secrets,
      ref.read(setupPersistenceProvider),
      onStage: (s) => state = state.copyWith(runStage: s),
    );
    if (!result.ok) {
      state = state.copyWith(
        phase: machine.FirstRunPhase.editing,
        clearRunStage: true,
        failedStage: result.failedStage,
        failureMessage: result.error,
        warnings: result.warnings,
      );
      return;
    }
    await _store.clear();
    ref.invalidate(touchModeProvider);
    state = state.copyWith(
      phase: machine.FirstRunPhase.committed,
      secrets: const FirstRunSecrets(),
      clearRunStage: true,
      clearFailure: true,
      warnings: [...result.warnings, ...result.failedUsers],
      resumedIncomplete: false,
    );
  }
}
