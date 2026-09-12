// ignore_for_file: library_private_types_in_public_api
// نسخةُ PicPos من قائمة فواتير البيع. المنطقُ (الحقولُ المعروضة، حجبُ
// المبالغ، الاختيارُ، الإجراءاتُ وحرّاسُها، شارةُ المرتجع) يبقى مطابقاً
// لتوأمِ UralCash في
// `screens/widgets/sales_invoices/sales_invoices_table.dart` — وأيُّ إصلاحٍ
// منطقيٍّ يتصلّح في المصدر أوّلاً ثمّ patch (مصيدة النسخ §٥.٨).
//
// ⚠️ **والشكلُ وحدَه هو الذي تباعد** (تصميمُ PicPos 2026-08-21): صفوفُ
// `DataTable2` صارت بطاقاتٍ في `ListView.builder`.
//
// ═══ ولماذا `ListView.builder` بالذات ═══
//
// لأن `DataTable2` **مُفهرَسٌ أصلاً** — يلفّ صفوفَه في `ListView.builder`،
// وذلك إصلاحٌ موثَّقٌ لتجمّدٍ فعليٍّ وقع مع `DataTable` القياسيّ. فالانتقالُ
// إلى بطاقاتٍ في `Column` كان سيُعيد العطبَ نفسَه بعد أن حُلّ. والقياسُ
// (2026-08-21): البطاقةُ المضغوطةُ ~٥٦ بكسل مقابل ~٤٨ للصفّ، فالكثافةُ
// تكاد تُحفَظ — بخلاف بطاقة التصميم الكاملة (~٨٠) التي كانت ستُضيّع ثلثَ
// المرئيّ.
//
// ولا طيَّ داخلَ الصفّ عن قصد: `lines` لا تصل مع الفاتورة
// (‏`sales_invoices_controller.dart` يبنيها `[]` مع تعليقِ «Need separate
// fetch»)، فكلُّ فتحةٍ كانت استعلاماً إضافيّاً. و«عرضُ التفاصيل» يبقى على
// زرّ العين كما كان.
part of 'sales_invoices_picpos_screen.dart';

/// زرار طباعة فاتورة البيع — `sales_print`. نسخة مطابقة لنسخة فورك UralCash
/// (`screens/widgets/sales_invoices/sales_invoices_table.dart`) — الملفين
/// مكتبتين منفصلتين فما ينفعش يتشاركوا دالة top-level.
@visibleForTesting
Widget buildSalesPrintButtonGuarded({required VoidCallback onPrint}) {
  return PermissionGuard(
    permission: PermissionCodes.salesPrint,
    allowManagerOverride: true,
    actionName: 'طباعة فاتورة بيع',
    onGranted: onPrint,
    child: IconButton(
      icon: const Icon(PhosphorIconsBold.printer, size: 18),
      color: AppColors.primary,
      tooltip: 'طباعة',
      onPressed: onPrint,
    ),
  );
}

/// أوزانُ الأعمدة — مصدرٌ واحدٌ يشترك فيه سطرُ العناوين وكلُّ بطاقة.
///
/// نسختان منفصلتان كانتا ستنحرفان بأوّل تعديل، فتُزاح العناوينُ عن أعمدتها
/// بلا ما يكسر بناءً — وهو انحرافٌ لا يظهر إلا بالعين.
const _kColNum = 150;
const _kColParty = 120;
const _kColDate = 80;
const _kColPlace = 135;
const _kColTotal = 100;
const _kColCollect = 155;
const double _kColStatusW = 104;
const double _kColActionsW = 172;
const double _kColCheckW = 38;

/// زرُّ إجراءٍ صغيرٌ مربَّعٌ — إطارٌ رفيعٌ وأيقونةٌ ملوّنةٌ بمعناها.
class _RowAction extends StatelessWidget {
  const _RowAction({
    required this.icon,
    required this.color,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(9),
          child: Container(
            width: 31,
            height: 31,
            decoration: BoxDecoration(
              border: Border.all(color: Theme.of(context).dividerColor),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(icon, size: 14, color: color),
          ),
        ),
      ),
    );
  }
}

