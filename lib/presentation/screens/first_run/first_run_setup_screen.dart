// شاشةُ الإعداد الأول (v2) — الإطار: شريطُ تقدّم، ستيبر جانبيّ، منطقةُ خطأٍ
// مُعلَنة، تذييلٌ بـ«السابق/التالي/إنهاء»، وزرُّ دليلٍ. تحلّ محلّ المعالج القديم
// في بوّابة الإقلاع (‏`buildFirstRunEntry`).
//
import 'dart:io' show exit;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart'
    show KeyDownEvent, LogicalKeyboardKey;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app_main_screen.dart';
import '../../../core/i18n/locale_provider.dart';
import '../../../core/i18n/tr.dart';
import '../../../core/theme/app_colors.dart';
import '../../../domain/models/first_run/first_run_path.dart';
import '../../../domain/models/first_run/first_run_steps.dart';
import '../../../domain/models/first_run/first_run_validation.dart';
import '../../picpos_shell/picpos_surface.dart';
import 'first_run_controller.dart';
import 'first_run_guide_dialog.dart';
import 'first_run_success_page.dart';
import 'first_run_texts.dart';
import 'steps/step_account.dart';
import 'steps/step_company.dart';
import 'steps/step_first_sync.dart';
import 'steps/step_link.dart';
import 'steps/step_mode.dart';
import 'steps/step_prep.dart';
import 'steps/step_review.dart';
import 'steps/step_storage_branch.dart';
import 'steps/step_storage_local.dart';
import 'steps/step_storage_pg.dart';
import 'steps/step_users_hq.dart';
import 'steps/step_users_local.dart';
import 'widgets/first_run_callout.dart';
import 'widgets/first_run_stepper.dart';

class FirstRunSetupScreen extends ConsumerStatefulWidget {
  const FirstRunSetupScreen({super.key, this.onStart, this.onRestart});

  /// «ابدأ الاستخدام» — الافتراضيُّ ينتقل إلى `MainScreen`.
  final VoidCallback? onStart;

  /// إعادة التشغيل الآن (المقر: PostgreSQL يحتاج إقلاعا جديدا). الافتراضي يُنهي
  /// العملية؛ هذه الشاشة تسبق تسجيل الدخول فلا سلة بيع قائمة تُفقد.
  final VoidCallback? onRestart;

  @override
  ConsumerState<FirstRunSetupScreen> createState() =>
      _FirstRunSetupScreenState();
}

