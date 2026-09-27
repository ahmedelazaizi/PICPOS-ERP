import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_colors.dart';
import '../../../domain/repositories/treasury_repository.dart';
import 'treasury_safe_card.dart';
import 'treasury_transactions_list.dart';

import 'package:ural_erp/l10n/app_localizations.dart';

/// Feature 011 / Issue UX-SCROLL — same conversion as TreasuryCashTab.
class TreasuryBankTab extends StatefulWidget {
  final AsyncValue<List<SafeData>> safes;
  final AsyncValue<List<TransactionData>> transactions;

  const TreasuryBankTab({
    super.key,
    required this.safes,
    required this.transactions,
  });

  @override
  State<TreasuryBankTab> createState() => _TreasuryBankTabState();
}

class _TreasuryBankTabState extends State<TreasuryBankTab> {
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
        // Bank Accounts List
        Expanded(
          flex: 1,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                AppLocalizations.of(context)!.bankAccounts,
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
                    final bankSafes = list
                        .where((s) => s.safeType == 'bank')
                        .toList();
                    if (bankSafes.isEmpty) {
                      return Center(
                        child: Text(
                          AppLocalizations.of(context)!.noBankAccounts,
                          style: const TextStyle(color: AppColors.textMuted),
                        ),
                      );
                    }
                    return ListView.builder(
                      controller: _safesScrollController,
                      itemCount: bankSafes.length,
                      itemBuilder: (context, index) {
                        return TreasurySafeCard(
                          safe: bankSafes[index],
                          isBank: true,
                        );
                      },
                    );
                  },
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (e, _) => Center(child: Text('Error: $e')),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 24),
        // Bank Transactions
        Expanded(
          flex: 2,
          child: widget.safes.when(
            data: (list) {
              final bankSafeIds = list
                  .where((s) => s.safeType == 'bank')
                  .map((s) => s.id)
                  .toList();
              return TreasuryTransactionsList(
                transactions: widget.transactions,
                typeFilter: 'bank',
                safeIds: bankSafeIds,
              );
            },
            loading: () => TreasuryTransactionsList(
              transactions: widget.transactions,
              typeFilter: 'bank',
            ),
            error: (_, _) => TreasuryTransactionsList(
              transactions: widget.transactions,
              typeFilter: 'bank',
            ),
          ),
        ),
      ],
    );
  }
}
