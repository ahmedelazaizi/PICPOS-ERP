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
        ],
      ),
    );
  }
}
