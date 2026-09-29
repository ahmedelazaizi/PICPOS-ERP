import 'package:ural_erp/core/i18n/tr.dart';
// صفُّ ملخّص المخزون بهويّة PicPos — **فوركٌ بقرار المالك 2026-08-22**.
//
// المصدر: `screens/inventory/widgets/inventory_summary_row.dart`، ويبقى بلا
// مساسٍ لشاشة UralCash.
//
// ⚠️ **و`InventorySummaryCard` تُستورَد ولا تُنسَخ**: بطاقةٌ صغيرةٌ لم يطلب
// التصميمُ تغييرَها، ونسخُها كان سيضاعف ملفّاً بلا سبب. ‏(صفُّ عدّاداتِ
// التصميم نفسُه — `invKpis` — يُرسم في الشاشة بـ`PicPosKpiRow` المشتركة، وهذا
// الصفُّ شيءٌ آخر يعرض قيمةَ المخزون وتكلفتَه.)
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/shimmer_loading.dart';
import '../../../data/providers/inventory_providers.dart';
import '../../screens/inventory/widgets/inventory_summary_card.dart';
import '../../../core/constants/app_constants.dart';

class InventorySummaryRowPicpos extends ConsumerWidget {
  const InventorySummaryRowPicpos({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Spec 136 ISS-9 — totals come from a cheap SQL aggregate, not from
    // mapping the whole product catalog (which caused a 762ms stall).
    final summaryAsync = ref.watch(inventorySummaryProvider);
    return summaryAsync.when(
      data: (s) {
        final totalActive = s.activeCount;
        final lowStock = s.lowStockCount;
        final totalValue = s.totalValue;

        return Row(
          children: [
            InventorySummaryCard(
              title: tr('إجمالي الأصناف'),
              value: totalActive.toString(),
              icon: PhosphorIconsBold.listBullets,
              color: AppColors.primary,
            ),
            const SizedBox(width: 16),
            InventorySummaryCard(
              title: tr('تنبيهات انخفاض المخزون'),
              value: lowStock.toString(),
              icon: PhosphorIconsBold.warningCircle,
              color: AppColors.warning,
            ),
            const SizedBox(width: 16),
            InventorySummaryCard(
              title: tr('إجمالي قيمة المخزون'),
              value:
                  '${totalValue.toStringAsFixed(AppConstants.decimalPlaces)} ${AppConstants.currencySymbolEn}',
              icon: PhosphorIconsBold.coins,
              color: AppColors.success,
            ),
          ],
        );
      },
      loading: () => Row(
        children: List.generate(
          3,
          (index) => Expanded(child: ShimmerLoading.card()),
        ),
      ),
      error: (_, _) => const SizedBox.shrink(),
    );
  }
}
