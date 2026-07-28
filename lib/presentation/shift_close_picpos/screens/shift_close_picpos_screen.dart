import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/permissions/permission_codes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/providers/providers.dart';
import '../../../services/client_write_interceptor.dart';
import '../../picpos_shell/picpos_content_card.dart';
import '../../picpos_shell/picpos_screen_scaffold.dart';
import '../../pos/providers/pos_closing_controller.dart';
import '../../pos/widgets/pos_cashier_closing_dialog.dart';
import '../../screens/reports/shifts_report_screen.dart';
import '../../widgets/permission_guard.dart';
import '../widgets/picpos_opening_balance_dialog.dart';

// منطق منسوخ من shift_close_screen.dart (Task 10A) — أي إصلاح منطقي
// يتصلّح في المصدر أولاً ثم patch (مصيدة النسخ §٥.٨).
//
// الشاشة الأصل (lib/presentation/screens/shift_close_screen.dart) شاشة أساس
// محايدة بلا هوية علامة، ٢١٣ سطر. الـ State (_ShiftCloseScreenState) بما فيه
// `_openShift` كاملاً (treasuryRepo.openShift + ClientWriteInterceptor.openShift
// + branchScopeProvider + mirror fire-and-forget) و`_viewAllShifts` وبنية
// `_buildBody` — كل ده منسوخ هنا حرفياً بلا أي تعديل منطقي. يتغيّر بس اسم
// الكلاس وطبقة العرض (تستخدم picpos_shell بدل Scaffold+AppBar)، والديالوج
// اللي يفتحه `_openShift`: هنا `PicposOpeningBalanceDialog` (فورك بهوية PicPos
// من Task 10B) بدل `PosOpeningBalanceDialog`. زر الإغلاق لسه يستدعي
// `PosCashierClosingDialog.show` الموجود كما هو (10C يبدّله للمعاد تصميمه).
//
// `posClosingControllerProvider`/`PosClosingState`،
// `treasuryRepositoryProvider.openShift/getCurrentOpenShift`،
// `ClientWriteInterceptor.openShift`، `PosCashierClosingDialog.show`،
// `ShiftsReportScreen`، `PermissionCodes.posShiftClose`، `branchScopeProvider`
// و`authProvider` مُعاد استخدامهم من UralCash زي ما هم (import، مش نسخ).
class ShiftClosePicposScreen extends ConsumerStatefulWidget {
  const ShiftClosePicposScreen({super.key});

  @override
  ConsumerState<ShiftClosePicposScreen> createState() =>
      _ShiftClosePicposScreenState();
}

class _ShiftClosePicposScreenState
    extends ConsumerState<ShiftClosePicposScreen> {
  bool _isOpeningShift = false;

  Future<void> _openShift() async {
    final authState = ref.read(authProvider);
    final userId = authState.user?.id;
    if (userId == null) return;

    final userName =
        authState.user?.displayName ?? authState.user?.username ?? 'كاشير';

    // Same dialog `_enforceShiftForCashier` shows at login — reused as-is
    // (PicPos-skinned fork of it).
    final opening = await showDialog<double>(
      context: context,
      barrierDismissible: false,
      builder: (_) => PicposOpeningBalanceDialog(userName: userName),
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

  @override
  Widget build(BuildContext context) {
    final closingState = ref.watch(posClosingControllerProvider);

    return PicPosScreenScaffold(
      title: 'إغلاق الوردية',
      subtitle: 'فتح وإغلاق ورديات الكاشير',
      icon: PhosphorIconsBold.lockKey,
      body: PermissionGuard(
        permission: PermissionCodes.posShiftClose,
        allowManagerOverride: true,
        actionName: 'إغلاق الوردية',
        child: _buildBody(closingState),
      ),
    );
  }

  Widget _buildBody(PosClosingState state) {
    if (state.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    final noOpenShift = state.error == 'no_open_shift';

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PicPosContentCard(
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
                        noOpenShift
                            ? 'لا توجد وردية مفتوحة'
                            : 'يوجد وردية مفتوحة حالياً',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (!noOpenShift && state.resolvedShiftId != null)
                        Text(
                          'رقم الوردية: #${state.resolvedShiftId}',
                          style: const TextStyle(
                            color: AppColors.textMuted,
                            fontSize: 13,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
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
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
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
        ],
      ),
    );
  }
}
