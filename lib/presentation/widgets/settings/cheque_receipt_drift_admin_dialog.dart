// Spec 133 — Cheque Receipt Voucher: Single Customer Credit (FR-011 UI surface).
//
// Server-mode-only admin maintenance dialog that displays which customers
// have historical drift from the double-credit bug observed on build
// 3.1.0+202 and earlier. Read-only — no repair button. Repair is deferred
// to a follow-on spec.
//
// Modeled on branch_scope_admin_dialog.dart (Spec 084c). Opened from
// settings_screen.dart's "أدوات صيانة المسؤول" section.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/permissions/permission_codes.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../data/providers/providers.dart';
import '../../../services/cheque_receipt_drift_audit_service.dart';
import '../../../services/cheque_receipt_drift_repair_service.dart';

void showChequeReceiptDriftAdminDialog(BuildContext context) {
  showDialog(
    context: context,
    builder: (_) => const _ChequeReceiptDriftAdminDialog(),
  );
}

class _ChequeReceiptDriftAdminDialog extends ConsumerStatefulWidget {
  const _ChequeReceiptDriftAdminDialog();

  @override
  ConsumerState<_ChequeReceiptDriftAdminDialog> createState() =>
      _ChequeReceiptDriftAdminDialogState();
}

class _ChequeReceiptDriftAdminDialogState
    extends ConsumerState<_ChequeReceiptDriftAdminDialog> {
  List<ChequeReceiptDriftRecord>? _records;
  bool _loading = true;
  String? _error;

  // R2 / §IV — the double-submission guard MUST be an instance field, declared
  // OUTSIDE any StatefulBuilder, so it survives rebuilds.
  bool _repairing = false;
  ChequeDriftRepairResult? _lastResult;

  @override
  void initState() {
    super.initState();
    _runAudit();
  }

  Future<void> _runAudit() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final service =
          ChequeReceiptDriftAuditService(ref.read(databaseProvider));
      final breakdown = await service.getBreakdown();
      if (!mounted) return;
      setState(() {
        _records = breakdown;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _confirmAndRepair() async {
    // R1 defense-in-depth — the button is already hidden for non-admins; re-check
    // here so the action can never run without the accounting-management
    // permission even if reached another way.
    if (!_canRunRepair()) {
      AppToast.show(context, 'ليس لديك صلاحية تنفيذ هذا الإصلاح.',
          type: ToastType.error);
      return;
    }

    final records = _records ?? const <ChequeReceiptDriftRecord>[];
    final totalCustomers = records.length;
    final totalOverCredit =
        records.fold<double>(0, (sum, r) => sum + r.overCreditTotal);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Row(
            children: [
              Icon(PhosphorIconsBold.warning, color: AppColors.warning),
              SizedBox(width: 8),
              Text('تأكيد تطبيق الإصلاح'),
            ],
          ),
          content: Text(
            'سيتم تصحيح رصيد $totalCustomers عميل بإجمالي '
            '${totalOverCredit.toStringAsFixed(AppConstants.decimalPlaces)} '
            '${AppConstants.currencySymbolEn} عبر قيد تسوية متوازن.\n\n'
            'لا يتم تعديل أرصدة الخزائن أو حركاتها.\n'
            'يُطبَّق هذا الإصلاح مرة واحدة فقط لكل جهاز.\n\n'
            'تأكد من وجود نسخة احتياطية حديثة قبل المتابعة.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.warning,
                foregroundColor: Colors.white,
              ),
              child: const Text('تأكيد الإصلاح'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true) return;

    setState(() => _repairing = true);
    try {
      final adminId = ref.read(authProvider).user?.id ?? 0;
      final result = await ChequeReceiptDriftRepairService(
        ref.read(databaseProvider),
      ).repair(changedBy: adminId);
      if (!mounted) return;
      _lastResult = result;
      // Refresh the breakdown so the operator sees the post-repair state.
      await _runAudit();
      if (!mounted) return;
      AppToast.show(context, _resultMessage(result),
          type: result.outcome == ChequeDriftRepairOutcome.failed
              ? ToastType.error
              : ToastType.success);
    } catch (e) {
      if (mounted) {
        AppToast.show(context, 'فشل الإصلاح: $e', type: ToastType.error);
      }
    } finally {
      if (mounted) setState(() => _repairing = false);
    }
  }

  String _resultMessage(ChequeDriftRepairResult r) {
    switch (r.outcome) {
      case ChequeDriftRepairOutcome.healed:
        return 'تم تصحيح ${r.healedCount} عميل بإجمالي '
            '${r.totalHealed.toStringAsFixed(AppConstants.decimalPlaces)} '
            '${AppConstants.currencySymbolEn}.';
      case ChequeDriftRepairOutcome.noop:
        return 'لا يوجد ازدواج لإصلاحه — لم يتم تعديل أي بيانات.';
      case ChequeDriftRepairOutcome.skipped:
        if (r.reason == ChequeDriftRepairReason.alreadyApplied) {
          return 'تم تطبيق الإصلاح مسبقاً على هذا الجهاز.';
        }
        if (r.reason == ChequeDriftRepairReason.notServer) {
          return 'الإصلاح يعمل على جهاز السيرفر فقط — تصل الأجهزة الأخرى '
              'للحالة المصححة عبر المزامنة.';
        }
        return 'تم تخطي الإصلاح.';
      case ChequeDriftRepairOutcome.failed:
        if (r.reason == ChequeDriftRepairReason.missingCorrectionAccount) {
          return kChequeDriftMissingCorrectionAccountMessage;
        }
        return 'فشل الإصلاح.';
    }
  }

  Widget _repairSummaryBanner(ChequeDriftRepairResult r) {
    final ok = r.outcome != ChequeDriftRepairOutcome.failed;
    final color = ok ? AppColors.success : AppColors.error;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        border: Border.all(color: color.withValues(alpha: 0.3)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(ok ? PhosphorIconsBold.checkCircle : PhosphorIconsBold.xCircle,
              color: color, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _resultMessage(r),
              style: TextStyle(fontSize: 12, color: color),
            ),
          ),
        ],
      ),
    );
  }

  /// R1 (Spec 138) — the repair is a live financial mutation, so gate the
  /// ACTION behind the accounting-management permission (the read-only audit
  /// stays viewable to any server user). System-admin bypasses non-critical
  /// permissions, matching `PermissionGuard._checkPermission`.
  bool _canRunRepair() {
    final perms =
        ref.watch(currentUserPermissionsProvider).asData?.value ??
            const <String>[];
    final isSystemAdmin =
        perms.contains('system_admin') || perms.contains('*');
    return isSystemAdmin || perms.contains(PermissionCodes.accountingManage);
  }

  @override
  Widget build(BuildContext context) {
    final records = _records ?? const <ChequeReceiptDriftRecord>[];
    final totalCustomers = records.length;
    final totalOverCredit =
        records.fold<double>(0, (sum, r) => sum + r.overCreditTotal);
    final canRepair = _canRunRepair();

    return Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        title: const Row(
          children: [
            Icon(PhosphorIconsBold.magnifyingGlass,
                color: AppColors.warning),
            SizedBox(width: 8),
            Text('تدقيق ازدواج شيكات القبض'),
          ],
        ),
        content: SizedBox(
          width: 600,
          height: 480,
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? Center(
                      child: Text(
                        'فشل التدقيق: $_error',
                        style: const TextStyle(color: AppColors.error),
                      ),
                    )
                  : _buildContent(totalCustomers, totalOverCredit, records),
        ),
        actions: [
          TextButton(
            onPressed: (_loading || _repairing) ? null : _runAudit,
            child: const Text('إعادة الفحص'),
          ),
          // R1 — the repair action is hidden for users without the
          // accounting-management permission; the read-only audit above stays
          // fully visible to them.
          if (canRepair)
            ElevatedButton.icon(
              icon: _repairing
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(PhosphorIconsBold.wrench, size: 16),
              label: const Text('تطبيق الإصلاح'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.warning,
                foregroundColor: Colors.white,
              ),
              onPressed: (_loading || _repairing || totalCustomers == 0)
                  ? null
                  : _confirmAndRepair,
            ),
          TextButton(
            onPressed: _repairing ? null : () => Navigator.of(context).pop(),
            child: const Text('إغلاق'),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(
    int totalCustomers,
    double totalOverCredit,
    List<ChequeReceiptDriftRecord> records,
  ) {
    if (records.isEmpty) {
      return const Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(PhosphorIconsBold.checkCircle,
              size: 48, color: AppColors.success),
          SizedBox(height: 12),
          Text(
            'لا يوجد ازدواج في سجلات شيكات القبض.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14),
          ),
          SizedBox(height: 4),
          Text(
            'كل سندات قبض الشيكات تم تسجيلها بقيد واحد لكل شيك.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.warning.withValues(alpha: 0.08),
            border:
                Border.all(color: AppColors.warning.withValues(alpha: 0.3)),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _Stat(
                label: 'عملاء متأثرون',
                value: totalCustomers.toString(),
              ),
              _Stat(
                label: 'إجمالي مبلغ الازدواج',
                value:
                    '${totalOverCredit.toStringAsFixed(AppConstants.decimalPlaces)} ${AppConstants.currencySymbolEn}',
                color: AppColors.error,
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        const Text(
          'اضغط "تطبيق الإصلاح" لتصحيح أرصدة العملاء المتأثرين بقيد تسوية '
          'متوازن (لا يتم المساس بأرصدة الخزائن). يُطبَّق مرة واحدة فقط لكل جهاز.',
          style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
        ),
        if (_lastResult != null) ...[
          const SizedBox(height: 8),
          _repairSummaryBanner(_lastResult!),
        ],
        const SizedBox(height: 12),
        Expanded(
          child: SingleChildScrollView(
            child: DataTable(
              columnSpacing: 16,
              columns: const [
                DataColumn(label: Text('العميل')),
                DataColumn(
                    label: Text('عدد الشيكات'), numeric: true),
                DataColumn(
                    label: Text('مبلغ الازدواج'), numeric: true),
              ],
              rows: records
                  .map((r) => DataRow(cells: [
                        DataCell(Text(r.partyName)),
                        DataCell(Text(r.chequeCount.toString())),
                        DataCell(Text(
                          '${r.overCreditTotal.toStringAsFixed(AppConstants.decimalPlaces)} ${AppConstants.currencySymbolEn}',
                          style:
                              const TextStyle(color: AppColors.error),
                        )),
                      ]))
                  .toList(growable: false),
            ),
          ),
        ),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, this.color});

  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(
                fontSize: 11, color: AppColors.textSecondary)),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }
}
