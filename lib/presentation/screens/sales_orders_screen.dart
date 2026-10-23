import 'package:picpos_erp/core/i18n/tr.dart';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/theme/app_colors.dart';
import '../../core/constants/app_constants.dart';
import '../../data/providers/providers.dart';
import '../../domain/repositories/i_sales_orders_repository.dart';
import '../../domain/repositories/parties_repository.dart';
import '../../domain/repositories/branch_repository.dart';
import 'package:drift/drift.dart' hide Column;
import '../../core/widgets/app_toast.dart';

/// Sales Orders Screen — طلبات البيع
/// Status flow: draft → sent → confirmed → delivered → (converted to invoice)
///            ↘ cancelled
class SalesOrdersScreen extends ConsumerStatefulWidget {
  const SalesOrdersScreen({super.key});

  @override
  ConsumerState<SalesOrdersScreen> createState() => _SalesOrdersScreenState();
}

class _SalesOrdersScreenState extends ConsumerState<SalesOrdersScreen> {
  String _filterStatus = 'all';
  final _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final salesRepo = ref.watch(salesOrdersRepositoryProvider);
    final partiesRepo = ref.watch(partiesRepositoryProvider);
    final branchRepo = ref.watch(branchRepositoryProvider);

    return Directionality(
      textDirection: ui.TextDirection.rtl,
      // لا تجاوزَ للخلفيّة: الثيمُ يعرّف `scaffoldBackgroundColor` للوضعَين.
      child: Scaffold(
        appBar: AppBar(
          title:  Text(tr('طلبات البيع')),
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          actions: [
            ElevatedButton.icon(
              onPressed: () => _showCreateOrderDialog(salesRepo, partiesRepo, branchRepo),
              icon: const Icon(PhosphorIconsBold.plus, size: 16),
              label:  Text(tr('طلب بيع جديد')),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: AppColors.primary,
              ),
            ),
            const SizedBox(width: 16),
          ],
        ),
        body: Column(
          children: [
            // Status filter chips
            Padding(
              padding: const EdgeInsets.all(12),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _buildFilterChip('all', tr('الكل'), PhosphorIconsBold.list),
                    const SizedBox(width: 8),
                    _buildFilterChip('draft', tr('مسودة'), PhosphorIconsBold.pencilSimple),
                    const SizedBox(width: 8),
                    _buildFilterChip('sent', tr('مرسل'), PhosphorIconsBold.paperPlaneRight),
                    const SizedBox(width: 8),
                    _buildFilterChip('confirmed', tr('مؤكد'), PhosphorIconsBold.checkCircle),
                    const SizedBox(width: 8),
                    _buildFilterChip('delivered', tr('تم التسليم'), PhosphorIconsBold.package),
                    const SizedBox(width: 8),
                    _buildFilterChip('cancelled', tr('ملغي'), PhosphorIconsBold.xCircle),
                  ],
                ),
              ),
            ),
            // Search bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: tr('بحث عن طلب بيع...'),
                  prefixIcon: const Icon(PhosphorIconsBold.magnifyingGlass, size: 18),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(icon: const Icon(Icons.clear, size: 18), onPressed: () { _searchController.clear(); setState(() => _searchQuery = ''); })
                      : null,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onChanged: (v) => setState(() => _searchQuery = v.trim().toLowerCase()),
              ),
            ),
            const SizedBox(height: 8),
            // Orders list
            Expanded(
              child: StreamBuilder<List<SalesOrderData>>(
                stream: _filterStatus == 'all'
                    ? salesRepo.watchSalesOrders()
                    : salesRepo.watchSalesOrdersByStatus(_filterStatus),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  var orders = snapshot.data!;
                  if (_searchQuery.isNotEmpty) {
                    orders = orders.where((o) =>
                      o.orderNumber.toLowerCase().contains(_searchQuery) ||
                      (o.notes ?? '').toLowerCase().contains(_searchQuery)
                    ).toList();
                  }
                  if (orders.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(PhosphorIconsBold.clipboardText, size: 64,
                              color: AppColors.textMuted.withValues(alpha: 0.3)),
                          const SizedBox(height: 16),
                          Text(tr('لا توجد طلبات بيع'),
                              style: GoogleFonts.cairo(color: AppColors.textMuted)),
                        ],
                      ),
                    );
                  }

                  return ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    itemCount: orders.length,
                    itemBuilder: (context, i) {
                      final order = orders[i];
                      return _buildOrderCard(salesRepo, partiesRepo, order);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterChip(String status, String label, IconData icon) {
    final selected = _filterStatus == status;
    return FilterChip(
      selected: selected,
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: selected ? Colors.white : AppColors.textMuted),
          const SizedBox(width: 4),
          Text(label),
        ],
      ),
      onSelected: (_) => setState(() => _filterStatus = status),
      selectedColor: AppColors.primary,
      checkmarkColor: Colors.white,
      labelStyle: GoogleFonts.cairo(
        fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
        color: selected ? Colors.white : AppColors.textPrimary,
        fontSize: 12,
      ),
    );
  }

  Widget _buildOrderCard(ISalesOrdersRepository salesRepo, IPartiesRepository partiesRepo, SalesOrderData order) {
    final statusInfo = _getStatusInfo(order.status);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: statusInfo.$2.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(statusInfo.$3, color: statusInfo.$2, size: 20),
        ),
        title: Row(
          children: [
            Text(order.orderNumber,
                style: GoogleFonts.cairo(fontWeight: FontWeight.w700, fontSize: 13)),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: statusInfo.$2.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(statusInfo.$1,
                  style: GoogleFonts.cairo(fontSize: 9, color: statusInfo.$2, fontWeight: FontWeight.w700)),
            ),
          ],
        ),
        subtitle: FutureBuilder<Party?>(
          future: order.customerId != null
              ? partiesRepo.getPartyById(order.customerId!)
              : Future.value(null),
          builder: (ctx, snap) {
            final customerName = snap.data?.name ?? tr('بدون عميل');
            return Text(
              '$customerName  •  ${order.orderDate.toString().substring(0, 10)}  •  ${order.total.toStringAsFixed(AppConstants.decimalPlaces)} ${AppConstants.currencySymbolEn}',
              style: GoogleFonts.cairo(fontSize: 11, color: AppColors.textMuted),
            );
          },
        ),
        trailing: PopupMenuButton<String>(
          onSelected: (action) => _handleAction(salesRepo, order, action),
          itemBuilder: (_) => [
            if (order.status == 'draft') ...[
               PopupMenuItem(value: 'send', child: Text(tr('إرسال للعميل'))),
               PopupMenuItem(value: 'delete', child: Text(tr('حذف'), style: const TextStyle(color: AppColors.error))),
            ],
            if (order.status == 'sent')
               PopupMenuItem(value: 'confirm', child: Text(tr('تأكيد'))),
            if (order.status == 'confirmed')
               PopupMenuItem(value: 'deliver', child: Text(tr('تسليم'))),
            if (order.status != 'cancelled' && order.status != 'delivered')
               PopupMenuItem(value: 'cancel', child: Text(tr('إلغاء'), style: const TextStyle(color: AppColors.error))),
            // Field-report 2026-05-14: previously a cancelled order had
            // no actions, so operators couldn't edit or recover from a
            // mis-click on إلغاء. Re-activating flips status back to
            // 'draft' (safest — operator must re-confirm to re-reserve
            // stock). The DAO already handles cancelled→draft cleanly.
            if (order.status == 'cancelled')
               PopupMenuItem(value: 'reactivate', child: Text(tr('إعادة تفعيل'))),
            if (order.status == 'confirmed' || order.status == 'delivered')
              if (order.convertedToInvoiceId == null)
                 PopupMenuItem(value: 'convert', child: Text(tr('تحويل لفاتورة مبيعات'))),
          ],
        ),
      ),
    );
  }

  (String, Color, IconData) _getStatusInfo(String status) {
    switch (status) {
      case 'draft':
        return (tr('مسودة'), AppColors.textMuted, PhosphorIconsBold.pencilSimple);
      case 'sent':
        return (tr('مرسل'), AppColors.info, PhosphorIconsBold.paperPlaneRight);
      case 'confirmed':
        return (tr('مؤكد'), AppColors.success, PhosphorIconsBold.checkCircle);
      case 'delivered':
        return (tr('تم التسليم'), AppColors.primary, PhosphorIconsBold.package);
      case 'cancelled':
        return (tr('ملغي'), AppColors.error, PhosphorIconsBold.xCircle);
      default:
        return ('غير معروف', AppColors.textMuted, PhosphorIconsBold.question);
    }
  }

  Future<void> _handleAction(ISalesOrdersRepository salesRepo, SalesOrderData order, String action) async {
    try {
      switch (action) {
        case 'send':
          await salesRepo.updateSalesOrderStatus(order.id, 'sent');
        case 'confirm':
          await salesRepo.updateSalesOrderStatus(order.id, 'confirmed');
        case 'deliver':
          // "تسليم" is a three-in-one action: flip status → delivered,
          // materialise the sales invoice, and post its treasury receipt.
          // Previously we only flipped the status, so the quotation/order
          // stayed with no invoice and the treasury never saw the cash —
          // the root cause the user reported as "لا يتم تحويلها ولا يظهر
          // تحصيلها فى الخزينة". convertSOToInvoice() does all three
          // inside one DAO transaction (status, invoice, receipt) and
          // stamps convertedToInvoiceId so the UI flips to "محول".
          final invoiceId = await salesRepo.convertSOToInvoice(order.id);
          if (mounted) {
            AppToast.show(
              context,
              tr('تم تسليم الطلب وإنشاء فاتورة مبيعات #{invoiceId} بنجاح', {'invoiceId': invoiceId}),
            );
          }
        case 'cancel':
          await salesRepo.updateSalesOrderStatus(order.id, 'cancelled');
        case 'reactivate':
          await salesRepo.updateSalesOrderStatus(order.id, 'draft');
          if (mounted) {
            AppToast.show(context, tr('تم إعادة تفعيل الطلب كمسودة'));
          }
        case 'delete':
          await salesRepo.deleteSalesOrder(order.id);
        case 'convert':
          final invoiceId = await salesRepo.convertSOToInvoice(order.id);
          if (mounted) {
            AppToast.show(context, tr('تم إنشاء فاتورة مبيعات #{invoiceId} بنجاح', {'invoiceId': invoiceId}));
          }
      }
    } catch (e) {
      if (mounted) {
        AppToast.show(context, tr('خطأ: {e}', {'e': e}), type: ToastType.error);
      }
    }
  }

  void _showCreateOrderDialog(ISalesOrdersRepository salesRepo, IPartiesRepository partiesRepo, IBranchRepository branchRepo) async {
    final productRepo = ref.read(productRepositoryProvider);
    final allProducts = await productRepo.getAllProducts();

    int? selectedCustomerId;
    int? selectedWarehouseId;
    int? selectedCostCenterId;
    DateTime orderDate = DateTime.now();
    final notesCtrl = TextEditingController();
    final List<Map<String, dynamic>> orderItems = [];
    double orderTotal = 0;

    void recalculate(StateSetter setDialogState) {
      orderTotal = orderItems.fold(0.0, (sum, item) => sum + (item['total'] as double));
      setDialogState(() {});
    }

    // Recompute a single line's tax amount + total. Mirrors the per-line tax
    // model in the sales-invoice form: when taxEnabled is false the line
    // contributes zero tax regardless of the entered rate.
    void recalcLine(Map<String, dynamic> item) {
      final lineTotal = (item['quantity'] as double) * (item['unitPrice'] as double);
      final taxAmt = (item['taxEnabled'] as bool)
          ? lineTotal * ((item['taxRate'] as double) / 100)
          : 0.0;
      item['taxAmount'] = taxAmt;
      item['total'] = lineTotal + taxAmt;
    }

        if (!mounted) return;

    showDialog(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: ui.TextDirection.rtl,
        child: StatefulBuilder(builder: (ctx, setDialogState) {
          return AlertDialog(
            title: Text(tr('طلب بيع جديد'), style: GoogleFonts.cairo(fontWeight: FontWeight.w700)),
            content: SizedBox(
              width: 650,
              height: 550,
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Customer picker
                    FutureBuilder<List<Party>>(
                      future: partiesRepo.getParties(isCustomer: true),
                      builder: (ctx, snap) {
                        if (!snap.hasData) return const LinearProgressIndicator();
                        final activeCustomers = snap.data!.where((p) => p.isActive).toList();
                        activeCustomers.sort((a, b) => a.name.compareTo(b.name));
                        
                        return DropdownButtonFormField<int?>(
                          initialValue: selectedCustomerId,
                          isExpanded: true,
                          decoration: InputDecoration(
                            labelText: tr('العميل (اختياري)'),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                            isDense: true,
                          ),
                          items: [
                             DropdownMenuItem<int?>(value: null, child: Text(tr('بدون عميل'))),
                            ...activeCustomers.map((c) => DropdownMenuItem<int?>(
                                  value: c.id,
                                  child: Text(c.name, overflow: TextOverflow.ellipsis),
                                )),
                          ],
                          onChanged: (v) => setDialogState(() => selectedCustomerId = v),
                        );
                      },
                    ),
                    const SizedBox(height: 10),
                    // Warehouse picker — Spec 103: على جهاز عميلٍ مربوطٍ بفرع
                    // لا تُعرَض مخازنُ فروعٍ أخرى. وهنا آكد: أوّلُ مخزنٍ
                    // يُنتقى تلقائيّاً أدناه، فقائمةٌ غيرُ محصورةٍ قد تختار
                    // مخزنَ فرعٍ آخر بلا لمسةٍ من الكاشير.
                    FutureBuilder<List<Warehouse>>(
                      future: branchRepo.getScopedWarehouses(),
                      builder: (ctx, snap) {
                        if (!snap.hasData) return const LinearProgressIndicator();
                        final warehouses = snap.data!;
                        warehouses.sort((a, b) => a.name.compareTo(b.name));
                        
                        if (selectedWarehouseId == null && warehouses.isNotEmpty) {
                          selectedWarehouseId = warehouses.first.id;
                        }
                        return DropdownButtonFormField<int>(
                          initialValue: selectedWarehouseId,
                          isExpanded: true,
                          decoration: InputDecoration(
                            labelText: tr('المستودع *'),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                            isDense: true,
                          ),
                          items: warehouses.map((w) => DropdownMenuItem<int>(
                                value: w.id,
                                child: Text(trData(w.name)),
                              )).toList(),
                          onChanged: (v) => setDialogState(() => selectedWarehouseId = v),
                        );
                      },
                    ),
                    const SizedBox(height: 12),
                    // Product search
                    Text(tr('الأصناف:'), style: GoogleFonts.cairo(fontWeight: FontWeight.w700, fontSize: 13)),
                    const SizedBox(height: 6),
                    Builder(builder: (context) {
                      TextEditingController? acCtrl;
                      return Autocomplete<Product>(
                        optionsBuilder: (textValue) {
                          if (textValue.text.isEmpty) return const [];
                          final q = textValue.text.toLowerCase();
                          return allProducts.where((p) =>
                              p.name.toLowerCase().contains(q) ||
  // ignore: dead_code
                              (p.code.toLowerCase().contains(q) ?? false) ||
                              (p.barcode?.contains(textValue.text) ?? false));
                        },
  // ignore: dead_code
                        displayStringForOption: (p) => '${p.name} (${p.code ?? "-"})',
                        fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
                          acCtrl = controller;
                          return TextField(
                            controller: controller,
                            focusNode: focusNode,
                            decoration:  InputDecoration(
                              hintText: tr('ابحث بالاسم أو الكود أو الباركود...'),
                              prefixIcon: const Icon(PhosphorIconsBold.magnifyingGlass, size: 18),
                              border: const OutlineInputBorder(),
                              isDense: true,
                            ),
                            style: const TextStyle(fontSize: 13),
                          );
                        },
                        onSelected: (product) {
                          setDialogState(() {
                            final item = <String, dynamic>{
                              'productId': product.id,
                              'productName': product.name,
                              'quantity': 1.0,
                              'unitPrice': product.salePrice,
                              'taxRate': product.taxRate,
                              // Seed the taxable flag from the product card,
                              // exactly like the sales-invoice form.
                              'taxEnabled': product.taxRate > 0,
                              'taxAmount': 0.0,
                              'total': 0.0,
                            };
                            recalcLine(item);
                            orderItems.add(item);
                            recalculate(setDialogState);
                          });
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            acCtrl?.clear();
                          });
                        },
                      );
                    }),
                    const SizedBox(height: 8),
                    // Items table
                    if (orderItems.isNotEmpty)
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: DataTable(
                        columnSpacing: 10,
                        headingRowHeight: 32,
                        dataRowMinHeight: 30,
                        dataRowMaxHeight: 40,
                        columns:  [
                          DataColumn(label: Text(tr('الصنف'), style: const TextStyle(fontSize: 11))),
                          DataColumn(label: Text(tr('الكمية'), style: const TextStyle(fontSize: 11))),
                          DataColumn(label: Text(tr('السعر'), style: const TextStyle(fontSize: 11))),
                          DataColumn(label: Text(tr('الضريبة %'), style: const TextStyle(fontSize: 11))),
                          DataColumn(label: Text(tr('قيمة الضريبة'), style: const TextStyle(fontSize: 11))),
                          DataColumn(label: Text(tr('الإجمالي'), style: const TextStyle(fontSize: 11))),
                          const DataColumn(label: Text('', style: TextStyle(fontSize: 11))),
                        ],
                        rows: orderItems.asMap().entries.map((entry) {
                          final i = entry.key;
                          final item = entry.value;
                          return DataRow(cells: [
                            DataCell(Text(item['productName'] as String, style: const TextStyle(fontSize: 11))),
                            DataCell(SizedBox(width: 50, child: TextFormField(
                              initialValue: (item['quantity'] as double).toString(),
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              style: const TextStyle(fontSize: 11),
                              decoration: const InputDecoration(isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 4)),
                              onChanged: (val) {
                                final qty = double.tryParse(val) ?? 1;
                                item['quantity'] = qty;
                                recalcLine(item);
                                recalculate(setDialogState);
                              },
                            ))),
                            DataCell(SizedBox(width: 60, child: TextFormField(
                              initialValue: (item['unitPrice'] as double).toStringAsFixed(AppConstants.decimalPlaces),
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              style: const TextStyle(fontSize: 11),
                              decoration: const InputDecoration(isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 4)),
                              onChanged: (val) {
                                final price = double.tryParse(val) ?? 0;
                                item['unitPrice'] = price;
                                recalcLine(item);
                                recalculate(setDialogState);
                              },
                            ))),
                            // Tax % — checkbox to toggle taxable + editable
                            // rate, mirroring the sales-invoice items table.
                            DataCell(SizedBox(
                              width: 118,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  SizedBox(
                                    width: 28,
                                    child: Checkbox(
                                      value: item['taxEnabled'] as bool,
                                      visualDensity: VisualDensity.compact,
                                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                      onChanged: (val) {
                                        setDialogState(() {
                                          item['taxEnabled'] = val ?? false;
                                          recalcLine(item);
                                          recalculate(setDialogState);
                                        });
                                      },
                                    ),
                                  ),
                                  Expanded(
                                    child: TextFormField(
                                      key: ValueKey('so_tax_rate_${i}_${item['productId']}_${item['taxEnabled']}'),
                                      enabled: item['taxEnabled'] as bool,
                                      initialValue: (item['taxRate'] as double).toStringAsFixed(0),
                                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                      style: const TextStyle(fontSize: 11),
                                      decoration: const InputDecoration(
                                        isDense: true,
                                        suffixText: '%',
                                        contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                                      ),
                                      onChanged: (val) {
                                        item['taxRate'] = double.tryParse(val) ?? 0.0;
                                        recalcLine(item);
                                        recalculate(setDialogState);
                                      },
                                    ),
                                  ),
                                ],
                              ),
                            )),
                            DataCell(Text((item['taxAmount'] as double).toStringAsFixed(AppConstants.decimalPlaces), style: const TextStyle(fontSize: 11))),
                            DataCell(Text((item['total'] as double).toStringAsFixed(AppConstants.decimalPlaces), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold))),
                            DataCell(IconButton(
                              icon: const Icon(PhosphorIconsBold.trash, size: 14, color: AppColors.error),
                              onPressed: () {
                                setDialogState(() {
                                  orderItems.removeAt(i);
                                  recalculate(setDialogState);
                                });
                              },
                            )),
                          ]);
                        }).toList(),
                        ),
                      ),
                    if (orderItems.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Text(tr('الإجمالي: '), style: GoogleFonts.cairo(fontWeight: FontWeight.w700)),
                            Text(orderTotal.toStringAsFixed(AppConstants.decimalPlaces),
                                style: GoogleFonts.cairo(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.primary)),
                          ],
                        ),
                      ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: notesCtrl,
                      maxLines: 2,
                      decoration: InputDecoration(
                        labelText: tr('ملاحظات'),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        isDense: true,
                      ),
                    ),
                    // GAP-09: Cost Center dropdown
                    const SizedBox(height: 10),
                    FutureBuilder<List<CostCenter>>(
                      future: ref.read(accountingRepositoryProvider).getActiveCostCenters(),
                      builder: (ctx, ccSnap) {
                        final ccList = ccSnap.data ?? [];
                        if (ccList.isEmpty) return const SizedBox.shrink();
                        return DropdownButtonFormField<int?>(
                          initialValue: selectedCostCenterId,
                          isExpanded: true,
                          decoration: InputDecoration(
                            labelText: tr('مركز التكلفة'),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                            isDense: true,
                          ),
                          items: [
                             DropdownMenuItem<int?>(value: null, child: Text(tr('بدون'))),
                            ...ccList.map((cc) => DropdownMenuItem<int?>(value: cc.id, child: Text(trData(cc.name)))),
                          ],
                          onChanged: (v) => setDialogState(() => selectedCostCenterId = v),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child:  Text(tr('إلغاء'))),
              ElevatedButton.icon(
                onPressed: selectedWarehouseId == null
                    ? null
                    : () async {
                        if (orderItems.isEmpty) {
                          AppToast.show(context, tr('يرجى إضافة صنف واحد على الأقل'), type: ToastType.info);
                          return;
                        }
                        try {
                          final companions = orderItems.map((item) {
                            final enabled = item['taxEnabled'] as bool;
                            return SalesOrderItemsCompanion.insert(
                              orderId: 0, // Will be set by repository
                              productId: item['productId'] as int,
                              quantity: item['quantity'] as double,
                              unitPrice: item['unitPrice'] as double,
                              total: item['total'] as double,
                              // Exempt lines store a zero rate, matching the
                              // sales-invoice save mapping.
                              taxRate: Value(enabled ? item['taxRate'] as double : 0.0),
                              taxAmount: Value(item['taxAmount'] as double),
                            );
                          }).toList();

                          await salesRepo.createSalesOrder(
                            customerId: selectedCustomerId,
                            warehouseId: selectedWarehouseId!,
                            orderDate: orderDate,
                            notes: notesCtrl.text.isNotEmpty ? notesCtrl.text : null,
                            costCenterId: selectedCostCenterId,
                            items: companions,
                          );
                          if (ctx.mounted) Navigator.pop(ctx);
                          if (mounted) {
                            AppToast.show(context, tr('تم إنشاء طلب البيع بنجاح'));
                          }
                        } catch (e) {
                          if (mounted) {
                            AppToast.show(context, tr('خطأ: {e}', {'e': e}), type: ToastType.error);
                          }
                        }
                      },
                icon: const Icon(PhosphorIconsBold.floppyDisk, size: 16),
                label: Text(tr('إنشاء'), style: GoogleFonts.cairo(fontWeight: FontWeight.w700)),
              ),
            ],
          );
        }),
      ),
    );
  }
}
