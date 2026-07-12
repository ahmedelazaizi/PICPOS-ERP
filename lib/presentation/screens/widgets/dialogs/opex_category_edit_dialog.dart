import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../../../data/database/database.dart';
import '../../../../data/providers/repository_providers.dart';
import '../../../../data/providers/manufacturing_providers.dart';
import 'package:drift/drift.dart' hide Column;

/// Standardized dialog for creating or editing an Opex category.
class OpexCategoryEditDialog extends ConsumerStatefulWidget {
  final OpExpenseCategoryData? existing;

  const OpexCategoryEditDialog({super.key, this.existing});

  @override
  ConsumerState<OpexCategoryEditDialog> createState() => _OpexCategoryEditDialogState();
}

class _OpexCategoryEditDialogState extends ConsumerState<OpexCategoryEditDialog> {
  final _nameController = TextEditingController();
  final _rateController = TextEditingController();
  String _type = 'indirect';
  String _allocation = 'fixed_monthly';
  bool _isProduction = true;
  bool _isSaving = false;

  final Map<String, String> _types = {
    'direct': 'مباشرة',
    'indirect': 'غير مباشرة',
    'fixed': 'ثابتة',
    'variable': 'متغيرة',
  };

  final Map<String, String> _allocations = {
    'per_unit': 'لكل وحدة',
    'per_hour': 'بالساعة',
    'per_order': 'لكل أمر تصنيع',
    'fixed_monthly': 'توزيع شهري ثابت',
  };

  @override
  void initState() {
    super.initState();
    if (widget.existing != null) {
      _nameController.text = widget.existing!.name;
      _rateController.text = widget.existing!.defaultRate.toStringAsFixed(2);
      _type = widget.existing!.type;
      _allocation = widget.existing!.allocationMethod;
      _isProduction = widget.existing!.isProductionRelated;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _rateController.dispose();
    super.dispose();
  }

  Future<void> _handleSave() async {
    if (_isSaving) return;
    if (_nameController.text.isEmpty) {
      AppToast.show(context, 'يرجى إدخال اسم الفئة', type: ToastType.error);
      return;
    }

    setState(() => _isSaving = true);

    try {
      final repo = ref.read(manufacturingRepositoryProvider);
      final rate = double.tryParse(_rateController.text) ?? 0;

      if (widget.existing != null) {
        await repo.updateExpenseCategory(
          widget.existing!.id,
          OpExpenseCategoriesCompanion(
            name: Value(_nameController.text),
            type: Value(_type),
            isProductionRelated: Value(_isProduction),
            allocationMethod: Value(_allocation),
            defaultRate: Value(rate),
          ),
        );
      } else {
        await repo.createExpenseCategory(
          name: _nameController.text,
          type: _type,
          isProductionRelated: _isProduction,
          allocationMethod: _allocation,
          defaultRate: rate,
        );
      }

      if (mounted) {
        Navigator.pop(context, true);
        AppToast.show(context, 'تم الحفظ بنجاح', type: ToastType.success);
      }
      ref.invalidate(expenseCategoriesProvider);
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
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      widget.existing == null ? PhosphorIconsBold.plus : PhosphorIconsBold.pencilSimple,
                      color: AppColors.primary,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        widget.existing == null ? 'فئة مصروف جديدة' : 'تعديل فئة',
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(PhosphorIconsBold.x),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                const Divider(height: 24),
                TextField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: 'اسم الفئة *',
                    hintText: 'مثال: كهرباء المصنع',
                    prefixIcon: Icon(PhosphorIconsBold.textT),
                    border: OutlineInputBorder(),
                  ),
                  autofocus: true,
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: _type,
                        decoration: const InputDecoration(
                          labelText: 'النوع',
                          prefixIcon: Icon(PhosphorIconsBold.tag),
                          border: OutlineInputBorder(),
                        ),
                        items: _types.entries
                            .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
                            .toList(),
                        onChanged: (v) => setState(() => _type = v!),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: _allocation,
                        decoration: const InputDecoration(
                          labelText: 'طريقة التوزيع',
                          prefixIcon: Icon(PhosphorIconsBold.arrowsOutLineHorizontal),
                          border: OutlineInputBorder(),
                        ),
                        items: _allocations.entries
                            .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
                            .toList(),
                        onChanged: (v) => setState(() => _allocation = v!),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _rateController,
                        decoration: const InputDecoration(
                          labelText: 'المعدل الافتراضي',
                          prefixIcon: Icon(PhosphorIconsBold.currencyCircleDollar),
                          border: OutlineInputBorder(),
                        ),
                        keyboardType: TextInputType.number,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: CheckboxListTile(
                        value: _isProduction,
                        onChanged: (v) => setState(() => _isProduction = v ?? true),
                        title: const Text('متعلقة بالإنتاج', style: TextStyle(fontSize: 13)),
                        controlAffinity: ListTileControlAffinity.leading,
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
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
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Text('حفظ', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
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
