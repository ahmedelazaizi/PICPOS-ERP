import 'package:picpos_erp/core/i18n/tr.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../core/theme/app_colors.dart';
import '../../data/providers/providers.dart';
import '../widgets/dialogs/app_confirm_dialog.dart';
import '../../core/widgets/app_toast.dart';
import 'products/widgets/unit_edit_dialog.dart';

/// Units Management Screen — CRUD for measurement unit names
/// (e.g., قطعة/Piece, كرتونة/Carton, عبوة/Pack, كيس/Bag)
class UnitsManagementScreen extends ConsumerStatefulWidget {
  const UnitsManagementScreen({super.key});

  @override
  ConsumerState<UnitsManagementScreen> createState() =>
      _UnitsManagementScreenState();
}

class _UnitsManagementScreenState
    extends ConsumerState<UnitsManagementScreen> {
  List<Unit> _units = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadUnits();
  }

  Future<void> _loadUnits() async {
    setState(() => _loading = true);
    try {
      final repo = ref.read(productRepositoryProvider);
      final units = await repo.getAllUnits();
      if (mounted) setState(() { _units = units; _loading = false; });
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _showUnitDialog({Unit? existing}) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => UnitEditDialog(existing: existing),
    );

    if (result == true) _loadUnits();
  }

  Future<void> _deleteUnit(Unit unit) async {
    final confirmed = await AppConfirmDialog.show(
      context,
      title: tr('حذف وحدة القياس'),
      message: tr('هل أنت متأكد من حذف "{p0}"؟', {'p0': trData(unit.name)}),
      confirmLabel: tr('حذف'),
      color: AppColors.error,
      icon: PhosphorIconsBold.trash,
    );

    if (confirmed == true) {
      try {
        final repo = ref.read(productRepositoryProvider);
        await repo.deleteUnit(unit.id);
        _loadUnits();
      } catch (e) {
        if (mounted) {
          AppToast.show(context, tr('خطأ في الحذف: {e}', {'e': e}), type: ToastType.error);
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title:  Text(tr('إدارة وحدات القياس')),
          actions: [
            IconButton(
              icon: const Icon(PhosphorIconsBold.plus),
              tooltip: tr('إضافة وحدة جديدة'),
              onPressed: () => _showUnitDialog(),
            ),
          ],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _units.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(PhosphorIconsLight.package, size: 80, color: Colors.grey.shade400),
                        const SizedBox(height: 16),
                        Text(
                          tr('لا توجد وحدات قياس بعد'),
                          style: TextStyle(
                            fontSize: 18,
                            color: Colors.grey.shade600,
                          ),
                        ),
                        const SizedBox(height: 8),
                        ElevatedButton.icon(
                          icon: const Icon(PhosphorIconsBold.plus),
                          label:  Text(tr('إضافة وحدة')),
                          onPressed: () => _showUnitDialog(),
                        ),
                      ],
                    ),
                  )
                : Padding(
                    padding: const EdgeInsets.all(24),
                    child: Card(
                      child: ListView.separated(
                        itemCount: _units.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final unit = _units[index];
                          return ListTile(
                            leading: CircleAvatar(
                              backgroundColor: AppColors.primary.withValues(alpha: 0.1),
                              child: Text(
                                trData(unit.symbol),
                                style: const TextStyle(
                                  color: AppColors.primary,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                            title: Text(
                              trData(unit.name),
                              style: const TextStyle(fontWeight: FontWeight.w600),
                            ),
                            subtitle: Text(
                              tr('معامل التحويل: {p0}', {'p0': unit.conversionFactor}),
                              style: TextStyle(color: Colors.grey.shade600),
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(PhosphorIconsLight.pencilSimple),
                                  tooltip: tr('تعديل'),
                                  onPressed: () => _showUnitDialog(existing: unit),
                                ),
                                IconButton(
                                  icon: const Icon(PhosphorIconsLight.trash, color: AppColors.error),
                                  tooltip: tr('حذف'),
                                  onPressed: () => _deleteUnit(unit),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ),
      ),
    );
  }
}
