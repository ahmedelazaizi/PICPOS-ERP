import 'package:picpos_erp/core/i18n/tr.dart';
import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:drift/drift.dart' show Value;
import '../../../../data/providers/providers.dart';
import '../../../widgets/dialogs/app_form_dialog.dart';
import 'package:picpos_erp/l10n/app_localizations.dart';

class UnitEditDialog extends AppFormDialog<bool> {
  final Unit? existing;

  const UnitEditDialog({super.key, this.existing});

  @override
  AppFormDialogState<bool, UnitEditDialog> createState() => _UnitEditDialogState();
}

class _UnitEditDialogState extends AppFormDialogState<bool, UnitEditDialog> {
  late final nameController = registerController(widget.existing?.name);
  late final symbolController = registerController(widget.existing?.symbol);
  late final factorController = registerController(
    (widget.existing?.conversionFactor ?? 1.0).toString(),
  );

  @override
  String get dialogTitle =>
      widget.existing == null ? tr('إضافة وحدة قياس') : tr('تعديل وحدة قياس');

  @override
  IconData get dialogIcon =>
      widget.existing == null ? PhosphorIconsBold.plusCircle : PhosphorIconsBold.pencilSimple;

  @override
  Widget buildFormContent(BuildContext context, AppLocalizations localizations) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: nameController,
          decoration:  InputDecoration(
            labelText: tr('اسم الوحدة'),
            hintText: tr('مثال: كرتونة، عبوة، قطعة'),
            prefixIcon: const Icon(PhosphorIconsLight.package, size: 20),
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: symbolController,
          decoration:  InputDecoration(
            labelText: tr('الرمز'),
            hintText: tr('مثال: كرتون، عبوة، قطعة'),
            prefixIcon: const Icon(PhosphorIconsLight.tag, size: 20),
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: factorController,
          decoration:  InputDecoration(
            labelText: tr('معامل التحويل الافتراضي'),
            hintText: '1.0',
            prefixIcon: const Icon(PhosphorIconsLight.arrowsCounterClockwise, size: 20),
          ),
          keyboardType: TextInputType.number,
        ),
      ],
    );
  }

  @override
  Future<bool> onSave() async {
    final name = nameController.text.trim();
    final symbol = symbolController.text.trim();
    final factor = double.tryParse(factorController.text) ?? 1.0;

    if (name.isEmpty || symbol.isEmpty) {
      throw 'يرجى ملء اسم الوحدة والرمز';
    }

    final repo = ref.read(productRepositoryProvider);
    if (widget.existing == null) {
      await repo.insertUnit(UnitsCompanion.insert(
        name: name,
        symbol: symbol,
        conversionFactor: Value(factor),
      ));
    } else {
      await repo.updateUnit(widget.existing!.copyWith(
        name: name,
        symbol: symbol,
        conversionFactor: factor,
      ));
    }

    return true;
  }
}
