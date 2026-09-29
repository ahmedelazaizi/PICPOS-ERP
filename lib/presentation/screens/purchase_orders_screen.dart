import 'package:ural_erp/core/i18n/tr.dart';
import 'package:ural_erp/core/constants/app_constants.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart' hide TextDirection;
import '../../core/theme/app_colors.dart';
import '../picpos_shell/picpos_surface.dart';
import '../../data/providers/providers.dart';
import '../../domain/repositories/purchase_orders_repository.dart';
import '../../domain/repositories/parties_repository.dart';
import '../../domain/repositories/branch_repository.dart';
import 'package:drift/drift.dart' hide Column;
import '../../core/widgets/app_toast.dart';

/// Purchase Orders Screen — Full PO lifecycle management
class PurchaseOrdersScreen extends ConsumerStatefulWidget {
  const PurchaseOrdersScreen({super.key});

  @override
  ConsumerState<PurchaseOrdersScreen> createState() => _PurchaseOrdersScreenState();
}

class _PurchaseOrdersScreenState extends ConsumerState<PurchaseOrdersScreen> {
  String _statusFilter = 'all';
  final _dateFormat = DateFormat('yyyy/MM/dd');
  final _searchController = TextEditingController();
  String _searchQuery = '';
  bool _actionBusy = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  static Map<String, _StatusInfo> get _statuses => {
    'all': _StatusInfo(tr('الكل'), Colors.grey, PhosphorIconsBold.list),
    'draft': _StatusInfo(tr('مسودة'), const Color(0xFF6B7280), PhosphorIconsBold.pencilSimple),
    'sent': _StatusInfo(tr('مُرسل'), const Color(0xFF2563EB), PhosphorIconsBold.paperPlaneTilt),
    'confirmed': _StatusInfo(tr('مؤكد'), const Color(0xFF7C3AED), PhosphorIconsBold.checkCircle),
    'received': _StatusInfo(tr('مُستلم'), const Color(0xFF059669), PhosphorIconsBold.package),
    'cancelled': _StatusInfo(tr('ملغي'), const Color(0xFFDC2626), PhosphorIconsBold.xCircle),
  };

