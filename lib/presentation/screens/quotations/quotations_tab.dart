import 'dart:async';
import 'package:flutter/material.dart';
import 'dart:ui' as ui;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/number_utils.dart';
import '../../../core/widgets/app_state_view.dart';
import '../../../core/widgets/shimmer_loading.dart';
import 'quotations_controller.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../data/providers/providers.dart';
import '../../../services/invoice_generator.dart';
import '../../../domain/entities/quotation_entity.dart';

class QuotationsTab extends ConsumerStatefulWidget {
  final void Function(QuotationEntity)? onEditQuotation;
  final void Function(QuotationEntity)? onConvertQuotation;

  const QuotationsTab({
    super.key,
    this.onEditQuotation,
    this.onConvertQuotation,
  });

  @override
  ConsumerState<QuotationsTab> createState() => _QuotationsTabState();
}

class _QuotationsTabState extends ConsumerState<QuotationsTab> {
  final _searchController = TextEditingController();
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      final state = ref.read(quotationsControllerProvider);
      if (!state.isLoading && state.hasMore) {
        ref.read(quotationsControllerProvider.notifier).loadQuotations();
      }
    }
  }

  Future<void> _showQuotationDetails(int quotationId) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    // Close the loading indicator exactly once, from whichever branch
    // completes first (success, empty result, error, or timeout).
    var loadingClosed = false;
    void closeLoading() {
      if (loadingClosed) return;
      loadingClosed = true;
      if (mounted) Navigator.pop(context);
    }

    QuotationEntity? details;
    try {
      details = await ref
          .read(quotationsRepositoryProvider)
          .getQuotationWithDetails(quotationId)
          .timeout(const Duration(seconds: 10));
    } on TimeoutException {
      closeLoading();
      if (mounted) {
        AppToast.show(
          context,
          'انتهت مهلة تحميل تفاصيل العرض — تأكد من الاتصال بالسيرفر',
          type: ToastType.error,
        );
      }
      return;
    } catch (e) {
      closeLoading();
      if (mounted) {
        AppToast.show(context, 'حدث خطأ غير متوقع', type: ToastType.error);
      }
      return;
    }

    closeLoading();
    if (!mounted) return;

    if (details == null) {
      AppToast.show(
        context,
        'فشل في تحميل تفاصيل العرض',
        type: ToastType.error,
      );
      return;
    }

    // Promote to non-null for use inside the builder closure — Dart's flow
    // analysis doesn't carry the `details != null` check into nested closures.
    final loaded = details;

    try {
      showDialog(
        context: context,
        builder: (dialogCtx) => AlertDialog(
          title: Text('عرض سعر #${loaded.quotationNumber}'),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('العميل: ${loaded.customerName ?? "نقدي"}'),
                Text('بواسطة: ${loaded.userName}'),
                Text(
                  'التاريخ: ${DateFormat('yyyy-MM-dd').format(loaded.quotationDate)}',
                ),
                const Divider(),
                Expanded(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: loaded.items.length,
                    itemBuilder: (context, index) {
                      final item = loaded.items[index];
                      return ListTile(
                        title: Text(item.productName ?? 'صنف غير معروف'),
                        subtitle: Text(
                          '${item.quantity} x ${NumberUtils.formatCurrency(item.unitPrice)}',
                        ),
                        trailing: Text(
                          NumberUtils.formatCurrency(item.total),
                        ),
                      );
                    },
                  ),
                ),
                const Divider(),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'الإجمالي',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                      ),
                    ),
                    Text(
                      NumberUtils.formatCurrency(loaded.total),
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                        color: AppColors.primary,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: const Text('إغلاق'),
            ),
            IconButton(
              icon: const Icon(PhosphorIconsBold.printer),
              tooltip: 'طباعة',
              color: AppColors.primary,
              onPressed: () {
                InvoiceGenerator.printSalesInvoice(
                  invoiceNumber: loaded.quotationNumber,
                  date: loaded.quotationDate,
                  customerName: loaded.customerName,
                  items: loaded.items
                      .map(
                        (i) => InvoiceItem(
                          name: i.productName ?? 'صنف غير معروف',
                          quantity: i.quantity,
                          price: i.unitPrice,
                          total: i.total,
                        ),
                      )
                      .toList(),
                  subtotal: loaded.subtotal,
                  discount: loaded.discount,
                  tax: loaded.tax,
                  total: loaded.total,
                  paid: 0,
                  notes: loaded.notes, // ADDED: Pass quotation notes
                  title: 'عرض سعر',
                  db: ref.read(databaseProvider),
                );
              },
            ),
            if (widget.onEditQuotation != null &&
                loaded.status == 'draft')
              IconButton(
                icon: const Icon(PhosphorIconsBold.pencilSimple),
                tooltip: 'تعديل',
                color: AppColors.info,
                onPressed: () {
                  Navigator.pop(dialogCtx);
                  widget.onEditQuotation!(loaded);
                },
              ),
            if (loaded.status == 'draft')
              IconButton(
                icon: const Icon(PhosphorIconsBold.trash),
                tooltip: 'حذف',
                color: AppColors.error,
                onPressed: () async {
                  final confirm = await showDialog<bool>(
                    context: dialogCtx,
                    builder: (ctx) => AlertDialog(
                      title: const Text('حذف عرض سعر'),
                      content: Text(
                        'هل أنت متأكد من حذف عرض السعر رقم ${loaded.quotationNumber}؟',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: const Text('إلغاء'),
                        ),
                        FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.error,
                          ),
                          onPressed: () => Navigator.pop(ctx, true),
                          child: const Text('حذف'),
                        ),
                      ],
                    ),
                  );
                  if (confirm == true) {
                    await ref
                        .read(quotationsRepositoryProvider)
                        .deleteQuotationAndItems(loaded.id);
                    if (dialogCtx.mounted) {
                      // ignore: use_build_context_synchronously
                      Navigator.pop(dialogCtx);
                      ref
                          .read(quotationsControllerProvider.notifier)
                          .loadQuotations();
                    }
                    if (!context.mounted) return;
                    AppToast.show(
                      // ignore: use_build_context_synchronously
                      context,
                      'تم حذف عرض السعر بنجاح',
                      type: ToastType.success,
                    );
                  }
                },
              ),
            if (widget.onConvertQuotation != null &&
                loaded.status == 'draft')
              FilledButton.icon(
                icon: const Icon(PhosphorIconsBold.shoppingCart),
                label: const Text('تحويل إلى فاتورة'),
                onPressed: () async {
                  Navigator.pop(dialogCtx);
                  widget.onConvertQuotation!(loaded);
                },
              ),
          ],
        ),
      );
    } catch (e) {
      // Details dialog construction failed (very unusual — the loading
      // spinner is already closed at this point, so don't try to pop it
      // again). Just inform the user.
      if (mounted) {
        AppToast.show(context, 'حدث خطأ غير متوقع', type: ToastType.error);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(quotationsControllerProvider);
    final controller = ref.read(quotationsControllerProvider.notifier);

    return Column(
      children: [
        // Filters
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // Search
              Expanded(
                flex: 2,
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'بحث برقم العرض أو اسم العميل...',
                    prefixIcon: const Icon(PhosphorIconsBold.magnifyingGlass),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    isDense: true,
                  ),
                  onChanged: (val) => controller.updateSearchQuery(val),
                ),
              ),
              const SizedBox(width: 12),
              // Date Range
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(PhosphorIconsBold.calendarBlank),
                  label: Text(
                    state.dateRange != null
                        ? '${state.dateRange!.start.day}/${state.dateRange!.start.month} - ${state.dateRange!.end.day}/${state.dateRange!.end.month}'
                        : 'تاريخ',
                  ),
                  onPressed: () async {
                    final range = await showDateRangePicker(
                      context: context,
                      firstDate: DateTime(2020),
                      lastDate: DateTime.now().add(const Duration(days: 365)),
                      initialDateRange: state.dateRange,
                      builder: (context, child) {
                        return Directionality(
                          textDirection: ui.TextDirection.rtl,
                          child: Theme(
                            data: Theme.of(context).copyWith(
                              colorScheme: const ColorScheme.light(
                                primary: AppColors.primary,
                              ),
                            ),
                            child: Center(
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(
                                  maxWidth: 450,
                                  maxHeight: 600,
                                ),
                                child: child!,
                              ),
                            ),
                          ),
                        );
                      },
                    );
                    if (range != null) {
                      controller.updateDateRange(range);
                    }
                  },
                ),
              ),
              if (state.dateRange != null) ...[
                const SizedBox(width: 4),
                IconButton(
                  icon: const Icon(PhosphorIconsBold.x, size: 16),
                  tooltip: 'إلغاء فلتر التاريخ',
                  onPressed: () => controller.updateDateRange(null),
                ),
              ],
              const SizedBox(width: 12),
              // Status Filter
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'all', label: Text('الكل')),
                  ButtonSegment(value: 'draft', label: Text('مسودة')),
                  ButtonSegment(value: 'converted', label: Text('محول')),
                ],
                selected: {state.statusFilter},
                onSelectionChanged: (Set<String> newSelection) {
                  controller.updateStatusFilter(newSelection.first);
                },
                style: const ButtonStyle(visualDensity: VisualDensity.compact),
              ),
            ],
          ),
        ),

        // Data Table — Day 11: unified state via AppStateView.
        Expanded(
          child: AppStateView(
            isLoading: state.isLoading && state.quotations.isEmpty,
            isEmpty: state.quotations.isEmpty,
            emptyMessage: 'لا توجد عروض أسعار',
            emptyIcon: PhosphorIconsBold.fileText,
            loadingItemCount: 10,
            child: ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  itemCount:
                      state.quotations.length + (state.isLoading ? 1 : 0),
                  itemBuilder: (context, index) {
                    if (index == state.quotations.length) {
                      return const Center(
                        child: Padding(
                          padding: EdgeInsets.all(16),
                          child: CircularProgressIndicator(),
                        ),
                      );
                    }

                    final quotation = state.quotations[index];
                    final isConverted = quotation.status == 'converted';

                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        leading: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: isConverted
                                ? AppColors.success.withValues(alpha: 0.1)
                                : AppColors.info.withValues(alpha: 0.1),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            isConverted
                                ? PhosphorIconsBold.checkCircle
                                : PhosphorIconsBold.fileText,
                            color: isConverted
                                ? AppColors.success
                                : AppColors.info,
                          ),
                        ),
                        title: Row(
                          children: [
                            Text(
                              quotation.quotationNumber,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color:
                                    (isConverted
                                            ? AppColors.success
                                            : AppColors.warning)
                                        .withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(
                                  color:
                                      (isConverted
                                              ? AppColors.success
                                              : AppColors.warning)
                                          .withValues(alpha: 0.3),
                                ),
                              ),
                              child: Text(
                                isConverted ? 'محول' : 'مسودة',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: isConverted
                                      ? AppColors.success
                                      : AppColors.warning,
                                ),
                              ),
                            ),
                          ],
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                const Icon(
                                  PhosphorIconsBold.user,
                                  size: 14,
                                  color: AppColors.textMuted,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  quotation.customerName ?? 'عميل نقدي',
                                  style: const TextStyle(fontSize: 12),
                                ),
                                const SizedBox(width: 16),
                                const Icon(
                                  PhosphorIconsBold.calendar,
                                  size: 14,
                                  color: AppColors.textMuted,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  DateFormat(
                                    'yyyy-MM-dd HH:mm',
                                  ).format(quotation.quotationDate),
                                  style: const TextStyle(fontSize: 12),
                                ),
                              ],
                            ),
                          ],
                        ),
                        trailing: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              NumberUtils.formatCurrency(quotation.total),
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                                color: AppColors.primary,
                              ),
                            ),
                          ],
                        ),
                        onTap: () {
                          _showQuotationDetails(quotation.id);
                        },
                      ),
                    );
                  },
                ), // ListView.builder
          ), // AppStateView
        ), // Expanded
      ],
    );
  }
}
