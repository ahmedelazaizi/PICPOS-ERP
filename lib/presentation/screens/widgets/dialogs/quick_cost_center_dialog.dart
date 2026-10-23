import 'package:picpos_erp/core/i18n/tr.dart';
import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../../data/providers/providers.dart';
import '../../../widgets/dialogs/app_form_dialog.dart';
import 'package:picpos_erp/l10n/app_localizations.dart';

class QuickCostCenterDialog extends AppFormDialog<int?> {
  const QuickCostCenterDialog({super.key});

  @override
  AppFormDialogState<int?, QuickCostCenterDialog> createState() => _QuickCostCenterDialogState();
}

class _QuickCostCenterDialogState extends AppFormDialogState<int?, QuickCostCenterDialog> {
  late final codeController = registerController();
  late final nameController = registerController();

  @override
  void initState() {
    super.initState();
    _suggestCode();
  }

  Future<void> _suggestCode() async {
    final accountingRepo = ref.read(accountingRepositoryProvider);
    final centers = await accountingRepo.getActiveCostCenters();
    codeController.text = 'CC-${(centers.length + 1).toString().padLeft(2, '0')}';
  }

  @override
  String get dialogTitle => tr('إنشاء مركز تكلفة سريع');

  @override
  IconData get dialogIcon => PhosphorIconsBold.target;

  @override
  Widget buildFormContent(BuildContext context, AppLocalizations localizations) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: codeController,
          decoration:  InputDecoration(
            labelText: tr('الرمز'),
            prefixIcon: const Icon(PhosphorIconsBold.hash),
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: nameController,
          autofocus: true,
          decoration:  InputDecoration(
            labelText: tr('اسم مركز التكلفة *'),
            prefixIcon: const Icon(PhosphorIconsBold.textT),
          ),
        ),
      ],
    );
  }

  @override
  Future<int?> onSave() async {
    final code = codeController.text.trim();
    final name = nameController.text.trim();

    if (code.isEmpty || name.isEmpty) {
      throw 'يرجى ملء الرمز والاسم';
    }

    final accountingRepo = ref.read(accountingRepositoryProvider);
    final newId = await accountingRepo.createCostCenter(
      code: code,
      name: name,
    );

    return newId;
  }
}
