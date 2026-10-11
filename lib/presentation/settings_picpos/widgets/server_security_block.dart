import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:ural_erp/core/i18n/tr.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../data/providers/providers.dart';
import '../../../services/api/server_secrets.dart';
import '../../../services/api/table_bill_legacy_acceptance.dart';
import '../../../services/network_service.dart';
import '../../picpos_shell/picpos_dialog.dart';
import 'settings_blocks.dart';

/// إجراءان أمنيّان للمدير على الخادم المحلّي. يُعزَلان خلف هذا الصنف كي
/// تُحقَن بدائلُ في الاختبار دون فتح قاعدةٍ أو مخزنِ أسرارٍ حقيقيّ.
class ServerSecurityActions {
  const ServerSecurityActions({
    required this.rotateSessionSecret,
    required this.isLegacyAccepted,
    required this.disableLegacy,
    required this.audit,
  });

  /// يدوّر سرَّ الجلسات (يُبطل كلَّ الجلسات دفعةً واحدة).
  final Future<void> Function() rotateSessionSecret;

  /// هل رموزُ الطاولات المطبوعة القديمة ما زالت مقبولة؟
  final Future<bool> Function() isLegacyAccepted;

  /// يوقف قبولَ الرموز القديمة.
  final Future<void> Function() disableLegacy;

  /// يكتب حدثاً في سجلّ النشاط. لا يرمي أبداً.
  final Future<void> Function(String action, String description) audit;
}

final serverSecurityActionsProvider = Provider<ServerSecurityActions>((ref) {
  return ServerSecurityActions(
    rotateSessionSecret: () async {
      final secrets = NetworkService.instance.serverSecrets;
      if (secrets == null) {
        throw const ServerSecretsUnavailableException(
            'server secrets are not loaded (server not running)');
      }
      await secrets.rotate(ServerSecretKind.session);
    },
    isLegacyAccepted: () =>
        TableBillLegacyAcceptance.isEnabled(ref.read(databaseProvider)),
    disableLegacy: () =>
        TableBillLegacyAcceptance.disable(ref.read(databaseProvider)),
    audit: (action, description) async {
      try {
        final user = ref.read(authProvider).user;
        await ref.read(activityLoggerProvider).log(
              userId: user?.id,
              userName: user?.displayName ?? '',
              action: action,
              entityType: 'security',
              description: description,
            );
      } catch (_) {
        // السجلُّ المحلّيّ لا يُفشل إجراءً أمنيّاً نُفِّذ فعلاً.
      }
    },
  );
});

/// بلوك «أمان الخادم» في قسم الأجهزة المرتبطة. للمدير وحده — القسمُ نفسُه
/// يحجب غيرَه قبل بلوغ هذا البلوك.
class ServerSecurityBlock extends ConsumerStatefulWidget {
  const ServerSecurityBlock({super.key});

  @override
  ConsumerState<ServerSecurityBlock> createState() =>
      _ServerSecurityBlockState();
}

class _ServerSecurityBlockState extends ConsumerState<ServerSecurityBlock> {
  late Future<bool> _legacy = _loadLegacy();
  bool _busy = false;

  ServerSecurityActions get _actions => ref.read(serverSecurityActionsProvider);

  String _reason(Object e) =>
      e is ServerSecretsUnavailableException ? e.reason : '$e';

  Future<bool> _loadLegacy() async {
    try {
      return await _actions.isLegacyAccepted();
    } catch (_) {
      return true; // الافتراضيُّ في الخادم: مقبولة.
    }
  }

