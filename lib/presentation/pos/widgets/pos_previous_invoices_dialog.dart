import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/constants/app_constants.dart';
import '../../../data/providers/providers.dart';
import '../../../domain/repositories/sales_repository.dart';
import 'pos_invoice_items_view.dart';

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

                        // The footer is built from `filteredInvoices` — the
                        // exact list the ListView renders — so the count and
                        // sum always describe what is on screen: they follow
                        // both search boxes and recompute on every stream tick.
                        return Column(
                          children: [
                            Expanded(
                              child: filteredInvoices.isEmpty
                                  ? _buildEmptyState()
                                  : ListView.separated(
                                      itemCount: filteredInvoices.length,
                                      separatorBuilder: (_, _) =>
                                          const Divider(height: 1),
                                      itemBuilder: (context, index) {
                                        final invoice = filteredInvoices[index];
                                        return _buildInvoiceTile(
                                            context, invoice, userMap);
                                      },
                                    ),
                            ),
                            _buildTotalsFooter(filteredInvoices),
                          ],
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
    // No authenticated user → empty list, not "everything".
    //
    // The old predicate folded `user?.id == null` into `isAdmin`, which existed
    // only to avoid the `user!.id` null-assertion two lines down — but the
    // effect was that a null user was treated as an ADMIN and shown every
    // invoice in the shift. Reaching the POS requires a login, so this branch
    // should be unreachable; if it is ever reached, showing nothing is the
    // safe failure and the assertion below is then provably safe.
    final user = authState.user;
    if (user == null) return Stream.value(const []);

    // مدير النظام بس هو اللي بيشوف كل فواتير الوردية. قبل كده كانت
    // `isAdmin || isManager`، وهي بتتحدد بمطابقة اسم الدور — فـ«مدير فرع»
    // كان بيشوف فواتير كل الكاشيرية بلا صلاحية.
    final isAdmin = authState.hasSystemAdminBypass;
    final shiftStart = _shiftStartTime;
    // Spec 136 ISS-25 — scope to the OPEN SHIFT window so a shift that crosses
    // midnight keeps showing its pre-midnight invoices (the calendar-day
    // streams dropped them at 00:00). Admin/manager → whole shift window;
    // cashier → own invoices in the window. No open shift → legacy "today".
    if (shiftStart != null) {
      return salesRepo.watchSalesSince(
        shiftStart,
        userId: isAdmin ? null : user.id,
      );
    }
    if (isAdmin) {
      return salesRepo.watchTodaySales();
    }
    return salesRepo.watchTodaySalesForUser(user.id);
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

  /// Count + sum of the rows currently displayed.
  ///
  /// ── Why «إجمالي المعروض» and never «إجمالي المبيعات» ──────────────────
  /// This is the gross total of the visible rows, and it deliberately does NOT
  /// net returns: the streams behind this dialog exclude return invoices
  /// entirely, so netting would mean pulling rows back in that the list above
  /// does not show — a footer that silently disagrees with its own table.
  /// The authoritative net figure for a shift stays the shift-closing dialog.
  ///
  /// Voided invoices are NOT summed, and need no extra filter here:
  /// `SalesActionsDao.voidSalesInvoice` sets `isDeleted: true` alongside
  /// `status: 'voided'`, so every stream feeding this dialog already drops them
  /// via its existing `isDeleted.equals(false)` predicate.
  ///
  /// It renders `0` rather than disappearing when the list is empty. A footer
  /// that vanishes reads as a rendering bug, and "zero sales this shift" is
  /// itself information the cashier wants confirmed.
  Widget _buildTotalsFooter(List<SalesInvoiceData> invoices) {
    final total = invoices.fold<double>(0, (sum, inv) => sum + inv.total);
    final isFiltered =
        _invoiceSearchQuery.isNotEmpty || _orderSearchQuery.isNotEmpty;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border)),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(8)),
      ),
      child: Row(
        children: [
          const Icon(PhosphorIconsBold.receipt,
              size: 16, color: AppColors.textMuted),
          const SizedBox(width: 6),
          Text(
            'عدد الفواتير: ${invoices.length}',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          if (isFiltered) ...[
            const SizedBox(width: 8),
            const Text(
              '(حسب البحث)',
              style: TextStyle(fontSize: 11, color: AppColors.textMuted),
            ),
          ],
          const Spacer(),
          const Text(
            'إجمالي المعروض:',
            style: TextStyle(color: AppColors.textMuted),
          ),
          const SizedBox(width: 6),
          Text(
            '${total.toStringAsFixed(AppConstants.decimalPlaces)} '
            '${AppConstants.currencySymbolAr}',
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              color: AppColors.success,
              fontSize: 16,
            ),
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

  /// Line-item detail for one invoice.
  ///
  /// Body delegated to the shared [PosInvoiceItemsView] — which also replaced
  /// the per-item `getProductById` loop this used to run before it could paint.
  /// A reprint button was added: the operator was already one click from the
  /// printer icon in the row behind this dialog, and having to close it to
  /// reach that was pure friction.
  void _showInvoiceDetails(
    BuildContext context,
    SalesInvoiceData invoice,
  ) {
    showDialog<void>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: Text('أصناف فاتورة #${invoice.invoiceNumber}'),
          content: SizedBox(
            width: 400,
            child: PosInvoiceItemsView(
              invoiceId: invoice.id,
              invoiceTotal: invoice.total,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('إغلاق'),
            ),
            ElevatedButton.icon(
              onPressed: () => widget.onReprint(invoice.id),
              icon: const Icon(PhosphorIconsBold.printer, size: 18),
              label: const Text('إعادة الطباعة'),
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
