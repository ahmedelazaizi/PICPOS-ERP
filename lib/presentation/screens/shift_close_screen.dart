import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/permissions/permission_codes.dart';
import '../../core/theme/app_colors.dart';
import '../../data/providers/providers.dart';
import '../../services/client_write_interceptor.dart';
import '../pos/providers/pos_closing_controller.dart';
import '../pos/widgets/pos_cashier_closing_dialog.dart';
import '../pos/widgets/pos_opening_balance_dialog.dart';
import '../widgets/permission_guard.dart';
import 'reports/shifts_report_screen.dart';

/// Task 10A — shared-engine, brand-neutral base screen for
/// `ScreenId.shiftClose` / `AppScreen.shiftClose`.
///
/// Lets the current user open or close their own cash-drawer shift, and
/// deep-links to the existing shift history report. Every piece of business
/// logic here is reused as-is from the existing (UralCash-origin) shift
/// lifecycle — this screen adds no new provider, query, or write path:
///
/// - Shift status comes from [posClosingControllerProvider] /
///   [PosClosingState] — the same state the cashier-closing dialog already
///   computes (`resolvedShiftId`, `error == 'no_open_shift'`).
/// - "Close shift" shows the existing [PosCashierClosingDialog] unmodified.
/// - "Open shift" calls `treasuryRepositoryProvider.openShift(...)` plus the
///   `ClientWriteInterceptor.openShift(...)` server mirror — mirroring
///   `_enforceShiftForCashier` in `app_main_screen.dart`.
/// - "View all shifts" pushes the existing [ShiftsReportScreen] — the
///   `getShiftsReportPaginated` query is NOT duplicated here.
///
/// This screen is intentionally plain/neutral (no PicPos shell, no brand
/// conditional of any kind) so it stays cleanly patchable to UralCash.
/// A PicPos-identity fork of this screen is a separate task.
/// كل الورديات المفتوحة على الفرع — القسم اللي بيعوّض الإغلاق الإجباري.
///
/// ── ليه موجود ────────────────────────────────────────────────────────────
/// إلغاء بوابة الإغلاق الإجباري شال الآلية اللي كانت بتضمن إن مفيش وردية
/// تتساب بلا ترصيد. بدل ما نمنع الكاشير، المسؤولية بقت على المشرف: اللي عنده
/// `pos_shift_close` بيشوف الورديات المتروكة ويقفلها.
///
/// ── ليه زرار الإغلاق بيتعطّل على ورديات الغير ────────────────────────────
/// `PosClosingController` بيحلّ الوردية المستهدفة حسب `isOriginallyAdmin`:
/// اللي مش مدير أصلي بيقفل **ورديته هو** مهما كانت الوردية اللي ضغط عليها.
/// فتفعيل الزرار على وردية غيره كان هيقفل الوردية الغلط بصمت — وده بالظبط
/// النوع اللي سبق٠١٣٦ اتكتب عشانه. التعطيل مع سبب مكتوب أأمن.
///
/// دالة عليا `@visibleForTesting` عشان تتبني لوحدها: الشاشة بتقرا
/// `posClosingControllerProvider` اللي بيحسب تعداد الوردية المالي من قاعدة
/// بيانات حقيقية.
@visibleForTesting
Widget buildOpenShiftsSection({
  required List<ShiftData> shifts,
  required Map<int, String> userNames,
  required int? currentUserId,
  required bool canCloseOthers,
  required void Function(ShiftData) onClose,
}) {
  if (shifts.isEmpty) {
    return const Card(
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(PhosphorIconsBold.checkCircle, color: AppColors.success),
            SizedBox(width: 12),
            Expanded(child: Text('لا توجد ورديات مفتوحة على الفرع')),
          ],
        ),
      ),
    );
  }

  return Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (final shift in shifts)
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'وردية #${shift.id} — ${userNames[shift.userId] ?? 'مستخدم #${shift.userId}'}',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'فُتحت: ${_formatShiftStart(shift.startTime)}'
                        ' · رصيد افتتاحي: ${shift.openingBalance.toStringAsFixed(2)}',
                        style: const TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 12,
                        ),
                      ),
                      if (!canCloseOthers && shift.userId != currentUserId)
                        const Padding(
                          padding: EdgeInsets.only(top: 4),
                          child: Text(
                            'إغلاق وردية كاشير تاني متاح لمدير النظام فقط',
                            style: TextStyle(
                              color: AppColors.warning,
                              fontSize: 11,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                PermissionGuard(
                  permission: PermissionCodes.posShiftClose,
                  allowManagerOverride: true,
                  actionName: 'إغلاق وردية #${shift.id}',
                  // صريحة: الحارس بيمسك الضغطة، ولو ما عرفش يشغّل إيه بعد
                  // الموافقة بيفكّ القفل وبس (f8d3fa9).
                  onGranted: () => onClose(shift),
                  child: ElevatedButton.icon(
                    onPressed: (canCloseOthers || shift.userId == currentUserId)
                        ? () => onClose(shift)
                        : null,
                    icon: const Icon(PhosphorIconsBold.lockKey, size: 16),
                    label: const Text('إغلاق الوردية'),
                  ),
                ),
              ],
            ),
          ),
        ),
    ],
  );
}

