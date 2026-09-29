// ignore_for_file: library_private_types_in_public_api
// نسخةُ PicPos من قائمة فواتير المشتريات — **مرآةُ شكلٍ** لتوأمِ المبيعات
// في `sales_invoices_picpos/screens/sales_invoices_table.dart`: صفوفُ
// `AppDataTable` صارت بطاقاتٍ مضغوطةً في `ListView.builder`.
//
// ═══ ولماذا `ListView.builder` بالذات ═══
//
// لأن `DataTable2` **مُفهرَسٌ أصلاً** — يلفّ صفوفَه في `ListView.builder`،
// وذلك إصلاحٌ موثَّقٌ لتجمّدٍ فعليٍّ وقع مع `DataTable` القياسيّ. فالانتقالُ
// إلى بطاقاتٍ في `Column` كان سيُعيد العطبَ نفسَه بعد أن حُلّ. والبطاقةُ
// المضغوطةُ ~٥٦ بكسل مقابل ~٤٨ للصفّ، فالكثافةُ تكاد تُحفَظ.
//
// ⚠️ **وثلاثةُ فروقٍ مقيسةٍ لا منسوخة:**
//
// ‏١) **لا حجبَ على المبالغ** — لا وجودَ لـ`purchases_amounts_view`. اقرأ
//    التفصيلَ في رأس `purchases_totals_bar.dart`.
//
// ‏٢) **ثلاثةُ إجراءاتٍ لا أربعة.** فورك UralCash للمشتريات لا يحمل زرَّ حذفٍ
//    في الصفّ إطلاقاً (عرضٌ · تعديلٌ · طباعة فقط)، والحذفُ المجمَّع وحدَه في
//    شريط التحديد. وإضافةُ زرِّ حذفٍ «مطابقةً للمبيعات» كانت ستخلق إجراءً
//    مدمِّراً لم يكن موجوداً — لا مرآةَ شكلٍ بل توسيعُ سطحِ خطر.
//
// ‏٣) **بوّابةُ التعديل صلاحيةٌ لا قفل.** المبيعاتُ تُظهر زرَّ التعديل حين
//    `!isLocked`؛ والمشترياتُ تُظهره دائماً وتُعطّله بـ`purchases_edit`
//    (قرارُ مالكٍ 2026-07-22 — التعديلُ مسموحٌ ولو رُحِّلت، بتأكيدٍ صريح).
part of 'purchases_picpos_screen.dart';

/// أوزانُ الأعمدة — مصدرٌ واحدٌ يشترك فيه سطرُ العناوين وكلُّ بطاقة.
///
/// نسختان منفصلتان كانتا ستنحرفان بأوّل تعديل، فتُزاح العناوينُ عن أعمدتها
/// بلا ما يكسر بناءً — وهو انحرافٌ لا يظهر إلا بالعين.
const _kPurColNum = 150;
const _kPurColParty = 130;
const _kPurColDate = 80;
const _kPurColPlace = 135;
const _kPurColTotal = 100;
const _kPurColPay = 155;
/// عرضُ عمود «حالة الترحيل» — قرارُ المالك 2026-09-18:
/// «الحالة» **عمودان** لا عمودٌ واحد.
const double _kPurColPostedW = 118;
const double _kPurColStatusW = 104;


/// ثلاثةُ أزرارٍ (‏31) وفاصلان (‏5) = ‏103؛ و‏118 تترك هامشاً لا ينضغط.
const double _kPurColActionsW = 118;
const double _kPurColCheckW = 38;

/// زرُّ إجراءٍ صغيرٌ مربَّعٌ — إطارٌ رفيعٌ وأيقونةٌ ملوّنةٌ بمعناها.
class _PurRowAction extends StatelessWidget {
  const _PurRowAction({
    required this.icon,
    required this.color,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final String tooltip;

  /// `null` ⇒ معطَّل. يبقى الزرُّ مرئيّاً كي يعرف المستخدمُ أن الإجراءَ موجودٌ
  /// لكنه لا يملكه — لا أن يختفي فيبدو غيرَ مدعوم.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
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
            child: Icon(
              icon,
              size: 14,
              color: enabled ? color : color.withValues(alpha: .32),
            ),
          ),
        ),
      ),
    );
  }
}

class PurchasesInvoicesTable extends ConsumerWidget {
  final void Function(InvoiceEntity) onView;
  final void Function(InvoiceEntity) onEdit;
  final void Function(InvoiceEntity) onPrint;

