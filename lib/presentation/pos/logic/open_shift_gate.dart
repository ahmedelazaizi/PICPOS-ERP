import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/theme/app_colors.dart';
import '../../../data/providers/providers.dart';

/// Outcome of [ensureShiftClosed].
enum ShiftGateResult {
  /// No open shift to begin with — the caller may proceed.
  clear,

  /// There WAS an open shift and it has now been settled. The caller may
  /// proceed **if** it asked the closing dialog not to end the session.
  ///
  /// ── ليه حالة منفصلة عن [blocked] ─────────────────────────────────────────
  /// قبل كده كانت البوابة بترجع `blocked` في الحالتين — «المستخدم ألغى» و«قفل
  /// بنجاح» — وده كان مقبول وقت ما كان ليها مستدعي واحد (تسجيل الخروج)، لأن
  /// ديالوج الإغلاق بيسجّل الخروج بنفسه فمكانش فيه فرق عملي.
  ///
  /// لكن مسار «تحويل المستخدم» **محتاج** يكمّل بعد الإغلاق الناجح، وبالحالة
  /// الواحدة كان بيقف — فديالوج التبديل عمره ما فتح، والكاشير كان بيلاقي نفسه
  /// على شاشة تسجيل الدخول. الفرق بين الحالتين هو الإصلاح.
  closed,

  /// The user has an open shift and it is STILL open — they cancelled. No
  /// caller may proceed.
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

  if (closeNow != true || !context.mounted) return ShiftGateResult.blocked;

  await showClosingDialog(context);

  // ── ليه بنسأل قاعدة البيانات تاني بدل ما نصدّق الديالوج ────────────────────
  // `showClosingDialog` نوعها `Future<void>` — مابترجعش نجاح أو فشل، والكاشير
  // ممكن يقفل الديالوج بلا ما يقفل الوردية، أو الإغلاق نفسه يرمي. فالمصدر
  // الوحيد الموثوق هو الوردية نفسها: لو بقت مقفولة يبقى قُفلت.
  //
  // ودي كمان بتخلّي البوابة تفضل صح لو أي ديالوج إغلاق (PicPos أو UralCash أو
  // أي واحد جاي) غيّر سلوكه الداخلي.
  try {
    final stillOpen =
        await ref.read(treasuryRepositoryProvider).getCurrentOpenShift(userId);
    return stillOpen == null
        ? ShiftGateResult.closed
        : ShiftGateResult.blocked;
  } catch (_) {
    // مقدرناش نتأكد → نفترض الأسوأ. `blocked` بتوقف المستدعي، وده الفشل الآمن:
    // وردية مفتوحة بتفضل مفتوحة أحسن من تحويل مستخدم فوق وردية لسه شغّالة.
    return ShiftGateResult.blocked;
  }
}
