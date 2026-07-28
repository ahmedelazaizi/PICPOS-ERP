import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/app_error_handler.dart';
import '../../../core/widgets/app_state_view.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../core/permissions/permission_codes.dart';

import '../../../data/providers/providers.dart';
import '../../../domain/repositories/purchases_repository.dart' show PurchaseReturnItem;
import '../../../services/invoice_generator.dart';

import '../../providers/purchase_return_provider.dart';
import '../../widgets/permission_guard.dart'; // B5: Manager approval
import '../../widgets/common/common.dart';

import '../../picpos_shell/picpos_screen_scaffold.dart';
import '../../picpos_shell/picpos_content_card.dart';

// ── Part files (منسوخة حرفياً من lib/presentation/screens/purchase_returns/ —
// الشاشة الأصل `part of` خاص فما ينفعش تتعمل import، فبتنتقل بنسخ حرفي هنا؛
// راجع تعليق مصيدة النسخ في رأس كل ملف). ──────────────────────────────────
part 'purchase_returns_picpos_logic.dart';
part 'purchase_returns_picpos_details.dart';

/// شاشة مرتجع المشتريات بهوية PicPos. تُختار بالعلامة في app_main_screen
/// (`Brand.isPicPos`). تعيد استخدام نفس `purchaseReturnProvider` (وتوابعه
/// `PurchaseReturnState`/`PurchaseReturnNotifier`) و`InvoiceGenerator` و
/// `SyncPendingBanner` من UralCash — فقط طبقة العرض تبدّلت لـ `picpos_shell`.
///
/// الفلاتر (`_buildSupplierFilter`/`_buildProductFilter`) والقائمة
/// (`_buildInvoiceList`) inline كما في الأصل، ولوحة التفاصيل تأتي من mixin
/// منسوخ (`buildReturnDetailsPanel`). الشكل العام «قائمة + تفاصيل» (Row
/// بعمودين) محفوظ من الأصل بلا تغيير، وكذلك كل الإجراءات: حوار «سجل
/// المرتجعات» (`showReturnsHistoryDialog`)، تدفّق تأكيد الإرجاع/الطباعة A4،
/// تصنيف سبب الإرجاع (B4)، الموافقة الإدارية على المرتجعات عالية القيمة (B5)،
/// وتعديل مرتجع مُرحّل (Feature 015، محكوم بصلاحية `purchases_return_edit`).
///
/// راجع lib/presentation/screens/purchase_returns_screen.dart (الأصل).
class PurchaseReturnsPicposScreen extends ConsumerStatefulWidget {
  const PurchaseReturnsPicposScreen({super.key});

  @override
  ConsumerState<PurchaseReturnsPicposScreen> createState() =>
      _PurchaseReturnsPicposScreenState();
}