  /// `purchases_edit` — تُقاس مرّةً في الشاشة وتُمرَّر، لا تُقرأ لكلّ صفّ.
  final bool canEdit;

  const PurchasesInvoicesTable({
    super.key,
    required this.onView,
    required this.onEdit,
    required this.onPrint,
    required this.canEdit,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filteredInvoices = ref.watch(
        purchaseInvoicesControllerProvider.select((s) => s.filteredInvoices));
    final docs = ref.watch(
        purchaseInvoicesControllerProvider.select((s) => s.filteredDocs));
    final supplierNames = ref.watch(
        purchaseInvoicesControllerProvider.select((s) => s.supplierNames));
    final selectedInvoices = ref.watch(
        purchaseInvoicesControllerProvider.select((s) => s.selectedInvoices));
    final returnedAmounts = ref.watch(
        purchaseInvoicesControllerProvider.select((s) => s.returnedAmounts));
    final warehouseNames = ref.watch(
        purchaseInvoicesControllerProvider.select((s) => s.warehouseNames));
    final warehouseBranchId = ref.watch(
        purchaseInvoicesControllerProvider.select((s) => s.warehouseBranchId));
    final branchNames = ref.watch(
        purchaseInvoicesControllerProvider.select((s) => s.branchNames));
    final costCenterNames = ref.watch(
        purchaseInvoicesControllerProvider.select((s) => s.costCenterNames));
    final postedIds = ref.watch(
        purchaseInvoicesControllerProvider.select((s) => s.postedInvoiceIds));

    final notifier = ref.read(purchaseInvoicesControllerProvider.notifier);

    if (docs.isEmpty) {
      // تُميَّز «لا فواتيرَ إطلاقاً» من «المرشِّحاتُ ضيّقت النتيجةَ إلى الصفر»
      // — والثانيةُ تعرض إعادةَ تعيينٍ كي لا يفكّ المستخدمُ كلَّ حبّةٍ وحدَها.
      final hasFilters = notifier.hasActiveFilters;
      return Expanded(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                hasFilters
                    ? PhosphorIconsBold.funnelSimple
                    : PhosphorIconsBold.shoppingCart,
                size: 64,
                color: AppColors.textMuted.withValues(alpha: 0.3),
              ),
              const SizedBox(height: 16),
              Text(
                hasFilters
                    ? tr('لا نتائج تطابق الفلاتر الحالية')
                    : tr('لا توجد فواتير مشتريات'),
                style: const TextStyle(color: AppColors.textMuted),
              ),
              if (hasFilters) ...[
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  icon: const Icon(PhosphorIconsBold.arrowsCounterClockwise,
                      size: 16),
                  label:  Text(tr('إعادة تعيين الفلاتر')),
                  onPressed: notifier.clearAllFilters,
                ),
              ],
            ],
          ),
        ),
      );
    }

    // ⚠️ ويُقاس على الفواتير وحدَها: الأوامرُ لا تُحدّد، فلو دخلت
    // المقامَ لما اكتمل «تحديدُ الكلّ» أبداً.
    final allSelected = filteredInvoices.isNotEmpty &&
        selectedInvoices.length == filteredInvoices.length;

    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(
          children: [
            _PurHeaderRow(
              allSelected: allSelected,
              onToggleAll: notifier.toggleAllSelection,
            ),
            const SizedBox(height: 6),
            Expanded(
              // مُفهرَسٌ — لا تُبنى إلا البطاقاتُ المرئيّة. اقرأ رأسَ الملفّ
              // لسبب هذا الاختيار بالذات.
              child: ListView.separated(
                itemCount: docs.length,
                separatorBuilder: (_, _) => const SizedBox(height: 6),
                itemBuilder: (context, i) {
                  // مستندان لا واحد — وكلٌّ ببطاقته: أمرُ الشراء
                  // يفتقر إلى نصف أعمدة الفاتورة.
                  final doc = docs[i];
                  if (doc is PurchaseOrderDoc) {
                    return _PurOrderCard(
                      order: doc.order,
                      supplierNames: supplierNames,
                      warehouseNames: warehouseNames,
                      costCenterNames: costCenterNames,
                    );
                  }
                  final invoice = (doc as PurchaseInvoiceDoc).invoice;
                  return _PurInvoiceCard(
                    invoice: invoice,
                    selected: selectedInvoices.contains(invoice.id),
                    onToggleSelect: () {
                      final id = invoice.id;
                      if (id != null) notifier.toggleSelection(id);
                    },
                    returnedAmount: returnedAmounts[invoice.id] ?? 0.0,
                    posted: postedIds?.contains(invoice.id),

                    supplierNames: supplierNames,
                    warehouseNames: warehouseNames,
                    warehouseBranchId: warehouseBranchId,
                    branchNames: branchNames,
                    costCenterNames: costCenterNames,
                    canEdit: canEdit,
                    onView: onView,
                    onEdit: onEdit,
                    onPrint: onPrint,
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
class _PurHeaderRow extends StatelessWidget {
  const _PurHeaderRow({required this.allSelected, required this.onToggleAll});

  final bool allSelected;
  final VoidCallback onToggleAll;

  @override
  Widget build(BuildContext context) {
    final muted = _purMuted(context);
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
            width: _kPurColCheckW,
            child: Checkbox(
              value: allSelected,
              onChanged: (_) => onToggleAll(),
              visualDensity: VisualDensity.compact,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
          label(tr('رقم الفاتورة'), _kPurColNum),
          label(tr('المورد'), _kPurColParty),
          label(tr('التاريخ'), _kPurColDate),
          label(tr('الفرع · المخزن · مركز التكلفة'), _kPurColPlace),
          label(tr('الإجمالي'), _kPurColTotal, align: TextAlign.end),
          label(tr('السداد'), _kPurColPay),
          SizedBox(
            width: _kPurColPostedW,
            child: Text(
              tr('حالة الترحيل'),
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: muted,
              ),
            ),
          ),
          SizedBox(
            width: _kPurColStatusW,
            child: Text(
              tr('حالة السداد'),
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: muted,
              ),
            ),
          ),
          SizedBox(
            width: _kPurColActionsW,
            child: Text(
              tr('الإجراءات'),
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
class _PurInvoiceCard extends StatelessWidget {
  const _PurInvoiceCard({
    required this.invoice,
    required this.selected,
    required this.onToggleSelect,
    required this.returnedAmount,
    required this.posted,
    required this.supplierNames,
    required this.warehouseNames,
    required this.warehouseBranchId,
    required this.branchNames,
    required this.costCenterNames,
    required this.canEdit,
    required this.onView,
    required this.onEdit,
    required this.onPrint,
  });

  final InvoiceEntity invoice;
  final bool selected;
  final VoidCallback onToggleSelect;
  final double returnedAmount;

  /// هل لهذه الفاتورة قيدٌ مُرحَّلٌ في الأستاذ؟ `null` ⇒ **لم يُعرَف بعد**.
  final bool? posted;
  final Map<int, String> supplierNames;
  final Map<int, String> warehouseNames;
  final Map<int, int?> warehouseBranchId;
  final Map<int, String> branchNames;
  final Map<int, String> costCenterNames;
  final bool canEdit;
  final void Function(InvoiceEntity) onView;
  final void Function(InvoiceEntity) onEdit;
  final void Function(InvoiceEntity) onPrint;

  /// نفسُ احتياطِ فورك UralCash حرفاً بحرف: «غير محدد» لا «مورد #N» — فاتورةُ
  /// شراءٍ بلا مورّدٍ مسجَّلٍ حالةٌ واردةٌ لا خطأُ بحثٍ في خريطة.
  String get _supplierName {
    final id = invoice.partyId;
    if (id == null) return tr('غير محدد');
    return supplierNames[id] ?? tr('غير محدد');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = _purMuted(context);

    // المرتجعُ يخفض المستحقَّ للمورد، فيُطرَح من المتبقي المعروض. وسالبٌ يعني
    // أن المرتجعَ تجاوز غيرَ المسدَّد فالمورّدُ مدينٌ لنا بالفرق — لونٌ مختلف.
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
        ? tr('مدفوع')
        : isPartial
            ? tr('جزئي')
            : isCancelled
                ? tr('ملغي')
                : tr('غير مدفوع');
    final statusIcon = isPaid
        ? PhosphorIconsBold.checkCircle
        : isPartial
            ? PhosphorIconsBold.clock
            : isCancelled
                ? PhosphorIconsBold.prohibit
                : PhosphorIconsBold.warningCircle;

    final whId = invoice.warehouseId;
    final whName = whId != null ? (warehouseNames[whId] ?? 'WH#$whId') : '—';
    // يُفضَّل `branchId` المختوم على الفاتورة (‏L3)، ويُرجَع إلى المخزن للصفوف
    // القديمة التي لم تُعبَّأ بعد.
    final brId =
        invoice.branchId ?? (whId != null ? warehouseBranchId[whId] : null);
    final brName = brId != null ? (branchNames[brId] ?? tr('فرع #{brId}', {'brId': brId})) : null;
    // Spec 119 (Bug K) — «—» أنظفُ من «م.ت #6» حين يغيب مركزُ التكلفة.
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
            width: _kPurColCheckW,
            child: Checkbox(
              value: selected,
              onChanged: (_) => onToggleSelect(),
              visualDensity: VisualDensity.compact,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),

          // ── رقمُ الفاتورة + شارةُ المرتجع + المخزن سطراً خافتاً ────────
          Expanded(
            flex: _kPurColNum,
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
                    if (invoice.status == InvoiceStatus.returned ||
                        invoice.status == InvoiceStatus.partialReturn) ...[
                      const SizedBox(width: 5),
                      _PurchaseReturnBadge(
                        full: invoice.status == InvoiceStatus.returned,
                      ),
                    ],
                    if (invoice.isLocked) ...[
                      const SizedBox(width: 5),
                      Tooltip(
                        message: tr('مُرحّلة محاسبياً'),
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

          // ── المورد ────────────────────────────────────────────────────
          Expanded(
            flex: _kPurColParty,
            child: Text(
              _supplierName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              // برتقاليٌّ لا أزرق — نفسُ لونِ المورد في فورك UralCash، ويُبقي
              // الطرفَ المقابلَ مميَّزاً عن العميل في شاشة المبيعات.
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: AppColors.warning,
              ),
            ),
          ),

          // ── التاريخ ───────────────────────────────────────────────────
          Expanded(
            flex: _kPurColDate,
            child: Text(
              invoice.invoiceDate.toString().substring(0, 10),
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
            flex: _kPurColPlace,
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

          // ── الإجمالي ──────────────────────────────────────────────────
          Expanded(
            flex: _kPurColTotal,
            child: Align(
              alignment: AlignmentDirectional.centerEnd,
              child: Text(
                invoice.total.toStringAsFixed(AppConstants.decimalPlaces),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
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

          // ── السداد: المسدَّد · المتبقي · شريطٌ رفيع ────────────────────
          Expanded(
            flex: _kPurColPay,
            child: _PurPaymentCell(
              paid: invoice.paid,
              remaining: remaining,
              total: invoice.total,
              returned: returnedAmount,
            ),
          ),

          // ── حالةُ الترحيل — من الأستاذ لا من `isLocked` ─────────
          SizedBox(
            width: _kPurColPostedW,
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: _PurPostedPill(posted: posted),
            ),
          ),

          // ── حالةُ السداد ───────────────────────────────
          SizedBox(
            width: _kPurColStatusW,
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
                    // ونفسُ العلّة هنا: «غير مدفوع» أطولُ من الخانة.
                    Flexible(
                      child: Text(
                        statusLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w800,
                          color: statusColor,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // ── الإجراءات — ثلاثةٌ لا أربعة (اقرأ رأسَ الملفّ) ─────────────
          SizedBox(
            width: _kPurColActionsW,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _PurRowAction(
                  icon: PhosphorIconsBold.eye,
                  color: AppColors.info,
                  tooltip: tr('عرض التفاصيل'),
                  onTap: () => onView(invoice),
                ),
                const SizedBox(width: 5),
                _PurRowAction(
                  icon: PhosphorIconsBold.pencilSimple,
                  color: AppColors.warning,
                  // نفسُ مصدرِ عمود «حالة الترحيل» — الأستاذُ لا `isLocked`
                  // التي لا يرفعها مسارُ الإنشاء أصلاً. و`posted == null`
                  // («لم يُعرَف بعد») تُقرأ تلميحاً محايداً لا ادّعاءَ فيه.
                  tooltip: canEdit
                      ? (posted == true ? tr('تعديل فاتورة مُرحّلة') : tr('تعديل'))
                      : tr('لا تملك صلاحية تعديل فواتير المشتريات'),
                  onTap: canEdit ? () => onEdit(invoice) : null,
                ),
                const SizedBox(width: 5),
                // purchases_print — نفسُ حارسِ فورك UralCash، بنفس
                // `allowManagerOverride` و`actionName`.
                PermissionGuard(
                  permission: PermissionCodes.purchasesPrint,
                  allowManagerOverride: true,
                  actionName: tr('طباعة فاتورة مشتريات'),
                  onGranted: () => onPrint(invoice),
                  child: _PurRowAction(
                    icon: PhosphorIconsBold.printer,
                    color: AppColors.primary,
                    tooltip: tr('طباعة'),
                    onTap: () => onPrint(invoice),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}


/// بطاقةُ **أمرِ شراء** — أخٌ لبطاقة الفاتورة لا حالةٌ منها.
///
/// ═══ لماذا بطاقةٌ مستقلّة ═══
///
/// أمرُ الشراء يفتقر إلى نصف أعمدة الفاتورة: لا مسدَّدَ له ولا متبقّي ولا
/// قيدَ في الأستاذ ولا فرعَ مختوماً عليه. وبطاقةٌ واحدةٌ تُفرِغ نصفَ خاناتها
/// كانت ستعرض «مدفوعٌ ٠ من ٥٠٠٠» على التزامٍ لم يُستلَم بعد — وصفرٌ في خانةِ
/// سدادٍ يُقرأ «متأخّراً» لا «غيرَ منطبق».
///
/// ⚠️ **والخانتان تُرسَمان «—» بتلميحَيهما**، ودورةُ حياة الأمر تظهر وسماً
/// بجوار رقمه — حيث يرى القارئُ أصلاً أنّه ليس فاتورة. فلا عمودٌ يقول شيئاً
/// ليس هو.
class _PurOrderCard extends StatelessWidget {
  const _PurOrderCard({
    required this.order,
    required this.supplierNames,
    required this.warehouseNames,
    required this.costCenterNames,
  });

  final PurchaseOrderRow order;
  final Map<int, String> supplierNames;
  final Map<int, String> warehouseNames;
  final Map<int, String> costCenterNames;

  /// تسميةُ حالة الأمر ولونُها — مفرداتٌ خاصّةٌ به لا مفرداتُ السداد.
  static (String, Color) _statusOf(String raw) => switch (raw) {
        'draft' => (tr('مسودة'), AppColors.textMuted),
        'sent' => (tr('مُرسَل'), AppColors.info),
        'confirmed' => (tr('مؤكَّد'), AppColors.primary),
        'received' => (tr('مُستلَم'), AppColors.success),
        'cancelled' => (tr('ملغى'), AppColors.error),
        _ => (raw, AppColors.textMuted),
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = _purMuted(context);
    final (statusLabel, statusColor) = _statusOf(order.status);
    final whName = order.warehouseId != null
        ? (warehouseNames[order.warehouseId] ?? 'WH#${order.warehouseId}')
        : '—';
    final ccName = order.costCenterId != null
        ? (costCenterNames[order.costCenterId] ?? '—')
        : '—';

    Widget dash(String tip) => Tooltip(
          message: tip,
          child: Text(
            '—',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: muted,
            ),
          ),
        );

    return Container(
      decoration: BoxDecoration(
        color: theme.cardColor,
        border: Border.all(color: theme.dividerColor),
        borderRadius: BorderRadius.circular(14),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: Row(
        children: [
          // خانةُ التحديد تبقى فارغةً: الأفعالُ المجمّعة (طباعةٌ وحذف) مبنيّةٌ
          // على الفواتير، وصندوقٌ يُؤشَّر ولا يفعل شيئاً أسوأُ من غيابه.
          const SizedBox(width: _kPurColCheckW),

          Expanded(
            flex: _kPurColNum,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Wrap(
                  spacing: 5,
                  runSpacing: 2,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      order.orderNumber,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                        color: theme.textTheme.bodyMedium?.color,
                      ),
                    ),
                    const _PurDocKindBadge(),
                    _PurOrderStatusBadge(label: statusLabel, color: statusColor),
                    if (order.isConverted)
                      Tooltip(
                        message: tr('حُوِّل إلى فاتورة مشتريات'),
                        child: Icon(PhosphorIconsBold.arrowBendUpLeft,
                            size: 11, color: muted),
                      ),
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

          Expanded(
            flex: _kPurColParty,
            child: Text(
              supplierNames[order.supplierId] ?? tr('مورد #{p0}', {'p0': order.supplierId}),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ),

          Expanded(
            flex: _kPurColDate,
            child: Text(
              '${order.orderDate.day}/${order.orderDate.month}/'
              '${order.orderDate.year}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11.5, color: muted),
            ),
          ),

          Expanded(
            flex: _kPurColPlace,
            child: Text(
              ccName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, color: muted),
            ),
          ),

          Expanded(
            flex: _kPurColTotal,
            child: Text(
              order.total.toStringAsFixed(AppConstants.decimalPlaces),
              textAlign: TextAlign.end,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ),
          const SizedBox(width: 10),

          Expanded(
            flex: _kPurColPay,
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: dash(tr('أمرُ الشراء التزامٌ — لا سدادَ عليه حتى يُفوتَر')),
            ),
          ),

          SizedBox(
            width: _kPurColPostedW,
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: dash(tr('أمرُ الشراء لا يُرحَّل إلى دفتر الأستاذ')),
            ),
          ),

          SizedBox(
            width: _kPurColStatusW,
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: dash(tr('حالةُ الأمر موسومةٌ بجوار رقمه')),
            ),
          ),

          const SizedBox(width: _kPurColActionsW),
        ],
      ),
    );
  }
}

/// وسمُ «أمر شراء» — يميّز الصفَّ عن الفاتورة بنظرة.
class _PurDocKindBadge extends StatelessWidget {
  const _PurDocKindBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.info.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.info.withValues(alpha: 0.4)),
      ),
      child:  Text(
        tr('أمر شراء'),
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          color: AppColors.info,
        ),
      ),
    );
  }
}

/// وسمُ دورةِ حياة الأمر — مفرداتُه الخمسُ لا مفرداتُ السداد الثلاث.
class _PurOrderStatusBadge extends StatelessWidget {
  const _PurOrderStatusBadge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          color: color,
        ),
      ),
    );
  }
}

/// وسمُ حالة الترحيل — **ثلاثُ حالاتٍ لا حالتان**.
///
/// ⚠️ **والثالثةُ ليست ترفاً:** `null` تعني «لم يُعرَف بعد» — الاستعلامُ
/// يصل بعد التحميل الأوّل وقد يُخفق. ورسمُ «غير مُرحَّل» حمراء حينئذٍ
/// يصبغ **كلَّ** الصفوف بإنذارٍ ماليٍّ كاذب، وهو أسوأُ من لا شيء.
class _PurPostedPill extends StatelessWidget {
  const _PurPostedPill({required this.posted});

  final bool? posted;

  @override
  Widget build(BuildContext context) {
    final muted = _purMuted(context);
    if (posted == null) {
      return Tooltip(
        message: tr('حالة الترحيل قيد القراءة من دفتر الأستاذ'),
        child: Text('—',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800,
                color: muted)),
      );
    }
    final ok = posted!;
    final color = ok ? AppColors.success : AppColors.error;
    return Tooltip(
      message: ok
          ? tr('لها قيدٌ مُرحَّلٌ في دفتر الأستاذ')
          : tr('لا قيدَ مُرحَّلاً لها — راجعها قبل الإقفال'),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: color.withValues(alpha: .12),
          border: Border.all(color: color.withValues(alpha: .35)),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              ok ? PhosphorIconsBold.bookOpen : PhosphorIconsBold.warningCircle,
              size: 11,
              color: color,
            ),
            // ⚠️ **`Flexible` لازمةٌ والعمودُ ثابتُ العرض.** الوسمُ يعيش
            // في `SizedBox` بـ١١٨px والنصُّ غيرُ محدود، فـ`Row` يمنحه
            // عرضاً غيرَ محدودٍ ويفيض. مقيسٌ: «غير مُرحَّل» فاضت ٢٦ بكسل.
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                ok ? tr('مُرحَّل') : tr('غير مُرحَّل'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                  color: color,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// خليّةُ السداد — المسدَّدُ والمتبقي وشريطٌ يقسم الإجماليَّ بينهما.
class _PurPaymentCell extends StatelessWidget {
  const _PurPaymentCell({
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
    final muted = _purMuted(context);
    final remainingColor = remaining > 0
        ? AppColors.error
        : remaining < 0
            ? AppColors.warning
            : AppColors.success;

    String fmt(double v) => v.toStringAsFixed(AppConstants.decimalPlaces);
    final paidPct =
        total <= 0 ? 0.0 : (paid / total * 100).clamp(0, 100).toDouble();
    final retPct = total <= 0
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
                tr('متبقي {p0}', {'p0': fmt(remaining)}),
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
        // (‏`Flexible` يمنح عديمَ الوزن قياسَه الطبيعيّ). نفسُ درسِ المبيعات.
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
                      child: ColoredBox(color: muted.withValues(alpha: .18)),
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
