part of '../party_statement_screen.dart';

// ═══════════════════════════════════════════════════════════════════════════
// PARTY STATEMENT — Table & UI: Header, Summary, Date Filter, Statement
// ═══════════════════════════════════════════════════════════════════════════

mixin _PartyStatementTableMixin on ConsumerState<PartyStatementScreen> {
  // Abstract — provided by the shell
  Party? get party;
  PartySummary? get summary;
  List<PartyStatementEntry> get entries;
  DateTime? get fromDate;
  set fromDate(DateTime? val);
  DateTime? get toDate;
  set toDate(DateTime? val);
  DateFormat get dateFormat;
  Future<void> loadData();

  double get totalDebit => entries.fold(0, (sum, e) => sum + e.debit);
  double get totalCredit => entries.fold(0, (sum, e) => sum + e.credit);
  double get finalBalance => entries.isNotEmpty ? entries.last.balance : 0;

  DateTimeRange? get dateRange => fromDate != null && toDate != null
      ? DateTimeRange(start: fromDate!, end: toDate!)
      : null;

  Future<void> selectDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      initialDateRange: dateRange,
      locale: const Locale('ar'),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: AppColors.primary, onPrimary: Colors.white,
            ),
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400, maxHeight: 500),
              child: child!,
            ),
          ),
        );
      },
    );

    if (picked != null) {
      setState(() { fromDate = picked.start; toDate = picked.end; });
      loadData();
    }
  }

  void clearDateFilter() {
    setState(() { fromDate = null; toDate = null; });
    loadData();
  }

  void setDateRange(DateTime start, DateTime end) {
    setState(() { fromDate = start; toDate = end; });
    loadData();
  }

  /// Compact header: party name + balance in a single slim bar
  Widget buildPartyHeader() {
    if (party == null) return const SizedBox.shrink();

    final accentColor = widget.isSupplier ? AppColors.warning : AppColors.primary;
    final balanceAmount = party!.balance;
    final balanceLabel = balanceAmount > 0
        ? (widget.isSupplier ? 'مستحق للمورد' : 'مستحق على العميل')
        : (balanceAmount < 0 ? 'رصيد لصالحه' : 'الحساب متزن');

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [accentColor, accentColor.withValues(alpha: 0.85)],
          begin: Alignment.centerRight, end: Alignment.centerLeft,
        ),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          // Party icon
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              shape: BoxShape.circle,
            ),
            child: Icon(
              widget.isSupplier ? PhosphorIconsBold.truck : PhosphorIconsBold.user,
              color: Colors.white, size: 22,
            ),
          ),
          const SizedBox(width: 12),
          // Party name + phone
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  party!.name,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                ),
                if (party!.phone != null && party!.phone!.isNotEmpty)
                  Text(
                    party!.phone!,
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
              ],
            ),
          ),
          // Summary metrics inline
          _buildInlineMetric(
            widget.isSupplier ? 'المشتريات' : 'المبيعات',
            summary?.totalInvoices ?? 0,
            Colors.white,
          ),
          const SizedBox(width: 24),
          _buildInlineMetric(
            widget.isSupplier ? 'المدفوعات' : 'التحصيلات',
            summary?.totalPayments ?? 0,
            Colors.white,
          ),
          const SizedBox(width: 24),
          // Balance
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  balanceLabel,
                  style: const TextStyle(color: Colors.white70, fontSize: 10),
                ),
                Text(
                  '${balanceAmount.abs().toStringAsFixed(AppConstants.decimalPlaces)} ${AppConstants.currencySymbolEn}',
                  style: const TextStyle(
                    fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInlineMetric(String label, double value, Color color) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: TextStyle(color: color.withValues(alpha: 0.7), fontSize: 10)),
        Text(
          value.toStringAsFixed(AppConstants.decimalPlaces),
          style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }

  /// Summary cards are now merged into header — this returns empty
  Widget buildSummaryCards() => const SizedBox.shrink();

  Widget buildDateFilter() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          _buildQuickFilter('اليوم', () => setDateRange(DateTime.now(), DateTime.now())),
          _buildQuickFilter('أمس', () {
            final y = DateTime.now().subtract(const Duration(days: 1));
            setDateRange(y, y);
          }),
          _buildQuickFilter('هذا الشهر', () => setDateRange(DateTime(DateTime.now().year, DateTime.now().month, 1), DateTime.now())),
          _buildQuickFilter('هذا العام', () => setDateRange(DateTime(DateTime.now().year, 1, 1), DateTime.now())),
          const Spacer(),
          TextButton.icon(
            onPressed: selectDateRange,
            icon: const Icon(PhosphorIconsBold.calendarBlank, size: 16),
            label: Text(
              fromDate != null && toDate != null
                  ? '${dateFormat.format(fromDate!)} - ${dateFormat.format(toDate!)}'
                  : 'تخصيص الفترة',
              style: const TextStyle(fontSize: 12),
            ),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            ),
          ),
          if (fromDate != null)
            IconButton(
              icon: const Icon(PhosphorIconsBold.x, size: 16, color: AppColors.error),
              onPressed: clearDateFilter,
              tooltip: 'إلغاء الفلتر',
              constraints: const BoxConstraints(maxHeight: 32, maxWidth: 32),
              padding: EdgeInsets.zero,
            ),
        ],
      ),
    );
  }

  Widget _buildQuickFilter(String label, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: ActionChip(
        label: Text(label, style: const TextStyle(fontSize: 11)),
        onPressed: onTap,
        backgroundColor: AppColors.surface,
        side: BorderSide(color: AppColors.primary.withValues(alpha: 0.1)),
        padding: const EdgeInsets.symmetric(horizontal: 4),
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
  }

  Widget buildStatementTable() {
    if (entries.isEmpty) {
      return Container(
        decoration: BoxDecoration(color: Theme.of(context).cardColor, borderRadius: BorderRadius.circular(12)),
        child: const Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(PhosphorIconsBold.fileX, size: 48, color: AppColors.textMuted),
            SizedBox(height: 12),
            Text('لا توجد سجلات خلال هذه الفترة', style: TextStyle(color: AppColors.textMuted, fontSize: 16)),
          ]),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border.withValues(alpha: 0.15)),
      ),
      child: Column(
        children: [
          // Table header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.04),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
            ),
            child: const Row(
              children: [
                Expanded(flex: 2, child: Text('التاريخ', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13))),
                Expanded(flex: 4, child: Text('البيان', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13))),
                Expanded(flex: 2, child: Text('رقم المستند', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13), textAlign: TextAlign.center)),
                Expanded(flex: 2, child: Text('مدين (+)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppColors.error), textAlign: TextAlign.center)),
                Expanded(flex: 2, child: Text('دائن (-)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppColors.success), textAlign: TextAlign.center)),
                Expanded(flex: 2, child: Text('الرصيد', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13), textAlign: TextAlign.center)),
              ],
            ),
          ),
          const Divider(height: 1),
          // Scrollable body
          Expanded(
            child: ListView.separated(
              padding: EdgeInsets.zero,
              itemCount: entries.length,
              separatorBuilder: (_, _) => Divider(height: 1, color: AppColors.border.withValues(alpha: 0.1)),
              itemBuilder: (context, index) {
                final entry = entries[index];
                final isEven = index.isEven;
                return Container(
                  color: isEven ? Colors.transparent : AppColors.surface.withValues(alpha: 0.4),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    children: [
                      // Date
                      Expanded(
                        flex: 2,
                        child: Text(
                          dateFormat.format(entry.date),
                          style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
                        ),
                      ),
                      // Description with icon
                      Expanded(
                        flex: 4,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _getEntryIcon(entry.entryType),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                entry.description,
                                style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                      // Document number
                      Expanded(
                        flex: 2,
                        child: entry.invoiceNumber != null
                            ? Center(
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(6),
                                  onTap: () => viewDocument(entry),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: AppColors.primary.withValues(alpha: 0.06),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(PhosphorIconsBold.eye, size: 11, color: AppColors.primary),
                                        const SizedBox(width: 4),
                                        Flexible(
                                          child: Text(
                                            entry.invoiceNumber!,
                                            style: const TextStyle(fontSize: 11, color: AppColors.primary, fontWeight: FontWeight.w600),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              )
                            : const Center(child: Text('-', style: TextStyle(color: AppColors.textMuted))),
                      ),
                      // Debit
                      Expanded(
                        flex: 2,
                        child: Text(
                          entry.debit > 0 ? entry.debit.toStringAsFixed(AppConstants.decimalPlaces) : '',
                          style: const TextStyle(color: AppColors.error, fontWeight: FontWeight.w600, fontSize: 13),
                          textAlign: TextAlign.center,
                        ),
                      ),
                      // Credit
                      Expanded(
                        flex: 2,
                        child: Text(
                          entry.credit > 0 ? entry.credit.toStringAsFixed(AppConstants.decimalPlaces) : '',
                          style: const TextStyle(color: AppColors.success, fontWeight: FontWeight.w600, fontSize: 13),
                          textAlign: TextAlign.center,
                        ),
                      ),
                      // Balance
                      Expanded(
                        flex: 2,
                        child: Text(
                          entry.balance.toStringAsFixed(AppConstants.decimalPlaces),
                          style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 13,
                            color: entry.balance > 0 ? AppColors.error : AppColors.success,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _getEntryIcon(String entryType) {
    final (icon, color) = switch (entryType) {
      'invoice' => (PhosphorIconsBold.fileText, AppColors.primary),
      'payment' => (PhosphorIconsBold.arrowArcLeft, AppColors.error),
      'receipt' => (PhosphorIconsBold.arrowArcRight, AppColors.success),
      'opening' => (PhosphorIconsBold.flag, AppColors.info),
      'discount' => (PhosphorIconsBold.tag, AppColors.warning),
      _ => (PhosphorIconsBold.dotsThree, AppColors.textMuted),
    };
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Icon(icon, size: 12, color: color),
    );
  }

  Widget buildTotalsFooter() {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.1)),
      ),
      child: Row(
        children: [
          const Icon(PhosphorIconsBold.calculator, color: AppColors.textMuted, size: 18),
          const SizedBox(width: 8),
          const Text('إجمالي الفترة', style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.textMuted, fontSize: 12)),
          const Spacer(),
          _buildTotalItem('مدين (+)', totalDebit, AppColors.error),
          const SizedBox(width: 32),
          _buildTotalItem('دائن (-)', totalCredit, AppColors.success),
          const SizedBox(width: 32),
          _buildTotalItem('صافي الحركة', finalBalance, finalBalance > 0 ? AppColors.error : AppColors.success, isBold: true),
        ],
      ),
    );
  }

  Widget _buildTotalItem(String label, double value, Color color, {bool isBold = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: const TextStyle(fontSize: 10, color: AppColors.textMuted)),
        const SizedBox(height: 2),
        Text(
          '${value.toStringAsFixed(AppConstants.decimalPlaces)} ${AppConstants.currencySymbolEn}',
          style: TextStyle(fontSize: isBold ? 16 : 14, fontWeight: isBold ? FontWeight.bold : FontWeight.w600, color: color),
        ),
      ],
    );
  }

  // Abstract — from dialogs mixin
  Future<void> viewDocument(PartyStatementEntry entry);
}