class _PurchaseReturnsPicposScreenState
    extends ConsumerState<PurchaseReturnsPicposScreen>
    with _PurchaseReturnsPicposLogic, _PurchaseReturnsPicposDetailsPanel {
  final _searchController = TextEditingController();
  final _returnReasonController = TextEditingController(); // B4
  String _selectedReasonCategory = ''; // B4: Return reason categorization

  @override
  void initState() {
    super.initState();
    Future.microtask(
      () => ref.read(purchaseReturnProvider.notifier).loadInvoices(),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    _returnReasonController.dispose();
    super.dispose();
  }

  Future<void> _selectFromDate() async {
    final state = ref.read(purchaseReturnProvider);
    final date = await showDatePicker(
      context: context,
      initialDate: state.fromDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (date != null) {
      ref.read(purchaseReturnProvider.notifier).setFromDate(date);
    }
  }

  Future<void> _selectToDate() async {
    final state = ref.read(purchaseReturnProvider);
    final date = await showDatePicker(
      context: context,
      initialDate: state.toDate,
      firstDate: state.fromDate,
      lastDate: DateTime.now(),
    );
    if (date != null) {
      ref.read(purchaseReturnProvider.notifier).setToDate(date);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(purchaseReturnProvider);
    final notifier = ref.read(purchaseReturnProvider.notifier);

    return PicPosScreenScaffold(
      title: 'مرتجع المشتريات',
      subtitle: 'تسجيل ومتابعة مرتجعات الشراء',
      icon: PhosphorIconsBold.arrowUUpLeft,
      headerActions: [
        OutlinedButton.icon(
          onPressed: showReturnsHistoryDialog,
          icon: const Icon(PhosphorIconsBold.clockCounterClockwise, size: 16),
          label: const Text('سجل المرتجعات'),
        ),
      ],
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Left side - Purchase invoice list
          Expanded(
            flex: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SyncPendingBanner(
                  tableName: 'purchase_returns',
                  label: 'مرتجع مشتريات',
                ),
                const SizedBox(height: 12),
                // Filters card
                PicPosContentCard(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(
                            PhosphorIconsBold.funnel,
                            size: 18,
                            color: AppColors.primary,
                          ),
                          SizedBox(width: 8),
                          Text(
                            'تصفية',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: InkWell(
                              onTap: _selectFromDate,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 10,
                                ),
                                decoration: BoxDecoration(
                                  border: Border.all(
                                    color: AppColors.textMuted
                                        .withValues(alpha: 0.3),
                                  ),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(
                                      PhosphorIconsBold.calendar,
                                      size: 16,
                                      color: AppColors.textMuted,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      'من: ${state.fromDate.day}/${state.fromDate.month}/${state.fromDate.year}',
                                      style: const TextStyle(fontSize: 13),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: InkWell(
                              onTap: _selectToDate,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 10,
                                ),
                                decoration: BoxDecoration(
                                  border: Border.all(
                                    color: AppColors.textMuted
                                        .withValues(alpha: 0.3),
                                  ),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(
                                      PhosphorIconsBold.calendar,
                                      size: 16,
                                      color: AppColors.textMuted,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      'إلى: ${state.toDate.day}/${state.toDate.month}/${state.toDate.year}',
                                      style: const TextStyle(fontSize: 13),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      // البند 7: البحث يذهب الآن إلى SQL. سابقاً كان
                      // `contains()` في الذاكرة فوق أحدث 500 فاتورة —
                      // فيفشل صامتاً على أي فاتورة أقدم.
                      TextField(
                        controller: _searchController,
                        decoration: InputDecoration(
                          hintText: 'البحث برقم الفاتورة (رقمنا أو رقم المورد)...',
                          prefixIcon: const Icon(
                            PhosphorIconsBold.magnifyingGlass,
                            size: 16,
                          ),
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                            vertical: 10,
                            horizontal: 12,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        onChanged: (v) => ref
                            .read(purchaseReturnProvider.notifier)
                            .setInvoiceQuery(v),
                      ),
                      const SizedBox(height: 10),
                      // البند 7: فلترا المورد والصنف.
                      Row(
                        children: [
                          Expanded(
                            child: _buildSupplierFilter(state.supplierId),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _buildProductFilter(state.productId),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Invoice list header
                Row(
                  children: [
                    const Icon(
                      PhosphorIconsBold.listDashes,
                      size: 18,
                      color: AppColors.primary,
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'الفواتير',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '${state.invoices.length} فاتورة',
                      style: const TextStyle(color: AppColors.textMuted),
                    ),
                  ],
                ),
                const SizedBox(height: 8),

                // Invoice list
                Expanded(
                  child: PicPosContentCard(
                    padding: const EdgeInsets.all(8),
                    child: _buildInvoiceList(state, notifier),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(width: 16),

          // Right side - Return details
          Expanded(
            flex: 3,
            child: buildReturnDetailsPanel(state, notifier),
          ),
        ],
      ),
    );
  }

  /// البند 7 — فلتر المورد. القائمة تُبنى من الموردين المعرَّفين فعلاً، عبر
  /// نفس المسار الذي تستعمله شاشة فاتورة المشتريات (`getSuppliers`) بدل
  /// استحداث مزوّد جديد.
  Widget _buildSupplierFilter(int? selected) {
    return FutureBuilder(
      future: ref.read(productRepositoryProvider).getSuppliers(),
      builder: (context, snapshot) {
        final suppliers = snapshot.data ?? const [];
        return DropdownButtonFormField<int?>(
          initialValue: selected,
          isExpanded: true,
          isDense: true,
          style: const TextStyle(fontSize: 13, color: AppColors.textPrimary),
          decoration: InputDecoration(
            hintText: 'المورد',
            prefixIcon: const Icon(PhosphorIconsBold.truck, size: 16),
            isDense: true,
            contentPadding:
                const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          ),
          items: [
            const DropdownMenuItem<int?>(
              value: null,
              child: Text('كل الموردين', style: TextStyle(fontSize: 13)),
            ),
            for (final s in suppliers)
              DropdownMenuItem<int?>(
                value: s.id,
                child: Text(s.name,
                    style: const TextStyle(fontSize: 13),
                    overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: (v) =>
              ref.read(purchaseReturnProvider.notifier).setSupplierFilter(v),
        );
      },
    );
  }

  /// البند 7 — فلتر الصنف: «الصنف الموجود في جميع الفواتير».
  Widget _buildProductFilter(int? selected) {
    final productsAsync = ref.watch(allProductsProvider);
    return productsAsync.when(
      loading: () => const SizedBox(height: 40),
      error: (_, _) => const SizedBox(height: 40),
      data: (products) => DropdownButtonFormField<int?>(
        initialValue: selected,
        isExpanded: true,
        isDense: true,
        style: const TextStyle(fontSize: 13, color: AppColors.textPrimary),
        decoration: InputDecoration(
          hintText: 'الصنف',
          prefixIcon: const Icon(PhosphorIconsBold.package, size: 16),
          isDense: true,
          contentPadding:
              const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        ),
        items: [
          const DropdownMenuItem<int?>(
            value: null,
            child: Text('كل الأصناف', style: TextStyle(fontSize: 13)),
          ),
          for (final p in products)
            DropdownMenuItem<int?>(
              value: p.id,
              child: Text(p.name,
                  style: const TextStyle(fontSize: 13),
                  overflow: TextOverflow.ellipsis),
            ),
        ],
        onChanged: (v) =>
            ref.read(purchaseReturnProvider.notifier).setProductFilter(v),
      ),
    );
  }

  Widget _buildInvoiceList(
    PurchaseReturnState state,
    PurchaseReturnNotifier notifier,
  ) {
    // البند 7: لا ترشيح في الذاكرة بعد الآن — كل الفلاتر نُفِّذت في SQL، فما
    // يصل هنا هو النتيجة الكاملة لا شريحة مبتورة منها.
    final invoices = state.invoices;

    // Day 11: unified loading / empty states via AppStateView.
    return AppStateView(
      isLoading: state.isLoading && invoices.isEmpty,
      isEmpty: invoices.isEmpty,
      emptyMessage: 'لا توجد فواتير مشتريات في هذه الفترة',
      emptyIcon: PhosphorIconsBold.receipt,
      child: ListView.builder(
        itemCount: invoices.length,
        itemBuilder: (ctx, index) {
          final invoice = invoices[index];
          final isSelected = state.selectedInvoice?.id == invoice.id;

          return Card(
            color: isSelected ? AppColors.primary.withValues(alpha: 0.1) : null,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
              side: isSelected
                  ? const BorderSide(color: AppColors.primary, width: 2)
                  : BorderSide.none,
            ),
            child: ListTile(
              onTap: () => notifier.selectInvoice(invoice),
              leading: CircleAvatar(
                backgroundColor:
                    isSelected ? AppColors.primary : AppColors.info.withValues(alpha: 0.1),
                child: Icon(PhosphorIconsBold.receipt,
                    size: 18, color: isSelected ? Colors.white : AppColors.info),
              ),
              title: Text(
                '# ${invoice.invoiceNumber}',
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: isSelected ? AppColors.primary : null),
              ),
              subtitle: Text(
                '${invoice.invoiceDate.day}/${invoice.invoiceDate.month}/${invoice.invoiceDate.year}',
                style: const TextStyle(fontSize: 12),
              ),
              trailing: Text(
                '${invoice.total.toStringAsFixed(AppConstants.decimalPlaces)} ${AppConstants.currencySymbolEn}',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          );
        },
      ),
    );
  }

  double _calculateReturnTotal() {
    final state = ref.read(purchaseReturnProvider);
    if (state.invoiceItems.isEmpty) return 0;
    double total = 0;
    for (final item in state.invoiceItems) {
      final qty = state.returnQuantities[item.item.id] ?? 0;
      total += qty * item.item.unitCost;
    }
    return total;
  }
}
