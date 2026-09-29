import 'package:ural_erp/core/i18n/tr.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:intl/intl.dart' as intl;
import '../../../../core/constants/app_constants.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../data/providers/providers.dart';
import '../../../../core/widgets/shimmer_loading.dart';
import '../../../widgets/branch_chip.dart';
import '../sales_invoices_notifier.dart';

class SalesInvoicesDashboard extends ConsumerStatefulWidget {
  final Function(SalesInvoiceData) onView;
  final Function(SalesInvoiceData) onPrint;
  final Function(SalesInvoiceData) onReturn;
  final Function(SalesInvoiceData) onDelete;
  final Function(SalesInvoicesFormNotifier) onCreateNew;

  const SalesInvoicesDashboard({
    super.key,
    required this.onView,
    required this.onPrint,
    required this.onReturn,
    required this.onDelete,
    required this.onCreateNew,
  });

  @override
  ConsumerState<SalesInvoicesDashboard> createState() =>
      _SalesInvoicesDashboardState();
}

class _SalesInvoicesDashboardState
    extends ConsumerState<SalesInvoicesDashboard> {
  final _searchController = TextEditingController();
  String _statusFilter = 'all';
  String _saleTypeFilter = 'all'; // POS-6: order type filter
  DateTime? _startDate;
  DateTime? _endDate;
  final _currencyFormat = intl.NumberFormat.currency(
    symbol: '',
    decimalDigits: AppConstants.decimalPlaces,
  );

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final salesRepo = ref.watch(salesRepositoryProvider);
    final invoicesStream = salesRepo.watchAllRawInvoices();

    return StreamBuilder<List<SalesInvoiceData>>(
      stream: invoicesStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: ShimmerLoading(height: 400));
        }

        if (snapshot.hasError) {
          return Center(child: Text(tr('خطأ: {p0}', {'p0': snapshot.error})));
        }

        final allInvoices = snapshot.data ?? [];

        // Filtering
        final filteredInvoices = allInvoices.where((inv) {
          final matchesSearch =
              inv.invoiceNumber.contains(_searchController.text) ||
              (inv.notes?.contains(_searchController.text) ?? false);

          final matchesStatus =
              _statusFilter == 'all' ||
              (_statusFilter == 'paid' && inv.paid >= inv.total) ||
              (_statusFilter == 'pending' && inv.paid < inv.total) ||
              (_statusFilter == 'returned' && inv.status == 'returned');

          final matchesDate =
              (_startDate == null || inv.createdAt.isAfter(_startDate!)) &&
              (_endDate == null ||
                  inv.createdAt.isBefore(
                    _endDate!.add(const Duration(days: 1)),
                  ));

          // POS-6: filter by order type
          final matchesSaleType = _saleTypeFilter == 'all' ||
              inv.saleType == _saleTypeFilter ||
              (_saleTypeFilter == 'internal' && (inv.saleType == 'default' || inv.saleType == 'internal'));

          return matchesSearch && matchesStatus && matchesDate && matchesSaleType;
        }).toList();

        // Summary Calculations
        final totalSales = filteredInvoices
            .where((i) => i.status != 'returned')
            .fold(0.0, (sum, i) => sum + i.total);
        final totalPaid = filteredInvoices
            .where((i) => i.status != 'returned')
            .fold(0.0, (sum, i) => sum + i.paid);
        final totalReturns = filteredInvoices
            .where((i) => i.status == 'returned')
            .fold(0.0, (sum, i) => sum + i.total);
        final todayInvoices = allInvoices
            .where(
              (i) =>
                  i.createdAt.year == DateTime.now().year &&
                  i.createdAt.month == DateTime.now().month &&
                  i.createdAt.day == DateTime.now().day,
            )
            .toList();

        return Column(
          children: [
            // Summary Cards
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                children: [
                  _buildSummaryCard(
                    tr('إجمالي المبيعات'),
                    _currencyFormat.format(totalSales),
                    PhosphorIconsBold.money,
                    AppColors.success,
                  ),
                  const SizedBox(width: 16),
                  _buildSummaryCard(
                    tr('إجمالي التحصيل'),
                    _currencyFormat.format(totalPaid),
                    PhosphorIconsBold.handCoins,
                    AppColors.primary,
                  ),
                  const SizedBox(width: 16),
                  _buildSummaryCard(
                    tr('إجمالي المرتجعات'),
                    _currencyFormat.format(totalReturns),
                    PhosphorIconsBold.arrowUUpLeft,
                    AppColors.error,
                  ),
                  const SizedBox(width: 16),
                  _buildSummaryCard(
                    tr('فواتير اليوم'),
                    todayInvoices.length.toString(),
                    PhosphorIconsBold.calendarCheck,
                    AppColors.info,
                  ),
                ],
              ),
            ),

            // Filters Bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _searchController,
                          decoration:  InputDecoration(
                            hintText: tr('بحث برقم الفاتورة أو الملاحظات...'),
                            prefixIcon: const Icon(PhosphorIconsBold.magnifyingGlass),
                            border: const OutlineInputBorder(),
                            isDense: true,
                          ),
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                      const SizedBox(width: 16),
                      DropdownButton<String>(
                        value: _statusFilter,
                        items:  [
                          DropdownMenuItem(
                            value: 'all',
                            child: Text(tr('كل الفواتير')),
                          ),
                          DropdownMenuItem(
                            value: 'paid',
                            child: Text(tr('مدفوعة بالكامل')),
                          ),
                          DropdownMenuItem(
                            value: 'pending',
                            child: Text(tr('متبقي')),
                          ),
                          DropdownMenuItem(
                            value: 'returned',
                            child: Text(tr('مرتجع')),
                          ),
                        ],
                        onChanged: (val) =>
                            setState(() => _statusFilter = val!),
                      ),
                      const SizedBox(width: 12),
                      // POS-6: Order type filter
                      DropdownButton<String>(
                        value: _saleTypeFilter,
                        items:  [
                          DropdownMenuItem(value: 'all', child: Text(tr('كل الأنواع'))),
                          DropdownMenuItem(value: 'internal', child: Text(tr('داخلي'))),
                          DropdownMenuItem(value: 'delivery', child: Text(tr('توصيل'))),
                          DropdownMenuItem(value: 'talabat', child: Text(tr('طلبات'))),
                          DropdownMenuItem(value: 'careem', child: Text(tr('كريم'))),
                        ],
                        onChanged: (val) =>
                            setState(() => _saleTypeFilter = val!),
                      ),
                      const SizedBox(width: 16),
                      ElevatedButton.icon(
                        onPressed: () {
                          ref
                              .read(salesInvoicesFormProvider.notifier)
                              .clearForm();
                          widget.onCreateNew(
                            ref.read(salesInvoicesFormProvider.notifier),
                          );
                        },
                        icon: const Icon(PhosphorIconsBold.plus),
                        label:  Text(tr('فاتورة جديدة')),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // Invoices Table
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Card(
                  child: filteredInvoices.isEmpty
                      ?  Center(child: Text(tr('لا توجد فواتير تطابق البحث')))
                      : SingleChildScrollView(
                          scrollDirection: Axis.vertical,
                          child: PaginatedDataTable(
                            header:  Text(tr('سجل الفواتير')),
                            columns:  [
                              DataColumn(label: Text(tr('الرقم'))),
                              DataColumn(label: Text(tr('التاريخ'))),
                              DataColumn(label: Text(tr('الفرع'))),
                              DataColumn(label: Text(tr('العميل'))),
                              DataColumn(label: Text(tr('نوع الطلب'))),
                              DataColumn(label: Text(tr('الإجمالي'))),
                              DataColumn(label: Text(tr('المدفوع'))),
                              DataColumn(label: Text(tr('الحالة'))),
                              DataColumn(label: Text(tr('الإجراءات'))),
                            ],
                            source: _InvoicesDataSource(
                              invoices: filteredInvoices,
                              onView: widget.onView,
                              onPrint: widget.onPrint,
                              onReturn: widget.onReturn,
                              onDelete: widget.onDelete,
                              currencyFormat: _currencyFormat,
                            ),
                            rowsPerPage: 10,
                            showFirstLastButtons: true,
                          ),
                        ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildSummaryCard(
    String title,
    String value,
    IconData icon,
    Color color,
  ) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 32),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textMuted,
                  ),
                ),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _InvoicesDataSource extends DataTableSource {
  final List<SalesInvoiceData> invoices;
  final Function(SalesInvoiceData) onView;
  final Function(SalesInvoiceData) onPrint;
  final Function(SalesInvoiceData) onReturn;
  final Function(SalesInvoiceData) onDelete;
  final intl.NumberFormat currencyFormat;

  _InvoicesDataSource({
    required this.invoices,
    required this.onView,
    required this.onPrint,
    required this.onReturn,
    required this.onDelete,
    required this.currencyFormat,
  });

  @override
  DataRow? getRow(int index) {
    if (index >= invoices.length) return null;
    final inv = invoices[index];
    final isReturned = inv.status == 'returned';

    return DataRow(
      cells: [
        DataCell(
          Text(
            inv.invoiceNumber,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
        DataCell(
          Text(intl.DateFormat('yyyy/MM/dd HH:mm').format(inv.createdAt)),
        ),
        // Feature 004 — branch chip column. Hidden when invoice has no
        // branch link (legacy data); same colour-per-branch convention as
        // journal entries and treasury for visual consistency.
        DataCell(BranchChip(branchId: inv.branchId, compact: true)),
        DataCell(
          Text(
            inv.customerId != null ? tr('عميل #{p0}', {'p0': inv.customerId}) : tr('عميل نقدي'),
          ),
        ),
        // POS-6: Order type cell
        DataCell(
          Text(
            _saleTypeLabel(inv.saleType),
            style: TextStyle(
              fontSize: 12,
              color: inv.saleType == 'default' || inv.saleType == 'internal'
                  ? AppColors.info
                  : AppColors.warning,
            ),
          ),
        ),
        DataCell(Text(currencyFormat.format(inv.total))),
        DataCell(Text(currencyFormat.format(inv.paid))),
        DataCell(
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: isReturned
                  ? AppColors.error.withValues(alpha: 0.1)
                  : (inv.paid >= inv.total
                        ? AppColors.success.withValues(alpha: 0.1)
                        : AppColors.warning.withValues(alpha: 0.1)),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              isReturned
                  ? tr('مرتجع')
                  : (inv.paid >= inv.total ? tr('مدفوعة') : tr('متبقي')),
              style: TextStyle(
                color: isReturned
                    ? AppColors.error
                    : (inv.paid >= inv.total
                          ? AppColors.success
                          : AppColors.warning),
                fontSize: 12,
              ),
            ),
          ),
        ),
        DataCell(
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(PhosphorIconsBold.eye, size: 18),
                onPressed: () => onView(inv),
                color: AppColors.primary,
              ),
              IconButton(
                icon: const Icon(PhosphorIconsBold.printer, size: 18),
                onPressed: () => onPrint(inv),
                color: AppColors.info,
              ),
              if (!isReturned)
                IconButton(
                  icon: const Icon(PhosphorIconsBold.arrowUUpLeft, size: 18),
                  onPressed: () => onReturn(inv),
                  color: AppColors.warning,
                ),
              IconButton(
                icon: const Icon(PhosphorIconsBold.trash, size: 18),
                onPressed: () => onDelete(inv),
                color: AppColors.error,
              ),
            ],
          ),
        ),
      ],
    );
  }

  static String _saleTypeLabel(String type) {
    switch (type) {
      case 'delivery': return tr('توصيل');
      case 'talabat': return tr('طلبات');
      case 'careem': return tr('كريم');
      case 'ashyae': return tr('أشياء');
      case 'internal': return tr('داخلي');
      default: return 'داخلي';
    }
  }

  @override
  bool get isRowCountApproximate => false;

  @override
  int get rowCount => invoices.length;

  @override
  int get selectedRowCount => 0;
}
