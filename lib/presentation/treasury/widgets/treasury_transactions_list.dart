import 'package:flutter/material.dart';
import 'package:ural_erp/core/widgets/app_toast.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../core/theme/app_colors.dart';

import '../../../services/generators/thermal_receipt_generator.dart';
import '../../../data/providers/providers.dart';

import 'package:ural_erp/l10n/app_localizations.dart';
import '../../../../../../core/constants/app_constants.dart';
import '../../../core/config/brand.dart';

/// Feature 011 / Issue UX-SCROLL — converted from ConsumerWidget to
/// ConsumerStatefulWidget so we can persist a ScrollController across
/// rebuilds. The list re-emits whenever a sync writes a safe_transaction
/// (every sale, every receipt voucher, every shift close — i.e. tens of
/// times per minute on a busy POS); the previous implicit-controller
/// pattern lost scroll position on every emission, so the user couldn't
/// even scroll to the bottom of the page before the screen "reloaded".
class TreasuryTransactionsList extends ConsumerStatefulWidget {
  final AsyncValue<List<TransactionData>> transactions;
  final String? typeFilter;
  final List<int> safeIds;

  const TreasuryTransactionsList({
    super.key,
    required this.transactions,
    this.typeFilter,
    this.safeIds = const [],
  });

  @override
  ConsumerState<TreasuryTransactionsList> createState() =>
      _TreasuryTransactionsListState();
}