String _formatShiftStart(DateTime t) {
  String two(int v) => v.toString().padLeft(2, '0');
  return '${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}';
}

class ShiftCloseScreen extends ConsumerStatefulWidget {
  const ShiftCloseScreen({super.key});

  @override
  ConsumerState<ShiftCloseScreen> createState() => _ShiftCloseScreenState();
}

class _ShiftCloseScreenState extends ConsumerState<ShiftCloseScreen> {
  bool _isOpeningShift = false;

  Future<void> _openShift() async {
    final authState = ref.read(authProvider);
    final userId = authState.user?.id;
    if (userId == null) return;

    final userName =
        authState.user?.displayName ?? authState.user?.username ?? 'كاشير';

    // Same dialog `_enforceShiftForCashier` shows at login — reused as-is.
    final opening = await showDialog<double>(
      context: context,
      barrierDismissible: false,
      builder: (_) => PosOpeningBalanceDialog(userName: userName),
    );
    if (opening == null || !mounted) return; // cancelled

    setState(() => _isOpeningShift = true);
    try {
      int? scopedBranchId;
      try {
        final scope = await ref.read(branchScopeProvider.future);
        scopedBranchId = scope.primaryBranchId;
      } catch (_) {
        // Non-fatal — openShift falls back gracefully without a branch id.
      }

      final treasuryRepo = ref.read(treasuryRepositoryProvider);
      await treasuryRepo.openShift(userId, opening, branchId: scopedBranchId);

      // Mirror to server (fire-and-forget — queues if offline), forwarding
      // the freshly-inserted local shift's id/globalId — same pattern as
      // `_enforceShiftForCashier` in app_main_screen.dart.
      try {
        final active = await treasuryRepo.getCurrentOpenShift(userId);
        unawaited(
          ClientWriteInterceptor.openShift(
            userId,
            opening,
            localShiftId: active?.id,
            branchId: scopedBranchId,
            globalId: active?.globalId,
          ),
        );
      } catch (_) {
        // Non-fatal — the local open already succeeded.
      }

      ref.invalidate(posClosingControllerProvider);
    } finally {
      if (mounted) setState(() => _isOpeningShift = false);
    }
  }

