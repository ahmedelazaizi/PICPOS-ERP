import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
// `SalesInvoiceItemWithProduct` يجي من `providers.dart` — ملف `projections.dart`
// نفسه `part of` قاعدة البيانات فمايتستوردش مباشرة.
import '../../../data/providers/providers.dart';

/// The item lines of a posted sales invoice plus its total.
///
/// Extracted from `PosPreviousInvoicesDialog._showInvoiceDetails` so the PicPos
/// «الفاتورة السابقة» dialog renders lines the same way rather than growing a
/// second, drifting copy. Shared by both tills.
///
/// ── The N+1 this fixes ────────────────────────────────────────────────────
/// The original loaded items with `getSalesInvoiceItems`, then resolved names
/// with one `productRepo.getProductById` per DISTINCT product before the dialog
/// could paint — a 20-line invoice meant up to 21 round trips. `SalesRepository
/// .getInvoiceItemsWithProduct` is a single left-outer join that already
/// carries the product, and its `displayName` handles a hard-deleted product
/// (`'صنف محذوف #id'`), which the old `productMap` fallback also did. So this
/// is strictly fewer queries for the same output.
class PosInvoiceItemsView extends ConsumerWidget {
  final int invoiceId;

  /// Invoice total, shown in the footer. Passed in rather than summed from the
  /// lines on purpose: the header total is the posted figure (after invoice-
  /// level discount and tax), and re-deriving it here would let this widget
  /// disagree with every other screen that quotes the same invoice.
  final double invoiceTotal;

  final double maxHeight;

  const PosInvoiceItemsView({
    super.key,
    required this.invoiceId,
    required this.invoiceTotal,
    this.maxHeight = 400,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final salesRepo = ref.read(salesRepositoryProvider);

    return FutureBuilder<List<SalesInvoiceItemWithProduct>>(
      future: salesRepo.getInvoiceItemsWithProduct(invoiceId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 32),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasError) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Text(
              'تعذّر تحميل أصناف الفاتورة: ${snapshot.error}',
              style: const TextStyle(color: AppColors.error),
            ),
          );
        }

        final rows = snapshot.data ?? const <SalesInvoiceItemWithProduct>[];

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (rows.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Text(
                  'لا توجد أصناف في هذه الفاتورة',
                  style: TextStyle(color: AppColors.textMuted),
                ),
              )
            else
              ConstrainedBox(
                constraints: BoxConstraints(maxHeight: maxHeight),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: rows.length,
                  itemBuilder: (context, index) {
                    final row = rows[index];
                    return ListTile(
                      dense: true,
                      title: Text(
                        row.displayName,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Text(
                        '${row.item.quantity} × '
                        '${row.item.unitPrice.toStringAsFixed(AppConstants.decimalPlaces)} '
                        '${AppConstants.currencySymbolAr}',
                      ),
                      trailing: Text(
                        '${row.item.total.toStringAsFixed(AppConstants.decimalPlaces)} '
                        '${AppConstants.currencySymbolAr}',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    );
                  },
                ),
              ),
            const Divider(),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'الإجمالي (${rows.length} صنف)',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Text(
                    '${invoiceTotal.toStringAsFixed(AppConstants.decimalPlaces)} '
                    '${AppConstants.currencySymbolAr}',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: AppColors.success,
                      fontSize: 18,
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}