  Future<void> _rotate() async {
    if (_busy) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => const _RotateConfirmDialog(),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await _actions.rotateSessionSecret();
      await _actions.audit(
        'rotate_server_secrets',
        tr('تدوير مفاتيح الخادم: أُبطلت كل جلسات الأجهزة والويب'),
      );
      if (mounted) {
        AppToast.show(context, tr('تم تدوير مفاتيح الخادم — أُبطلت الجلسات'));
      }
    } catch (e) {
      await _actions.audit(
        'rotate_server_secrets_failed',
        tr('فشل تدوير مفاتيح الخادم'),
      );
      if (mounted) {
        AppToast.show(context, tr('تعذّر تدوير مفاتيح الخادم: {e}', {'e': _reason(e)}),
            type: ToastType.error);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _disableLegacy() async {
    if (_busy) return;
    final ok = await showPicPosConfirm(
      context,
      icon: PhosphorIconsBold.qrCode,
      title: tr('إيقاف قبول رموز الطاولات القديمة'),
      message: tr(
        'ستتوقف رموز QR المطبوعة القديمة عن العمل فوراً، ولن تفتح حساب أي طاولة. تأكد أنك طبعت الرموز الجديدة ولصقتها قبل المتابعة.',
      ),
      confirmLabel: tr('أوقف الرموز القديمة'),
      danger: true,
    );
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    try {
      await _actions.disableLegacy();
      await _actions.audit(
        'disable_legacy_table_qr',
        tr('أُوقف قبول رموز QR القديمة للطاولات'),
      );
      if (mounted) {
        AppToast.show(context, tr('أُوقف قبول الرموز القديمة'));
        setState(() => _legacy = Future.value(false));
      }
    } catch (e) {
      if (mounted) {
        AppToast.show(context, tr('تعذّر إيقاف الرموز القديمة: {e}', {'e': _reason(e)}),
            type: ToastType.error);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => SettingsBlock(
    key: const Key('ld_server_security'),
    title: tr('أمان الخادم'),
    subtitle: tr('إجراءات للمدير: تدوير المفاتيح ورموز الطاولات'),
    tint: AppColors.error,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingsDangerRow(
          key: const Key('ld_rotate_row'),
          icon: PhosphorIconsBold.arrowsClockwise,
          title: tr('تدوير مفاتيح الخادم'),
          sub: tr('يُبطل كل جلسات الأجهزة والويب مرة واحدة؛ تعيد الأجهزة المقترنة جلساتها تلقائياً'),
          actionLabel: tr('تدوير المفاتيح'),
          onPressed: _busy ? () {} : _rotate,
        ),
        FutureBuilder<bool>(
          future: _legacy,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const SizedBox(height: 56);
            }
            final accepted = snap.data ?? true;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SettingsRowsBody(children: [
                  SettingsValueRow(
                    key: const Key('ld_legacy_status'),
                    first: true,
                    icon: PhosphorIconsBold.qrCode,
                    title: tr('رموز QR المطبوعة القديمة للطاولات'),
                    sub: tr('الرموز المطبوعة بالمفتاح القديم قبل إعادة الطباعة'),
                    value: accepted ? tr('مقبولة') : tr('موقوفة'),
                    tint: accepted ? AppColors.warning : AppColors.success,
                  ),
                ]),
                if (accepted)
                  SettingsDangerRow(
                    key: const Key('ld_legacy_row'),
                    icon: PhosphorIconsBold.qrCode,
                    title: tr('أعدتُ طباعة رموز QR للطاولات'),
                    sub: tr('أوقف قبول الرموز القديمة — ستتوقف الرموز المطبوعة سابقاً'),
                    actionLabel: tr('أوقف الرموز القديمة'),
                    onPressed: _busy ? () {} : _disableLegacy,
                  ),
              ],
            );
          },
        ),
      ],
    ),
  );
}

/// تأكيدٌ مزدوج: يلزم كتابةُ كلمة التأكيد قبل أن يُفعَّل الزرّ.
class _RotateConfirmDialog extends StatefulWidget {
  const _RotateConfirmDialog();

  @override
  State<_RotateConfirmDialog> createState() => _RotateConfirmDialogState();
}

class _RotateConfirmDialogState extends State<_RotateConfirmDialog> {
  final _controller = TextEditingController();
  late final String _word = tr('تدوير');

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _matches => _controller.text.trim() == _word;

  @override
  Widget build(BuildContext context) => PicPosDialog(
    icon: PhosphorIconsBold.arrowsClockwise,
    accent: AppColors.error,
    title: tr('تدوير مفاتيح الخادم'),
    width: 520,
    onCancel: () => Navigator.pop(context, false),
    primaryAction: PicPosDialogAction(
      label: tr('تدوير المفاتيح'),
      color: AppColors.error,
      onPressed: _matches ? () => Navigator.pop(context, true) : null,
    ),
    body: [
      Text(
        tr('تحذير: سيُبطل هذا كل جلسات الأجهزة والويب مرة واحدة. تعيد الأجهزة المقترنة جلساتها تلقائياً، أما جلسات الويب والمستخدمون المتصلون فسيُطلب منهم تسجيل الدخول من جديد.'),
        style: const TextStyle(
            fontSize: 13, fontWeight: FontWeight.w600, height: 1.6),
      ),
      TextField(
        key: const Key('ld_rotate_confirm_field'),
        controller: _controller,
        autofocus: true,
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(
          labelText: tr('اكتب «{word}» للتأكيد', {'word': _word}),
        ),
      ),
    ],
  );
}
