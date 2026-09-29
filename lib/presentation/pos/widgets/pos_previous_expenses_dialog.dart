import 'package:ural_erp/core/i18n/tr.dart';
// ignore_for_file: avoid_dynamic_calls
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/providers/providers.dart';
import '../../../services/client_write_interceptor.dart';
import '../../../services/generators/thermal_receipt_generator.dart';
import '../providers/pos_notification_provider.dart';
import 'pos_expense_dialog.dart';

/// Dialog for viewing and managing previous expenses from the POS
class PosPreviousExpensesDialog extends ConsumerStatefulWidget {
  const PosPreviousExpensesDialog({super.key});

  /// Static helper to show the dialog
  static Future<void> show(BuildContext context) async {
    return showDialog<void>(
      context: context,
      builder: (context) => const PosPreviousExpensesDialog(),
    );
  }

  @override
  ConsumerState<PosPreviousExpensesDialog> createState() =>
      _PosPreviousExpensesDialogState();
}

class _PosPreviousExpensesDialogState
    extends ConsumerState<PosPreviousExpensesDialog> {
  bool _canManageExpenses = false;
  bool _isLoading = true;
  Future<List<TransactionData>>? _expensesFuture;
  // Spec 136 ISS-25 — start of the active open shift; expenses are scoped to
  // this window instead of calendar midnight so a shift crossing midnight
  // keeps its earlier expenses.
  DateTime? _shiftStartTime;

  @override
  void initState() {
    super.initState();
    _checkPermissions();
  }

  Future<void> _checkPermissions() async {
    final authRepo = ref.read(authRepositoryProvider);
    final authState = ref.read(authProvider);
    final currentUserId = authState.user?.id;

    if (currentUserId != null) {
      _canManageExpenses = await authRepo.userHasPermission(
        currentUserId,
        'pos_expense_delete',
      );
      // Spec 136 ISS-25 — load the open shift's start so _fetchExpenses scopes
      // to the shift window rather than calendar midnight.
      final treasuryRepo = ref.read(treasuryRepositoryProvider);
      final shift = await treasuryRepo.getCurrentOpenShift(currentUserId);
      _shiftStartTime = shift?.startTime;
    }

    if (mounted) {
      setState(() {
        _isLoading = false;
      });
      _refreshExpenses();
    }
  }

  void _refreshExpenses() {
    final treasuryRepo = ref.read(treasuryRepositoryProvider);
    final authState = ref.read(authProvider);
    final currentUserId = authState.user?.id;
    final filterUserId = _canManageExpenses ? null : currentUserId;
    setState(() {
      _expensesFuture = _fetchExpenses(treasuryRepo, filterUserId);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        title: Row(
          children: [
            const Icon(
              PhosphorIconsBold.clockCounterClockwise,
              color: AppColors.info,
            ),
            const SizedBox(width: 8),
             Text(tr('المصروفات السابقة')),
            const Spacer(),
            // Refresh button
            IconButton(
              onPressed: _refreshExpenses,
              icon: const Icon(PhosphorIconsBold.arrowsClockwise, size: 18),
              tooltip: tr('تحديث'),
            ),
            if (!_canManageExpenses)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.info.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child:  Text(
                  tr('مصروفاتي'),
                  style: const TextStyle(fontSize: 10, color: AppColors.info),
                ),
              ),
          ],
        ),
        content: SizedBox(
          width: 500,
          height: 400,
          child: FutureBuilder<List<TransactionData>>(
            future: _expensesFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              final vouchers = snapshot.data ?? [];

              if (vouchers.isEmpty) {
                return  Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        PhosphorIconsBold.money,
                        size: 48,
                        color: AppColors.textMuted,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        tr('لا توجد مصروفات اليوم'),
                        style: const TextStyle(color: AppColors.textMuted),
                      ),
                    ],
                  ),
                );
              }

              return ListView.builder(
                itemCount: vouchers.length,
                itemBuilder: (context, index) {
                  final voucher = vouchers[index];
                  return Card(
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: AppColors.error.withValues(alpha: 0.1),
                        child: Text(
                          '${index + 1}',
                          style: const TextStyle(color: AppColors.error),
                        ),
                      ),
                      title: Text(tr('{p0} د.أ', {'p0': voucher.amount.toStringAsFixed(AppConstants.decimalPlaces)})),
                      subtitle: Text(
                        voucher.description ?? voucher.category,
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(
                              PhosphorIconsBold.printer,
                              color: AppColors.info,
                            ),
                            tooltip: tr('طباعة'),
                            onPressed: () => _printExpenseReceipt(voucher),
                          ),
                          if (_canManageExpenses)
                            IconButton(
                              icon: const Icon(
                                PhosphorIconsBold.trash,
                                color: AppColors.error,
                                size: 20,
                              ),
                              tooltip: tr('حذف'),
                              onPressed: () => _deleteExpense(voucher),
                            ),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
        actions: [
          ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(context);
              PosExpenseDialog.show(context);
            },
            icon: const Icon(PhosphorIconsBold.plus, size: 18),
            label:  Text(tr('إضافة مصروف')),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child:  Text(tr('إغلاق')),
          ),
        ],
      ),
    );
  }

  Future<List<TransactionData>> _fetchExpenses(ITreasuryRepository treasuryRepo, int? userId) async {
    // Spec 136 ISS-25 — scope to the open shift window; fall back to calendar
    // midnight when no shift is open.
    final start = _shiftStartTime ??
        DateTime.now()
            .copyWith(hour: 0, minute: 0, second: 0, millisecond: 0, microsecond: 0);
    final transactions = await treasuryRepo.getTransactionsByDateRange(
      start,
      DateTime.now(),
      userId: userId,
    );
    return transactions
        .where(
          (t) =>
              t.transactionType == 'payment' &&
              t.category != 'payment_adjustment',
        )
        .toList();
  }

  Future<void> _printExpenseReceipt(dynamic voucher) async {
    showPosToast(
      context,
      ref,
      tr('جاري طباعة سند مصروف بقيمة {p0} د.أ', {'p0': voucher.amount.toStringAsFixed(AppConstants.decimalPlaces)}),
      type: PosNotificationType.info,
    );
    try {
      final settingsRepo = ref.read(settingsRepositoryProvider);
      final settings = await settingsRepo.getReceiptSettings();
      await ThermalReceiptGenerator.printVoucher(
        voucherNumber: 'EXP-${voucher.id}',
        voucherType: tr('صرف'),
        amount: (voucher.amount as num).toDouble(),
        date: voucher.createdAt,
        companyName: settings['companyName'] as String?,
        companyPhone: settings['companyPhone'] as String?,
        companyAddress: settings['companyAddress'] as String?,
        description: voucher.description ?? voucher.category ?? tr('مصروف'),
        employeeName: voucher.userName,
        printersRepo: ref.read(printersRepositoryProvider),
      );
    } catch (e) {
      if (mounted) {
        showPosToast(
          context,
          ref,
          tr('خطأ في الطباعة: {e}', {'e': e}),
          type: PosNotificationType.error,
        );
      }
    }
  }

  Future<void> _deleteExpense(dynamic voucher) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (c) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title:  Text(tr('تأكيد حذف المصروف')),
          content: Text(
            'هل أنت متأكد من حذف سند مصروف ${voucher.amount.toStringAsFixed(AppConstants.decimalPlaces)} د.أ؟\n'
            'سيتم إرجاع المبلغ للخزنة.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child:  Text(tr('إلغاء')),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(c, true),
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
              child:  Text(tr('حذف')),
            ),
          ],
        ),
      ),
    );

    if (confirm == true) {
      final treasuryRepo = ref.read(treasuryRepositoryProvider);
      final authState = ref.read(authProvider);
      try {
        // Fire-and-forget server delete (interceptor queues offline).
        // ALWAYS delete locally too — the interceptor returns `true` for
        // both "server succeeded" and "queued for retry", so gating the
        // local delete on its return value left the row in the local DB
        // whenever the write was merely queued. Dialog reads only local
        // rows, so the user saw the success toast but the entry stayed.
        ClientWriteInterceptor.deleteExpense(voucher.id).catchError((e) {
          debugPrint('[PosPreviousExpenses] background server delete failed: $e');
          return false;
        });
        await treasuryRepo.deleteExpenseTransaction(voucher.id);
        final activityLogRepo = ref.read(activityLogRepositoryProvider);
        await activityLogRepo.logActivity(
          userId: authState.user?.id,
          userName: authState.user?.displayName ?? tr('مستخدم'),
          action: 'delete_expense',
          entityType: 'expense',
          entityId: voucher.id,
          description: tr('حذف سند مصروف {p0}', {'p0': voucher.amount.toStringAsFixed(AppConstants.decimalPlaces)}),
        );
        setState(() {}); // Refresh list
        _refreshExpenses();
        if (mounted) {
          showPosToast(
            context,
            ref,
            tr('تم حذف المصروف بنجاح'),
            type: PosNotificationType.success,
          );
        }
      } catch (e) {
        if (mounted) {
          showPosToast(
            context,
            ref,
            tr('خطأ في الحذف: {e}', {'e': e}),
            type: PosNotificationType.error,
          );
        }
      }
    }
  }
}