  @override
  Widget build(BuildContext context) {
    final poRepo = ref.watch(purchaseOrdersRepositoryProvider);
    final partiesRepo = ref.watch(partiesRepositoryProvider);
    final branchRepo = ref.watch(branchRepositoryProvider);

    return Directionality(
      textDirection: TextDirection.rtl,
      // لا تجاوزَ للخلفيّة: الثيمُ يعرّف `scaffoldBackgroundColor` للوضعَين.
      child: Scaffold(
        body: Column(
          children: [
            _buildHeader(context, poRepo, partiesRepo, branchRepo),
            _buildStatusFilters(),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: tr('بحث عن أمر شراء...'),
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
            Expanded(
              child: StreamBuilder<List<PurchaseOrderData>>(
                stream: _statusFilter == 'all'
                    ? poRepo.watchPurchaseOrders()
                    : poRepo.watchPurchaseOrdersByStatus(_statusFilter),
                builder: (context, snapshot) {
                  // Issue 13 (Feature 018): without an explicit hasError branch
                  // a Drift stream error (e.g. db locked during pop, transient
                  // schema migration race) bubbles up as the default
                  // ErrorWidget — which on Windows desktop is the dreaded
                  // "blue screen" the user reported on back-button.
                  if (snapshot.hasError) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          tr('تعذّر تحميل أوامر الشراء: {p0}', {'p0': snapshot.error}),
                          textAlign: TextAlign.center,
                          style: GoogleFonts.cairo(
                            color: AppColors.textSecondary,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    );
                  }
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
                    return _buildEmptyState(context, poRepo, partiesRepo, branchRepo);
                  }
                  return ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: orders.length,
                    itemBuilder: (context, index) => _buildOrderCard(context, poRepo, partiesRepo, orders[index]),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, PurchaseOrdersRepository poRepo, IPartiesRepository partiesRepo, IBranchRepository branchRepo) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.primaryDark, AppColors.primary],
          begin: AlignmentDirectional.topEnd,
          end: AlignmentDirectional.bottomStart,
        ),
      ),
      child: Row(
        children: [
          // زرُّ رجوعٍ بنفس عقد `PicPosPageHeader`: يظهر حين تكون الشاشةُ
          // **مدفوعةً** على راوت، ويختفي حين تُفتَح من الشريط الجانبيّ
          // (`canPop == false`) لأنّ التنقّلَ هناك بالشريط لا بالرجوع.
          //
          // ⚠️ بلاغُ المالك 2026-08-26: الشاشةُ تُفتَح من **أربعة** مواضعَ،
          // ثلاثةٌ منها `push` (مركزُ تقارير PicPos · فواتيرُ مشترياته ·
          // فواتيرُ مشتريات UralCash) وواحدٌ من الشريط. فكانت الثلاثةُ تقع
          // في شاشةٍ لا مخرجَ منها إلّا مفتاحُ لوحةِ المفاتيح.
          //
          // وفي RTL «رجوع» سهمٌ إلى اليمين (→) مطابقةً لبقيّة الشاشات.
          if (Navigator.canPop(context)) ...[
            IconButton(
              onPressed: () => Navigator.maybePop(context),
              icon: const Icon(Icons.arrow_forward),
              color: Colors.white,
              tooltip: tr('رجوع'),
              style: IconButton.styleFrom(
                backgroundColor: Colors.white.withValues(alpha: 0.15),
              ),
            ),
            const SizedBox(width: 10),
          ],
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(PhosphorIconsBold.clipboardText, color: Colors.white, size: 24),
          ),
          const SizedBox(width: 14),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(tr('أوامر الشراء'),
                  style: GoogleFonts.cairo(fontSize: 20, fontWeight: FontWeight.w800, color: Colors.white)),
              Text(tr('إدارة دورة أوامر الشراء الكاملة'),
                  style: GoogleFonts.cairo(fontSize: 11, color: Colors.white.withValues(alpha: 0.7))),
            ],
          ),
          const Spacer(),
          ElevatedButton.icon(
            onPressed: () => _showCreatePODialog(context, poRepo, partiesRepo, branchRepo),
            icon: const Icon(PhosphorIconsBold.plus, size: 18),
            label: Text(tr('أمر شراء جديد'), style: GoogleFonts.cairo(fontWeight: FontWeight.w700)),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: AppColors.primary,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusFilters() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: context.picposCard,
        border: Border(bottom: BorderSide(color: context.picposHairline)),
      ),
      child: SizedBox(
        height: 36,
        child: ListView(
          scrollDirection: Axis.horizontal,
          children: _statuses.entries.map((entry) {
            final isSelected = _statusFilter == entry.key;
            final info = entry.value;
            return Padding(
              padding: const EdgeInsetsDirectional.only(end: 6),
              child: FilterChip(
                selected: isSelected,
                label: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(info.icon, size: 14, color: isSelected ? Colors.white : info.color),
                    const SizedBox(width: 4),
                    Text(info.label, style: GoogleFonts.cairo(
                      fontSize: 11, color: isSelected ? Colors.white : AppColors.textPrimary,
                      fontWeight: FontWeight.w600,
                    )),
                  ],
                ),
                selectedColor: info.color,
                backgroundColor: info.color.withValues(alpha: 0.06),
                onSelected: (_) => setState(() => _statusFilter = entry.key),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                  side: BorderSide(color: isSelected ? info.color : info.color.withValues(alpha: 0.2)),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 4),
                visualDensity: VisualDensity.compact,
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context, PurchaseOrdersRepository poRepo, IPartiesRepository partiesRepo, IBranchRepository branchRepo) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(PhosphorIconsBold.clipboardText, size: 64, color: AppColors.textMuted),
          const SizedBox(height: 16),
          Text(tr('لا توجد أوامر شراء'), style: GoogleFonts.cairo(fontSize: 16, color: AppColors.textMuted)),
          const SizedBox(height: 8),
          ElevatedButton.icon(
            onPressed: () => _showCreatePODialog(context, poRepo, partiesRepo, branchRepo),
            icon: const Icon(PhosphorIconsBold.plus, size: 16),
            label: Text(tr('إنشاء أمر شراء'), style: GoogleFonts.cairo()),
          ),
        ],
      ),
    );
  }

  Widget _buildOrderCard(BuildContext context, PurchaseOrdersRepository poRepo, IPartiesRepository partiesRepo, PurchaseOrderData order) {
    final statusInfo = _statuses[order.status] ?? _statuses['draft']!;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: statusInfo.color.withValues(alpha: 0.2)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          children: [
            // Top row: PO number + status + total
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: statusInfo.color.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(statusInfo.icon, color: statusInfo.color, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(order.orderNumber,
                              style: GoogleFonts.cairo(fontSize: 14, fontWeight: FontWeight.w700)),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: statusInfo.color.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(statusInfo.label,
                                style: GoogleFonts.cairo(fontSize: 10, color: statusInfo.color, fontWeight: FontWeight.w700)),
                          ),
                        ],
                      ),
                      Text(_dateFormat.format(order.orderDate),
                          style: GoogleFonts.cairo(fontSize: 11, color: AppColors.textMuted)),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(order.total.toStringAsFixed(AppConstants.decimalPlaces),
                        style: GoogleFonts.cairo(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.primary)),
                    if (order.expectedDate != null)
                      Text(tr('متوقع: {p0}', {'p0': _dateFormat.format(order.expectedDate!)}),
                          style: GoogleFonts.cairo(fontSize: 10, color: AppColors.textMuted)),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 8),
            // Supplier info
            FutureBuilder<Party?>(
              future: partiesRepo.getPartyById(order.supplierId),
              builder: (context, snap) {
                // Issue 13 (Feature 018): on error fall back to the supplier
                // id placeholder rather than letting the ErrorWidget paint —
                // a transient repo failure shouldn't crash the whole list.
                final name = snap.hasError
                    ? '#${order.supplierId}'
                    : (snap.data?.name ?? '#${order.supplierId}');
                return Row(
                  children: [
                    const Icon(PhosphorIconsBold.storefront, size: 14, color: AppColors.info),
                    const SizedBox(width: 6),
                    Text(name, style: GoogleFonts.cairo(fontSize: 12, color: AppColors.textSecondary)),
                  ],
                );
              },
            ),
            const SizedBox(height: 8),
            // Action buttons
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (order.status == 'draft') ...[
                  _actionBtn(tr('إرسال'), PhosphorIconsBold.paperPlaneTilt, const Color(0xFF2563EB), () async {
                    await poRepo.updatePurchaseOrderStatus(order.id, 'sent');
                  }),
                  const SizedBox(width: 6),
                  _actionBtn(tr('حذف'), PhosphorIconsBold.trash, AppColors.error, () async {
                    await poRepo.deletePurchaseOrder(order.id);
                  }),
                ],
                if (order.status == 'sent')
                  _actionBtn(tr('تأكيد'), PhosphorIconsBold.checkCircle, const Color(0xFF7C3AED), () async {
                    await poRepo.updatePurchaseOrderStatus(order.id, 'confirmed');
                  }),
                if (order.status == 'confirmed')
                  _actionBtn(tr('استلام وتحويل لفاتورة'), PhosphorIconsBold.receipt, AppColors.success, () async {
                    try {
                      await poRepo.convertPOToInvoice(order.id);
                      if (context.mounted) {
                        AppToast.show(context, tr('تم تحويل {p0} إلى فاتورة مشتريات', {'p0': order.orderNumber}));
                      }
                    } catch (e) {
                      if (context.mounted) {
                        AppToast.show(context, tr('خطأ: {p0}', {'p0': e.toString()}), type: ToastType.error);
                      }
                    }
                  }),
                if (order.status != 'cancelled' && order.status != 'received') ...[
                  const SizedBox(width: 6),
                  _actionBtn(tr('إلغاء'), PhosphorIconsBold.xCircle, AppColors.error, () async {
                    await poRepo.updatePurchaseOrderStatus(order.id, 'cancelled');
                  }),
                ],
                // Field-report 2026-05-14: cancelled POs had no actions,
                // so operators couldn't recover from a mis-click on
                // إلغاء. Re-activating flips status back to 'draft' so
                // the order is editable again.
                if (order.status == 'cancelled') ...[
                  const SizedBox(width: 6),
                  _actionBtn(tr('إعادة تفعيل'), PhosphorIconsBold.arrowCounterClockwise, AppColors.info, () async {
                    await poRepo.updatePurchaseOrderStatus(order.id, 'draft');
                    if (context.mounted) {
                      AppToast.show(context, tr('تم إعادة تفعيل الطلب كمسودة'));
                    }
                  }),
                ],
                if (order.convertedToInvoiceId != null) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.success.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(PhosphorIconsBold.link, size: 12, color: AppColors.success),
                        const SizedBox(width: 4),
                        Text(tr('فاتورة #{p0}', {'p0': order.convertedToInvoiceId}),
                            style: GoogleFonts.cairo(fontSize: 10, color: AppColors.success, fontWeight: FontWeight.w700)),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _actionBtn(String label, IconData icon, Color color, Future<void> Function() onTap) {
    return InkWell(
      onTap: _actionBusy ? null : () async {
        setState(() => _actionBusy = true);
        try {
          await onTap();
        } catch (_) {
          // Issue 13 (Feature 018): if the user popped the screen while an
          // action awaited, calling setState on a disposed State throws
          // — and the rethrow paints the ErrorWidget. Guard both setState
          // calls and only rethrow when the widget is still alive so the
          // error has somewhere to surface.
          if (mounted) {
            setState(() => _actionBusy = false);
            rethrow;
          }
        } finally {
          if (mounted) setState(() => _actionBusy = false);
        }
      },
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: _actionBusy ? 0.04 : 0.08),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: color.withValues(alpha: _actionBusy ? 0.4 : 1.0)),
            const SizedBox(width: 4),
            Text(label, style: GoogleFonts.cairo(fontSize: 11, color: color.withValues(alpha: _actionBusy ? 0.4 : 1.0), fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }

  void _showCreatePODialog(BuildContext context, PurchaseOrdersRepository poRepo, IPartiesRepository partiesRepo, IBranchRepository branchRepo) async {
    final productRepo = ref.read(productRepositoryProvider);
    final allProducts = await productRepo.getAllProducts();

    int? selectedSupplierId;
    int? selectedWarehouseId;
    int? selectedCostCenterId;
    DateTime orderDate = DateTime.now();
    DateTime? expectedDate;
    final notesCtrl = TextEditingController();
    final List<Map<String, dynamic>> orderItems = [];
    double orderTotal = 0;

    void recalculate(StateSetter setDialogState) {
      orderTotal = orderItems.fold(0.0, (sum, item) => sum + (item['total'] as double));
      setDialogState(() {});
    }

    bool saving = false;

        if (!context.mounted) return;

    showDialog(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: StatefulBuilder(builder: (ctx, setDialogState) {
          return AlertDialog(
            title: Row(
              children: [
                const Icon(PhosphorIconsBold.clipboardText, color: AppColors.primary, size: 20),
                const SizedBox(width: 8),
                Text(tr('أمر شراء جديد'), style: GoogleFonts.cairo(fontWeight: FontWeight.w700)),
              ],
            ),
            content: SizedBox(
              width: 650,
              height: 550,
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Supplier autocomplete search
                    FutureBuilder<List<Party>>(
                      future: partiesRepo.getSuppliers(),
                      builder: (context, snap) {
                        final suppliers = snap.data ?? [];
                        return Autocomplete<Party>(
                          optionsBuilder: (textValue) {
                            if (textValue.text.isEmpty) return suppliers;
                            final q = textValue.text.toLowerCase();
                            return suppliers.where((s) =>
                                s.name.toLowerCase().contains(q) ||
                                (s.phone?.contains(textValue.text) ?? false));
                          },
                          displayStringForOption: (s) => s.name,
                          fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
                            return TextField(
                              controller: controller,
                              focusNode: focusNode,
                              decoration: InputDecoration(
                                labelText: tr('المورد *'),
                                hintText: tr('ابحث عن المورد...'),
                                prefixIcon: const Icon(PhosphorIconsBold.truck, size: 18),
                                border: const OutlineInputBorder(),
                                isDense: true,
                                suffixIcon: selectedSupplierId != null
                                    ? IconButton(
                                        icon: const Icon(PhosphorIconsBold.x, size: 14),
                                        onPressed: () {
                                          controller.clear();
                                          setDialogState(() => selectedSupplierId = null);
                                        },
                                      )
                                    : null,
                              ),
                              style: GoogleFonts.cairo(fontSize: 13),
                            );
                          },
                          onSelected: (supplier) {
                            setDialogState(() => selectedSupplierId = supplier.id);
                          },
                        );
                      },
                    ),
                    const SizedBox(height: 10),
                    // Warehouse dropdown — Spec 103: على جهاز عميلٍ مربوطٍ
                    // بفرع لا تُعرَض مخازنُ فروعٍ أخرى. أمرُ الشراء يتحوّل
                    // إلى فاتورةٍ تُرحَّل على فرع المخزن، فاختيارُ مخزنٍ
                    // غريبٍ هنا يُورَّث إلى المستند المالي.
                    FutureBuilder<List<Warehouse>>(
                      future: branchRepo.getScopedWarehouses(),
                      builder: (context, snap) {
                        final warehouses = snap.data ?? [];
                        return DropdownButtonFormField<int>(
                          decoration:  InputDecoration(labelText: tr('المستودع *'), isDense: true, border: const OutlineInputBorder()),
                          initialValue: selectedWarehouseId,
                          items: warehouses.map((w) => DropdownMenuItem(value: w.id, child: Text(w.name, style: const TextStyle(fontSize: 13)))).toList(),
                          onChanged: (v) => setDialogState(() => selectedWarehouseId = v),
                        );
                      },
                    ),
                    const SizedBox(height: 10),
                    // Dates row
                    Row(
                      children: [
                        Expanded(
                          child: InkWell(
                            onTap: () async {
                              final picked = await showDatePicker(
                                context: ctx,
                                initialDate: orderDate,
                                firstDate: DateTime(2020),
                                lastDate: DateTime(2050),
                              );
                              if (picked != null) setDialogState(() => orderDate = picked);
                            },
                            child: InputDecorator(
                              decoration:  InputDecoration(labelText: tr('تاريخ الأمر'), isDense: true, border: const OutlineInputBorder()),
                              child: Text(_dateFormat.format(orderDate), style: const TextStyle(fontSize: 13)),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: InkWell(
                            onTap: () async {
                              final picked = await showDatePicker(
                                context: ctx,
                                initialDate: expectedDate ?? DateTime.now().add(const Duration(days: 7)),
                                firstDate: DateTime(2020),
                                lastDate: DateTime(2050),
                              );
                              if (picked != null) setDialogState(() => expectedDate = picked);
                            },
                            child: InputDecorator(
                              decoration:  InputDecoration(labelText: tr('تاريخ التسليم المتوقع'), isDense: true, border: const OutlineInputBorder()),
                              child: Text(expectedDate != null ? _dateFormat.format(expectedDate!) : tr('اختياري'), style: const TextStyle(fontSize: 13)),
                            ),
                          ),
                        ),
                      ],
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
                          final lineTotal = product.costPrice * 1.0;
                          final taxAmt = lineTotal * (product.taxRate / 100);
                          setDialogState(() {
                            orderItems.add({
                              'productId': product.id,
                              'productName': product.name,
                              'quantity': 1.0,
                              'unitCost': product.costPrice,
                              'taxRate': product.taxRate,
                              'taxAmount': taxAmt,
                              'total': lineTotal + taxAmt,
                            });
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
                      DataTable(
                        columnSpacing: 10,
                        headingRowHeight: 32,
                        dataRowMinHeight: 30,
                        dataRowMaxHeight: 40,
                        columns:  [
                          DataColumn(label: Text(tr('الصنف'), style: const TextStyle(fontSize: 11))),
                          DataColumn(label: Text(tr('الكمية'), style: const TextStyle(fontSize: 11))),
                          DataColumn(label: Text(tr('السعر'), style: const TextStyle(fontSize: 11))),
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
                                final lineTotal = qty * (item['unitCost'] as double);
                                item['taxAmount'] = lineTotal * ((item['taxRate'] as double) / 100);
                                item['total'] = lineTotal + (item['taxAmount'] as double);
                                recalculate(setDialogState);
                              },
                            ))),
                            DataCell(SizedBox(width: 60, child: TextFormField(
                              initialValue: (item['unitCost'] as double).toStringAsFixed(AppConstants.decimalPlaces),
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              style: const TextStyle(fontSize: 11),
                              decoration: const InputDecoration(isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 4)),
                              onChanged: (val) {
                                final cost = double.tryParse(val) ?? 0;
                                item['unitCost'] = cost;
                                final lineTotal = (item['quantity'] as double) * cost;
                                item['taxAmount'] = lineTotal * ((item['taxRate'] as double) / 100);
                                item['total'] = lineTotal + (item['taxAmount'] as double);
                                recalculate(setDialogState);
                              },
                            ))),
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
                      decoration:  InputDecoration(labelText: tr('ملاحظات'), isDense: true, border: const OutlineInputBorder()),
                      maxLines: 2,
                      style: const TextStyle(fontSize: 13),
                    ),
                    // GAP-10: Cost Center dropdown
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
                            ...ccList.map((cc) => DropdownMenuItem<int?>(value: cc.id, child: Text(cc.name))),
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
                onPressed: saving ? null : () async {
                  if (selectedSupplierId == null || selectedWarehouseId == null) {
                    AppToast.show(context, tr('يجب اختيار المورد والمستودع'), type: ToastType.info);
                    return;
                  }
                  if (orderItems.isEmpty) {
                    AppToast.show(context, tr('يرجى إضافة صنف واحد على الأقل'), type: ToastType.info);
                    return;
                  }
                  setDialogState(() => saving = true);
                  try {
                    final companions = orderItems.map((item) {
                      return PurchaseOrderItemsCompanion.insert(
                        orderId: 0, // Will be set by repository
                        productId: item['productId'] as int,
                        quantity: item['quantity'] as double,
                        unitCost: item['unitCost'] as double,
                        total: item['total'] as double,
                        taxRate: Value(item['taxRate'] as double),
                        taxAmount: Value(item['taxAmount'] as double),
                      );
                    }).toList();

                    await poRepo.createPurchaseOrder(
                      supplierId: selectedSupplierId!,
                      warehouseId: selectedWarehouseId!,
                      orderDate: orderDate,
                      expectedDate: expectedDate,
                      notes: notesCtrl.text.isEmpty ? null : notesCtrl.text,
                      costCenterId: selectedCostCenterId,
                      items: companions,
                    );
                    if (ctx.mounted) Navigator.pop(ctx);
                    if (context.mounted) {
                      AppToast.show(context, tr('تم إنشاء أمر الشراء بنجاح'));
                    }
                  } catch (e) {
                    setDialogState(() => saving = false);
                    if (context.mounted) {
                      AppToast.show(context, tr('خطأ: {p0}', {'p0': e.toString()}), type: ToastType.error);
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

class _StatusInfo {
  final String label;
  final Color color;
  final IconData icon;
  const _StatusInfo(this.label, this.color, this.icon);
}