class _FirstRunSetupScreenState extends ConsumerState<FirstRunSetupScreen> {
  void _start() {
    if (widget.onStart != null) {
      widget.onStart!();
      return;
    }
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(builder: (_) => const MainScreen()),
      (r) => false,
    );
  }

  void _onNext(FirstRunUiState s) {
    final ctl = ref.read(firstRunControllerProvider.notifier);
    if (s.draft.currentStep == FirstRunStep.review) {
      ctl.finish();
    } else {
      ctl.next();
    }
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key != LogicalKeyboardKey.enter &&
        key != LogicalKeyboardKey.numpadEnter) {
      return KeyEventResult.ignored;
    }
    // لا على زرٍّ ولا رقاقة: هناك Enter يضغطها.
    final focus = FocusManager.instance.primaryFocus;
    final inText =
        focus?.context?.findAncestorWidgetOfExactType<EditableText>() != null;
    if (focus != null && focus != node && !inText) return KeyEventResult.ignored;
    final s = ref.read(firstRunControllerProvider);
    if (s.loading || s.busy || s.committed) return KeyEventResult.ignored;
    if (validateStep(s.draft.currentStep, s.draft, s.secrets) != null) {
      return KeyEventResult.ignored;
    }
    _onNext(s);
    return KeyEventResult.handled;
  }

  Widget _stepBody(FirstRunUiState s) {
    final path = s.draft.path;
    return switch (s.draft.currentStep) {
      FirstRunStep.mode => const StepMode(),
      FirstRunStep.company => const StepCompany(),
      FirstRunStep.storage => switch (path) {
          FirstRunPath.hq => const StepStoragePg(),
          FirstRunPath.branch => const StepStorageBranch(),
          _ => const StepStorageLocal(),
        },
      FirstRunStep.users => path == FirstRunPath.hq
          ? const StepUsersHq()
          : const StepUsersLocal(),
      FirstRunStep.prep => const StepPrep(),
      FirstRunStep.link => const StepLink(),
      FirstRunStep.firstSync => const StepFirstSync(),
      FirstRunStep.account => const StepAccount(),
      FirstRunStep.review => const StepReview(),
      FirstRunStep.success => const SizedBox.shrink(),
    };
  }

  @override
  Widget build(BuildContext context) {
    // إعادةُ البناء عند تبديل اللغة (‏`tr()` يقرأ اللغةَ الحاليّة).
    ref.watch(userLocaleProvider);
    final isEnglish = I18nCatalog.activeLocale.languageCode == 'en';
    final s = ref.watch(firstRunControllerProvider);
    return Directionality(
      textDirection: isEnglish ? TextDirection.ltr : TextDirection.rtl,
      child: Focus(
        autofocus: true,
        onKeyEvent: _onKey,
        child: Scaffold(
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          body: SafeArea(
            child: s.loading
                ? const Center(child: CircularProgressIndicator())
                : s.committed
                    ? FirstRunSuccessPage(
                        onStart: _start,
                        onRestart: widget.onRestart ?? () => exit(0),
                      )
                    : _shell(context, s),
          ),
        ),
      ),
    );
  }

  Widget _shell(BuildContext context, FirstRunUiState s) {
    final d = s.draft;
    final steps = stepsFor(d.path);
    final titles = [for (final st in steps) firstRunStepTitle(st, d.path)];
    final step = d.currentStep;
    final issue = validateStep(step, d, s.secrets);
    final isReview = step == FirstRunStep.review;
    final canGo = !s.busy && issue == null;
    final ctl = ref.read(firstRunControllerProvider.notifier);

    final footer = Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          if (d.step > 0)
            OutlinedButton.icon(
              key: const Key('first_run_back'),
              onPressed: s.busy ? null : ctl.back,
              icon: const Icon(Icons.arrow_back, size: 18),
              label: Text(tr('السابق')),
            ),
          const Spacer(),
          if (issue != null && !s.busy)
            Flexible(
              child: Padding(
                padding: const EdgeInsetsDirectional.only(end: 12),
                child: Text(
                  firstRunIssueText(issue),
                  key: const Key('first_run_blocked_hint'),
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: context.picposMuted, fontSize: 12.5),
                ),
              ),
            ),
          FilledButton.icon(
            key: Key(isReview ? 'first_run_finish' : 'first_run_next'),
            onPressed: canGo ? () => _onNext(s) : null,
            style: FilledButton.styleFrom(
              backgroundColor: isReview ? AppColors.success : AppColors.primary,
              foregroundColor: Theme.of(context).colorScheme.onPrimary,
            ),
            icon: s.busy
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(isReview ? Icons.check_circle_outline : Icons.arrow_forward, size: 18),
            label: Text(
              isReview
                  ? (s.failedStage != null
                      ? tr('إعادة المحاولة')
                      : tr('إنهاء الإعداد والبدء'))
                  : tr('التالي'),
            ),
          ),
        ],
      ),
    );

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          firstRunStepTitle(step, d.path),
          key: const Key('first_run_step_title'),
          style: TextStyle(
            fontSize: 21,
            fontWeight: FontWeight.w900,
            color: context.picposText,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          firstRunStepSubtitle(step),
          style: TextStyle(fontSize: 13.5, color: context.picposMuted),
        ),
        const SizedBox(height: 14),
        if (s.resumedIncomplete)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: FirstRunCallout(
              key: const Key('first_run_resume_banner'),
              title: tr('إعداد غير مكتمل — أكمل'),
              body: tr('توقف الإعداد السابق قبل اكتماله. راجع البيانات ثم أكمل؛ لن يتكرر شيء.'),
              tone: FirstRunTone.warning,
              icon: Icons.history,
            ),
          ),
        // منطقةُ خطأٍ واحدةٌ مُعلَنةٌ لقارئ الشاشة.
        Semantics(
          liveRegion: true,
          container: true,
          child: s.error == null
              ? const SizedBox.shrink()
              : Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: FirstRunCallout(
                    key: const Key('first_run_error'),
                    title: firstRunIssueText(s.error!.issue),
                    tone: FirstRunTone.danger,
                    icon: Icons.error_outline,
                  ),
                ),
        ),
        Expanded(child: SingleChildScrollView(child: _stepBody(s))),
        footer,
      ],
    );

    return LayoutBuilder(builder: (context, c) {
      final wide = c.maxWidth >= 900;
      final stepper = FirstRunStepper(
        titles: titles,
        current: d.step,
        maxStep: d.maxStep,
        compact: !wide,
        onSelect: ctl.jumpToStep,
      );
      return Column(
        children: [
          _header(context, d.step, titles.length),
          Semantics(
            label: tr('التقدم'),
            value: '${d.step + 1}/${titles.length}',
            child: LinearProgressIndicator(
              key: const Key('first_run_progress'),
              value: (d.step + 1) / titles.length,
              minHeight: 3,
            ),
          ),
          Expanded(
            child: wide
                ? Row(
                    children: [
                      Container(
                        width: 264,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: context.picposCard,
                          border: BorderDirectional(
                            end: BorderSide(color: context.picposHairline),
                          ),
                        ),
                        child: SingleChildScrollView(child: stepper),
                      ),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(28, 18, 28, 8),
                          child: Align(
                            alignment: AlignmentDirectional.topStart,
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 820),
                              child: content,
                            ),
                          ),
                        ),
                      ),
                    ],
                  )
                : Column(
                    children: [
                      stepper,
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: content,
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      );
    });
  }

  Widget _header(BuildContext context, int index, int total) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      decoration: BoxDecoration(
        color: context.picposCard,
        border: Border(bottom: BorderSide(color: context.picposHairline)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.primary,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              Icons.rocket_launch_outlined,
              size: 22,
              color: Theme.of(context).colorScheme.onPrimary,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              tr('إعداد النسخة'),
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w900,
                color: context.picposText,
              ),
            ),
          ),
          Text(
            tr('{p0} من {p1}', {'p0': index + 1, 'p1': total}),
            key: const Key('first_run_step_counter'),
            style: TextStyle(color: context.picposMuted, fontSize: 13),
          ),
          const SizedBox(width: 8),
          IconButton(
            key: const Key('first_run_guide'),
            tooltip: tr('دليل الإعداد'),
            onPressed: () => showFirstRunGuide(context),
            icon: Icon(Icons.help_outline, color: context.picposBrandInk),
          ),
        ],
      ),
    );
  }
}