class _TreasuryTransactionsListState
    extends ConsumerState<TreasuryTransactionsList> {
  final ScrollController _scrollController = ScrollController();
  // Issue 1 (Feature 022): operator-driven search/filter so historical
  // vouchers can actually be found. The dataset is bounded (recent
  // transactions only) so client-side filtering is fine — no paging
  // needed yet. Three knobs:
  //   - text search (matches voucher number / description / amount)
  //   - type chip (all / receipts only / payments only)
  //   - parties / categories surface in the existing rows
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  String _typeFilter = 'all'; // 'all' | 'receipt' | 'payment'

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  bool _matchesSearch(TransactionData t) {
    if (_searchQuery.isEmpty) return true;
    final q = _searchQuery.toLowerCase();
    if (t.voucherNumber.toLowerCase().contains(q)) return true;
    if ((t.description ?? '').toLowerCase().contains(q)) return true;
    if (t.amount.toStringAsFixed(AppConstants.decimalPlaces).contains(q)) {
      return true;
    }
    return false;
  }

  bool _matchesTypeFilter(TransactionData t) {
    if (_typeFilter == 'all') return true;
    return t.transactionType == _typeFilter;
  }

  String _getCategoryLabel(BuildContext context, String category) {
    final localizations = AppLocalizations.of(context)!;
    switch (category) {
      case 'customer_payment':
        return localizations.customerPayment;
      case 'supplier_payment':
        return localizations.supplierPayment;
      case 'sales':
        return localizations.sales;
      case 'purchase':
        return localizations.purchase;
      case 'expense':
        return localizations.expense;
      case 'salary':
        return localizations.salary;
      case 'advance':
        return localizations.advance;
      case 'loan':
        return localizations.loan;
      default:
        return localizations.other;
    }
  }

  Future<void> _printVoucher(
    BuildContext context,
    WidgetRef ref,
    TransactionData t,
  ) async {
    try {
      final settingsRepo = ref.read(settingsRepositoryProvider);
      final partiesRepo = ref.read(partiesRepositoryProvider);
      final companyName =
          await settingsRepo.getSetting('company_name') ?? Brand.documentCompanyFallback;
      final companyPhone = await settingsRepo.getSetting('company_phone');

      // Get party name if available
      String? partyName;
      if (t.partyId != null) {
        final party = await partiesRepo.getPartyById(t.partyId!);
        partyName = party?.name;
      }

      // Build description with category
      // ignore: use_build_context_synchronously
      final categoryLabel = _getCategoryLabel(context, t.category);
      final fullDescription = t.description != null
          ? '$categoryLabel - ${t.description}'
          : categoryLabel;

      await ThermalReceiptGenerator.printVoucher(
        voucherNumber: t.voucherNumber,
        voucherType: t.transactionType == 'receipt' ? 'receipt' : 'payment',
        amount: t.amount,
        date: t.createdAt,
        partyName: partyName,
        description: fullDescription,
        companyName: companyName,
        companyPhone: companyPhone,
      );

      if (context.mounted) {
        AppToast.show(context, 'جاري الطباعة...', type: ToastType.success);
      }
    } catch (e) {
      if (context.mounted) {
        AppToast.show(context, 'خطأ في الطباعة: $e', type: ToastType.error);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          AppLocalizations.of(context)!.recentTransactions,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: Theme.of(context).textTheme.titleLarge?.color,
          ),
        ),
        const SizedBox(height: 12),
        // Issue 1 (Feature 022): search + type-filter row.
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'بحث برقم السند، الوصف، أو المبلغ',
                  prefixIcon: const Icon(
                    PhosphorIconsBold.magnifyingGlass,
                    size: 18,
                  ),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 18),
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _searchQuery = '');
                          },
                        )
                      : null,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                onChanged: (v) =>
                    setState(() => _searchQuery = v.trim()),
              ),
            ),
            const SizedBox(width: 12),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'all', label: Text('الكل')),
                ButtonSegment(value: 'receipt', label: Text('قبض')),
                ButtonSegment(value: 'payment', label: Text('صرف')),
              ],
              selected: {_typeFilter},
              onSelectionChanged: (sel) =>
                  setState(() => _typeFilter = sel.first),
              showSelectedIcon: false,
            ),
          ],
        ),
        const SizedBox(height: 12),
        Expanded(
          child: Card(
            elevation: 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: widget.transactions.when(
              data: (list) {
                // Filter by safe IDs to show only transactions for this tab's safes
                var filtered = widget.safeIds.isNotEmpty
                    ? list.where((t) => widget.safeIds.contains(t.safeId)).toList()
                    : list;
                // Issue 1 (Feature 022): apply search + type chip on top
                // of the existing safe filter.
                filtered = filtered
                    .where(_matchesTypeFilter)
                    .where(_matchesSearch)
                    .toList();
                if (filtered.isEmpty) {
                  return Center(
                    child: Text(
                      _searchQuery.isNotEmpty || _typeFilter != 'all'
                          ? 'لا توجد سندات مطابقة'
                          : AppLocalizations.of(context)!.noTransactions,
                      style: const TextStyle(color: AppColors.textMuted),
                    ),
                  );
                }

                return ListView.separated(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(16),
                  itemCount: filtered.length,
                  separatorBuilder: (ctx, idx) => const Divider(),
                  itemBuilder: (context, index) {
                    final t = filtered[index];
                    final isReceipt = t.transactionType == 'receipt';

                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: isReceipt
                            ? AppColors.success.withValues(alpha: 0.1)
                            : AppColors.error.withValues(alpha: 0.1),
                        child: Icon(
                          isReceipt
                              ? PhosphorIconsBold.arrowCircleDown
                              : PhosphorIconsBold.arrowCircleUp,
                          color: isReceipt
                              ? AppColors.success
                              : AppColors.error,
                        ),
                      ),
                      title: Text(
                        t.voucherNumber,
                        style: const TextStyle(fontWeight: FontWeight.w500),
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(_getCategoryLabel(context, t.category)),
                          Text(
                            '${t.createdAt.day}/${t.createdAt.month}/${t.createdAt.year}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.textMuted,
                            ),
                          ),
                        ],
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '${isReceipt ? '+' : '-'}${t.amount.toStringAsFixed(AppConstants.decimalPlaces)} ${AppConstants.currencySymbolEn}',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: isReceipt
                                  ? AppColors.success
                                  : AppColors.error,
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            icon: const Icon(
                              PhosphorIconsBold.printer,
                              size: 20,
                            ),
                            color: AppColors.primary,
                            tooltip: 'طباعة السند',
                            onPressed: () => _printVoucher(context, ref, t),
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('خطأ: $e')),
            ),
          ),
        ),
      ],
    );
  }
}
