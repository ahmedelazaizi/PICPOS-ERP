import 'package:flutter/material.dart';
import 'package:ural_erp/core/widgets/app_toast.dart';
import 'package:ural_erp/core/utils/app_error_handler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/shimmer_loading.dart';

import '../../../data/providers/providers.dart';
import '../../../services/generators/thermal_receipt_generator.dart';
import '../../../services/invoice_generator.dart';

import '../../providers/sales_return_provider.dart';
import '../../../domain/entities/product_entity.dart';
import '../../widgets/permission_guard.dart'; // B5: Manager approval
// دفعة ٩ — حرّاس sales_return_delete و sales_return_print في ملف الـlogic.
import '../../../core/permissions/permission_codes.dart';
import '../../widgets/common/common.dart';

import '../../shared_widgets/open_shift_prompt.dart';
import '../../picpos_shell/picpos_screen_scaffold.dart';
import '../../picpos_shell/picpos_content_card.dart';
import '../../picpos_shell/picpos_returns_panel.dart';
import '../../../domain/models/picpos_return_view.dart';

// ── Part files (منسوخة حرفياً من lib/presentation/screens/sales_returns/ —
// الشاشة الأصل `part of _SalesReturnsScreenState` خاصة فما ينفعش تتعمل import،
// فبتنتقل بنسخ حرفي هنا؛ راجع تعليق مصيدة النسخ في رأس كل ملف). ──────────────
part 'sales_returns_picpos_logic.dart';
part 'sales_returns_picpos_details.dart';

/// شاشة مرتجع المبيعات بهوية PicPos. تُختار بالعلامة في app_main_screen
/// (`Brand.isPicPos`). تعيد استخدام نفس `salesReturnProvider` (وتوابعه
/// `SalesReturnState`/`SalesReturnNotifier`) و`ThermalReceiptGenerator` و
/// `SyncPendingBanner` من UralCash — فقط طبقة العرض تبدّلت لـ `picpos_shell`.
///
/// القائمة (`_buildInvoiceList`) inline كما في الأصل، ولوحة التفاصيل تأتي من
/// mixin منسوخ (`buildReturnDetailsPanel`). الشكل العام «قائمة + تفاصيل»
/// (Row بعمودين) محفوظ من الأصل بلا تغيير، وكذلك كل الإجراءات: حوار «سجل
/// المرتجعات» (`showReturnsHistoryDialog`)، تدفّق تأكيد الإرجاع/الطباعة،
/// وضع الاستبدال، وضع الإتلاف، تصنيف سبب الإرجاع، والموافقة الإدارية على
/// المرتجعات عالية القيمة.
///
/// راجع lib/presentation/screens/sales_returns_screen.dart (الأصل).
class SalesReturnsPicposScreen extends ConsumerStatefulWidget {
  final SalesInvoiceData? initialInvoice;

  const SalesReturnsPicposScreen({super.key, this.initialInvoice});

  @override
  ConsumerState<SalesReturnsPicposScreen> createState() =>
      _SalesReturnsPicposScreenState();
}

