// A1 (adoption contract §C.7-5): "فحص اعتماد الإعداد" - shown once, before the
// login, after a networked setup finished. Reads the RUNNING system and shows
// each item PASS / FAIL / not required. A blocking FAIL forbids the login and
// offers "retry" and "re-provision this device".
import 'dart:io' show exit;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/locale_provider.dart';
import '../../../core/i18n/tr.dart';
import '../../../services/deployment/self_check.dart';
import '../../picpos_shell/picpos_surface.dart';
import 'provisioning_providers.dart';
import 'reprovision_confirm_dialog.dart';
import 'widgets/first_run_callout.dart';

String selfCheckLabel(SelfCheckId id) => switch (id) {
      SelfCheckId.record => tr('سجل الجهاز'),
      SelfCheckId.mode => tr('نمط التشغيل'),
      SelfCheckId.database => tr('قاعدة بيانات السيرفر الرئيسي جاهزة'),
      SelfCheckId.pairing => tr('إقران الجهاز بالسيرفر الرئيسي'),
      SelfCheckId.server => tr('الاتصال بالسيرفر الرئيسي'),
      SelfCheckId.deltaPull => tr('سحب التغييرات من الرئيسي خلال 60 ثانية'),
      SelfCheckId.mainMatch => tr('الشركة والعملة والباقة مطابقة للرئيسي'),
      SelfCheckId.firstSync => tr('المزامنة الأولى (الفروع والمخازن)'),
      SelfCheckId.users => tr('بيانات دخول مستخدمي الفرع'),
      SelfCheckId.noDefaultAdmin => tr('لا حساب افتراضي admin/admin'),
    };

class FirstRunSelfCheckScreen extends ConsumerStatefulWidget {
  const FirstRunSelfCheckScreen({super.key, required this.onPassed, this.onRestart});

  /// After a passed check (login next).
  final VoidCallback onPassed;

  /// After "re-provision": restart the app (default: end the process).
  final VoidCallback? onRestart;

  @override
  ConsumerState<FirstRunSelfCheckScreen> createState() =>
      _FirstRunSelfCheckScreenState();
}

class _FirstRunSelfCheckScreenState
    extends ConsumerState<FirstRunSelfCheckScreen> {
  SelfCheckReport? _report;
  bool _running = false;
  bool _reprovisioned = false;

  @override
  void initState() {
    super.initState();
    Future<void>(_run);
  }

  Future<void> _run() async {
    if (!mounted || _running) return;
    setState(() => _running = true);
    final r = await ref.read(selfCheckRunnerProvider).run();
    if (!mounted) return;
    setState(() {
      _report = r;
      _running = false;
    });
  }

  Future<void> _continue() async {
    await ref.read(provisioningActionsProvider).markSelfCheckPassed();
    widget.onPassed();
  }

  Future<void> _reprovision() async {
    if (!await confirmReprovision(context)) return;
    await ref.read(provisioningActionsProvider).reprovision();
    if (mounted) setState(() => _reprovisioned = true);
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(userLocaleProvider);
    final isEnglish = I18nCatalog.activeLocale.languageCode == 'en';
    return Directionality(
      textDirection: isEnglish ? TextDirection.ltr : TextDirection.rtl,
      child: Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: _reprovisioned ? _restartPrompt() : _checks(context),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _restartPrompt() => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FirstRunCallout(
            key: const Key('self_check_reprovisioned'),
            title: tr('تمت إعادة التوفير. أعد تشغيل البرنامج لبدء الإعداد من جديد.'),
            tone: FirstRunTone.success,
            icon: Icons.check_circle_outline,
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            key: const Key('self_check_restart'),
            onPressed: widget.onRestart ?? () => exit(0),
            icon: const Icon(Icons.restart_alt),
            label: Text(tr('إعادة التشغيل الآن')),
          ),
        ],
      );

  Widget _checks(BuildContext context) {
    final report = _report;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          tr('فحص اعتماد الإعداد'),
          key: const Key('self_check_title'),
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w900,
            color: context.picposText,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          tr('نتأكد أن ما اخترته في الإعداد هو ما يعمل فعلًا على هذا الجهاز قبل تسجيل الدخول.'),
          style: TextStyle(color: context.picposMuted),
        ),
        const SizedBox(height: 16),
        if (report == null)
          const Center(child: CircularProgressIndicator())
        else ...[
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: context.picposCard,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: context.picposHairline),
            ),
            child: Column(
              children: [for (final i in report.items) _row(context, i)],
            ),
          ),
          if (report.needsRePair) ...[
            const SizedBox(height: 12),
            FirstRunCallout(
              key: const Key('self_check_repair_prompt'),
              title: tr('فُقدت هوية إقران هذا الجهاز أو رمزه.'),
              body: tr('أعد إقران الجهاز برمز جديد من السيرفر الرئيسي: اختر «إعادة توفير هذا الجهاز».'),
              tone: FirstRunTone.warning,
              icon: Icons.link_off,
            ),
          ],
          const SizedBox(height: 18),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                key: const Key('self_check_continue'),
                onPressed: report.canContinue ? _continue : null,
                icon: const Icon(Icons.login),
                label: Text(tr('متابعة إلى تسجيل الدخول')),
              ),
              OutlinedButton.icon(
                key: const Key('self_check_retry'),
                onPressed: _running ? null : _run,
                icon: const Icon(Icons.refresh),
                label: Text(tr('إعادة المحاولة')),
              ),
              OutlinedButton.icon(
                key: const Key('self_check_reprovision'),
                onPressed: _reprovision,
                icon: const Icon(Icons.settings_backup_restore),
                label: Text(tr('إعادة توفير هذا الجهاز')),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _row(BuildContext context, SelfCheckItem i) {
    final (icon, color, text) = switch (i.status) {
      SelfCheckStatus.pass => (
          Icons.check_circle,
          firstRunToneColor(FirstRunTone.success),
          tr('سليم')
        ),
      SelfCheckStatus.fail => (
          Icons.cancel,
          firstRunToneColor(FirstRunTone.danger),
          tr('فشل')
        ),
      SelfCheckStatus.skip => (
          Icons.remove_circle_outline,
          context.picposMuted,
          tr('غير مطلوب')
        ),
    };
    return Padding(
      key: Key('self_check_row_${i.id.name}'),
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(selfCheckLabel(i.id),
                style: TextStyle(color: context.picposText)),
          ),
          Text(text,
              style: TextStyle(color: color, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}
