import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/constants/app_constants.dart';
import '../../../data/providers/providers.dart';
import '../../../domain/repositories/sales_repository.dart';

/// Dialog for viewing and reprinting/editing previous invoices from the current shift
class PosPreviousInvoicesDialog extends ConsumerStatefulWidget {
  final Function(SalesInvoiceData) onEdit;
  final Function(int) onReprint;
  final Function(int) onPrintKitchen;

  const PosPreviousInvoicesDialog({
    super.key,
    required this.onEdit,
    required this.onReprint,
    required this.onPrintKitchen,
  });

  /// Static helper to show the dialog
  static Future<void> show(
    BuildContext context, {
    required Function(SalesInvoiceData) onEdit,
    required Function(int) onReprint,
    required Function(int) onPrintKitchen,
  }) async {
    return showDialog<void>(
      context: context,
      builder: (context) => PosPreviousInvoicesDialog(
        onEdit: onEdit,
        onReprint: onReprint,
        onPrintKitchen: onPrintKitchen,
      ),
    );
  }

  @override
  ConsumerState<PosPreviousInvoicesDialog> createState() =>
      _PosPreviousInvoicesDialogState();
}

class _PosPreviousInvoicesDialogState
    extends ConsumerState<PosPreviousInvoicesDialog> {
  String _invoiceSearchQuery = '';
  String _orderSearchQuery = '';
  DateTime? _shiftStartTime;

  @override
  void initState() {
    super.initState();
    _loadShiftStartTime();
  }

  Future<void> _loadShiftStartTime() async {
    final treasuryRepo = ref.read(treasuryRepositoryProvider);
    final authState = ref.read(authProvider);
    final userId = authState.user?.id ?? 1;
    final shift = await treasuryRepo.getCurrentOpenShift(userId);
    if (mounted) {
      setState(() {
        _shiftStartTime = shift?.startTime;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final salesRepo = ref.read(salesRepositoryProvider);
    final authState = ref.watch(authProvider);

    return Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        title: const Row(
          children: [
            Icon(PhosphorIconsBold.receipt, color: AppColors.info),
            SizedBox(width: 8),
            Text('الفواتير السابقة'),
            Spacer(),
            Text(
              'اليوم',
              style: TextStyle(fontSize: 12, color: AppColors.textMuted),
            ),
          ],
        ),
        content: SizedBox(
          width: 700,
          height: 600,
          child: Column(
            children: [
              // Search Fields Row
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      decoration: InputDecoration(
                        hintText: 'بحث برقم الفاتورة',
                        prefixIcon: const Icon(
                          PhosphorIconsBold.magnifyingGlass,
                          size: 18,
                        ),
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      onChanged: (value) =>
                          setState(() => _invoiceSearchQuery = value),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      decoration: InputDecoration(
                        hintText: 'بحث برقم الطلب',
                        prefixIcon: const Icon(
                          PhosphorIconsBold.hash,
                          size: 18,
                        ),
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      keyboardType: TextInputType.number,
                      onChanged: (value) =>
                          setState(() => _orderSearchQuery = value),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Divider(height: 1),
              const SizedBox(height: 8),

              // Invoices List
              Expanded(
                child: FutureBuilder<Map<int, String>>(
                  future: _getUserMap(),
                  builder: (context, userSnap) {
                    final userMap = userSnap.data ?? {};
                    return StreamBuilder<List<SalesInvoiceData>>(
                      stream: _getInvoicesStream(salesRepo, authState),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState ==
                            ConnectionState.waiting) {
                          return const Center(
                            child: CircularProgressIndicator(),
                          );
                        }

                        var filteredInvoices = snapshot.data ?? [];
                        filteredInvoices = _applyFilters(
                          filteredInvoices,
                          authState,
                        );

                        if (filteredInvoices.isEmpty) {
                          return _buildEmptyState();
                        }

                        return ListView.separated(
                          itemCount: filteredInvoices.length,
                          separatorBuilder: (_, _) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final invoice = filteredInvoices[index];
                            return _buildInvoiceTile(context, invoice, userMap);
                          },
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
        ],
      ),
    );
  }

  Stream<List<SalesInvoiceData>> _getInvoicesStream(
    SalesRepository salesRepo,
    AuthState authState,
  ) {
    final isAdmin = authState.isAdmin ||
        authState.isManager ||
        authState.user?.id == null;
    final shiftStart = _shiftStartTime;
    // Spec 136 ISS-25 — scope to the OPEN SHIFT window so a shift that crosses
    // midnight keeps showing its pre-midnight invoices (the calendar-day
    // streams dropped them at 00:00). Admin/manager → whole shift window;
    // cashier → own invoices in the window. No open shift → legacy "today".
    if (shiftStart != null) {
      return salesRepo.watchSalesSince(
        shiftStart,
        userId: isAdmin ? null : authState.user!.id,
      );
    }
    if (isAdmin) {
      return salesRepo.watchTodaySales();
    }
    return salesRepo.watchTodaySalesForUser(authState.user!.id);
  }

  List<SalesInvoiceData> _applyFilters(
    List<SalesInvoiceData> invoices,
    AuthState authState,
  ) {
    var filtered = invoices;

    // Spec 136 ISS-25 — the shift-window scoping now happens in the stream
    // (_getInvoicesStream), so no client-side shift filter is needed here; a
    // client filter could only ever HIDE rows, never recover the pre-midnight
    // ones the old calendar-day stream dropped. Search filters only below.

    // Search query filters
    if (_invoiceSearchQuery.isNotEmpty) {
      filtered = filtered
          .where(
            (inv) => inv.invoiceNumber.toLowerCase().contains(
              _invoiceSearchQuery.toLowerCase(),
            ),
          )
          .toList();
    }

    if (_orderSearchQuery.isNotEmpty) {
      final orderNum = int.tryParse(_orderSearchQuery);
      if (orderNum != null) {
        filtered = filtered
            .where((inv) => inv.orderNumber == orderNum)
            .toList();
      } else {
        filtered = filtered
            .where(
              (inv) =>
                  inv.orderNumber?.toString().contains(_orderSearchQuery) ??
                  false,
            )
            .toList();
      }
    }

    return filtered;
  }

  Widget _buildInvoiceTile(
    BuildContext context,
    SalesInvoiceData invoice,
    Map<int, String> userMap,
  ) {
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: AppColors.success.withValues(alpha: 0.1),
        child: Text(
          invoice.orderNumber != null
              ? '#${invoice.orderNumber}'
              : '#${invoice.id}',
          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
        ),
      ),
      title: Row(
        children: [
          Text(
            'فاتورة #${invoice.invoiceNumber}',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          if (invoice.orderNumber != null) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.info.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                'طلب ${invoice.orderNumber}',
                style: const TextStyle(
                  fontSize: 10,
                  color: AppColors.info,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ],
      ),
      subtitle: Text(
        '${userMap[invoice.userId] ?? ''} | ${invoice.createdAt.hour}:${invoice.createdAt.minute.toString().padLeft(2, '0')} - ${invoice.paymentMethod}',
        style: const TextStyle(fontSize: 12),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '${invoice.total.toStringAsFixed(AppConstants.decimalPlaces)} ${AppConstants.currencySymbolAr}',
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              color: AppColors.success,
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(
              PhosphorIconsBold.eye,
              size: 20,
              color: AppColors.info,
            ),
            onPressed: () => _showInvoiceDetails(context, invoice),
            tooltip: 'تفاصيل الأصناف',
          ),
          IconButton(
            icon: const Icon(
              PhosphorIconsBold.pencilSimple,
              size: 20,
              color: AppColors.warning,
            ),
            onPressed: () {
              Navigator.pop(context);
              widget.onEdit(invoice);
            },
            tooltip: 'تعديل الفاتورة',
          ),
          IconButton(
            icon: const Icon(
              PhosphorIconsBold.cookingPot,
              size: 20,
              color: AppColors.info,
            ),
            onPressed: () => widget.onPrintKitchen(invoice.id),
            tooltip: 'طباعة المطبخ',
          ),
          IconButton(
            icon: const Icon(PhosphorIconsBold.printer, size: 20),
            onPressed: () => widget.onReprint(invoice.id),
            tooltip: 'إعادة طباعة',
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            PhosphorIconsBold.receiptX,
            size: 64,
            color: AppColors.textMuted,
          ),
          const SizedBox(height: 16),
          Text(
            _invoiceSearchQuery.isEmpty && _orderSearchQuery.isEmpty
                ? 'لا توجد فواتير اليوم'
                : 'لا توجد نتائج بحث',
            style: const TextStyle(color: AppColors.textMuted),
          ),
        ],
      ),
    );
  }

  Future<void> _showInvoiceDetails(
    BuildContext context,
    SalesInvoiceData invoice,
  ) async {
    final salesRepo = ref.read(salesRepositoryProvider);
    final productRepo = ref.read(productRepositoryProvider);
    final items = await salesRepo.getSalesInvoiceItems(invoice.id);

    // Fetch product names since they aren't in the items record
    final productMap = <int, String>{};
    for (final item in items) {
      if (!productMap.containsKey(item.productId)) {
        final product = await productRepo.getProductById(item.productId);
        productMap[item.productId] = product?.name ?? 'منتج غير معروف';
      }
    }

    if (!context.mounted) return;

    showDialog(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: Text('أصناف فاتورة #${invoice.invoiceNumber}'),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 400),
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: items.length,
                    itemBuilder: (context, index) {
                      final item = items[index];
                      final productName =
                          productMap[item.productId] ?? 'منتج غير معروف';
                      return ListTile(
                        dense: true,
                        title: Text(
                          productName,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Text(
                          '${item.quantity} x ${item.unitPrice.toStringAsFixed(AppConstants.decimalPlaces)} ${AppConstants.currencySymbolEn}',
                        ),
                        trailing: Text(
                          '${item.total.toStringAsFixed(AppConstants.decimalPlaces)} ${AppConstants.currencySymbolEn}',
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
                      const Text(
                        'الإجمالي',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      Text(
                        '${invoice.total.toStringAsFixed(AppConstants.decimalPlaces)} ${AppConstants.currencySymbolEn}',
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
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('إغلاق'),
            ),
          ],
        ),
      ),
    );
  }

  Future<Map<int, String>> _getUserMap() async {
    final authRepo = ref.read(authRepositoryProvider);
    final allUsers = await authRepo.watchAllUsers().first;
    return {
      for (final u in allUsers)
        u.user.id: u.user.displayName.isNotEmpty ? u.user.displayName : u.user.username,
    };
  }
}
