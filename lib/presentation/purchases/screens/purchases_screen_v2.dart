// ignore_for_file: avoid_dynamic_calls
import 'package:flutter/material.dart';
import 'package:ural_erp/core/widgets/app_toast.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../core/theme/app_colors.dart';

import '../../../core/logging/app_logger.dart';
import '../../../data/providers/providers.dart';
import '../../../services/invoice_generator.dart';
import '../providers/purchases_controller.dart';
import '../widgets/purchase_cart_view.dart';
import '../../screens/purchases/purchases_form_notifier.dart'
    show purchaseInvoicesProvider, purchasesWithSupplierProvider;
import '../../../../../../core/constants/app_constants.dart';

/// Purchases Screen V2 - Clean Architecture
/// Target: < 300 lines
class PurchasesScreenV2 extends ConsumerStatefulWidget {
  const PurchasesScreenV2({super.key});

  @override
  ConsumerState<PurchasesScreenV2> createState() => _PurchasesScreenV2State();
}

class _PurchasesScreenV2State extends ConsumerState<PurchasesScreenV2>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    logger.info('PurchasesScreenV2 initialized', correlationId: 'PURCHASES');
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: _buildAppBar(),
      body: TabBarView(
        controller: _tabController,
        children: [_buildDashboardTab(), _buildNewInvoiceTab()],
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      title: const Text('المشتريات'),
      bottom: TabBar(
        controller: _tabController,
        labelColor: Colors.white,
        unselectedLabelColor: Colors.white70,
        indicatorColor: Colors.white,
        indicatorWeight: 3,
        tabs: const [
          Tab(icon: Icon(PhosphorIconsBold.chartBar), text: 'لوحة القيادة'),
          Tab(icon: Icon(PhosphorIconsBold.plus), text: 'فاتورة جديدة'),
        ],
      ),
      actions: [
        IconButton(
          icon: const Icon(PhosphorIconsBold.arrowClockwise),
          tooltip: 'تحديث',
          onPressed: () => ref.invalidate(purchaseInvoicesProvider),
        ),
      ],
    );
  }

  Widget _buildDashboardTab() {
    final invoicesAsync = ref.watch(purchasesWithSupplierProvider);

    return invoicesAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('خطأ: $e')),
      data: (invoices) {
        if (invoices.isEmpty) return _buildEmptyState();
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: invoices.length,
          itemBuilder: (context, index) => _buildInvoiceCard(invoices[index]),
        );
      },
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            PhosphorIconsBold.shoppingCart,
            size: 80,
            color: AppColors.textMuted.withValues(alpha: 0.3),
          ),
          const SizedBox(height: 16),
          const Text(
            'لا توجد فواتير مشتريات',
            style: TextStyle(fontSize: 18, color: AppColors.textMuted),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: () => _tabController.animateTo(1),
            icon: const Icon(PhosphorIconsBold.plus),
            label: const Text('إنشاء فاتورة جديدة'),
          ),
        ],
      ),
    );
  }

  Widget _buildInvoiceCard(dynamic invoiceWithSupplier) {
    final invoice = invoiceWithSupplier.invoice;
    final supplierName = invoiceWithSupplier.supplierName ?? 'مورد غير محدد';
    final remaining = invoice.total - invoice.paid;
    final isPaid = remaining <= 0;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ExpansionTile(
        leading: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: isPaid
                ? AppColors.success.withValues(alpha: 0.1)
                : AppColors.warning.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            isPaid ? PhosphorIconsBold.checkCircle : PhosphorIconsBold.clock,
            color: isPaid ? AppColors.success : AppColors.warning,
          ),
        ),
        title: Row(
          children: [
            Text(
              invoice.invoiceNumber,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const Spacer(),
            Text(
              '${invoice.total.toStringAsFixed(AppConstants.decimalPlaces)} ${AppConstants.currencySymbolEn}',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: AppColors.primary,
              ),
            ),
          ],
        ),
        subtitle: Text(
          '${invoice.invoiceDate.toString().substring(0, 10)} | $supplierName',
        ),
        trailing: isPaid
            ? const Icon(
                PhosphorIconsBold.checkCircle,
                color: AppColors.success,
                size: 20,
              )
            : Text(
                'متبقي: ${remaining.toStringAsFixed(AppConstants.decimalPlaces)}',
                style: const TextStyle(fontSize: 12, color: AppColors.error),
              ),
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildActionButton(
                  PhosphorIconsBold.eye,
                  'تفاصيل',
                  AppColors.info,
                  () => _showInvoiceDetails(invoice),
                ),
                _buildActionButton(
                  PhosphorIconsBold.pencil,
                  'تعديل',
                  AppColors.warning,
                  () => _editInvoice(invoice),
                ),
                _buildActionButton(
                  PhosphorIconsBold.printer,
                  'طباعة',
                  AppColors.primary,
                  () => _printInvoice(invoice),
                ),
                _buildActionButton(
                  PhosphorIconsBold.trash,
                  'حذف',
                  AppColors.error,
                  () => _deleteInvoice(invoice),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton(
    IconData icon,
    String label,
    Color color,
    VoidCallback onTap,
  ) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(height: 4),
            Text(label, style: TextStyle(fontSize: 12, color: color)),
          ],
        ),
      ),
    );
  }

  void _showInvoiceDetails(dynamic invoice) async {
    final purchasesRepo = ref.read(purchasesRepositoryProvider);
    final items = await purchasesRepo.getInvoiceItemsWithProduct(invoice.id);
    final partiesRepo = ref.read(partiesRepositoryProvider);
    final supplier = await partiesRepo.getPartyById(invoice.supplierId);

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            const Icon(PhosphorIconsBold.receipt, color: AppColors.warning),
            const SizedBox(width: 8),
            Text('فاتورة شراء #${invoice.invoiceNumber}'),
          ],
        ),
        content: SizedBox(
          width: 600,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildDetailRow('المورد', supplier?.name ?? 'غير محدد'),
                _buildDetailRow(
                  'التاريخ',
                  invoice.invoiceDate.toString().substring(0, 10),
                ),
                _buildDetailRow(
                  'الإجمالي',
                  '${invoice.total.toStringAsFixed(AppConstants.decimalPlaces)} ${AppConstants.currencySymbolEn}',
                  bold: true,
                ),
                _buildDetailRow(
                  'المدفوع',
                  '${invoice.paid.toStringAsFixed(AppConstants.decimalPlaces)} ${AppConstants.currencySymbolEn}',
                ),
                _buildDetailRow(
                  'المتبقي',
                  '${(invoice.total - invoice.paid).toStringAsFixed(AppConstants.decimalPlaces)} ${AppConstants.currencySymbolEn}',
                  color: invoice.total - invoice.paid > 0
                      ? AppColors.error
                      : AppColors.success,
                ),
                const Divider(height: 24),
                const Text(
                  'الأصناف:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                DataTable(
                  columnSpacing: 20,
                  columns: const [
                    DataColumn(label: Text('الصنف')),
                    DataColumn(label: Text('الكمية')),
                    DataColumn(label: Text('السعر')),
                    DataColumn(label: Text('الإجمالي')),
                  ],
                  rows: items
                      .map(
                        (item) => DataRow(
                          cells: [
                            DataCell(Text(item.product.name)),
                            DataCell(
                              Text(item.item.quantity.toStringAsFixed(2)),
                            ),
                            DataCell(
                              Text(
                                '${item.item.unitCost.toStringAsFixed(AppConstants.decimalPlaces)} ${AppConstants.currencySymbolEn}',
                              ),
                            ),
                            DataCell(
                              Text(
                                '${(item.item.quantity * item.item.unitCost).toStringAsFixed(AppConstants.decimalPlaces)} ${AppConstants.currencySymbolEn}',
                              ),
                            ),
                          ],
                        ),
                      )
                      .toList(),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إغلاق'),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(
    String label,
    String value, {
    bool bold = false,
    Color? color,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label),
          Text(
            value,
            style: TextStyle(
              fontWeight: bold ? FontWeight.bold : FontWeight.normal,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  void _editInvoice(dynamic invoice) async {
    final purchasesRepo = ref.read(purchasesRepositoryProvider);
    final controller = ref.read(purchasesControllerProvider.notifier);
    final partiesRepo = ref.read(partiesRepositoryProvider);
    final supplier = await partiesRepo.getPartyById(invoice.supplierId);
    final items = await purchasesRepo.getInvoiceItemsWithProduct(invoice.id);

    // Load invoice data into controller for editing
    await controller.loadForEdit(
      invoiceId: invoice.id,
      supplierId: invoice.supplierId,
      supplierName: supplier?.name,
      paid: invoice.paid,
      notes: invoice.notes,
      items: items,
    );

    // Switch to invoice tab
    _tabController.animateTo(1);

    if (mounted) {
      AppToast.show(
        context,
        'تم تحميل الفاتورة ${invoice.invoiceNumber} للتعديل',
        type: ToastType.info,
      );
    }
  }

  void _printInvoice(dynamic invoice) async {
    try {
      final purchasesRepo = ref.read(purchasesRepositoryProvider);
      final partiesRepo = ref.read(partiesRepositoryProvider);
      final supplier = await partiesRepo.getPartyById(invoice.supplierId);
      final items = await purchasesRepo.getInvoiceItemsWithProduct(invoice.id);
      final settingsRepo = ref.read(settingsRepositoryProvider);
      final String? companyName = await settingsRepo.getSetting('company_name');

      await InvoiceGenerator.printPurchaseInvoice(
        invoiceNumber: invoice.invoiceNumber,
        date: invoice.invoiceDate,
        supplierName: supplier?.name ?? 'غير محدد',
        items: items
            .map(
              (item) => InvoiceItem(
                name: item.product.name,
                quantity: item.item.quantity,
                price: item.item.unitCost,
                total: item.item.quantity * item.item.unitCost,
              ),
            )
            .toList(),
        total: invoice.total,
        paid: invoice.paid,
        companyName: companyName,
      );
    } catch (e) {
      if (mounted) {
        AppToast.show(context, 'خطأ في الطباعة: $e', type: ToastType.error);
      }
    }
  }

  void _deleteInvoice(dynamic invoice) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('حذف الفاتورة'),
        content: Text(
          'هل أنت متأكد من حذف الفاتورة ${invoice.invoiceNumber}؟\nسيتم عكس حركات المخزون والمديونية.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      try {
        final purchasesRepo = ref.read(purchasesRepositoryProvider);
        await purchasesRepo.deleteInvoice(invoice.id);

        if (mounted) {
          AppToast.show(
            context,
            'تم حذف الفاتورة بنجاح',
            type: ToastType.success,
          );
        }
        ref.invalidate(purchasesWithSupplierProvider);
      } catch (e) {
        if (mounted) {
          AppToast.show(context, 'خطأ في الحذف: $e', type: ToastType.error);
        }
      }
    }
  }

  Widget _buildNewInvoiceTab() {
    final suppliersAsync = ref.watch(allSuppliersProvider);
    final state = ref.watch(purchasesControllerProvider);

    return Row(
      children: [
        // Left: Product Selection
        Expanded(flex: 3, child: _buildProductSelection()),
        // Right: Cart
        Expanded(
          flex: 2,
          child: Container(
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              border: const Border(left: BorderSide(color: AppColors.border)),
            ),
            child: Column(
              children: [
                _buildSupplierSelector(suppliersAsync, state),
                Expanded(child: PurchaseCartView(onSave: () => _saveInvoice())),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSupplierSelector(
    AsyncValue<List<Party>> suppliersAsync,
    PurchasesState state,
  ) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: suppliersAsync.when(
        loading: () => const LinearProgressIndicator(),
        error: (e, _) => Text('خطأ: $e'),
        data: (suppliers) => Autocomplete<Party>(
          optionsBuilder: (textValue) {
            if (textValue.text.isEmpty) return suppliers;
            return suppliers.where(
              (s) =>
                  s.name.toLowerCase().contains(textValue.text.toLowerCase()) ||
                  (s.phone?.contains(textValue.text) ?? false),
            );
          },
          displayStringForOption: (s) => s.name,
          initialValue: state.selectedSupplierId != null
              ? TextEditingValue(
                  text:
                      suppliers
                          .where((s) => s.id == state.selectedSupplierId)
                          .firstOrNull
                          ?.name ??
                      '',
                )
              : null,
          fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
            return TextField(
              controller: controller,
              focusNode: focusNode,
              decoration: InputDecoration(
                labelText: 'المورد',
                prefixIcon: const Icon(PhosphorIconsBold.user),
                hintText: 'ابحث عن المورد...',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                isDense: true,
                suffixIcon: state.selectedSupplierId != null
                    ? IconButton(
                        icon: const Icon(PhosphorIconsBold.x, size: 14),
                        onPressed: () {
                          controller.clear();
                          ref
                              .read(purchasesControllerProvider.notifier)
                              .setSupplier(0, '');
                        },
                      )
                    : null,
              ),
            );
          },
          onSelected: (supplier) {
            ref
                .read(purchasesControllerProvider.notifier)
                .setSupplier(supplier.id, supplier.name);
          },
        ),
      ),
    );
  }

  Widget _buildProductSelection() {
    final productsAsync = ref.watch(allProductsProvider);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: 'بحث عن منتج...',
              prefixIcon: const Icon(PhosphorIconsBold.magnifyingGlass),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              isDense: true,
            ),
            onChanged: (value) => setState(() {}),
          ),
        ),
        Expanded(
          child: productsAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('خطأ: $e')),
            data: (products) {
              final filtered = _filterProducts(products);
              return GridView.builder(
                padding: const EdgeInsets.all(12),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 4,
                  childAspectRatio: 1.2,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                ),
                itemCount: filtered.length,
                itemBuilder: (context, index) =>
                    _buildProductCard(filtered[index]),
              );
            },
          ),
        ),
      ],
    );
  }

  List<dynamic> _filterProducts(List<dynamic> products) {
    final query = _searchController.text.toLowerCase();
    if (query.isEmpty) return products.where((p) => p.isActive).toList();
    return products
        .where(
          (p) =>
              p.isActive &&
              (p.name.toLowerCase().contains(query) ||
                  p.code.toLowerCase().contains(query)),
        )
        .toList();
  }

  Widget _buildProductCard(dynamic product) {
    return Card(
      child: InkWell(
        onTap: () =>
            ref.read(purchasesControllerProvider.notifier).addToCart(product),
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                PhosphorIconsBold.package,
                size: 32,
                color: AppColors.primary,
              ),
              const SizedBox(height: 8),
              Text(
                product.name,
                style: const TextStyle(fontWeight: FontWeight.w600),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 4),
              Text(
                '${product.costPrice.toStringAsFixed(AppConstants.decimalPlaces)} ${AppConstants.currencySymbolEn}',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _saveInvoice() async {
    final invoiceId = await ref
        .read(purchasesControllerProvider.notifier)
        .saveInvoice();
    if (invoiceId != null && mounted) {
      AppToast.show(context, 'تم حفظ الفاتورة بنجاح', type: ToastType.success);
      _tabController.animateTo(0);
      ref.invalidate(purchaseInvoicesProvider);
    } else if (mounted) {
      AppToast.show(context, 'فشل حفظ الفاتورة', type: ToastType.error);
    }
  }
}