// ignore_for_file: avoid_dynamic_calls
part of 'branch_management_screen.dart';

// ═══════════════════════════════════════════════════════════════════════════
// BRANCH MANAGEMENT — Dialogs & Action Handlers
// Extracted from branch_management_screen.dart for maintainability (PIR Phase 2)
// ═══════════════════════════════════════════════════════════════════════════

/// Mixin providing all dialog and CRUD action methods for
/// [_BranchManagementScreenState].
mixin _BranchManagementDialogsMixin on State<BranchManagementScreen> {
  // ── Required accessors from main state ──
  WidgetRef get screenRef;
  void refreshAuxData();

  // ─────────────────────────────────────────────────────────────────────
  // ADD DIALOGS
  // ─────────────────────────────────────────────────────────────────────

  void showAddBranchDialog() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => const BranchEditDialog(),
    );
    if (result == true && mounted) {
      AppToast.show(context, tr('تم إضافة الفرع بنجاح'), type: ToastType.success);
    }
  }

  void showAddWarehouseDialog() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => const WarehouseEditDialog(),
    );
    if (result == true && mounted) {
      AppToast.show(context, tr('تم إضافة المخزن بنجاح'), type: ToastType.success);
    }
  }

  // ─────────────────────────────────────────────────────────────────────
  // ACTION DIALOGS
  // ─────────────────────────────────────────────────────────────────────

  void showBranchActionsDialog(dynamic branch) {
    showDialog(
      context: context,
      builder: (dialogCtx) => Directionality(
        textDirection: ui.TextDirection.rtl,
        child: SimpleDialog(
          title: Text(branch.name, style: const TextStyle(fontWeight: FontWeight.bold)),
          children: [
            SimpleDialogOption(
              onPressed: () { Navigator.pop(dialogCtx); handleBranchAction('edit', branch); },
              child:  Row(children: [
                const Icon(PhosphorIconsBold.pencil, color: AppColors.primary, size: 20),
                const SizedBox(width: 12),
                Text(tr('تعديل')),
              ]),
            ),
            SimpleDialogOption(
              onPressed: () { Navigator.pop(dialogCtx); handleBranchAction('warehouses', branch); },
              child:  Row(children: [
                const Icon(PhosphorIconsBold.warehouse, color: Colors.teal, size: 20),
                const SizedBox(width: 12),
                Text(tr('المخازن')),
              ]),
            ),
            SimpleDialogOption(
              onPressed: () { Navigator.pop(dialogCtx); handleBranchAction('stats', branch); },
              child:  Row(children: [
                const Icon(PhosphorIconsBold.chartBar, color: Colors.blue, size: 20),
                const SizedBox(width: 12),
                Text(tr('إحصائيات')),
              ]),
            ),
            SimpleDialogOption(
              onPressed: () { Navigator.pop(dialogCtx); handleBranchAction('delete', branch); },
              child:  Row(children: [
                const Icon(PhosphorIconsBold.trash, color: AppColors.error, size: 20),
                const SizedBox(width: 12),
                Text(tr('حذف'), style: const TextStyle(color: AppColors.error)),
              ]),
            ),
          ],
        ),
      ),
    );
  }

  void showWarehouseActionsDialog(dynamic warehouse) {
    showDialog(
      context: context,
      builder: (dialogCtx) => Directionality(
        textDirection: ui.TextDirection.rtl,
        child: SimpleDialog(
          title: Text(warehouse.name, style: const TextStyle(fontWeight: FontWeight.bold)),
          children: [
            SimpleDialogOption(
              onPressed: () { Navigator.pop(dialogCtx); handleWarehouseAction('edit', warehouse); },
              child:  Row(children: [
                const Icon(PhosphorIconsBold.pencil, color: AppColors.primary, size: 20),
                const SizedBox(width: 12),
                Text(tr('تعديل')),
              ]),
            ),
            SimpleDialogOption(
              onPressed: () { Navigator.pop(dialogCtx); handleWarehouseAction(warehouse.isDefault ? 'undefault' : 'default', warehouse); },
              child: Row(children: [
                Icon(warehouse.isDefault ? PhosphorIconsBold.starHalf : PhosphorIconsBold.star, color: Colors.amber, size: 20),
                const SizedBox(width: 12),
                Text(warehouse.isDefault ? tr('إلغاء الافتراضي') : tr('تعيين كافتراضي')),
              ]),
            ),
            SimpleDialogOption(
              onPressed: () { Navigator.pop(dialogCtx); handleWarehouseAction('delete', warehouse); },
              child:  Row(children: [
                const Icon(PhosphorIconsBold.trash, color: AppColors.error, size: 20),
                const SizedBox(width: 12),
                Text(tr('حذف'), style: const TextStyle(color: AppColors.error)),
              ]),
            ),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────
  // ACTION HANDLERS
  // ─────────────────────────────────────────────────────────────────────

  TabController get tabController;

  void handleBranchAction(String action, dynamic branch) async {
  // ignore: unused_local_variable
    final branchRepo = screenRef.read(branchRepositoryProvider);

    switch (action) {
      case 'edit':
        _showEditBranchDialog(branch);
        break;
      case 'warehouses':
        tabController.animateTo(1);
        break;
      case 'stats':
        _showBranchStats(branch);
        break;
      case 'delete':
        // Feature 049 (v131) — pre-flight count of user_branch_access
        // rows. If zero → simple confirm. If > 0 → bulk-reassign dialog.
        // The pre-v131 path went straight to the DAO's HARD DELETE which
        // hit FK 23503 every time the branch had ANY user assignment
        // (field repro 2026-05-13 14:04 trying to dedup "الفرع الرئيسي").
        await _showBranchDeleteDialog(branch);
        break;
    }
  }

  // Feature 049 (v131) — branch-delete dialog with bulk-reassign for
  // user_branch_access. Mirrors the Feature 045 categories dialog.
  Future<void> _showBranchDeleteDialog(dynamic branch) async {
    final branchRepo = screenRef.read(branchRepositoryProvider);

    int userCount;
    try {
      userCount = await branchRepo.countUsersWithBranchAccess(branch.id as int);
    } catch (e) {
      if (mounted) {
        AppToast.show(context, tr('تعذّر قراءة عدد المستخدمين: {e}', {'e': e}),
            type: ToastType.error);
      }
      return;
    }
    if (!mounted) return;

    if (userCount == 0) {
      // No user assignments to reassign — regular confirm.
      final confirmed = await AppConfirmDialog.show(
        context,
        title: tr('تأكيد الحذف'),
        message: tr('هل تريد حذف الفرع "{p0}"؟', {'p0': branch.name}),
        confirmLabel: tr('حذف'),
        isDangerous: true,
      );
      if (confirmed != true || !mounted) return;
      await _runBranchDelete(branch, reassignTo: null);
      return;
    }

    // Has user assignments → bulk-reassign dialog.
    final allBranches = await branchRepo.getAllBranches();
    if (!mounted) return;
    final candidates = allBranches
        .where((b) => b.id != branch.id && b.isActive)
        .toList();
    if (candidates.isEmpty) {
      AppToast.show(context,
          tr('لا يوجد فرع آخر نشط لنقل المستخدمين إليه. أضف فرعاً آخر أولاً.'),
          type: ToastType.error);
      return;
    }

    int? selectedDestId = candidates.first.id;
    bool isDeleting = false;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => Directionality(
          textDirection: ui.TextDirection.rtl,
          child: AlertDialog(
            title: Row(
              children: [
                const Icon(PhosphorIconsBold.warning, color: AppColors.error),
                const SizedBox(width: 8),
                Expanded(child: Text(tr('حذف فرع "{p0}"', {'p0': branch.name}))),
              ],
            ),
            content: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.warning.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        const Icon(PhosphorIconsBold.warning,
                            color: AppColors.warning, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            tr('هذا الفرع مرتبط بـ {userCount} مستخدم.', {'userCount': userCount}),
                            style: const TextStyle(
                                fontSize: 13, color: AppColors.warning),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                   Text(tr('انقل المستخدمين إلى:'),
                      style: const TextStyle(fontSize: 13)),
                  const SizedBox(height: 6),
                  DropdownButtonFormField<int>(
                    initialValue: selectedDestId,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                    ),
                    items: candidates
                        .map((b) => DropdownMenuItem<int>(
                              value: b.id,
                              child: Text(b.name),
                            ))
                        .toList(),
                    onChanged: isDeleting
                        ? null
                        : (v) => setDialogState(() => selectedDestId = v),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    tr('بعد النقل سيتم حذف فرع "{p0}" بشكل آمن (soft-delete: تاريخ الفرع وسجلاته يبقى محفوظاً).', {'p0': branch.name}),
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: isDeleting ? null : () => Navigator.pop(ctx),
                child:  Text(tr('إلغاء')),
              ),
              ElevatedButton.icon(
                icon: const Icon(PhosphorIconsBold.arrowRight, size: 16),
                style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.error),
                onPressed: isDeleting
                    ? null
                    : () async {
                        setDialogState(() => isDeleting = true);
                        Navigator.pop(ctx);
                        await _runBranchDelete(branch,
                            reassignTo: selectedDestId);
                      },
                label: isDeleting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    :  Text(tr('نقل وحذف')),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _runBranchDelete(dynamic branch, {int? reassignTo}) async {
    final branchRepo = screenRef.read(branchRepositoryProvider);
    try {
      await branchRepo.deleteBranch(branch.id as int,
          reassignUsersToBranchId: reassignTo);
      _logActivity('delete_branch', 'branch', branch.id as int,
          tr('حذف فرع: {p0}{p1}', {'p0': branch.name, 'p1': reassignTo != null ? ' (نُقل المستخدمون إلى فرع #$reassignTo)' : ''}));
      if (mounted) {
        AppToast.show(context, tr('تم حذف الفرع'), type: ToastType.warning);
      }
    } catch (e) {
      if (mounted) {
        AppToast.show(
            context, e.toString().replaceAll('Exception: ', ''),
            type: ToastType.error);
      }
    }
  }

  void handleWarehouseAction(String action, dynamic warehouse) async {
    final branchRepo = screenRef.read(branchRepositoryProvider);

    switch (action) {
      case 'edit':
        _showEditWarehouseDialog(warehouse);
        break;
      case 'default':
        try {
          final intercepted = await ClientWriteInterceptor.setDefaultWarehouse(warehouse.id);
          if (!intercepted) {
            await branchRepo.setDefaultWarehouse(warehouse.id);
          }
          if (mounted) AppToast.show(context, tr('تم تعيين المخزن كافتراضي'), type: ToastType.success);
        } catch (e) {
          if (mounted) {
            AppToast.show(context, tr('خطأ: {p0}', {'p0': e.toString().replaceAll('Exception: ', '')}), type: ToastType.error);
          }
        }
        break;
      case 'undefault':
        try {
          final intercepted = await ClientWriteInterceptor.unsetDefaultWarehouse(warehouse.id);
          if (!intercepted) {
            await branchRepo.unsetDefaultWarehouse(warehouse.id);
          }
          if (mounted) AppToast.show(context, tr('تم إلغاء المخزن الافتراضي'), type: ToastType.success);
        } catch (e) {
          if (mounted) {
            AppToast.show(context, tr('خطأ: {p0}', {'p0': e.toString().replaceAll('Exception: ', '')}), type: ToastType.error);
          }
        }
        break;
      case 'delete':
        final confirmed = await AppConfirmDialog.show(
          context,
          title: tr('تأكيد الحذف'),
          message: tr('هل تريد حذف المخزن "{p0}"؟', {'p0': warehouse.name}),
          confirmLabel: tr('حذف'),
          isDangerous: true,
        );
        if (confirmed == true) {
          try {
            final intercepted = await ClientWriteInterceptor.deleteWarehouse(warehouse.id);
            if (!intercepted) {
              await branchRepo.deleteWarehouse(warehouse.id);
            }
            _logActivity('delete_warehouse', 'warehouse', warehouse.id, tr('حذف مخزن: {p0}', {'p0': warehouse.name}));
            if (mounted) {
              AppToast.show(context, tr('تم حذف المخزن'), type: ToastType.warning);
            }
          } catch (e) {
            if (mounted) {
              AppToast.show(context, e.toString().replaceAll('Exception: ', ''), type: ToastType.error);
            }
          }
        }
        break;
    }
  }

  // ─────────────────────────────────────────────────────────────────────
  // STATS
  // ─────────────────────────────────────────────────────────────────────

  void _showBranchStats(dynamic branch) async {
    final branchRepo = screenRef.read(branchRepositoryProvider);
    final stats = await branchRepo.getBranchSalesSummary(branch.id);
    final inventoryValue = await branchRepo.getBranchInventoryValue(branch.id);

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr('إحصائيات: {p0}', {'p0': branch.name})),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildStatRow(tr('إجمالي المبيعات'), '${stats.totalSales.toStringAsFixed(AppConstants.decimalPlaces)} ${AppConstants.currencySymbolEn}'),
            _buildStatRow(tr('عدد الفواتير'), stats.invoiceCount.toString()),
            _buildStatRow(tr('متوسط الفاتورة'), '${stats.averageInvoiceValue.toStringAsFixed(AppConstants.decimalPlaces)} ${AppConstants.currencySymbolEn}'),
            _buildStatRow(tr('قيمة المخزون'), '${inventoryValue.toStringAsFixed(AppConstants.decimalPlaces)} ${AppConstants.currencySymbolEn}'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child:  Text(tr('إغلاق')),
          ),
        ],
      ),
    );
  }

  Widget _buildStatRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.primary)),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────
  // EDIT DIALOGS
  // ─────────────────────────────────────────────────────────────────────

  void _showEditBranchDialog(Branche branch) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => BranchEditDialog(existing: branch),
    );
    if (result == true && mounted) {
      AppToast.show(context, tr('تم تحديث الفرع بنجاح'), type: ToastType.success);
    }
  }

  void _showEditWarehouseDialog(Warehouse warehouse) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => WarehouseEditDialog(existing: warehouse),
    );
    if (result == true && mounted) {
      AppToast.show(context, tr('تم تحديث المخزن بنجاح'), type: ToastType.success);
    }
  }

  // ─────────────────────────────────────────────────────────────────────
  // QUICK CREATE COST CENTER
  // ─────────────────────────────────────────────────────────────────────

  Future<int?> showQuickCreateCostCenterDialog() async {
    final result = await showDialog<int?>(
      context: context,
      builder: (context) => const QuickCostCenterDialog(),
    );
    if (result != null) refreshAuxData();
    return result;
  }

  // ─────────────────────────────────────────────────────────────────────
  // ACTIVITY LOG HELPER
  // ─────────────────────────────────────────────────────────────────────

  void _logActivity(String action, String entityType, int? entityId, String description) async {
    try {
      final user = screenRef.read(authProvider).user;
      final logger = screenRef.read(activityLoggerProvider);
      await logger.log(
        userId: user?.id ?? 0,
        userName: user?.displayName ?? 'مجهول',
        action: action,
        entityType: entityType,
        description: description,
      );
    } catch (_) {}
  }
}
