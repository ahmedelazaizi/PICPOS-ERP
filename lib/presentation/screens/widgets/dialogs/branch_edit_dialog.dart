import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../../data/providers/providers.dart';
import '../../../widgets/dialogs/app_form_dialog.dart';
import 'package:ural_erp/l10n/app_localizations.dart';
import '../../../../services/network_service.dart';

class BranchEditDialog extends AppFormDialog<bool> {
  final Branche? existing;

  const BranchEditDialog({
    super.key,
    this.existing,
  });

  @override
  AppFormDialogState<bool, BranchEditDialog> createState() => _BranchEditDialogState();
}

class _BranchEditDialogState extends AppFormDialogState<bool, BranchEditDialog> {
  late final nameController = registerController(widget.existing?.name);
  // L4 (2026-04-28): branch code (e.g. "CAI", "ALX") for invoice number prefix.
  late final codeController = registerController(widget.existing?.code);
  late final addressController = registerController(widget.existing?.address);
  late final phoneController = registerController(widget.existing?.phone);
  int? selectedCostCenterId;
  int? selectedRegionId;

  @override
  void initState() {
    super.initState();
    selectedCostCenterId = widget.existing?.costCenterId;
    selectedRegionId = widget.existing?.regionId;
  }

  @override
  String get dialogTitle => widget.existing == null ? 'إضافة فرع جديد' : 'تعديل الفرع';

  @override
  IconData get dialogIcon => PhosphorIconsBold.buildings;

  @override
  Widget buildFormContent(BuildContext context, AppLocalizations localizations) {
    final accountingRepo = ref.watch(accountingRepositoryProvider);
    final AsyncValue<List<RegionData>> regionsAsync = ref.watch(allRegionsProvider);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: nameController,
          decoration: const InputDecoration(
            labelText: 'اسم الفرع *',
            prefixIcon: Icon(PhosphorIconsBold.buildings),
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: codeController,
          textCapitalization: TextCapitalization.characters,
          maxLength: 5,
          decoration: const InputDecoration(
            labelText: 'كود الفرع (يُستخدم بادئة لرقم الفاتورة، مثل CAI أو ALX)',
            hintText: 'CAI',
            prefixIcon: Icon(PhosphorIconsBold.tag),
            counterText: '',
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: addressController,
          decoration: const InputDecoration(
            labelText: 'العنوان',
            prefixIcon: Icon(PhosphorIconsBold.mapPin),
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: phoneController,
          decoration: const InputDecoration(
            labelText: 'رقم الهاتف',
            prefixIcon: Icon(PhosphorIconsBold.phone),
          ),
          keyboardType: TextInputType.phone,
        ),
        const SizedBox(height: 16),
        FutureBuilder<List<CostCenter>>(
          future: accountingRepo.getActiveCostCenters(),
          builder: (context, snapshot) {
            final centers = snapshot.data ?? [];
            // Ensure selected value exists in the list
            final validId = centers.any((c) => c.id == selectedCostCenterId)
                ? selectedCostCenterId
                : null;
            return DropdownButtonFormField<int?>(
              initialValue: validId,
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
        const SizedBox(height: 16),
        regionsAsync.when<Widget>(
          data: (regions) {
            final validRegionId = regions.any((r) => r.id == selectedRegionId)
                ? selectedRegionId
                : null;
            return DropdownButtonFormField<int?>(
              value: validRegionId,
              decoration: const InputDecoration(
                labelText: 'المنطقة (اختياري)',
                prefixIcon: Icon(PhosphorIconsBold.mapPin),
              ),
              items: [
                const DropdownMenuItem<int?>(
                  value: null,
                  child: Text('بدون منطقة'),
                ),
                ...regions.map(
                  (r) => DropdownMenuItem<int?>(
                    value: r.id,
                    child: Text(r.name),
                  ),
                ),
              ],
              onChanged: (value) {
                setState(() => selectedRegionId = value);
              },
            );
          },
          loading: () => const LinearProgressIndicator(),
          error: (e, st) => const SizedBox.shrink(),
        ),
      ],
    );
  }

  @override
  Future<bool> onSave() async {
    final name = nameController.text.trim();
    if (name.isEmpty) throw 'الرجاء إدخال اسم الفرع';

    // L4: validate branch code — uppercase, max 5 ASCII chars, unique
    var code = codeController.text.trim().toUpperCase();
    if (code.length > 5) throw 'كود الفرع لا يقبل أكثر من 5 أحرف';
    if (code.isNotEmpty && !RegExp(r'^[A-Z0-9]+$').hasMatch(code)) {
      throw 'كود الفرع يقبل أحرفاً إنجليزية وأرقام فقط';
    }
    final branchCode = code.isEmpty ? null : code;

    final branchRepo = ref.read(branchRepositoryProvider);

    final address =
        addressController.text.isNotEmpty ? addressController.text : null;
    final phone =
        phoneController.text.isNotEmpty ? phoneController.text : null;

    if (widget.existing == null) {
      await branchRepo.createBranch(
        name: name,
        code: branchCode,
        address: address,
        phone: phone,
        costCenterId: selectedCostCenterId,
        // Cluster 023 / Issue 4 — pass the operator-picked region on
        // create too. Previously dropped here, so newly-created branches
        // ignored the region selection silently and the user had to
        // re-open and edit to set it.
        regionId: selectedRegionId,
      );
    } else {
      await branchRepo.updateBranch(
        Branche(
          id: widget.existing!.id,
          name: name,
          code: branchCode,
          address: address,
          phone: phone,
          costCenterId: selectedCostCenterId,
          isActive: widget.existing!.isActive,
          globalId: widget.existing!.globalId,
          regionId: selectedRegionId,
          // Spec 129 F6 — preserve the seeded-default flag on edit so a
          // rename of the seeded branch doesn't strip its is_system_default.
          isSystemDefault: widget.existing!.isSystemDefault,
          rowVersion: 0,
        ),
      );
    }

    // Log activity
    try {
      final user = ref.read(authProvider).user;
      final logger = ref.read(activityLoggerProvider);
      await logger.log(
        userId: user?.id ?? 0,
        userName: user?.displayName ?? 'مجهول',
        action: widget.existing == null ? 'add_branch' : 'edit_branch',
        entityType: 'branch',
        description: '${widget.existing == null ? 'إضافة' : 'تعديل'} فرع: $name',
      );
    } catch (_) {}

    // Notify connected clients about branch change
    NetworkService.instance.broadcastChange('branches');

    return true;
  }
}
