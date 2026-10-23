import 'package:picpos_erp/core/i18n/tr.dart';
import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:drift/drift.dart' hide Column;
import '../../../../data/providers/providers.dart';
import '../../../../services/client_write_interceptor.dart';
import '../../../widgets/dialogs/app_form_dialog.dart';
import 'package:picpos_erp/l10n/app_localizations.dart';

class PartyEditDialog extends AppFormDialog<bool> {
  final Party? existing;
  final bool isSupplier;
  final bool isCustomer;

  const PartyEditDialog({
    super.key,
    this.existing,
    required this.isSupplier,
    required this.isCustomer,
  });

  @override
  AppFormDialogState<bool, PartyEditDialog> createState() => _PartyEditDialogState();
}

class _PartyEditDialogState extends AppFormDialogState<bool, PartyEditDialog> {
  late final nameController = registerController(widget.existing?.name);
  late final codeController = registerController(widget.existing?.code);
  late final phoneController = registerController(widget.existing?.phone);
  late final addressController = registerController(widget.existing?.address);
  late final taxIdController = registerController(widget.existing?.taxId);
  int? _selectedGroupId;
  List<PartyGroup> _groups = [];

  @override
  void initState() {
    super.initState();
    _selectedGroupId = widget.existing?.groupId;
    _loadGroups();
  }

  Future<void> _loadGroups() async {
    final db = ref.read(databaseProvider);
    final type = widget.isSupplier ? 'supplier' : 'customer';
    final groups = await db.getPartyGroupsByType(type);
    if (mounted) setState(() => _groups = groups);
  }

  @override
  String get dialogTitle => widget.existing == null
      ? (widget.isSupplier ? tr('إضافة مورد جديد') : tr('إضافة عميل جديد'))
      : (widget.isSupplier ? tr('تعديل بيانات المورد') : tr('تعديل بيانات العميل'));

  @override
  IconData get dialogIcon =>
      widget.isSupplier ? PhosphorIconsBold.truck : PhosphorIconsBold.user;

  @override
  Widget buildFormContent(BuildContext context, AppLocalizations localizations) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: codeController,
          decoration:  InputDecoration(
            labelText: tr('الكود'),
            prefixIcon: const Icon(PhosphorIconsLight.barcode, size: 20),
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: nameController,
          decoration: InputDecoration(
            labelText: widget.isSupplier ? tr('اسم المورد *') : tr('اسم العميل *'),
            prefixIcon: const Icon(PhosphorIconsLight.user, size: 20),
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: phoneController,
          decoration:  InputDecoration(
            labelText: tr('رقم الهاتف'),
            prefixIcon: const Icon(PhosphorIconsLight.phone, size: 20),
          ),
          keyboardType: TextInputType.phone,
        ),
        const SizedBox(height: 16),
        TextField(
          controller: addressController,
          decoration:  InputDecoration(
            labelText: tr('العنوان'),
            prefixIcon: const Icon(PhosphorIconsLight.mapPin, size: 20),
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: taxIdController,
          decoration:  InputDecoration(
            labelText: tr('الرقم الضريبي'),
            prefixIcon: const Icon(PhosphorIconsLight.hash, size: 20),
          ),
        ),
        if (_groups.isNotEmpty) ...[
          const SizedBox(height: 16),
          DropdownButtonFormField<int?>(
            value: _selectedGroupId,
            decoration:  InputDecoration(
              labelText: tr('التصنيف'),
              prefixIcon: const Icon(PhosphorIconsLight.folder, size: 20),
            ),
            items: [
               DropdownMenuItem<int?>(value: null, child: Text(tr('بدون تصنيف'))),
              ..._groups.map((g) => DropdownMenuItem(value: g.id, child: Text(g.name))),
            ],
            onChanged: (value) => setState(() => _selectedGroupId = value),
          ),
        ],
      ],
    );
  }

  @override
  Future<bool> onSave() async {
    final name = nameController.text.trim();
    final code = codeController.text.trim();
    final phone = phoneController.text.trim();
    final address = addressController.text.trim();
    final taxId = taxIdController.text.trim();

    if (name.isEmpty) {
      throw widget.isSupplier ? 'يرجى إدخال اسم المورد' : 'يرجى إدخال اسم العميل';
    }

    final partiesRepo = ref.read(partiesRepositoryProvider);

    if (widget.existing == null) {
      // ── Create ──
      var partyId = await ClientWriteInterceptor.createParty(
        name: name,
        phone: phone.isEmpty ? null : phone,
        address: address.isEmpty ? null : address,
        isCustomer: widget.isCustomer,
        isSupplier: widget.isSupplier,
      );

      if (partyId == null) {
        await partiesRepo.insertParty(
          PartiesCompanion.insert(
            name: name,
            code: Value(code.isEmpty ? null : code),
            phone: Value(phone.isEmpty ? null : phone),
            address: Value(address.isEmpty ? null : address),
            taxId: Value(taxId.isEmpty ? null : taxId),
            isCustomer: Value(widget.isCustomer),
            isSupplier: Value(widget.isSupplier),
            groupId: Value(_selectedGroupId),
          ),
        );
      }
    } else {
      // ── Update ──
      final updatedParty = widget.existing!.copyWith(
        name: name,
        code: Value(code.isEmpty ? null : code),
        phone: Value(phone.isEmpty ? null : phone),
        address: Value(address.isEmpty ? null : address),
        taxId: Value(taxId.isEmpty ? null : taxId),
        groupId: Value(_selectedGroupId),
      );

      final serverUpdated = await ClientWriteInterceptor.updateParty(widget.existing!.id, {
        'name': name,
        'code': code.isEmpty ? null : code,
        'phone': phone.isEmpty ? null : phone,
        'isSupplier': widget.isSupplier,
        'isCustomer': widget.isCustomer,
        'group_id': _selectedGroupId,
      });

      if (!serverUpdated) {
        await partiesRepo.updateParty(updatedParty);
      }
    }

    // Log activity
    try {
      final user = ref.read(authProvider).user;
      final logger = ref.read(activityLoggerProvider);
      await logger.log(
        userId: user?.id ?? 0,
        userName: user?.displayName ?? 'مجهول',
        action: widget.existing == null ? 'create' : 'update',
        entityType: 'party',
        description: '${widget.existing == null ? 'إضافة' : 'تعديل'} ${widget.isSupplier ? 'مورد' : 'عميل'}: $name',
      );
    } catch (_) {}

    return true;
  }
}
