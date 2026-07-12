import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:drift/drift.dart' show Value;
import '../../../../core/utils/uuid_v7.dart';
import '../../../../data/providers/providers.dart';
import '../../../../services/client_write_interceptor.dart';
import '../../../widgets/dialogs/app_form_dialog.dart';
import 'package:ural_erp/l10n/app_localizations.dart';

class WarehouseEditDialog extends AppFormDialog<bool> {
  final Warehouse? existing;

  const WarehouseEditDialog({
    super.key,
    this.existing,
  });

  @override
  AppFormDialogState<bool, WarehouseEditDialog> createState() => _WarehouseEditDialogState();
}

class _WarehouseEditDialogState extends AppFormDialogState<bool, WarehouseEditDialog> {
  late final nameController = registerController(widget.existing?.name);
  int? selectedBranchId;
  int? selectedCostCenterId;
  String selectedType = 'general';

  @override
  void initState() {
    super.initState();
    selectedBranchId = widget.existing?.branchId;
    selectedCostCenterId = widget.existing?.costCenterId;
    selectedType = widget.existing?.type ?? 'general';
  }

  @override
  String get dialogTitle => widget.existing == null ? 'إضافة مخزن جديد' : 'تعديل المخزن';

  @override
  IconData get dialogIcon => PhosphorIconsBold.warehouse;

  @override
  Widget buildFormContent(BuildContext context, AppLocalizations localizations) {
    final branchRepo = ref.watch(branchRepositoryProvider);
    final accountingRepo = ref.watch(accountingRepositoryProvider);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: nameController,
          decoration: const InputDecoration(
            labelText: 'اسم المخزن *',
            prefixIcon: Icon(PhosphorIconsBold.warehouse),
          ),
        ),
        const SizedBox(height: 16),
        StreamBuilder<List<Branche>>(
          stream: branchRepo.watchAllBranches(),
          builder: (context, snapshot) {
            final branches = snapshot.data ?? [];
            // Ensure selected value exists in the list
            final validBranchId = branches.any((b) => b.id == selectedBranchId)
                ? selectedBranchId
                : null;
            return DropdownButtonFormField<int?>(
              initialValue: validBranchId,
              decoration: const InputDecoration(
                labelText: 'الفرع',
                prefixIcon: Icon(PhosphorIconsBold.buildings),
              ),
              items: [
                const DropdownMenuItem<int?>(
                  value: null,
                  child: Text('بدون فرع'),
                ),
                ...branches.map(
                  (b) => DropdownMenuItem<int?>(
                    value: b.id,
                    child: Text(b.name),
                  ),
                ),
              ],
              onChanged: (value) {
                setState(() => selectedBranchId = value);
              },
            );
          },
        ),
        const SizedBox(height: 16),
        DropdownButtonFormField<String>(
          initialValue: selectedType,
          decoration: const InputDecoration(
            labelText: 'نوع المخزن',
            prefixIcon: Icon(PhosphorIconsBold.package),
          ),
          items: const [
            DropdownMenuItem(value: 'general', child: Text('عام')),
            DropdownMenuItem(value: 'raw_materials', child: Text('خامات')),
            DropdownMenuItem(value: 'finished_goods', child: Text('منتج تام')),
            DropdownMenuItem(value: 'retail', child: Text('بيع')),
          ],
          onChanged: (value) {
            setState(() => selectedType = value ?? 'general');
          },
        ),
        const SizedBox(height: 16),
        FutureBuilder<List<CostCenter>>(
          future: accountingRepo.getActiveCostCenters(),
          builder: (context, snapshot) {
            final centers = snapshot.data ?? [];
            // Ensure selected value exists in the list
            final validCcId = centers.any((c) => c.id == selectedCostCenterId)
                ? selectedCostCenterId
                : null;
            return DropdownButtonFormField<int?>(
              initialValue: validCcId,
              decoration: const InputDecoration(
                labelText: 'مركز التكلفة',
                prefixIcon: Icon(PhosphorIconsBold.target),
              ),
              items: [
                const DropdownMenuItem<int?>(
                  value: null,
                  child: Text('بدون مركز تكلفة'),
                ),
                ...centers.map(
                  (c) => DropdownMenuItem<int?>(
                    value: c.id,
                    child: Text(c.name),
                  ),
                ),
              ],
              onChanged: (value) {
                setState(() => selectedCostCenterId = value);
              },
            );
          },
        ),
      ],
    );
  }

  @override
  Future<bool> onSave() async {
    final name = nameController.text.trim();
    if (name.isEmpty) throw 'الرجاء إدخال اسم المخزن';

    final branchRepo = ref.read(branchRepositoryProvider);

    if (widget.existing == null) {
      // UUID-First (Phase 1): mint ONE UUID up-front so the same identity
      // lands on both server (via interceptor) and local cache.
      final warehouseGlobalId = UuidV7.generate();
      final serverId = await ClientWriteInterceptor.createWarehouse(
        name: name,
        branchId: selectedBranchId,
        globalId: warehouseGlobalId,
      );
      if (serverId == null) {
        await branchRepo.insertWarehouse(
          WarehousesCompanion.insert(
            name: name,
            branchId: Value(selectedBranchId),
            costCenterId: Value(selectedCostCenterId),
            type: Value(selectedType),
            globalId: Value(warehouseGlobalId),
          ),
        );
      }
    } else {
      final intercepted = await ClientWriteInterceptor.updateWarehouse(
        widget.existing!.id,
        {
          'name': name,
          'branchId': selectedBranchId,
        },
      );
      if (!intercepted) {
        await branchRepo.updateWarehouse(
          Warehouse(
            id: widget.existing!.id,
            name: name,
            branchId: selectedBranchId,
            costCenterId: selectedCostCenterId,
            type: selectedType,
            isDefault: widget.existing!.isDefault,
            isActive: widget.existing!.isActive,
            // Spec 129 F6 — preserve isSystemDefault across edits.
            isSystemDefault: widget.existing!.isSystemDefault,
            rowVersion: 0,
          ),
        );
      }
    }

    // Log activity
    try {
      final user = ref.read(authProvider).user;
      final logger = ref.read(activityLoggerProvider);
      await logger.log(
        userId: user?.id ?? 0,
        userName: user?.displayName ?? 'مجهول',
        action: widget.existing == null ? 'add_warehouse' : 'edit_warehouse',
        entityType: 'warehouse',
        description: '${widget.existing == null ? 'إضافة' : 'تعديل'} مخزن: $name',
      );
    } catch (_) {}

    return true;
  }
}
