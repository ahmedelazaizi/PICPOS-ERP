import 'package:picpos_erp/core/i18n/tr.dart';
// ═══════════════════════════════════════════════════════════════════════════
// DEVELOPER TOOLS SCREEN — locked behind the developer password
// ═══════════════════════════════════════════════════════════════════════════
//
// One screen, one purpose: let the developer (NOT the end-user, NOT
// even the admin) change runtime configuration after install. Every
// mutation flows through `ConfigService` so audit + hash + lock-checks
// stay in one place.
//
// Surfaces:
//   • Snapshot panel (profile / mode / hash) for diagnostics.
//   • Change business profile (dropdown of `BusinessProfileCatalog`).
//   • Change deployment mode (segmented control).
//   • Per-feature overrides (grouped by module: pos / restaurant /
//     enterprise; cores hidden because they can't be disabled).
//   • Reset setup wizard.
//   • Change / clear developer password.
//
// Access:
//   `DeveloperPasswordGate` wraps the whole screen. If the
//   `developerSessionProvider` is active, the gate is invisible. Else
//   a password prompt is shown and the screen mounts only on success.
//   The session uses a sliding 10-minute window.
// ═══════════════════════════════════════════════════════════════════════════

import 'package:picpos_erp/core/widgets/app_toast.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/config/business_profile.dart';
import '../../core/config/business_profile_meta.dart';
import '../../core/config/business_profile_provider.dart';
import '../../core/config/feature_key.dart';
import '../../core/config/runtime_config_snapshot.dart';
import '../../core/theme/app_colors.dart';
import '../../services/admin/data_wipe_service.dart';
import '../../data/providers/providers.dart';
import '../../services/deployment/commit_result.dart';
import '../../services/deployment/deployment_mode_committer.dart';
import '../../services/mirror_state.dart';
import '../../services/network_service.dart';
import '../picpos_shell/picpos_danger_confirm.dart';
import '../widgets/settings/mirror_pairing_dialog.dart';

class DeveloperToolsScreen extends ConsumerWidget {
  const DeveloperToolsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return const Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        body: DeveloperPasswordGate(child: _DeveloperToolsBody()),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════
// PASSWORD GATE — verifies the developer password before mounting body
// ═════════════════════════════════════════════════════════════════════════

/// بوّابةُ كلمةِ مرور المطوّر — لا تُركَّب [child] إلّا بعد التحقّق.
///
/// عامّةٌ عن قصد: قشرةُ PicPos (`DeveloperToolsPicposScreen`) تُعيد استعمالها
/// كما هي بدل نسخِها. وبوّابةٌ منسوخةٌ بوّابةٌ تتخلّف عن أصلها.
class DeveloperPasswordGate extends ConsumerStatefulWidget {
  final Widget child;
  const DeveloperPasswordGate({super.key, required this.child});

