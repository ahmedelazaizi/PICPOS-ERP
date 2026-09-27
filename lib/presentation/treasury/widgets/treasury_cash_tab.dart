import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ural_erp/core/utils/friendly_error.dart';
import '../../../core/theme/app_colors.dart';
import '../../../domain/repositories/treasury_repository.dart';
import 'treasury_safe_card.dart';
import 'treasury_transactions_list.dart';

import 'package:ural_erp/l10n/app_localizations.dart';

/// Feature 011 / Issue UX-SCROLL — converted to StatefulWidget so the
/// safes-list ScrollController persists across stream re-emissions
/// (every sale/voucher hits this tab's data; the previous implicit
/// controller lost scroll position on every rebuild).
class TreasuryCashTab extends StatefulWidget {
  final AsyncValue<List<SafeData>> safes;
  final AsyncValue<List<TransactionData>> transactions;

  const TreasuryCashTab({
    super.key,
    required this.safes,
    required this.transactions,
  });

  @override
  State<TreasuryCashTab> createState() => _TreasuryCashTabState();
}

class _TreasuryCashTabState extends State<TreasuryCashTab> {
  final ScrollController _safesScrollController = ScrollController();

  @override
  void dispose() {
    _safesScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Cash Safes List
        Expanded(
          flex: 1,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                AppLocalizations.of(context)!.cashSafes,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).textTheme.titleLarge?.color,
                ),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: widget.safes.when(
                  data: (list) {
                    final cashSafes = list
                        .where((s) => s.safeType == 'cash')
                        .toList();
                    if (cashSafes.isEmpty) {
                      return const Center(
                        child: Text(
                          'No cash safes',
                          style: TextStyle(color: AppColors.textMuted),
                        ),
                      ); // Fallback or add to ARB if missed
                    }
                    return ListView.builder(
                      controller: _safesScrollController,
                      itemCount: cashSafes.length,
                      itemBuilder: (context, index) {
                        return TreasurySafeCard(safe: cashSafes[index]);
                      },
                    );
                  },
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (e, _) => Center(child: Text(friendlyError(e))),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 24),
        // Cash Transactions
        Expanded(
          flex: 2,
          child: widget.safes.when(
            data: (list) {
              final cashSafeIds = list
                  .where((s) => s.safeType == 'cash')
                  .map((s) => s.id)
                  .toList();
              return TreasuryTransactionsList(
                transactions: widget.transactions,
                typeFilter: 'cash',
                safeIds: cashSafeIds,
              );
            },
            loading: () => TreasuryTransactionsList(
              transactions: widget.transactions,
              typeFilter: 'cash',
            ),
            error: (_, _) => TreasuryTransactionsList(
              transactions: widget.transactions,
              typeFilter: 'cash',
            ),
          ),
        ),
      ],
    );
  }
}
