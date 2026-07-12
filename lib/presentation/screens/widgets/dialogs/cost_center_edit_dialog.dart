import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../../../data/providers/providers.dart';
import '../../../../services/network_service.dart';

/// Standardized dialog for creating or editing a Cost Center.
class CostCenterEditDialog extends ConsumerStatefulWidget {
  final CostCenter? existing;
  final int? initialParentId;

  const CostCenterEditDialog({
    super.key,
    this.existing,
    this.initialParentId,
  });

  @override
  ConsumerState<CostCenterEditDialog> createState() => _CostCenterEditDialogState();
}

class _CostCenterEditDialogState extends ConsumerState<CostCenterEditDialog> {
  final _codeController = TextEditingController();
  final _nameController = TextEditingController();
  int? _selectedParentId;
  bool _isActive = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    if (widget.existing != null) {
      _codeController.text = widget.existing!.code;
      _nameController.text = widget.existing!.name;
      _selectedParentId = widget.existing!.parentId;
      _isActive = widget.existing!.isActive;
    } else {
      _selectedParentId = widget.initialParentId;
    }
  }

  @override
  void dispose() {
    _codeController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _handleSave() async {
    final code = _codeController.text.trim();
    final name = _nameController.text.trim();

    if (code.isEmpty || name.isEmpty) {
      AppToast.show(context, 'يرجى ملء جميع الحقول المطلوبة', type: ToastType.error);
      return;
    }

    setState(() => _isSaving = true);

    try {
      final accountingRepo = ref.read(accountingRepositoryProvider);

      if (widget.existing != null) {
        await accountingRepo.updateCostCenter(
          widget.existing!.id,
          code: code,
          name: name,
          parentId: _selectedParentId,
          isActive: _isActive,
        );
        _logActivity('update_cost_center', widget.existing!.id, 'تعديل مركز تكلفة: $name');
      } else {
        final id = await accountingRepo.createCostCenter(
          code: code,
          name: name,
          parentId: _selectedParentId,
        );
        _logActivity('create_cost_center', id, 'إضافة مركز تكلفة: $name');
      }

      if (mounted) {
        AppToast.show(context, 'تم الحفظ بنجاح', type: ToastType.success);
        // Notify connected clients about cost center change
        NetworkService.instance.broadcastChange('cost_centers');
        Navigator.pop(context, true);
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
    final accountingRepo = ref.watch(accountingRepositoryProvider);

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
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
                        widget.existing == null ? 'إضافة مركز تكلفة' : 'تعديل مركز تكلفة',
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
                  controller: _codeController,
                  decoration: const InputDecoration(
                    labelText: 'الرمز *',
                    hintText: 'مثال: BR-01',
                    prefixIcon: Icon(PhosphorIconsBold.hash),
                    border: OutlineInputBorder(),
                  ),
                  autofocus: true,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: 'الاسم *',
                    hintText: 'مثال: الفرع الرئيسي',
                    prefixIcon: Icon(PhosphorIconsBold.textT),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                FutureBuilder<List<CostCenter>>(
                  future: accountingRepo.getActiveCostCenters(),
                  builder: (context, snapshot) {
                    final centers = snapshot.data ?? [];
                    final validParents = widget.existing == null 
                        ? centers 
                        : centers.where((c) => c.id != widget.existing!.id).toList();

                    return DropdownButtonFormField<int?>(
                      initialValue: _selectedParentId,
                      decoration: const InputDecoration(
                        labelText: 'المركز الرئيسي (اختياري)',
                        prefixIcon: Icon(PhosphorIconsBold.treeStructure),
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        const DropdownMenuItem<int?>(value: null, child: Text('بدون (مركز رئيسي)')),
                        ...validParents.map((c) => DropdownMenuItem<int?>(
                          value: c.id,
                          child: Text(c.name),
                        )),
                      ],
                      onChanged: (val) => setState(() => _selectedParentId = val),
                    );
                  },
                ),
                if (widget.existing != null) ...[
                  const SizedBox(height: 16),
                  SwitchListTile(
                    title: const Text('نشط'),
                    subtitle: const Text('تعطيل المركز يمنع استخدامه في الحركات الجديدة'),
                    value: _isActive,
                    onChanged: (val) => setState(() => _isActive = val),
                    contentPadding: EdgeInsets.zero,
                  ),
                ],
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

  void _logActivity(String action, int entityId, String description) async {
    try {
      final user = ref.read(authProvider).user;
      final logger = ref.read(activityLoggerProvider);
      await logger.log(
        userId: user?.id ?? 0,
        userName: user?.displayName ?? 'مجهول',
        action: action,
        entityType: 'cost_center',
        description: description,
      );
    } catch (_) {}
  }
}