  @override
  ConsumerState<DeveloperPasswordGate> createState() =>
      _DeveloperPasswordGateState();
}

class _DeveloperPasswordGateState
    extends ConsumerState<DeveloperPasswordGate> {
  final _pwdCtl = TextEditingController();
  final _confirmCtl = TextEditingController();
  bool _visible = false;
  String? _error;
  bool _verifying = false;

  @override
  void dispose() {
    _pwdCtl.dispose();
    _confirmCtl.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    setState(() {
      _verifying = true;
      _error = null;
    });
    final auth = ref.read(developerAuthServiceProvider);
    final ok = await auth.verify(_pwdCtl.text);
    if (!ok) {
      setState(() {
        _verifying = false;
        _error = tr('كلمة المرور غير صحيحة');
      });
      return;
    }
    ref.read(developerSessionProvider.notifier).unlock();
    if (mounted) setState(() => _verifying = false);
  }

  /// مسار التعافي: تعيين كلمة مرور مطوّر لما تكون **مش مضبوطة أصلاً**.
  ///
  /// من غيره كان `--reset-dev-password` بيقفل الشاشة بدل ما يفتحها: الحالة
  /// الوحيدة اللي بيوصّلك ليها هي `isFirstTime`، وفيها الخانة والزرار
  /// الاتنين كانوا متعطّلين ومفيش أي طريق لتعيين كلمة جديدة — فالتعافي
  /// الموثَّق في `DeveloperAuthService` («يعيّن كلمة جديدة عند أول دخول»)
  /// ما كانش موجود، والحل الوحيد كان إعادة تشغيل الويزارد من الأول.
  ///
  /// أمنياً: الوصول للحالة دي بيتطلّب تشغيل الـ exe بعلم CLI أو متغيّر بيئة
  /// على الجهاز نفسه — يعني اللي يقدر يعمله يقدر أصلاً يوصل لملف الداتابيز.
  /// و`setPassword` بيسجّل في سجل التدقيق بمستوى critical.
  Future<void> _createPassword() async {
    final pwd = _pwdCtl.text.trim();
    final cnf = _confirmCtl.text.trim();
    if (pwd.length < 4 || pwd != cnf) {
      setState(() {
        _error = pwd.length < 4
            ? tr('يجب أن لا تقل كلمة المرور عن 4 أحرف')
            : tr('تأكيد كلمة المرور غير مطابق');
      });
      return;
    }
    setState(() {
      _verifying = true;
      _error = null;
    });
    try {
      await ref.read(developerAuthServiceProvider).setPassword(pwd);
      if (!mounted) return;
      ref.read(developerSessionProvider.notifier).unlock();
      setState(() => _verifying = false);
    } catch (e) {
      if (mounted) {
        setState(() {
          _verifying = false;
          _error = tr('فشل التعيين: {e}', {'e': e});
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(developerSessionProvider);
    if (session.isActive) {
      // Listen for the session expiring while the user is on the page
      // — kick them out so they can't continue mutating without
      // re-authenticating.
      return widget.child;
    }
    final auth = ref.watch(developerAuthServiceProvider);
    final isFirstTime = !auth.isConfigured;
    return Center(
      child: SizedBox(
        width: 420,
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  PhosphorIconsBold.shieldStar,
                  size: 48,
                  color: AppColors.primary,
                ),
                const SizedBox(height: 12),
                 Text(
                  tr('أدوات المطوّر'),
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  isFirstTime
                      ? tr('لم يتم تعيين كلمة مرور مطوّر على هذا التركيب. عيّن واحدة الآن لحماية الشاشة وفتحها.')
                      : tr('هذه الشاشة محمية. أدخل كلمة مرور المطوّر للمتابعة.'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textMuted,
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _pwdCtl,
                  obscureText: !_visible,
                  onSubmitted: (_) =>
                      isFirstTime ? _createPassword() : _verify(),
                  decoration: InputDecoration(
                    labelText: isFirstTime
                        ? tr('كلمة مرور مطوّر جديدة')
                        : tr('كلمة مرور المطوّر'),
                    prefixIcon: const Icon(PhosphorIconsBold.lock),
                    suffixIcon: IconButton(
                      icon: Icon(_visible
                          ? PhosphorIconsBold.eyeSlash
                          : PhosphorIconsBold.eye),
                      onPressed: () =>
                          setState(() => _visible = !_visible),
                    ),
                    errorText: isFirstTime ? null : _error,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
                if (isFirstTime) ...[
                  const SizedBox(height: 10),
                  TextField(
                    controller: _confirmCtl,
                    obscureText: !_visible,
                    onSubmitted: (_) => _createPassword(),
                    decoration: InputDecoration(
                      labelText: tr('تأكيد كلمة المرور'),
                      prefixIcon: const Icon(PhosphorIconsBold.lockKey),
                      errorText: _error,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                Row(
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child:  Text(tr('إلغاء')),
                    ),
                    const Spacer(),
                    ElevatedButton.icon(
                      onPressed: _verifying
                          ? null
                          : (isFirstTime ? _createPassword : _verify),
                      icon: _verifying
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Icon(isFirstTime
                              ? PhosphorIconsBold.key
                              : PhosphorIconsBold.signIn),
                      label: Text(isFirstTime ? tr('تعيين وفتح') : tr('فتح')),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════
// BODY — the actual tools (mounted only after the gate unlocks)
// ═════════════════════════════════════════════════════════════════════════

class _DeveloperToolsBody extends ConsumerWidget {
  const _DeveloperToolsBody();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
  // ignore: unused_local_variable
    final snapshot = ref.watch(runtimeConfigSnapshotProvider);
  // ignore: unused_local_variable
    final hash = ref.watch(runtimeConfigHashProvider);
  // ignore: unused_local_variable
    final session = ref.watch(developerSessionProvider);

    return Scaffold(
      appBar: AppBar(
        title:  Row(
          children: [
            const Icon(PhosphorIconsBold.shieldStar),
            const SizedBox(width: 8),
            Text(tr('أدوات المطوّر')),
          ],
        ),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: tr('إنهاء الجلسة'),
            icon: const Icon(PhosphorIconsBold.signOut),
            onPressed: () {
              ref.read(developerSessionProvider.notifier).clear();
              if (Navigator.canPop(context)) Navigator.pop(context);
            },
          ),
        ],
      ),
      body: const DeveloperToolsPanels(),
    );
  }
}

/// لوحاتُ أدوات المطوّر بلا قشرة (‏بلا `Scaffold`/`AppBar`).
///
/// استُخرجت ليركب عليها إطارُ العلامتَين معاً بلا نسخِ منطق: `_DeveloperToolsBody`
/// أعلاه (‏قشرةُ UralCash — حرفاً بحرفٍ ما كانت عليه) و
/// `DeveloperToolsPicposScreen` (‏قشرةُ PicPos). فلا تنطبق «مصيدةُ النسخ
/// §٥.٨»: لا نسخةَ ثانيةً تُصان، وشاشةُ UralCash لم يتبدّل فيها بايت.
///
/// ⚠️ **ولا تُركَّب إلّا خلفَ [DeveloperPasswordGate]** — هي بوّابةُ كلمةِ
/// مرور المطوّر، وتركيبُ اللوحات بدونها يفتح تبديلَ نمطِ التشغيل ومسحَ
/// البيانات بلا تحقّق.
///
/// [searchQuery] ترشيحٌ اختياريٌّ بعنوان اللوحة؛ فارغاً (‏وهو ما تمرّره قشرةُ
/// UralCash) يعرض السبعَ كلَّها بترتيبها.
class DeveloperToolsPanels extends ConsumerWidget {
  final String searchQuery;

  const DeveloperToolsPanels({super.key, this.searchQuery = ''});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshot = ref.watch(runtimeConfigSnapshotProvider);
    final hash = ref.watch(runtimeConfigHashProvider);
    final session = ref.watch(developerSessionProvider);

    // العنوانُ هنا هو عينُ العنوان الذي ترسمه كلُّ لوحةٍ في `_SectionHeader`
    // — لو تبدّل هناك فليتبدّل هنا، وإلّا رشّح البحثُ باسمٍ لا يراه المستخدم.
    final panels = <(String, Widget)>[
      (
        tr('الحالة الحالية'),
        _SnapshotPanel(snapshot: snapshot, hash: hash, session: session)
      ),
      (tr('تغيير ملف النشاط'), _ChangeProfileSection(snapshot: snapshot)),
      (tr('تغيير نمط التشغيل'), _ChangeModeSection(snapshot: snapshot)),
      (tr('تخصيص الميزات'), const _FeatureOverridesSection()),
      (tr('تغيير كلمة مرور المطوّر'), const _ChangeDeveloperPasswordSection()),
      (tr('منطقة الخطر — إعادة ضبط'), const _ResetWizardSection()),
      (tr('تصفير البيانات — بلا رجعة'), const _DataWipeSection()),
    ];

    final q = searchQuery.trim();
    final shown =
        q.isEmpty ? panels : panels.where((p) => p.$1.contains(q)).toList();

    if (shown.isEmpty) {
      return Center(
        child: Text(
          tr('لا توجد أداةٌ تطابق «{q}»', {'q': q}),
          style: const TextStyle(fontSize: 14, color: AppColors.textMuted),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        for (var i = 0; i < shown.length; i++) ...[
          if (i > 0) const SizedBox(height: 16),
          shown[i].$2,
        ],
      ],
    );
  }
}

// ─── Snapshot panel ─────────────────────────────────────────────────────

class _SnapshotPanel extends StatelessWidget {
  final RuntimeConfigSnapshot snapshot;
  final String hash;
  final DeveloperSession session;
  const _SnapshotPanel({
    required this.snapshot,
    required this.hash,
    required this.session,
  });

  String _hhmm(DateTime dt) =>
      '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final remaining = session.expiresAt == null
        ? Duration.zero
        : session.expiresAt!.difference(DateTime.now());
    return Card(
      color: AppColors.primary.withValues(alpha: 0.04),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  PhosphorIconsBold.gauge,
                  color: AppColors.primary,
                  size: 20,
                ),
                const SizedBox(width: 8),
                 Text(
                  tr('الحالة الحالية'),
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                if (remaining > Duration.zero)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.success.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      tr('الجلسة: {p0}:{p1}', {'p0': remaining.inMinutes, 'p1': (remaining.inSeconds % 60).toString().padLeft(2, '0')}),
                      style: const TextStyle(
                          fontSize: 10, color: AppColors.success),
                    ),
                  ),
              ],
            ),
            const Divider(),
            _row(tr('ملف النشاط'),
                BusinessProfileCatalog.metaFor(snapshot.profile).arabicName),
            _row(tr('نمط التشغيل'), _modeLabel(snapshot.mode)),
            _row('Config Hash', hash.substring(0, 12)),
            _row(tr('وقت اللقطة'), _hhmm(snapshot.capturedAt)),
          ],
        ),
      ),
    );
  }

  Widget _row(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            Text(label,
                style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
            const Spacer(),
            Text(value, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
          ],
        ),
      );

  String _modeLabel(DeploymentMode m) {
    switch (m) {
      case DeploymentMode.standalone: return tr('مستقل (Standalone)');
      case DeploymentMode.server:     return tr('سيرفر (Server)');
      case DeploymentMode.client:     return tr('عميل (Client)');
      case DeploymentMode.mirror:     return tr('مرآة (Mirror)');
    }
  }
}

// ─── Change profile ─────────────────────────────────────────────────────

class _ChangeProfileSection extends ConsumerStatefulWidget {
  final RuntimeConfigSnapshot snapshot;
  const _ChangeProfileSection({required this.snapshot});

  @override
  ConsumerState<_ChangeProfileSection> createState() =>
      _ChangeProfileSectionState();
}

class _ChangeProfileSectionState
    extends ConsumerState<_ChangeProfileSection> {
  late BusinessProfile _selected = widget.snapshot.profile;

  Future<void> _apply() async {
    if (_selected == widget.snapshot.profile) return;
    try {
      await ref.read(configServiceProvider).changeProfile(_selected);
      if (!mounted) return;
      AppToast.show(
        context,
        tr('تم تغيير ملف النشاط إلى {p0}', {'p0': BusinessProfileCatalog.metaFor(_selected).arabicName}),
        type: ToastType.success,
      );
    } catch (e) {
      if (mounted) {
        AppToast.show(context, '$e', type: ToastType.error);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
             _SectionHeader(
              icon: PhosphorIconsBold.briefcase,
              label: tr('تغيير ملف النشاط'),
            ),
            const SizedBox(height: 8),
             Text(
              tr('يبدّل قائمة الشاشات والـ feature flags بالكامل. أى overrides يدوية تظل سارية فوق الـ defaults الجديدة.'),
              style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<BusinessProfile>(
              initialValue: _selected,
              decoration:  InputDecoration(
                labelText: tr('ملف النشاط الجديد'),
                prefixIcon: const Icon(PhosphorIconsBold.briefcase),
                border: const OutlineInputBorder(),
              ),
              items: BusinessProfileCatalog.all()
                  .map((m) => DropdownMenuItem(
                        value: m.profile,
                        child: Text(m.arabicName),
                      ))
                  .toList(),
              onChanged: (v) => setState(() => _selected = v ?? _selected),
            ),
            const SizedBox(height: 8),
            Text(
              BusinessProfileCatalog.metaFor(_selected).arabicDescription,
              style: const TextStyle(
                fontSize: 11,
                color: AppColors.textMuted,
              ),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: ElevatedButton.icon(
                onPressed: _selected == widget.snapshot.profile
                    ? null
                    : _apply,
                icon: const Icon(PhosphorIconsBold.check),
                label:  Text(tr('تطبيق')),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Change mode ────────────────────────────────────────────────────────

class _ChangeModeSection extends ConsumerStatefulWidget {
  final RuntimeConfigSnapshot snapshot;
  const _ChangeModeSection({required this.snapshot});

  @override
  ConsumerState<_ChangeModeSection> createState() =>
      _ChangeModeSectionState();
}

class _ChangeModeSectionState extends ConsumerState<_ChangeModeSection> {
  late DeploymentMode _selected = widget.snapshot.mode;

  Future<void> _apply() async {
    if (_selected == widget.snapshot.mode) return;

    // Spec 097: flipping TO mirror requires a successful pairing handshake
    // FIRST. If the device is not paired (or its MirrorState was wiped),
    // open the pairing dialog inline. Only proceed with `changeMode` after
    // the dialog returns success. This keeps deployment_mode and
    // network_mode from drifting into a half-configured mirror state.
    if (_selected == DeploymentMode.mirror &&
        !MirrorState.instance.isConfigured) {
      final paired = await MirrorPairingDialog.show(context);
      if (!paired) {
        // Pairing cancelled or failed — revert the segmented control to
        // the current mode so the UI matches reality.
        if (mounted) {
          setState(() => _selected = widget.snapshot.mode);
        }
        return;
      }
    }

    // Spec 125 (US4 / FR-009 / FR-010): for modes that include a wipe
    // (client, mirror) require type-to-confirm. Otherwise a plain confirm.
    final needsWipe = _selected == DeploymentMode.client ||
        _selected == DeploymentMode.mirror;
    final ok = needsWipe
        ? await _showTypeToConfirmDialog(_selected)
        : await _showPlainConfirmDialog(_selected);
    if (ok != true) return;

    // Spec 125 (US4 / FR-008): route through DeploymentModeCommitter so
    // Dev Tools uses the exact same atomic pipeline as the Setup Wizard.
    // forceResync=true → re-runs first-sync (data may have drifted since
    // the last commit; the user explicitly asked to switch mode now).
    // Empty creds → committer skips pair (pairing was handled above via
    // MirrorPairingDialog when needed; or the target mode has no pair step).
    try {
      final db = ref.read(databaseProvider);
      final committer = DeploymentModeCommitter(db: db);
      final contract = committer.buildContract(
        target: _toNetworkMode(_selected),
        serverPort: NetworkService.instance.serverPort,
        serverHost: NetworkService.instance.serverAddress,
      );
      final result = await committer.commit(
        contract: contract,
        forceResync: true,
      );
      if (!mounted) return;
      if (result is CommitFailed) {
        AppToast.show(
          context,
          tr('فشل تغيير نمط التشغيل: {p0}', {'p0': result.reasonAr}),
          type: ToastType.error,
        );
        return;
      }
      // Refresh the riverpod state so the snapshot picker reflects the
      // new mode immediately. (ConfigService.changeMode also called
      // applyFromService — we replicate the minimal subset here.)
      ref.read(deploymentModeProvider.notifier).applyFromService(_selected);
      AppToast.show(
        context,
        tr('تم تغيير نمط التشغيل بنجاح — يفضّل إعادة تشغيل التطبيق'),
        type: ToastType.success,
      );
    } catch (e) {
      if (mounted) {
        AppToast.show(context, '$e', type: ToastType.error);
      }
    }
  }

  Future<bool?> _showPlainConfirmDialog(DeploymentMode target) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title:  Text(tr('تأكيد تغيير نمط التشغيل')),
        content: Text(
          tr('سيتم تحويل النظام إلى وضع "{p0}".\n\nتغيير نمط التشغيل يتطلّب إعادة تشغيل التطبيق ليأخذ تأثيره الكامل (network service / sync). هل تريد المتابعة؟', {'p0': _modeLabelAr(target)}),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child:  Text(tr('إلغاء')),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child:  Text(tr('تطبيق')),
          ),
        ],
      ),
    );
  }

  /// Spec 125 FR-010 — type-to-confirm for wipe-inducing modes (client/mirror).
  /// User must type "تأكيد" verbatim before the action button enables.
  Future<bool?> _showTypeToConfirmDialog(DeploymentMode target) {
    final controller = TextEditingController();
    final sentinel = tr('تأكيد');
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setStateD) {
          final matches = controller.text.trim() == sentinel;
          return AlertDialog(
            title:  Text(tr('تأكيد تغيير نمط التشغيل (إجراء حرج)')),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tr('سيتم تحويل النظام إلى وضع "{p0}".\n\nسيُمسح: البيانات الأساسية المحلية (الفروع، المخازن، الخزن، الحسابات).\nسيُستعاد من السيرفر: نفس البيانات بالنسخ الرسمية.\nالمدة المتوقعة: 10-30 ثانية على شبكة LAN عادية.\n\nاكتب "تأكيد" أدناه للمتابعة:', {'p0': _modeLabelAr(target)}),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: controller,
                  textDirection: TextDirection.rtl,
                  decoration:  InputDecoration(
                    border: const OutlineInputBorder(),
                    hintText: tr('تأكيد'),
                  ),
                  onChanged: (_) => setStateD(() {}),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child:  Text(tr('إلغاء')),
              ),
              ElevatedButton(
                onPressed: matches ? () => Navigator.pop(ctx, true) : null,
                child:  Text(tr('تنفيذ التحويل')),
              ),
            ],
          );
        },
      ),
    );
  }

  NetworkMode _toNetworkMode(DeploymentMode m) {
    switch (m) {
      case DeploymentMode.standalone: return NetworkMode.standalone;
      case DeploymentMode.server:     return NetworkMode.server;
      case DeploymentMode.client:     return NetworkMode.client;
      case DeploymentMode.mirror:     return NetworkMode.mirror;
    }
  }

  String _modeLabelAr(DeploymentMode m) {
    switch (m) {
      case DeploymentMode.standalone: return tr('مستقل');
      case DeploymentMode.server:     return tr('سيرفر');
      case DeploymentMode.client:     return tr('عميل');
      case DeploymentMode.mirror:     return tr('مرآة');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
             _SectionHeader(
              icon: PhosphorIconsBold.network,
              label: tr('تغيير نمط التشغيل'),
            ),
            const SizedBox(height: 12),
            SegmentedButton<DeploymentMode>(
              segments:  [
                ButtonSegment(
                  value: DeploymentMode.standalone,
                  label: Text(tr('مستقل')),
                  icon: const Icon(PhosphorIconsBold.desktop, size: 16),
                ),
                ButtonSegment(
                  value: DeploymentMode.server,
                  label: Text(tr('سيرفر')),
                  icon: const Icon(PhosphorIconsBold.hardDrives, size: 16),
                ),
                ButtonSegment(
                  value: DeploymentMode.client,
                  label: Text(tr('عميل')),
                  icon: const Icon(PhosphorIconsBold.deviceMobile, size: 16),
                ),
                ButtonSegment(
                  value: DeploymentMode.mirror,
                  label: Text(tr('مرآة')),
                  icon: const Icon(PhosphorIconsBold.copy, size: 16),
                ),
              ],
              selected: {_selected},
              onSelectionChanged: (s) =>
                  setState(() => _selected = s.first),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: ElevatedButton.icon(
                onPressed: _selected == widget.snapshot.mode ? null : _apply,
                icon: const Icon(PhosphorIconsBold.check),
                label:  Text(tr('تطبيق')),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Feature overrides ──────────────────────────────────────────────────

class _FeatureOverridesSection extends ConsumerWidget {
  const _FeatureOverridesSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final policy = ref.watch(featureFlagsProvider);
    final overrides = ref.watch(featureOverridesProvider);
    // Group keys by module, hide cores (cannot be disabled).
    final byModule = <String, List<FeatureKey>>{};
    for (final k in FeatureKey.values) {
      if (k.isCore) continue;
      byModule.putIfAbsent(k.module, () => []).add(k);
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
             _SectionHeader(
              icon: PhosphorIconsBold.toggleRight,
              label: tr('تخصيص الميزات'),
            ),
            const SizedBox(height: 8),
             Text(
              tr('كل ميزة لها قيمة افتراضية من ملف النشاط. أى توجيه يدوى هنا يحلّ محل الافتراضى. الميزات الأساسية (محاسبة / مخزون / مبيعات / خزينة) محمية ولا تظهر هنا.'),
              style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
            ),
            const SizedBox(height: 12),
            for (final entry in byModule.entries) ...[
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Text(
                  _moduleLabel(entry.key),
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
              for (final key in entry.value)
                _FeatureRow(
                  fk: key,
                  enabled: policy.flag(key),
                  hasOverride: overrides.containsKey(key),
                ),
              const Divider(),
            ],
          ],
        ),
      ),
    );
  }

  String _moduleLabel(String module) {
    switch (module) {
      case 'pos':         return tr('البيع السريع');
      case 'restaurant':  return tr('المطعم');
      case 'enterprise':  return tr('المؤسسة');
      default:            return module;
    }
  }
}

class _FeatureRow extends ConsumerWidget {
  final FeatureKey fk;
  final bool enabled;
  final bool hasOverride;
  const _FeatureRow({
    required this.fk,
    required this.enabled,
    required this.hasOverride,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  fk.name,
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                ),
                Text(
                  fk.settingKey,
                  style: const TextStyle(fontSize: 9, color: AppColors.textMuted),
                ),
              ],
            ),
          ),
          if (hasOverride)
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 6),
              child: IconButton(
                tooltip: tr('إزالة التوجيه (الرجوع للافتراضى)'),
                icon: const Icon(PhosphorIconsBold.arrowCounterClockwise, size: 16),
                onPressed: () {
                  ref.read(configServiceProvider).clearOverride(fk);
                },
              ),
            ),
          Switch(
            value: enabled,
            onChanged: (v) {
              ref.read(configServiceProvider).setOverride(fk, v);
            },
          ),
        ],
      ),
    );
  }
}

