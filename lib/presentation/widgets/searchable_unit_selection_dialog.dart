import 'package:picpos_erp/core/i18n/tr.dart';
import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/database/database.dart';

class SearchableUnitSelectionDialog extends StatefulWidget {
  final List<ProductUnit> units;
  final String? currentUnitName;

  const SearchableUnitSelectionDialog({
    super.key,
    required this.units,
    this.currentUnitName,
  });

  @override
  State<SearchableUnitSelectionDialog> createState() => _SearchableUnitSelectionDialogState();
}

class _SearchableUnitSelectionDialogState extends State<SearchableUnitSelectionDialog> {
  final _searchController = TextEditingController();
  List<ProductUnit> _filteredUnits = [];

  @override
  void initState() {
    super.initState();
    _filteredUnits = widget.units;
    _searchController.addListener(_filterUnits);
  }

  void _filterUnits() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      _filteredUnits = widget.units.where((u) {
        return u.unitName.toLowerCase().contains(query);
      }).toList();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 400,
        height: 500,
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                const Icon(PhosphorIconsBold.listMagnifyingGlass, color: AppColors.primary),
                const SizedBox(width: 12),
                 Text(
                  tr('اختر وحدة القياس'),
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(PhosphorIconsBold.x),
                ),
              ],
            ),
            const Divider(),
            TextField(
              controller: _searchController,
              autofocus: true,
              decoration: InputDecoration(
                hintText: tr('بحث عن وحدة...'),
                prefixIcon: const Icon(PhosphorIconsBold.magnifyingGlass),
                filled: true,
                fillColor: AppColors.primary.withValues(alpha: 0.05),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: _filteredUnits.isEmpty
                  ?  Center(child: Text(tr('لا توجد وحدات مطابقة')))
                  : ListView.separated(
                      itemCount: _filteredUnits.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final unit = _filteredUnits[index];
                        final isSelected = unit.unitName == widget.currentUnitName;

                        return ListTile(
                          onTap: () => Navigator.pop(context, unit),
                          leading: Icon(
                            isSelected ? PhosphorIconsBold.checkCircle : PhosphorIconsBold.circle,
                            color: isSelected ? AppColors.success : AppColors.textMuted,
                          ),
                          title: Text(
                            unit.unitName,
                            style: TextStyle(
                              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                              color: isSelected ? AppColors.primary : null,
                            ),
                          ),
                          subtitle: Text(tr('معامل التحويل: ×{p0}', {'p0': unit.quantityInBase.toStringAsFixed(0)})),
                          trailing: Text(
                            '${unit.salePrice.toStringAsFixed(AppConstants.decimalPlaces)} ${AppConstants.currencySymbol}',
                            style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.success),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
