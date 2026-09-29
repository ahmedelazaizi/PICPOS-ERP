import 'package:ural_erp/core/i18n/tr.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../data/providers/parties_providers.dart';
import '../../../widgets/searchable_dropdown.dart';
import '../../providers/pos_controller.dart';

class CartDeliveryPanel extends ConsumerWidget {
  final PosState state;
  final PosController controller;
  final double scaleFactor;

  const CartDeliveryPanel({
    super.key,
    required this.state,
    required this.controller,
    required this.scaleFactor,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (state.selectedCustomerId == null) return const SizedBox.shrink();

    final companiesAsync = ref.watch(allDeliveryCompaniesProvider);
    final fontSize = 13.0 * scaleFactor;
    final iconSize = 18.0 * scaleFactor;
    final spacing = 8.0 * scaleFactor;

    return Container(
      padding: EdgeInsets.all(8 * scaleFactor),
      decoration: BoxDecoration(
        color: state.deliveryStatus != null
            ? AppColors.info.withValues(alpha: 0.05)
            : null,
        border: Border.all(
          color: state.deliveryStatus != null
              ? AppColors.info.withValues(alpha: 0.3)
              : AppColors.border,
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(
                PhosphorIconsBold.truck,
                size: iconSize,
                color: state.deliveryStatus != null
                    ? AppColors.info
                    : AppColors.textMuted,
              ),
              SizedBox(width: spacing),
              Text(
                tr('توصيل الطلب'),
                style: TextStyle(
                  fontSize: fontSize,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              SizedBox(
                height: 24 * scaleFactor,
                child: Switch(
                  value: state.deliveryStatus != null,
                  onChanged: (v) {
                    controller.setDeliveryInfo(status: v ? 'pending' : null);
                  },
                ),
              ),
            ],
          ),
          if (state.deliveryStatus != null) ...[
            SizedBox(height: spacing),
            Row(
              children: [
                Expanded(
                  child: companiesAsync.when(
                    data: (companies) => SearchableDropdown(
                      items: companies,
                      value: companies
                          .where((c) => c.id == state.deliveryCompanyId)
                          .firstOrNull,
                      hint: tr('اختر شركة التوصيل'),
                      searchHint: tr('ابحث عن شركة...'),
                      labelBuilder: (c) => c.name,
                      onChanged: (c) =>
                          controller.setDeliveryInfo(companyId: c?.id),
                    ),
                    loading: () =>  Text(tr('جاري التحميل...')),
                    error: (_, _) =>  Text(tr('خطأ')),
                  ),
                ),
                SizedBox(width: spacing),
                Expanded(
                  child: TextField(
                    decoration: InputDecoration(
                      labelText: tr('رسوم التوصيل'),
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 8 * scaleFactor,
                        vertical: 8 * scaleFactor,
                      ),
                      border: const OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                    onChanged: (v) =>
                        controller.setDeliveryInfo(status: 'pending'),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