// ─── Change developer password ──────────────────────────────────────────

class _ChangeDeveloperPasswordSection extends ConsumerStatefulWidget {
  const _ChangeDeveloperPasswordSection();

  @override
  ConsumerState<_ChangeDeveloperPasswordSection> createState() =>
      _ChangeDeveloperPasswordSectionState();
}

class _ChangeDeveloperPasswordSectionState
    extends ConsumerState<_ChangeDeveloperPasswordSection> {
  final _newCtl = TextEditingController();
  final _confirmCtl = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _newCtl.dispose();
    _confirmCtl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final pwd = _newCtl.text.trim();
    final cnf = _confirmCtl.text.trim();
    if (pwd.length < 4 || pwd != cnf) {
      AppToast.show(
        context,
        pwd.length < 4
            ? tr('يجب أن لا تقل كلمة المرور عن 4 أحرف')
            : tr('تأكيد كلمة المرور غير مطابق'),
        type: ToastType.error,
      );
      return;
    }
    setState(() => _saving = true);
    try {
      await ref.read(developerAuthServiceProvider).setPassword(pwd);
      if (!mounted) return;
      _newCtl.clear();
      _confirmCtl.clear();
      AppToast.show(context, tr('تم تغيير كلمة مرور المطوّر'), type: ToastType.success);
      // Extend the active session — saves the user from re-entering the
      // (just-changed) password again.
      ref.read(developerSessionProvider.notifier).extend();
    } catch (e) {
      if (mounted) {
        AppToast.show(context, tr('فشل التغيير: {e}', {'e': e}), type: ToastType.error);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
             _SectionHeader(
              icon: PhosphorIconsBold.key,
              label: tr('تغيير كلمة مرور المطوّر'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _newCtl,
              obscureText: true,
              decoration:  InputDecoration(
                labelText: tr('كلمة مرور جديدة'),
                prefixIcon: const Icon(PhosphorIconsBold.lock),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _confirmCtl,
              obscureText: true,
              decoration:  InputDecoration(
                labelText: tr('تأكيد كلمة المرور'),
                prefixIcon: const Icon(PhosphorIconsBold.lockKey),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: ElevatedButton.icon(
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(PhosphorIconsBold.floppyDisk),
                label:  Text(tr('حفظ')),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Reset wizard ───────────────────────────────────────────────────────

class _ResetWizardSection extends ConsumerWidget {
  const _ResetWizardSection();

  Future<void> _reset(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title:  Text(tr('إعادة ضبط الإعداد')),
        content:  Text(
          tr('سيتم تشغيل الـ wizard من جديد عند بدء التطبيق التالى. البيانات (مبيعات / مشتريات / عملاء…) لا تُحذف. هل تريد المتابعة؟'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child:  Text(tr('إلغاء')),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.pop(ctx, true),
            child:  Text(tr('إعادة ضبط')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref.read(configServiceProvider).resetWizard();
      if (!context.mounted) return;
      AppToast.show(
        context,
        tr('تم إعادة الضبط — أعد تشغيل التطبيق'),
        type: ToastType.warning,
      );
    } catch (e) {
      if (context.mounted) {
        AppToast.show(context, '$e', type: ToastType.error);
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      color: AppColors.error.withValues(alpha: 0.04),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
             _SectionHeader(
              icon: PhosphorIconsBold.arrowsCounterClockwise,
              label: tr('منطقة الخطر — إعادة ضبط'),
              color: AppColors.error,
            ),
            const SizedBox(height: 8),
             Text(
              tr('يعيد تشغيل الـ setup wizard. البيانات تظل سليمة لكن إعدادات التشغيل (الملف، النمط، الميزات) ستُسأل من جديد.'),
              style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.error,
                  side: const BorderSide(color: AppColors.error),
                ),
                onPressed: () => _reset(context, ref),
                icon: const Icon(PhosphorIconsBold.arrowsCounterClockwise),
                label:  Text(tr('إعادة ضبط الإعداد')),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════
// Section header helper
// ═════════════════════════════════════════════════════════════════════════

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color? color;
  const _SectionHeader({
    required this.icon,
    required this.label,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppColors.primary;
    return Row(
      children: [
        Icon(icon, color: c, size: 20),
        const SizedBox(width: 8),
        Text(
          label,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 14,
            color: c,
          ),
        ),
      ],
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════
// تصفير البيانات — عمليات بلا رجعة
// ═════════════════════════════════════════════════════════════════════════
//
// كل زرار هنا بيحذف صفوف من قاعدة البيانات مباشرة ومفيش «إلغاء». الحمايات
// الأربعة اللي بينها المستخدم والحذف:
//   ١. القسم كله جوّه شاشة أدوات المطوّر، وهي محمية بكلمة مرور المطوّر.
//   ٢. تأكيد بالكتابة: لازم يكتب الكلمة المطلوبة حرفياً — مش زرار «موافق»
//      ينضغط بالغلط.
//   ٣. نسخة احتياطية إجبارية جوّه الخدمة، والحذف بيُلغى لو النسخة فشلت.
//   ٤. معاملة واحدة: لو الحذف وقع في نصه بيترجع كله.
//
// وترتيب الأزرار مقصود: المدمّر في الآخر، والفواتير قبل الأصناف والأطراف
// لأن دي بترفض التنفيذ لو فيه فواتير مرتبطة.
class _DataWipeSection extends ConsumerStatefulWidget {
  const _DataWipeSection();

  @override
  ConsumerState<_DataWipeSection> createState() => _DataWipeSectionState();
}

class _DataWipeSectionState extends ConsumerState<_DataWipeSection> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
             _SectionHeader(
              icon: PhosphorIconsBold.warningOctagon,
              label: tr('تصفير البيانات — بلا رجعة'),
              color: AppColors.error,
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.error.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(8),
                border:
                    Border.all(color: AppColors.error.withValues(alpha: 0.3)),
              ),
              child:  Text(
                tr('كل عملية هنا بتحذف من قاعدة البيانات مباشرة ومفيش تراجع. بتتاخد نسخة احتياطية تلقائياً قبل أي حذف، والعملية بتُلغى لو النسخة فشلت — النسخة دي هي طريق الرجوع الوحيد.\n\nالعمليات المالية بتحذف قيود اليومية وحركات المخزون المرتبطة كمان: فاتورة محذوفة وقيدها موجود معناها دفتر أستاذ مش متوازن.'),
                style: const TextStyle(fontSize: 12, height: 1.6),
              ),
            ),
            const SizedBox(height: 12),
            // ⚠️ قوائمُ الأثرِ مأخوذةٌ من توثيق `DataWipeService` نفسِه لا
            //    من التخمين — وكلُّ بندٍ هنا يقابل سطراً في تلك الدوالّ.
            _wipeTile(
              label: tr('حذف جميع فواتير المبيعات'),
              detail: tr('الفواتير وبنودها والدفعات وقيود اليومية وحركات المخزون'),
              confirmWord: tr('حذف المبيعات'),
              action: (s) => s.wipeSalesInvoices(),
              willDelete:  [
                tr('فواتير المبيعات وبنودها'),
                tr('دفعاتُها'),
                tr('قيودُ اليومية المرتبطة بها'),
                tr('حركاتُ المخزون الناتجةُ عنها'),
              ],
              willRemain:  [
                tr('الأصناف والعملاء'),
                tr('فواتير المشتريات'),
                tr('الإعدادات والمستخدمون'),
              ],
            ),
            _wipeTile(
              label: tr('حذف جميع فواتير المشتريات'),
              detail: tr('الفواتير وبنودها والتكاليف المحملة وقيودها وحركاتها'),
              confirmWord: tr('حذف المشتريات'),
              action: (s) => s.wipePurchaseInvoices(),
              willDelete:  [
                tr('فواتير المشتريات وبنودها'),
                tr('التكاليفُ المحمَّلة عليها'),
                tr('قيودُها وحركاتُها المخزنيّة'),
              ],
              willRemain:  [
                tr('الأصناف والموردون'),
                tr('فواتير المبيعات'),
                tr('الإعدادات والمستخدمون'),
              ],
            ),
            _wipeTile(
              label: tr('حذف جميع الأصناف'),
              detail: tr('الأصناف وأرصدتها وباركوداتها ووحداتها — بيُرفض لو فيه بنود فواتير مرتبطة'),
              confirmWord: tr('حذف الأصناف'),
              action: (s) => s.wipeProducts(),
              willDelete:  [
                tr('الأصناف وأرصدتُها'),
                tr('باركوداتُها ووحداتُها'),
              ],
              willRemain:  [
                tr('الفواتير — بل تُرفَض العمليةُ إن وُجدت'),
                tr('العملاء والموردون'),
                tr('الإعدادات والمستخدمون'),
              ],
            ),
            _wipeTile(
              label: tr('حذف جميع العملاء'),
              detail: tr('الطرف اللي هو عميل ومورد في نفس الوقت بتُلغى صفة العميل عنه فقط ومبيتحذفش'),
              confirmWord: tr('حذف العملاء'),
              action: (s) => s.wipeParties(customers: true),
              willDelete:  [
                tr('الأطرافُ التي هي عملاءُ فقط'),
              ],
              willRemain:  [
                tr('الطرفُ الذي هو عميلٌ ومورّدٌ معاً — تُلغى صفةُ العميل فقط'),
                tr('الفواتير والأصناف'),
                tr('الإعدادات والمستخدمون'),
              ],
            ),
            _wipeTile(
              label: tr('حذف جميع الموردين'),
              detail: tr('بنفس قاعدة الأطراف المزدوجة'),
              confirmWord: tr('حذف الموردين'),
              action: (s) => s.wipeParties(customers: false),
              willDelete:  [
                tr('الأطرافُ التي هي موردون فقط'),
              ],
              willRemain:  [
                tr('الطرفُ الذي هو عميلٌ ومورّدٌ معاً — تُلغى صفةُ المورّد فقط'),
                tr('الفواتير والأصناف'),
                tr('الإعدادات والمستخدمون'),
              ],
            ),
            _wipeTile(
              label: tr('حذف الحسابات المضافة في دليل الحسابات'),
              detail: tr('الحسابات وربطها وقوالب اليومية — بيُرفض لو فيه بنود يومية مرتبطة'),
              confirmWord: tr('حذف الحسابات'),
              action: (s) => s.wipeChartOfAccounts(),
              willDelete:  [
                tr('الحساباتُ المُضافة'),
                tr('ربطُها بالعمليات'),
                tr('قوالبُ اليومية'),
              ],
              willRemain:  [
                tr('القيود — بل تُرفَض العمليةُ إن وُجدت بنودٌ مرتبطة'),
                tr('الحساباتُ الأصليّة'),
                tr('الإعدادات والمستخدمون'),
              ],
            ),
            const Divider(height: 24),
            _wipeTile(
              label: tr('تصفير كامل لقاعدة البيانات'),
              detail: tr('كل البيانات الحركية. بيسيب الإعدادات والمستخدمين والصلاحيات والفروع والمستودعات وتعريفات الصناديق — تركيب بلا مستخدمين مش مصفّر، ده تركيب مكسور'),
              confirmWord: tr('تصفير كامل'),
              action: (s) => s.wipeAllTransactionalData(),
              extraDanger: true,
              willDelete:  [
                tr('كلُّ الفواتير — مبيعاتٍ ومشترياتٍ ومرتجعات'),
                tr('حركاتُ المخزون والجرد'),
                tr('القيودُ المحاسبيّةُ وأرصدةُ العملاء والموردين'),
                tr('حركةُ الخزائن وسنداتُ القبض والصرف'),
                tr('سجلُّ العمليات والورديات'),
              ],
              willRemain:  [
                tr('الإعداداتُ كلُّها'),
                tr('المستخدمون والأدوارُ والصلاحيات'),
                tr('الفروعُ والمستودعاتُ وتعريفاتُ الصناديق'),
                tr('الأصنافُ والعملاءُ والموردون'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _wipeTile({
    required String label,
    required String detail,
    required String confirmWord,
    required Future<WipeResult> Function(DataWipeService) action,
    List<String> willDelete = const [],
    List<String> willRemain = const [],
    bool extraDanger = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: OutlinedButton(
        onPressed: _busy
            ? null
            : () => _confirmAndRun(
                  label,
                  confirmWord,
                  action,
                  willDelete: willDelete,
                  willRemain: willRemain,
                ),
        style: OutlinedButton.styleFrom(
          alignment: AlignmentDirectional.centerStart,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          side: BorderSide(
            color: AppColors.error.withValues(alpha: extraDanger ? 0.9 : 0.4),
            width: extraDanger ? 2 : 1,
          ),
          foregroundColor: AppColors.error,
        ),
        child: Row(
          children: [
            Icon(
              extraDanger
                  ? PhosphorIconsBold.skull
                  : PhosphorIconsBold.trash,
              size: 18,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 2),
                  Text(detail,
                      style: const TextStyle(
                          fontSize: 11,
                          height: 1.4,
                          color: AppColors.textMuted)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// تأكيدٌ بالكتابة ثمّ تنفيذ.
  ///
  /// ⚠️ **الحوارُ موحَّدٌ الآن** (`showPicPosDangerConfirm`) بعد أن كان
  /// `AlertDialog` محلّيّاً هنا: نفسُ حاجزِ الكلمة، ومعه قائمتا الأثر —
  /// «سيُحذف» و«سيبقى كما هو». وأكثرُ التردّد أمامَ زرِّ التصفير سببُه
  /// الجهلُ بما **يبقى** لا بما يُحذف.
  ///
  /// والقوائمُ تأتي من المستدعي لأنها تختلف لكلِّ عملية، ونصُّها مأخوذٌ من
  /// توثيق `DataWipeService` نفسِه لا من التخمين.
  Future<void> _confirmAndRun(
    String label,
    String confirmWord,
    Future<WipeResult> Function(DataWipeService) action, {
    List<String> willDelete = const [],
    List<String> willRemain = const [],
  }) async {
    final confirmed = await showPicPosDangerConfirm(
      context,
      icon: PhosphorIconsBold.warningOctagon,
      title: label,
      message: tr('العمليةُ بلا رجعة. تُؤخَذ نسخةٌ احتياطيّةٌ تلقائيّاً قبل التنفيذ، وفشلُها يوقف العملية.'),
      actionLabel: tr('نفّذ'),
      typedWord: confirmWord,
      willDelete: willDelete,
      willRemain: willRemain,
    );
    if (!confirmed || !mounted) return;

    setState(() => _busy = true);
    final result = await action(DataWipeService(ref.read(databaseProvider)));
    if (!mounted) return;
    setState(() => _busy = false);

    await showDialog<void>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: Row(
            children: [
              Icon(
                result.ok
                    ? PhosphorIconsBold.checkCircle
                    : PhosphorIconsBold.xCircle,
                color: result.ok ? AppColors.success : AppColors.error,
                size: 22,
              ),
              const SizedBox(width: 8),
              Text(result.ok ? tr('تم التنفيذ') : tr('لم يتم التنفيذ')),
            ],
          ),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: result.ok
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(tr('إجمالي الصفوف المحذوفة: {p0}', {'p0': result.totalRows}),
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 13)),
                        const Divider(),
                        // العدّ لكل جدول: «تم» لوحدها متقولش إيه اللي حصل،
                        // والمستخدم محتاج يعرف قبل ما يكمّل شغل.
                        for (final e in result.deleted.entries)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 1),
                            child: Row(
                              children: [
                                Expanded(
                                    child: Text(e.key,
                                        style: const TextStyle(fontSize: 12))),
                                Text('${e.value}',
                                    style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold)),
                              ],
                            ),
                          ),
                        if (result.backupPath != null) ...[
                          const Divider(),
                          Text(tr('النسخة الاحتياطية: {p0}', {'p0': result.backupPath}),
                              style: const TextStyle(
                                  fontSize: 11, color: AppColors.textMuted)),
                        ],
                      ],
                    )
                  : Text(result.error ?? tr('خطأ غير معروف'),
                      style: const TextStyle(fontSize: 13, height: 1.6)),
            ),
          ),
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx),
              child:  Text(tr('حسناً')),
            ),
          ],
        ),
      ),
    );
  }
}
