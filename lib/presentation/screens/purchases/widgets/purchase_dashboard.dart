import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/shimmer_loading.dart';
import '../../../../data/providers/providers.dart';
import '../../../../domain/entities/invoice_entity.dart' hide InvoiceStatus;
import '../purchases.dart';
import '../../../../../../../core/constants/app_constants.dart';

class PurchaseDashboard extends ConsumerWidget {
  final TabController tabController;
  final Function(InvoiceEntity) onEdit;
  final Function(InvoiceEntity) onView;
  final Function(InvoiceEntity) onPrint;
  final Function(InvoiceEntity, double) onPayment;

  const PurchaseDashboard({
    super.key,
    required this.tabController,
    required this.onEdit,
    required this.onView,
    required this.onPrint,
    required this.onPayment,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final invoices = ref.watch(purchaseInvoicesProvider);

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          // Summary Cards
          invoices.when(
            data: (invs) {
              final today = DateTime.now();
              final todayInvoices = invs
                  .where(
                    (i) =>
                        i.invoiceDate.day == today.day &&
                        i.invoiceDate.month == today.month &&
                        i.invoiceDate.year == today.year,
                  )
                  .toList();
              final totalToday = todayInvoices.fold<double>(
                0,
                (sum, i) => sum + i.total,
              );
              final totalUnpaid = invs
                  .where((i) => i.status.name != 'paid')
                  .fold<double>(0, (sum, i) => sum + (i.total - i.paid));

              return Row(
                children: [
                  _buildSummaryCard(
                    context,
                    'إجمالي الفواتير',
                    invs.length.toString(),
                    PhosphorIconsBold.receipt,
                    AppColors.primary,
                  ),
                  const SizedBox(width: 16),
                  _buildSummaryCard(
                    context,
                    'فواتير اليوم',
                    todayInvoices.length.toString(),
                    PhosphorIconsBold.calendarCheck,
                    AppColors.info,
                  ),
                  const SizedBox(width: 16),
                  _buildSummaryCard(
                    context,
                    'مشتريات اليوم',
                    '${totalToday.toStringAsFixed(AppConstants.decimalPlaces)} ${AppConstants.currencySymbolEn}',
                    PhosphorIconsBold.currencyCircleDollar,
                    AppColors.success,
                  ),
                  const SizedBox(width: 16),
                  _buildSummaryCard(
                    context,
                    'مستحق للموردين',
                    '${totalUnpaid.toStringAsFixed(AppConstants.decimalPlaces)} ${AppConstants.currencySymbolEn}',
                    PhosphorIconsBold.wallet,
                    AppColors.error,
                  ),
                ],
              );
            },
            loading: () => const SizedBox.shrink(),
            error: (e, s) => const SizedBox.shrink(),
          ),
          const SizedBox(height: 24),

          // Invoices Table
          Expanded(
            child: Card(
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: invoices.when(
                data: (invs) {
                  if (invs.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            PhosphorIconsBold.shoppingCart,
                            size: 64,
                            color: AppColors.textMuted.withValues(alpha: 0.5),
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            'لا توجد فواتير شراء',
                            style: TextStyle(
                              color: AppColors.textMuted,
                              fontSize: 18,
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'اضغط على "فاتورة شراء جديدة" لإضافة أول فاتورة',
                            style: TextStyle(color: AppColors.textMuted),
                          ),
                        ],
                      ),
                    );
                  }

                  return SingleChildScrollView(
                    child: DataTable(
                      headingRowColor: WidgetStateProperty.all(
                        Theme.of(context).scaffoldBackgroundColor,
                      ),
                      columns: const [
                        DataColumn(
                          label: Text(
                            'رقم الفاتورة',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                        DataColumn(
                          label: Text(
                            'المورد',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                        DataColumn(
                          label: Text(
                            'التاريخ',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                        DataColumn(
                          label: Text(
                            'الإجمالي',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                        DataColumn(
                          label: Text(
                            'المدفوع',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                        DataColumn(
                          label: Text(
                            'الحالة',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                        DataColumn(
                          label: Text(
                            'إجراءات',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                      rows: invs.map((inv) {
                        final remaining = inv.total - inv.paid;
                        return DataRow(
                          cells: [
                            DataCell(Text(inv.invoiceNumber)),
                            DataCell(
                              FutureBuilder<Party?>(
                                future: ref
                                    .read(partiesRepositoryProvider)
                                    .getPartyById(inv.partyId ?? 0),
                                builder: (context, snapshot) =>
                                    Text(snapshot.data?.name ?? '...'),
                              ),
                            ),
                            DataCell(
                              Text(
                                '${inv.invoiceDate.day}/${inv.invoiceDate.month}/${inv.invoiceDate.year}',
                              ),
                            ),
                            DataCell(
                              Text(
                                '${inv.total.toStringAsFixed(AppConstants.decimalPlaces)} ${AppConstants.currencySymbolEn}',
                              ),
                            ),
                            DataCell(
                              Text(
                                '${inv.paid.toStringAsFixed(AppConstants.decimalPlaces)} ${AppConstants.currencySymbolEn}',
                              ),
                            ),
                            DataCell(_buildStatusBadge(inv.status.name, remaining)),
                            DataCell(
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: const Icon(PhosphorIconsBold.eye),
                                    iconSize: 18,
                                    color: AppColors.primary,
                                    tooltip: 'عرض',
                                    onPressed: () => onView(inv),
                                  ),
                                  IconButton(
                                    icon: const Icon(PhosphorIconsBold.printer),
                                    iconSize: 18,
                                    color: AppColors.info,
                                    tooltip: 'طباعة',
                                    onPressed: () => onPrint(inv),
                                  ),
                                  IconButton(
                                    icon: const Icon(
                                      PhosphorIconsBold.pencilSimple,
                                    ),
                                    iconSize: 18,
                                    color: AppColors.warning,
                                    tooltip: 'تعديل',
                                    onPressed: () => onEdit(inv),
                                  ),
                                  if (remaining > 0)
                                    IconButton(
                                      icon: const Icon(
                                        PhosphorIconsBold.currencyCircleDollar,
                                      ),
                                      iconSize: 18,
                                      color: AppColors.success,
                                      tooltip: 'دفع',
                                      onPressed: () =>
                                          onPayment(inv, remaining),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        );
                      }).toList(),
                    ),
                  );
                },
                loading: () => Padding(
                  padding: const EdgeInsets.all(16),
                  child: ShimmerLoading.list(itemCount: 6),
                ),
                error: (e, _) => Center(child: Text('خطأ: $e')),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryCard(
    BuildContext context,
    String title,
    String value,
    IconData icon,
    Color color,
  ) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 28),
            ),
            const SizedBox(width: 16),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(color: AppColors.textMuted, fontSize: 14),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusBadge(String status, double remaining) {
    Color color;
    String text;

    if (status == 'paid') {
      color = AppColors.success;
      text = 'مدفوع';
    } else if (remaining <= 0) {
      color = AppColors.success;
      text = 'مسدد';
    } else if (status == 'partial') {
      color = AppColors.warning;
      text = 'جزئي';
    } else {
      color = AppColors.error;
      text = 'غير مدفوع';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
