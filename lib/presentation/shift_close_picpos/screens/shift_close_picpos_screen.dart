import 'package:picpos_erp/core/i18n/tr.dart';
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
import '../../screens/reports/shifts_report_screen.dart';
import '../../widgets/permission_guard.dart';
import '../widgets/picpos_cashier_closing_dialog.dart';
import '../widgets/picpos_opening_balance_dialog.dart';
import '../widgets/picpos_past_shifts_panel.dart';

// منطق منسوخ من shift_close_screen.dart (Task 10A) — أي إصلاح منطقي
// يتصلّح في المصدر أولاً ثم patch (مصيدة النسخ §٥.٨).
//
// الشاشة الأصل (lib/presentation/screens/shift_close_screen.dart) شاشة أساس
// محايدة بلا هوية علامة، ٢١٣ سطر. الـ State (_ShiftCloseScreenState) بما فيه
// `_openShift` كاملاً (treasuryRepo.openShift + ClientWriteInterceptor.openShift
// + branchScopeProvider + mirror fire-and-forget) و`_viewAllShifts` وبنية
// `_buildBody` — كل ده منسوخ هنا حرفياً بلا أي تعديل منطقي. يتغيّر بس اسم
// الكلاس وطبقة العرض (تستخدم picpos_shell بدل Scaffold+AppBar)، والديالوجين
// اللي يفتحهم `_openShift`/زر الإغلاق: هنا `PicposOpeningBalanceDialog` (فورك
// بهوية PicPos من Task 10B) بدل `PosOpeningBalanceDialog`، و
// `PicposCashierClosingDialog` (فورك بهوية PicPos من Task 10C) بدل
// `PosCashierClosingDialog`.
//
// `posClosingControllerProvider`/`PosClosingState`،
// `treasuryRepositoryProvider.openShift/getCurrentOpenShift`،
// `ClientWriteInterceptor.openShift`، `ShiftsReportScreen`،
// `PermissionCodes.posShiftClose`، `branchScopeProvider` و`authProvider`
// مُعاد استخدامهم من UralCash زي ما هم (import، مش نسخ).
class ShiftClosePicposScreen extends ConsumerStatefulWidget {
  const ShiftClosePicposScreen({super.key});

  @override
  ConsumerState<ShiftClosePicposScreen> createState() =>
      _ShiftClosePicposScreenState();
}

class _ShiftClosePicposScreenState extends ConsumerState<ShiftClosePicposScreen>
    with SingleTickerProviderStateMixin {
  bool _isOpeningShift = false;
  late final TabController _tabController =
      TabController(length: 2, vsync: this);

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _openShift() async {
    final authState = ref.read(authProvider);
    final userId = authState.user?.id;
    if (userId == null) return;

    final userName =
        authState.user?.displayName ?? authState.user?.username ?? tr('كاشير');

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
      title: tr('إغلاق الوردية'),
      subtitle: tr('فتح وإغلاق ورديات الكاشير'),
      icon: PhosphorIconsBold.lockKey,
      body: PermissionGuard(
        permission: PermissionCodes.posShiftClose,
        allowManagerOverride: true,
        actionName: tr('إغلاق الوردية'),
        child: Column(
          children: [
            TabBar(
              controller: _tabController,
              tabs:  [
                Tab(text: tr('الوردية الحالية')),
                Tab(text: tr('ورديات سابقة')),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildBody(closingState),
                  // Reachable without an open shift — reviewing or reprinting
                  // yesterday's close is exactly what you do before opening
                  // today's.
                  const SingleChildScrollView(
                    child: PicposPastShiftsPanel(),
                  ),
                ],
              ),
            ),
          ],
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
                            ? tr('لا توجد وردية مفتوحة')
                            : tr('يوجد وردية مفتوحة حالياً'),
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (!noOpenShift && state.resolvedShiftId != null)
                        Text(
                          tr('رقم الوردية: #{p0}', {'p0': state.resolvedShiftId}),
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
              label:  Text(tr('فتح وردية')),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
            )
          else
            ElevatedButton.icon(
              onPressed: () => PicposCashierClosingDialog.show(context),
              icon: const Icon(PhosphorIconsBold.signOut),
              label:  Text(tr('إغلاق الوردية')),
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
            label:  Text(tr('عرض كل الورديات')),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
          ),
        ],
      ),
    );
  }
}
