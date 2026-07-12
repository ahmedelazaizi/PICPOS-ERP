import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:ural_erp/l10n/app_localizations.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../data/providers/providers.dart';
import '../../../../data/database/sync_interceptor.dart';
import '../../../widgets/dialogs/app_form_dialog.dart';

class RegionEditDialog extends AppFormDialog<bool> {
  final RegionData? region; // null = create new

  const RegionEditDialog({super.key, this.region});

  @override
  AppFormDialogState<bool, RegionEditDialog> createState() =>
      _RegionEditDialogState();
}

class _RegionEditDialogState
    extends AppFormDialogState<bool, RegionEditDialog> {
  late final nameController = registerController(widget.region?.name);
  late final addressController = registerController(widget.region?.address);
  late final phoneController = registerController(widget.region?.phone);
  int? _selectedCostCenterId;

  bool get _isEdit => widget.region != null;

  @override
  void initState() {
    super.initState();
    _selectedCostCenterId = widget.region?.costCenterId;
  }

  @override
  String get dialogTitle =>
      _isEdit ? 'تعديل المنطقة' : 'إضافة منطقة جديدة';

  @override
  IconData get dialogIcon => PhosphorIconsBold.mapPin;

  @override
  Widget buildFormContent(
      BuildContext context, AppLocalizations localizations) {
    final accountingRepo = ref.watch(accountingRepositoryProvider);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: nameController,
          decoration: const InputDecoration(
            labelText: 'اسم المنطقة *',
            prefixIcon: Icon(PhosphorIconsBold.mapPin),
          ),
          autofocus: true,
        ),
        const SizedBox(height: 16),
        TextField(
          controller: addressController,
          decoration: const InputDecoration(
            labelText: 'العنوان (اختياري)',
            prefixIcon: Icon(PhosphorIconsBold.mapPinArea),
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: phoneController,
          decoration: const InputDecoration(
            labelText: 'الهاتف (اختياري)',
            prefixIcon: Icon(PhosphorIconsBold.phone),
          ),
          keyboardType: TextInputType.phone,
        ),
        const SizedBox(height: 16),
        FutureBuilder<List<CostCenter>>(
          future: accountingRepo.getActiveCostCenters(),
          builder: (context, snapshot) {
            final centers = snapshot.data ?? [];
            final validId = centers.any((c) => c.id == _selectedCostCenterId)
                ? _selectedCostCenterId
                : null;
            return DropdownButtonFormField<int?>(
              value: validId,
              decoration: const InputDecoration(
                labelText: 'مركز التكلفة (اختياري)',
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
              onChanged: (v) => setState(() => _selectedCostCenterId = v),
            );
          },
        ),
      ],
    );
  }

  @override
  Future<bool> onSave() async {
    final name = nameController.text.trim();
    if (name.isEmpty) throw 'الرجاء إدخال اسم المنطقة';

    final address =
        addressController.text.trim().isEmpty ? null : addressController.text.trim();
    final phone =
        phoneController.text.trim().isEmpty ? null : phoneController.text.trim();

    final repo = ref.read(regionRepositoryProvider);

    if (_isEdit) {
      // In client mode, also send to server
      await SyncInterceptor.instance?.updateRegion(
        id: widget.region!.id,
        name: name,
        address: address,
        phone: phone,
        costCenterId: _selectedCostCenterId,
      );
      await repo.updateRegion(widget.region!.copyWith(
        name: name,
        address: address,
        phone: phone,
        costCenterId: _selectedCostCenterId,
      ));
    } else {
      await SyncInterceptor.instance?.createRegion(
        name: name,
        address: address,
        phone: phone,
        costCenterId: _selectedCostCenterId,
      );
      await repo.createRegion(
        name: name,
        address: address,
        phone: phone,
        costCenterId: _selectedCostCenterId,
      );
    }

    return true;
  }
}
