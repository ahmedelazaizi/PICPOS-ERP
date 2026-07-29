import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/theme/app_colors.dart';
import '../../../data/providers/providers.dart';

/// Outcome of [ensureShiftClosed].
enum ShiftGateResult {
  /// No open shift — the caller may proceed.
  clear,

  /// The user has an open shift. The caller MUST NOT proceed; either the
  /// closing dialog was shown or the user backed out.
  blocked,
}

/// Forced shift close before leaving the session — logging out OR switching
/// to another user.
///
/// A shift left open is a shift whose transactions never get reconciled, so
/// this gate has no override, not even for a system admin. Admins don't open
/// a shift of their own (Spec 135), but if one exists because they acted
/// operationally, it still has to be settled — hence the check runs for
/// everyone.
///
/// Extracted so the logout path and the POS switch-user path share ONE
/// implementation. A second copy is exactly the kind of thing that silently
/// stops matching after the next change to either.
Future<ShiftGateResult> ensureShiftClosed({
  required BuildContext context,
  required WidgetRef ref,
  /// Shown to the user to explain WHY the shift must be closed now. The two
  /// callers phrase it differently ("قبل تسجيل الخروج" / "قبل تحويل المستخدم").
  required String reason,

  /// Brand-appropriate closing dialog. PicPos and UralCash have forked
  /// dialogs, so the caller supplies its own rather than this gate importing
  /// one and dragging a brand dependency into shared code.
  required Future<void> Function(BuildContext context) showClosingDialog,
}) async {
  final userId = ref.read(authProvider).user?.id;
  if (userId == null) return ShiftGateResult.clear;

  final openShift =
      await ref.read(treasuryRepositoryProvider).getCurrentOpenShift(userId);
  if (openShift == null) return ShiftGateResult.clear;
  if (!context.mounted) return ShiftGateResult.blocked;

  final closeNow = await showDialog<bool>(
    context: context,
    builder: (ctx) => Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        title: const Row(
          children: [
            Icon(PhosphorIconsBold.warningCircle, color: AppColors.warning),
            SizedBox(width: 8),
            Text('وردية مفتوحة'),
          ],
        ),
        content: Text(
          'لديك وردية مفتوحة (#${openShift.id}) لم يتم ترصيدها. '
          'يجب إغلاق الوردية $reason حتى لا تبقى معاملاتها دون ترصيد.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(PhosphorIconsBold.signOut),
            label: const Text('إغلاق الوردية'),
          ),
        ],
      ),
    ),
  );

  if (closeNow == true && context.mounted) {
    await showClosingDialog(context);
  }
  // Blocked either way: if the user cancelled, the shift is still open; if
  // they closed it, the closing dialog owns what happens next.
  return ShiftGateResult.blocked;
}
