import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:picpos_erp/core/i18n/tr.dart';

import '../../../core/utils/app_error_handler.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../services/cloud_sync/cloud_link_controller.dart';
import '../../picpos_shell/picpos_dialog.dart';

/// SEC-017 — "rotate signing key": generates a new Ed25519 seed on this
/// desktop, registers the new public key with the cloud and revokes EVERY
/// paired admin phone (they must re-pair and pin the new key). Use after a
/// suspected compromise of the desktop's key store.
class AdminKeyRotationButton extends StatelessWidget {
  const AdminKeyRotationButton({super.key, required this.controller, this.onDone});

  final CloudLinkController controller;
  final VoidCallback? onDone;

  Future<void> _run(BuildContext context) async {
    final confirmed = await showPicPosConfirm(
      context,
      icon: PhosphorIconsBold.arrowsClockwise,
      title: tr('تدوير مفتاح التوقيع'),
      message: tr('سيُنشأ مفتاح توقيع جديد وتُلغى كل هواتف الإدارة المقترنة؛ يلزم ربطها من جديد.'),
      confirmLabel: tr('تدوير وإلغاء الكل'),
      danger: true,
    );
    if (!confirmed || !context.mounted) return;
    try {
      final revoked = await controller.rotateAdminSigningKey();
      if (context.mounted) {
        AppToast.show(context, tr('تم تدوير المفتاح. أُلغي {n} هاتف.', {'n': revoked}));
      }
      onDone?.call();
    } catch (error, stack) {
      if (context.mounted) AppErrorHandler.handle(context, error, stack);
    }
  }

  @override
  Widget build(BuildContext context) => TextButton(
        key: const Key('ld_admin_rotate_key'),
        onPressed: () => _run(context),
        child: Text(tr('تدوير مفتاح التوقيع')),
      );
}
