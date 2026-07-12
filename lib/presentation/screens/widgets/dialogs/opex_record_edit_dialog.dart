import 'package:flutter/material.dart';
import 'dart:ui' as ui;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../../../data/providers/providers.dart';
import '../../../../data/providers/manufacturing_providers.dart';
import 'package:intl/intl.dart';

/// Standardized dialog for recording an operational expense.
class OpexRecordEditDialog extends ConsumerStatefulWidget {
  const OpexRecordEditDialog({super.key});

  @override
  ConsumerState<OpexRecordEditDialog> createState() => _OpexRecordEditDialogState();
}

class _OpexRecordEditDialogState extends ConsumerState<OpexRecordEditDialog> {
  final _amountController = TextEditingController();
  final _notesController = TextEditingController();
  int? _selectedCategoryId;
  int? _selectedCostCenterId;
  int? _selectedBranchId;
  DateTime _selectedDate = DateTime.now();
  bool _isSaving = false;

  @override
  void dispose() {
    _amountController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _handleSave() async {
    final amount = double.tryParse(_amountController.text) ?? 0;
    if (amount <= 0 || _selectedCategoryId == null) {
      AppToast.show(context, 'يرجى إدخال مبلغ صحيح واختيار فئة', type: ToastType.error);
      return;
    }

    setState(() => _isSaving = true);

    try {
      final accountingRepo = ref.read(accountingRepositoryProvider);

      // Get current user ID (default 1 if not available)
      final user = ref.read(authProvider).user;
      final userId = user?.id ?? 1;

      final categories = await ref.read(expenseCategoriesProvider.future);
      final cat = categories.firstWhere((c) => c.id == _selectedCategoryId);
      final description = cat.name;

      // EXP-2 (batch B7 / S-FAILLOUD): record + auto-post to the General
      // Ledger in ONE atomic call. This used to be two independent DAO
      // round-trips (recordExpense, then autoPostOperationalExpense) with no
      // shared transaction — if the post threw (EXP-1's unresolvable-account
      // guard), the op_expenses row from the first call stayed committed
      // with NO journal entry and no rollback. recordAndPostOperationalExpense
      // wraps both writes in a single db.transaction(), so a failed post now
      // rolls the insert back too — a failed save leaves no trace instead of
      // a silent GL-less orphan.
      // B13 EXP-3: this dialog has no payment-method / safe picker yet, so
      // `paymentMethod`/`safeId` are omitted — recordAndPostOperationalExpense
      // treats that as a CASH expense and silently resolves the default cash
      // safe (getDefaultSafeByType('cash')) to move the physical drawer
      // alongside the GL entry. Add an explicit selector here if/when this
      // dialog needs to support non-default safes or bank expenses.
      await accountingRepo.recordAndPostOperationalExpense(
        categoryId: _selectedCategoryId!,
        amount: amount,
        expenseDate: _selectedDate,
        description: _notesController.text.isNotEmpty
            ? '$description — ${_notesController.text}'
            : description,
        expenseAccountCode: cat.accountCode,
        notes: _notesController.text.isEmpty ? null : _notesController.text,
        userId: userId,
        branchId: _selectedBranchId,
        costCenterId: _selectedCostCenterId,
      );

      ref.invalidate(expenseCategoriesProvider);
      if (mounted) {
        AppToast.show(context, 'تم تسجيل المصروف بنجاح', type: ToastType.success);
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        AppToast.show(context, 'خطأ: $e', type: ToastType.error);
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final categoriesAsync = ref.watch(activeExpenseCategoriesProvider);
    final accountingRepo = ref.watch(accountingRepositoryProvider);

    return Directionality(
      textDirection: ui.TextDirection.rtl,
      child: Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 500),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Title
                Row(
                  children: [
                    const Icon(PhosphorIconsBold.coins, color: AppColors.primary),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'تسجيل مصروف تشغيلي',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(PhosphorIconsBold.x),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                const Divider(height: 24),
                // Category
                categoriesAsync.when(
                  data: (categories) {
                    if (categories.isEmpty) {
                      return const Text(
                        'أضف فئات مصروفات أولاً من تبويب "فئات المصروفات"',
                        style: TextStyle(color: AppColors.error),
                      );
                    }
                    _selectedCategoryId ??= categories.first.id;
                    return DropdownButtonFormField<int>(
                      value: _selectedCategoryId,
                      decoration: const InputDecoration(
                        labelText: 'فئة المصروف',
                        prefixIcon: Icon(PhosphorIconsBold.tag),
                        border: OutlineInputBorder(),
                      ),
                      items: categories
                          .map((c) => DropdownMenuItem(value: c.id, child: Text(c.name)))
                          .toList(),
                      onChanged: (v) => setState(() => _selectedCategoryId = v),
                    );
                  },
                  loading: () => const Center(child: CircularProgressIndicator()),
                  error: (e, _) => Text('خطأ: $e'),
                ),
                const SizedBox(height: 16),
                // Amount
                TextField(
                  controller: _amountController,
                  decoration: InputDecoration(
                    labelText: 'المبلغ *',
                    suffixText: AppConstants.currencySymbol,
                    prefixIcon: const Icon(PhosphorIconsBold.currencyCircleDollar),
                    border: const OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.number,
                  autofocus: true,
                ),
                const SizedBox(height: 16),
                // Date
                InkWell(
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _selectedDate,
                      firstDate: DateTime(2020),
                      lastDate: DateTime.now().add(const Duration(days: 30)),
                    );
                    if (picked != null) {
                      setState(() => _selectedDate = picked);
                    }
                  },
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'التاريخ',
                      prefixIcon: Icon(PhosphorIconsBold.calendarBlank),
                      border: OutlineInputBorder(),
                    ),
                    child: Text(DateFormat('yyyy/MM/dd').format(_selectedDate)),
                  ),
                ),
                const SizedBox(height: 16),
                // Notes
                TextField(
                  controller: _notesController,
                  decoration: const InputDecoration(
                    labelText: 'ملاحظات (اختياري)',
                    prefixIcon: Icon(PhosphorIconsBold.note),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                // Cost Center
                FutureBuilder<List<CostCenter>>(
                  future: accountingRepo.getActiveCostCenters(),
                  builder: (context, ccSnap) {
                    final ccList = ccSnap.data ?? [];
                    return DropdownButtonFormField<int?>(
                      value: _selectedCostCenterId,
                      decoration: const InputDecoration(
                        labelText: 'مركز التكلفة',
                        prefixIcon: Icon(PhosphorIconsBold.treeStructure),
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        const DropdownMenuItem<int?>(value: null, child: Text('بدون')),
                        ...ccList.map((cc) => DropdownMenuItem<int?>(value: cc.id, child: Text(cc.name))),
                      ],
                      onChanged: (v) => setState(() => _selectedCostCenterId = v),
                    );
                  },
                ),
                const SizedBox(height: 16),
                // Branch
                ref.watch(allBranchesProvider).when(
                  data: (branches) => DropdownButtonFormField<int?>(
                    value: _selectedBranchId,
                    decoration: const InputDecoration(
                      labelText: 'الفرع (اختياري)',
                      prefixIcon: Icon(PhosphorIconsBold.buildings),
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      const DropdownMenuItem<int?>(value: null, child: Text('كل الفروع')),
                      ...branches.map((b) => DropdownMenuItem<int?>(value: b.id, child: Text(b.name))),
                    ],
                    onChanged: (v) => setState(() => _selectedBranchId = v),
                  ),
                  loading: () => const SizedBox.shrink(),
                  error: (_, _) => const SizedBox.shrink(),
                ),
                const SizedBox(height: 20),
                // Save button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _isSaving ? null : _handleSave,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    child: _isSaving
                        ? const SizedBox(
                            width: 20, height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Text('حفظ المصروف', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