  void _viewAllShifts() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ShiftsReportScreen()),
    );
  }

  /// الورديات المفتوحة على فرع الجهاز. `branchId` بـ`null` بترجّع كل الفروع —
  /// نفس التدرّج اللي `PosClosingController` بيستعمله لما فرع الجهاز ما
  /// يتحلّش (سبق١٣٦): فرع الجهاز الأول، وبعدين الكل، عشان فرع متحلّ غلط
  /// ما يخفيش وردية متروكة.
  Future<List<ShiftData>> _loadOpenShifts() async {
    final treasuryRepo = ref.read(treasuryRepositoryProvider);
    int? terminalBranchId;
    try {
      terminalBranchId =
          (await ref.read(branchRepositoryProvider).getActiveBranch())?.id;
    } catch (_) {
      // Non-fatal — نكمّل على كل الفروع.
    }
    var shifts =
        await treasuryRepo.getOpenShiftsForBranch(branchId: terminalBranchId);
    if (shifts.isEmpty && terminalBranchId != null) {
      shifts = await treasuryRepo.getOpenShiftsForBranch(branchId: null);
    }
    return shifts;
  }

  /// بيفتح ديالوج الإغلاق الموجود — **مفيش منطق إغلاق تاني هنا**. نسخة تانية
  /// من حساب التعداد المالي بتبطّل تطابق أول تعديل.
  ///
  /// لما يبقى فيه أكتر من وردية مفتوحة، الديالوج نفسه بيعرض منتقي الورديات
  /// (`needsShiftSelection`) واللي بيقفل بيختار منه. القسم فوق هو وسيلة
  /// **الاكتشاف**؛ الديالوج فاضل هو صاحب القرار في أي وردية بتتقفل — عن قصد،
  /// عشان قواعد الحلّ بتاعت سبق١٣٦ تفضل في مكان واحد.
  Future<void> _closeShiftFromList(ShiftData shift) async {
    await PosCashierClosingDialog.show(context);
    if (mounted) setState(() {}); // إعادة تحميل القايمة بعد الإغلاق
  }

  @override
  Widget build(BuildContext context) {
    final closingState = ref.watch(posClosingControllerProvider);

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: const Text('إغلاق الوردية')),
        body: PermissionGuard(
          permission: PermissionCodes.posShiftClose,
          allowManagerOverride: true,
          actionName: 'إغلاق الوردية',
          child: _buildBody(closingState),
        ),
      ),
    );
  }

  Widget _buildBody(PosClosingState state) {
    if (state.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    final noOpenShift = state.error == 'no_open_shift';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(
                    noOpenShift
                        ? PhosphorIconsBold.warningCircle
                        : PhosphorIconsBold.checkCircle,
                    color: noOpenShift ? AppColors.warning : AppColors.success,
                    size: 32,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          noOpenShift ? 'لا توجد وردية مفتوحة' : 'يوجد وردية مفتوحة حالياً',
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                        if (!noOpenShift && state.resolvedShiftId != null)
                          Text(
                            'رقم الوردية: #${state.resolvedShiftId}',
                            style: const TextStyle(color: AppColors.textMuted, fontSize: 13),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          if (noOpenShift)
            ElevatedButton.icon(
              onPressed: _isOpeningShift ? null : _openShift,
              icon: _isOpeningShift
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(PhosphorIconsBold.cashRegister),
              label: const Text('فتح وردية'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
            )
          else
            ElevatedButton.icon(
              onPressed: () => PosCashierClosingDialog.show(context),
              icon: const Icon(PhosphorIconsBold.signOut),
              label: const Text('إغلاق الوردية'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.error,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _viewAllShifts,
            icon: const Icon(PhosphorIconsBold.listBullets),
            label: const Text('عرض كل الورديات'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
          ),
          const SizedBox(height: 24),

          // ─── الورديات المفتوحة على الفرع ───────────────────────────────
          // القسم ده بيعوّض بوابة الإغلاق الإجباري اللي اتلغت: الوردية بقت
          // تفضل مفتوحة عند الخروج والتبديل، فلازم يبقى فيه مكان واحد
          // بيوريها لمين مسؤول عن ترصيدها.
          const Row(
            children: [
              Icon(PhosphorIconsBold.users, color: AppColors.primary),
              SizedBox(width: 8),
              Text(
                'الورديات المفتوحة على الفرع',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 8),
          FutureBuilder<List<ShiftData>>(
            future: _loadOpenShifts(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              if (snapshot.hasError) {
                return Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text('تعذّر تحميل الورديات: ${snapshot.error}'),
                  ),
                );
              }

              final authState = ref.watch(authProvider);
              final users = ref.watch(allUsersProvider).value ?? const [];
              return buildOpenShiftsSection(
                shifts: snapshot.data ?? const [],
                userNames: {
                  for (final u in users)
  // ignore: dead_code
                    u.user.id: u.user.displayName ?? u.user.username,
                },
                currentUserId: authState.user?.id,
                canCloseOthers: authState.isOriginallyAdmin,
                onClose: _closeShiftFromList,
              );
            },
          ),
        ],
      ),
    );
  }
}
