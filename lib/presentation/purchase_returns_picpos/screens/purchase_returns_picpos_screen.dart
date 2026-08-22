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
import '../../picpos_shell/picpos_returns_panel.dart';
import '../../../domain/models/picpos_return_view.dart';

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
      body: _buildBody(state, notifier),
    );
  }

  /// تحويلُ صفِّ فاتورة المشتريات إلى صورةِ العرض المحايدة.
  ///
  /// ⚠️ **بلا اسمِ مورّد**: `PurchaseReturnState` لا تحمل خريطةَ أسماءٍ نظيرةً
  /// لـ`customerNames` في المبيعات، والشاشةُ اليوم تعرض التاريخَ وحدَه.
  /// فاشتقاقُ الاسم كان سيعني استعلاماً لكلّ صفّ (N+1) أو اختلاقاً — وكلاهما
  /// أسوأُ من سطرٍ أقصر. يُرفَع حين تحمل الحالةُ الأسماءَ كما في التوأم.
  PicPosReturnInvoiceRow _toRow(PurchaseInvoiceData inv) =>
      PicPosReturnInvoiceRow(
        id: inv.id,
        number: '# ${inv.invoiceNumber}',
        date: inv.invoiceDate,
        total: inv.total,
        status: PicPosReturnStatus.fromCode(inv.status),
      );

  Widget _buildBody(
    PurchaseReturnState state,
    PurchaseReturnNotifier notifier,
  ) {
    // ‏لا ترشيحَ في الذاكرة: كلُّ الفلاتر (المدى · الرقم · المورد · الصنف)
    // نُفِّذت في SQL، فما يصل هنا هو النتيجةُ الكاملةُ لا شريحةٌ مبتورةٌ منها.
    // فالعدّاداتُ والقائمةُ يقرآن نفسَ القائمة — بخلاف توأم المبيعات الذي
    // يرشّح بالبحث في الذاكرة فيفترقان.
    final rows = [for (final inv in state.invoices) _toRow(inv)];
    final kpis = PicPosReturnKpis.from(rows);
    final byId = {for (final inv in state.invoices) inv.id: inv};

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PicPosReturnsSummaryCards(kpis: kpis, isSales: false),
        const SizedBox(height: 12),
        const SyncPendingBanner(
          tableName: 'purchase_returns',
          label: 'مرتجع مشتريات',
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              // عمودُ القائمة أعرضُ قليلاً من توأم المبيعات (‏٤٤٠ لا ٤٠٠):
              // شريطُ الترشيح هنا يحمل منتقيَي المورد والصنف زيادةً.
              final listWidth = constraints.maxWidth < 1040
                  ? constraints.maxWidth * .40
                  : 440.0;
              return Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    width: listWidth,
                    child: PicPosReturnsInvoicePanel(
                      rows: rows,
                      selectedId: state.selectedInvoice?.id,
                      isLoading: state.isLoading,
                      emptyMessage: 'لا توجد فواتير مشتريات في هذه الفترة',
                      onSelect: (r) {
                        final inv = byId[r.id];
                        if (inv != null) notifier.selectInvoice(inv);
                      },
                      filters: _buildListFilters(state),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: buildReturnDetailsPanel(state, notifier)),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  /// شريطُ ترشيح القائمة — مدىً وبحثٌ ومنتقيا المورد والصنف.
  Widget _buildListFilters(PurchaseReturnState state) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _dateField(
                label: 'من ${state.fromDate.day}/${state.fromDate.month}',
                onTap: _selectFromDate,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _dateField(
                label: 'إلى ${state.toDate.day}/${state.toDate.month}',
                onTap: _selectToDate,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        // البحثُ يذهب إلى SQL — سابقاً كان `contains()` في الذاكرة فوق أحدث
        // ‏٥٠٠ فاتورة، فيفشل صامتاً على أيّ فاتورةٍ أقدم.
        SizedBox(
          height: 36,
          child: TextField(
            controller: _searchController,
            style: const TextStyle(fontSize: 12),
            decoration: InputDecoration(
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(vertical: 8),
              hintText: 'البحث برقم الفاتورة (رقمنا أو رقم المورد)...',
              hintStyle: TextStyle(
                fontSize: 12,
                color: picposReturnsMuted(context),
              ),
              prefixIcon: Icon(
                PhosphorIconsBold.magnifyingGlass,
                size: 14,
                color: picposReturnsMuted(context),
              ),
              prefixIconConstraints:
                  const BoxConstraints(minWidth: 34, minHeight: 34),
              filled: true,
              fillColor: Theme.of(context).scaffoldBackgroundColor,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide.none,
              ),
            ),
            onChanged: (v) =>
                ref.read(purchaseReturnProvider.notifier).setInvoiceQuery(v),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(child: _buildSupplierFilter(state.supplierId)),
            const SizedBox(width: 8),
            Expanded(child: _buildProductFilter(state.productId)),
          ],
        ),
      ],
    );
  }

  Widget _dateField({required String label, required VoidCallback onTap}) {
    final theme = Theme.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 11),
          decoration: BoxDecoration(
            border: Border.all(color: theme.dividerColor),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              Icon(PhosphorIconsBold.calendar,
                  size: 13, color: picposReturnsMuted(context)),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: theme.textTheme.bodyMedium?.color,
                  ),
                ),
              ),
            ],
          ),
        ),
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