class SalesInvoicesTable extends ConsumerWidget {
  final Function(InvoiceEntity) onView;
  final Function(InvoiceEntity) onEdit;
  final Function(InvoiceEntity) onPrint;
  final Function(InvoiceEntity) onDelete;
  final Function(InvoiceEntity) onWhatsApp;

  const SalesInvoicesTable({
    super.key,
    required this.onView,
    required this.onEdit,
    required this.onPrint,
    required this.onDelete,
    required this.onWhatsApp,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filteredInvoices = ref.watch(
        salesInvoicesControllerProvider.select((s) => s.filteredInvoices));
    final customerNames = ref.watch(
        salesInvoicesControllerProvider.select((s) => s.customerNames));
    final selectedInvoices = ref.watch(
        salesInvoicesControllerProvider.select((s) => s.selectedInvoices));
    final returnedAmounts = ref.watch(
        salesInvoicesControllerProvider.select((s) => s.returnedAmounts));

    // Build warehouse name map for branch indicator on all devices
    final warehousesList = ref.watch(allWarehousesProvider).value ?? [];
    final warehouseNames = <int, String>{};
    final warehouseBranchId = <int, int?>{};
    for (final w in warehousesList) {
      warehouseNames[w.id] = w.name;
      warehouseBranchId[w.id] = w.branchId;
    }
    // Branch name lookup so the cashier can see which branch issued each
    // invoice — resolved via warehouse.branchId since SalesInvoices doesn't
    // carry a direct branchId column (yet — Level 3).
    final branchesList = ref.watch(allBranchesProvider).value ?? [];
    final branchNames = <int, String>{
      for (final b in branchesList) b.id: b.name,
    };
    // Cost center lookup — sales invoices store costCenterId directly
    final costCentersList = ref.watch(allCostCentersProvider).value ?? [];
    final costCenterNames = <int, String>{
      for (final c in costCentersList) c.id: c.name,
    };

    if (filteredInvoices.isEmpty) {
      // Issue 8 — distinguish "no invoices at all" from "filters narrowed
      // the result set to empty". The latter offers a reset so the user
      // doesn't have to clear each chip individually.
      final hasFilters =
          ref.read(salesInvoicesControllerProvider.notifier).hasActiveFilters;

      // ── فراغٌ لا يُفسَّر بالفلاتر (‏قرارُ المالك 2026-08-23) ──────────────
      // مستخدمٌ غيرُ مميّزٍ بلا إسنادِ فرعٍ يحصل على نطاقٍ فارغ، فيُحجَب عنه
      // **كلُّ** صفٍّ موسومٍ بفرع — حتى فاتورةٌ باعها بنفسه. والسياسةُ
      // «الفشلُ يُقفِل» مقصودةٌ أمنيّاً وتبقى، لكنّ نتيجتَها كانت شاشةً
      // فارغةً تقول «لا توجد فواتير» — وهي **كذبة**: الفواتيرُ موجودةٌ
      // ومحجوبة. فيُقال السببُ صراحةً بدل أن يُتَّهَم النظامُ بالضياع.
      final emptyScope = ref.watch(branchScopeProvider.select((s) => s.value))
              ?.isEmptyScope ??
          false;

      if (emptyScope && !hasFilters) {
        return Expanded(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    PhosphorIconsBold.lockKey,
                    size: 64,
                    color: AppColors.warning.withValues(alpha: 0.35),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'لا فروعَ مُسنَدةٌ لحسابك',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: AppColors.textMuted,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'الفواتيرُ المرتبطةُ بفرعٍ مخفيّةٌ عنك حتى يُسنِد لك مديرُ '
                    'النظام فرعاً واحداً على الأقل. وهذا ليس عطباً في '
                    'البيانات — الفواتيرُ موجودةٌ ومحجوبة.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                  ),
                ],
              ),
            ),
          ),
        );
      }

      return Expanded(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                hasFilters
                    ? PhosphorIconsBold.funnelSimple
                    : PhosphorIconsBold.receipt,
                size: 64,
                color: AppColors.textMuted.withValues(alpha: 0.3),
              ),
              const SizedBox(height: 16),
              Text(
                hasFilters
                    ? 'لا نتائج تطابق الفلاتر الحالية'
                    : 'لا توجد فواتير مبيعات',
                style: const TextStyle(color: AppColors.textMuted),
              ),
              if (hasFilters) ...[
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  icon: const Icon(PhosphorIconsBold.arrowsCounterClockwise,
                      size: 16),
                  label: const Text('إعادة تعيين الفلاتر'),
                  onPressed: () => ref
                      .read(salesInvoicesControllerProvider.notifier)
                      .clearAllFilters(),
                ),
              ],
            ],
          ),
        ),
      );
    }

    final notifier = ref.read(salesInvoicesControllerProvider.notifier);
    final allSelected = selectedInvoices.length == filteredInvoices.length;

    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(
          children: [
            _HeaderRow(
              allSelected: allSelected,
              onToggleAll: notifier.toggleAllSelection,
            ),
            const SizedBox(height: 6),
            Expanded(
              // مُفهرَسٌ — لا تُبنى إلا البطاقاتُ المرئيّة. اقرأ رأسَ الملفّ
              // لسبب هذا الاختيار بالذات.
              child: ListView.separated(
                itemCount: filteredInvoices.length,
                separatorBuilder: (_, _) => const SizedBox(height: 6),
                itemBuilder: (context, i) {
                  final invoice = filteredInvoices[i];
                  return _InvoiceCard(
                    invoice: invoice,
                    selected: selectedInvoices.contains(invoice.id),
                    onToggleSelect: () => notifier.toggleSelection(invoice.id!),
                    returnedAmount: returnedAmounts[invoice.id] ?? 0.0,
                    customerNames: customerNames,
                    warehouseNames: warehouseNames,
                    warehouseBranchId: warehouseBranchId,
                    branchNames: branchNames,
                    costCenterNames: costCenterNames,
                    onView: onView,
                    onEdit: onEdit,
                    onPrint: onPrint,
                    onDelete: onDelete,
                    onWhatsApp: onWhatsApp,
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// سطرُ عناوين الأعمدة — خارجَ التمرير كي يبقى ثابتاً كرأس الجدول القديم.
class _HeaderRow extends StatelessWidget {
  const _HeaderRow({required this.allSelected, required this.onToggleAll});

  final bool allSelected;
  final VoidCallback onToggleAll;

  @override
  Widget build(BuildContext context) {
    final muted = _mutedOf(context);
    Widget label(String t, int flex, {TextAlign? align}) => Expanded(
          flex: flex,
          child: Text(
            t,
            textAlign: align,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: muted,
            ),
          ),
        );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Row(
        children: [
          SizedBox(
            width: _kColCheckW,
            child: Checkbox(
              value: allSelected,
              onChanged: (_) => onToggleAll(),
              visualDensity: VisualDensity.compact,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
          label('رقم الفاتورة', _kColNum),
          label('العميل', _kColParty),
          label('التاريخ', _kColDate),
          label('الفرع · المخزن · مركز التكلفة', _kColPlace),
          label('الإجمالي', _kColTotal, align: TextAlign.end),
          label('التحصيل', _kColCollect),
          SizedBox(
            width: _kColStatusW,
            child: Text(
              'الحالة',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: muted,
              ),
            ),
          ),
          SizedBox(
            width: _kColActionsW,
            child: Text(
              'الإجراءات',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: muted,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// بطاقةُ فاتورةٍ واحدة — مضغوطةٌ بارتفاعٍ ~٥٦ كي تبقى الكثافةُ قريبةً من
/// الجدول الذي حلّت محلَّه.
class _InvoiceCard extends StatelessWidget {
  const _InvoiceCard({
    required this.invoice,
    required this.selected,
    required this.onToggleSelect,
    required this.returnedAmount,
    required this.customerNames,
    required this.warehouseNames,
    required this.warehouseBranchId,
    required this.branchNames,
    required this.costCenterNames,
    required this.onView,
    required this.onEdit,
    required this.onPrint,
    required this.onDelete,
    required this.onWhatsApp,
  });

  final InvoiceEntity invoice;
  final bool selected;
  final VoidCallback onToggleSelect;
  final double returnedAmount;
  final Map<int, String> customerNames;
  final Map<int, String> warehouseNames;
  final Map<int, int?> warehouseBranchId;
  final Map<int, String> branchNames;
  final Map<int, String> costCenterNames;
  final Function(InvoiceEntity) onView;
  final Function(InvoiceEntity) onEdit;
  final Function(InvoiceEntity) onPrint;
  final Function(InvoiceEntity) onDelete;
  final Function(InvoiceEntity) onWhatsApp;

  String get _customerName {
    if (invoice.partyId == null) return 'عميل نقدي';
    final found = customerNames[invoice.partyId];
    if (found != null) return found;
    // Spec 002 (B4): the lookup map should resolve every existing FK now
    // that we load inactive customers too. If we still hit the fallback,
    // the party row itself is missing locally — log it so operators can
    // see chronic gaps.
    debugPrint('[SalesList] customer name fallback for '
        'partyId=${invoice.partyId} on invoice ${invoice.invoiceNumber}');
    return 'عميل #${invoice.partyId}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = _mutedOf(context);

    // Returns reduce the invoice's effective receivable, so subtract them
    // from the displayed remaining. A negative value means the refund
    // exceeds the unpaid balance and we owe the customer the difference —
    // color it accordingly so the cashier notices.
    final remaining = invoice.total - invoice.paid - returnedAmount;
    final isPaid = invoice.status == InvoiceStatus.paid;
    final isPartial = invoice.status == InvoiceStatus.partial;
    final isCancelled = invoice.status == InvoiceStatus.cancelled;

    final statusColor = isPaid
        ? AppColors.success
        : isPartial
            ? AppColors.warning
            : AppColors.error;
    final statusLabel = isPaid
        ? 'مدفوع'
        : isPartial
            ? 'جزئي'
            : isCancelled
                ? 'ملغي'
                : 'غير مدفوع';
    final statusIcon = isPaid
        ? PhosphorIconsBold.checkCircle
        : isPartial
            ? PhosphorIconsBold.clock
            : isCancelled
                ? PhosphorIconsBold.prohibit
                : PhosphorIconsBold.warningCircle;

    final whId = invoice.warehouseId;
    final whName = whId != null ? (warehouseNames[whId] ?? 'WH#$whId') : '—';
    // Prefer the direct branchId stamped on the invoice (L3). Falls back to
    // resolving via warehouse → branch FK for legacy rows not yet backfilled.
    final brId =
        invoice.branchId ?? (whId != null ? warehouseBranchId[whId] : null);
    final brName = brId != null ? (branchNames[brId] ?? 'فرع #$brId') : null;
    // Spec 119 (Bug K) — «—» أنظفُ من «م.ت #6» حين يغيب مركزُ التكلفة من
    // الخريطة (سباقٌ مع delta pull، أو مركزٌ محذوف).
    final ccName = invoice.costCenterId != null
        ? (costCenterNames[invoice.costCenterId] ?? '—')
        : '—';

    return Container(
      decoration: BoxDecoration(
        color: theme.cardColor,
        border: Border.all(
          color: selected ? AppColors.primary : theme.dividerColor,
        ),
        borderRadius: BorderRadius.circular(14),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: Row(
        children: [
          SizedBox(
            width: _kColCheckW,
            child: Checkbox(
              value: selected,
              onChanged: (_) => onToggleSelect(),
              visualDensity: VisualDensity.compact,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),

          // ── رقمُ الفاتورة + شارةُ المرتجع + المخزن سطراً خافتاً ────────
          Expanded(
            flex: _kColNum,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        invoice.invoiceNumber,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: theme.textTheme.bodyLarge?.color,
                          fontFeatures: const [
                            ui.FontFeature.tabularFigures()
                          ],
                        ),
                      ),
                    ),
                    // Return-status badge — makes it obvious the cashier
                    // should check "شاشة مرتجع المبيعات" for the details.
                    if (invoice.status == InvoiceStatus.returned ||
                        invoice.status == InvoiceStatus.partialReturn) ...[
                      const SizedBox(width: 5),
                      _ReturnBadge(
                          full: invoice.status == InvoiceStatus.returned),
                    ],
                    if (invoice.isLocked) ...[
                      const SizedBox(width: 5),
                      Tooltip(
                        message: 'مُرحّلة محاسبياً',
                        child: Icon(PhosphorIconsBold.lockSimple,
                            size: 11, color: muted),
                      ),
                    ],
                  ],
                ),
                Text(
                  whName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    color: muted,
                  ),
                ),
              ],
            ),
          ),

          // ── العميل ────────────────────────────────────────────────────
          Expanded(
            flex: _kColParty,
            child: Text(
              _customerName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: AppColors.info,
              ),
            ),
          ),

          // ── التاريخ ───────────────────────────────────────────────────
          Expanded(
            flex: _kColDate,
            child: Text(
              (invoice.createdAt ?? invoice.invoiceDate)
                  .toString()
                  .substring(0, 10),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: theme.textTheme.bodyMedium?.color,
                fontFeatures: const [ui.FontFeature.tabularFigures()],
              ),
            ),
          ),

          // ── الفرع · المخزن · مركز التكلفة ─────────────────────────────
          Expanded(
            flex: _kColPlace,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    const Icon(PhosphorIconsBold.buildings,
                        size: 11, color: AppColors.primary),
                    const SizedBox(width: 5),
                    Expanded(
                      child: Text(
                        brName ?? '—',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: theme.textTheme.bodyMedium?.color,
                        ),
                      ),
                    ),
                  ],
                ),
                Text(
                  '$whName · $ccName',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    color: muted,
                  ),
                ),
              ],
            ),
          ),

          // ── الإجمالي (محجوبٌ بـ`sales_amounts_view`) ──────────────────
          Expanded(
            flex: _kColTotal,
            child: Align(
              alignment: AlignmentDirectional.centerEnd,
              child: PermissionMaskedText(
                permission: PermissionCodes.salesAmountsView,
                text: invoice.total.toStringAsFixed(AppConstants.decimalPlaces),
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -.3,
                  color: theme.textTheme.bodyLarge?.color,
                  fontFeatures: const [ui.FontFeature.tabularFigures()],
                ),
              ),
            ),
          ),

          const SizedBox(width: 10),

          // ── التحصيل: المدفوع · المتبقي · شريطٌ رفيع ───────────────────
          //
          // الثلاثةُ محجوبةٌ بنفس الكود: المتبقي مشتقٌّ من الإجمالي والمدفوع،
          // فكشفُه وحدَه كان يسرّبهما. والشريطُ يُرسم من النسبة نفسِها،
          // فيُسطَّح عند الحجب — نفسُ قاعدة شريط البطاقة الرئيسيّة.
          Expanded(
            flex: _kColCollect,
            child: _CollectionCell(
              paid: invoice.paid,
              remaining: remaining,
              total: invoice.total,
              returned: returnedAmount,
            ),
          ),

          // ── الحالة ────────────────────────────────────────────────────
          SizedBox(
            width: _kColStatusW,
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: .12),
                  border: Border.all(color: statusColor.withValues(alpha: .35)),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(statusIcon, size: 11, color: statusColor),
                    const SizedBox(width: 5),
                    Text(
                      statusLabel,
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                        color: statusColor,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // ── الإجراءات ─────────────────────────────────────────────────
          SizedBox(
            width: _kColActionsW,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _RowAction(
                  icon: PhosphorIconsBold.eye,
                  color: AppColors.info,
                  tooltip: 'عرض التفاصيل',
                  onTap: () => onView(invoice),
                ),
                const SizedBox(width: 5),
                if (!invoice.isLocked) ...[
                  _RowAction(
                    icon: PhosphorIconsBold.pencilSimple,
                    color: AppColors.warning,
                    tooltip: 'تعديل الدفع / وسيلة الدفع',
                    onTap: () => onEdit(invoice),
                  ),
                  const SizedBox(width: 5),
                ],
                buildSalesPrintButtonGuarded(onPrint: () => onPrint(invoice)),
                const SizedBox(width: 5),
                // إرسالُ الفاتورة على واتساب — البندُ الثاني (2026-09-12).
                // زرٌّ مستقلٌّ لا مدخلُ قائمةٍ: الحراسةُ تُعطِّله فعلاً.
                _RowAction(
                  icon: PhosphorIconsBold.whatsappLogo,
                  color: AppColors.success,
                  tooltip: 'إرسال على واتساب',
                  onTap: () => onWhatsApp(invoice),
                ),
                if (!invoice.isLocked) ...[
                  const SizedBox(width: 5),
                  _RowAction(
                    icon: PhosphorIconsBold.trash,
                    color: AppColors.error,
                    tooltip: 'حذف',
                    onTap: () => onDelete(invoice),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// خليّةُ التحصيل — المدفوعُ والمتبقي وشريطٌ يقسم الإجماليَّ بينهما.
class _CollectionCell extends StatelessWidget {
  const _CollectionCell({
    required this.paid,
    required this.remaining,
    required this.total,
    required this.returned,
  });

  final double paid;
  final double remaining;
  final double total;
  final double returned;

  @override
  Widget build(BuildContext context) {
    final muted = _mutedOf(context);
    // متبقٍّ سالبٌ يعني أن المرتجعَ تجاوز الرصيدَ غيرَ المسدَّد، فنحن مدينون
    // للعميل بالفرق — لونٌ مختلفٌ كي ينتبه الكاشير.
    final remainingColor = remaining > 0
        ? AppColors.error
        : remaining < 0
            ? AppColors.warning
            : AppColors.success;

    return PermissionGuard(
      permission: PermissionCodes.salesAmountsView,
      fallback: _body(context, muted, masked: true, remainingColor: muted),
      child: _body(context, muted,
          masked: false, remainingColor: remainingColor),
    );
  }

  Widget _body(
    BuildContext context,
    Color muted, {
    required bool masked,
    required Color remainingColor,
  }) {
    String fmt(double v) => masked
        ? kMaskedValuePlaceholder
        : v.toStringAsFixed(AppConstants.decimalPlaces);
    final paidPct = (masked || total <= 0)
        ? 0.0
        : (paid / total * 100).clamp(0, 100).toDouble();
    final retPct = (masked || total <= 0)
        ? 0.0
        : (returned / total * 100).clamp(0, 100 - paidPct).toDouble();

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Flexible(
              child: Text(
                fmt(paid),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                  color: AppColors.success,
                  fontFeatures: [ui.FontFeature.tabularFigures()],
                ),
              ),
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                'متبقي ${fmt(remaining)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.end,
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  color: remainingColor,
                  fontFeatures: const [ui.FontFeature.tabularFigures()],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        // ⚠️ عرضٌ محسوبٌ لا `Expanded(flex:)` — الوزنُ صفراً لا يُلغي القطعة
        // (‏`Flexible` يمنح عديمَ الوزن قياسَه الطبيعيّ)، فكان الشريطُ يفشي
        // النسبةَ بالعرض بعد أن حُجبت بالنصّ. نفسُ درسِ البطاقة الرئيسيّة.
        SizedBox(
          height: 5,
          child: LayoutBuilder(
            builder: (context, c) {
              final w = c.maxWidth;
              final paidW = (w * paidPct / 100).clamp(0.0, w);
              final retW = (w * retPct / 100).clamp(0.0, w - paidW);
              return ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: ColoredBox(
                        color: muted.withValues(alpha: .18),
                      ),
                    ),
                    PositionedDirectional(
                      start: 0,
                      width: paidW,
                      top: 0,
                      bottom: 0,
                      child: const ColoredBox(color: AppColors.success),
                    ),
                    PositionedDirectional(
                      start: paidW,
                      width: retW,
                      top: 0,
                      bottom: 0,
                      child: const ColoredBox(color: AppColors.warning),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// Compact badge rendered next to an invoice number when the invoice's
/// status is `returned` or `partial_return`. Lets the cashier know to
/// look in "شاشة مرتجع المبيعات" for the matching return record
/// without having to open the invoice.
class _ReturnBadge extends StatelessWidget {
  final bool full;
  const _ReturnBadge({required this.full});

  @override
  Widget build(BuildContext context) {
    final color = full ? AppColors.error : AppColors.warning;
    return Tooltip(
      message: full
          ? 'تم إرجاع الفاتورة بالكامل — راجع شاشة مرتجع المبيعات للتفاصيل'
          : 'تم إرجاع جزء من الفاتورة — راجع شاشة مرتجع المبيعات للتفاصيل',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              full ? Icons.undo_rounded : Icons.rotate_left_rounded,
              size: 10,
              color: color,
            ),
            const SizedBox(width: 3),
            Text(
              full ? 'مُرتجعة' : 'مُرتجعة جزئياً',
              style: TextStyle(
                fontSize: 9.5,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