class _SalesReturnsPicposScreenState
    extends ConsumerState<SalesReturnsPicposScreen>
    with _SalesReturnsPicposLogic, _SalesReturnsPicposDetailsPanel {
  final _invoiceSearchController = TextEditingController();
  final _returnReasonController = TextEditingController();
  String _selectedReasonCategory = ''; // B4: Return reason categorization

  @override
  TextEditingController get returnReasonController => _returnReasonController;

  @override
  void initState() {
    super.initState();
    if (widget.initialInvoice != null) {
      Future.microtask(
        () => ref
            .read(salesReturnProvider.notifier)
            .selectInvoice(widget.initialInvoice!),
      );
    } else {
      Future.microtask(
        () => ref.read(salesReturnProvider.notifier).loadInvoices(),
      );
    }
  }

  @override
  void dispose() {
    _invoiceSearchController.dispose();
    _returnReasonController.dispose();
    super.dispose();
  }

  Future<void> _selectFromDate() async {
    final state = ref.read(salesReturnProvider);
    final date = await showDatePicker(
      context: context,
      initialDate: state.fromDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (date != null) {
      ref.read(salesReturnProvider.notifier).setFromDate(date);
    }
  }

  Future<void> _selectToDate() async {
    final state = ref.read(salesReturnProvider);
    final date = await showDatePicker(
      context: context,
      initialDate: state.toDate,
      firstDate: state.fromDate,
      lastDate: DateTime.now(),
    );
    if (date != null) {
      ref.read(salesReturnProvider.notifier).setToDate(date);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(salesReturnProvider);
    final notifier = ref.read(salesReturnProvider.notifier);

    ref.listen(salesReturnProvider.select((s) => s.error), (previous, next) {
      if (next != null) {
        AppToast.show(context, next.toString(), type: ToastType.error);
        notifier.clearError();
      }
    });

    return PicPosScreenScaffold(
      title: 'مرتجع المبيعات',
      subtitle: 'تسجيل ومتابعة مرتجعات البيع',
      icon: PhosphorIconsBold.arrowUUpLeft,
      headerActions: [
        OutlinedButton.icon(
          onPressed: () => showReturnsHistoryDialog(),
          icon: const Icon(PhosphorIconsBold.clockCounterClockwise, size: 16),
          label: const Text('سجل المرتجعات'),
        ),
      ],
      body: _buildBody(state, notifier),
    );
  }

  /// تحويلُ صفِّ الفاتورة إلى صورةِ العرض المحايدة.
  ///
  /// اسمُ العميل يأتي من `state.customerNames` المحمَّلةِ مسبقاً — لا استعلامَ
  /// لكلّ صفّ. وغيابُه يعني «عميل نقدي» كما كانت الشاشةُ تعرضه بالضبط.
  PicPosReturnInvoiceRow _toRow(SalesInvoiceData inv, SalesReturnState state) =>
      PicPosReturnInvoiceRow(
        id: inv.id,
        number: '# ${inv.invoiceNumber}',
        date: inv.invoiceDate,
        total: inv.total,
        status: PicPosReturnStatus.fromCode(inv.status),
        partyName: state.customerNames[inv.customerId] ?? 'عميل نقدي',
      );

  Widget _buildBody(SalesReturnState state, SalesReturnNotifier notifier) {
    final allRows = [for (final inv in state.invoices) _toRow(inv, state)];
    // العدّاداتُ من فواتير المدى كلِّها؛ القائمةُ من المرشَّحة بالبحث.
    final kpis = PicPosReturnKpis.from(allRows);
    final rows = allRows
        .where((r) => r.matchesNumber(_invoiceSearchController.text))
        .toList();
    final byId = {for (final inv in state.invoices) inv.id: inv};

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PicPosReturnsSummaryCards(kpis: kpis, isSales: true),
        const SizedBox(height: 12),
        const SyncPendingBanner(
          tableName: 'sales_returns',
          label: 'مرتجع مبيعات',
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              // ‏٤٠٠ بكسلٍ هو عمودُ التصميم (`400px 1fr`)، لكنّه يتقلّص على
              // لوحٍ ضيّقٍ بدل أن يسحق لوحَ التفاصيل إلى لا شيء.
              final listWidth =
                  constraints.maxWidth < 1000 ? constraints.maxWidth * .38 : 400.0;
              return Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    width: listWidth,
                    child: PicPosReturnsInvoicePanel(
                      rows: rows,
                      selectedId: state.selectedInvoice?.id,
                      isLoading: state.isLoading,
                      emptyMessage: 'لا توجد فواتير في هذه الفترة',
                      onSelect: (r) {
                        final inv = byId[r.id];
                        if (inv != null) notifier.selectInvoice(inv);
                      },
                      filters: _buildListFilters(state),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: _buildDetailsSide(state, notifier)),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  /// شريطُ ترشيح القائمة — مدىً وبحث. يُبنى هنا لا في اللوح المشترك، لأن
  /// شاشةَ المشتريات ترشّح في SQL ولها منتقي مورّدٍ إضافيّ.
  Widget _buildListFilters(SalesReturnState state) {
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
        SizedBox(
          height: 36,
          child: TextField(
            controller: _invoiceSearchController,
            style: const TextStyle(fontSize: 12),
            decoration: InputDecoration(
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(vertical: 8),
              hintText: 'البحث برقم الفاتورة...',
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
            onChanged: (_) => setState(() {}),
          ),
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

  Widget _buildDetailsSide(
    SalesReturnState state,
    SalesReturnNotifier notifier,
  ) {
    if (state.selectedInvoice == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              PhosphorIconsBold.arrowCounterClockwise,
              size: 80,
              color: AppColors.textMuted.withValues(alpha: 0.3),
            ),
            const SizedBox(height: 24),
            const Text(
              'اختر فاتورة من القائمة لعرض تفاصيلها',
              style: TextStyle(color: AppColors.textMuted, fontSize: 16),
            ),
          ],
        ),
      );
    }
    if (state.isLoading) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: ShimmerLoading.list(itemCount: 6),
      );
    }
    return buildReturnDetailsPanel(state, notifier);
  }
}
