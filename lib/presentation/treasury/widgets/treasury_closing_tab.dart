import 'package:ural_erp/core/i18n/tr.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_colors.dart';
import '../../../domain/repositories/treasury_repository.dart';

import '../screens/treasury_closing_screen.dart';
import 'package:ural_erp/l10n/app_localizations.dart';
import '../../../../../../core/constants/app_constants.dart';

class TreasuryClosingTab extends StatefulWidget {
  final AsyncValue<List<SafeData>> safes;
  final Function(SafeData) onClosing;

  const TreasuryClosingTab({
    super.key,
    required this.safes,
    required this.onClosing,
  });

  @override
  State<TreasuryClosingTab> createState() => _TreasuryClosingTabState();
}

class _TreasuryClosingTabState extends State<TreasuryClosingTab> {
  // Dedicated scroll controller so the Scrollbar widget can attach to
  // the same controller the GridView consumes — without this binding
  // the bar appears but doesn't react to mouse drag, and on a desktop
  // build the user has no visible cue that the list is scrollable.
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context)!;
    return widget.safes.when(
      data: (list) {
        return Column(
          children: [
            // Compact Closing Button — slim strip instead of giant banner
            InkWell(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const TreasuryClosingScreen(),
                  ),
                );
              },
              borderRadius: BorderRadius.circular(10),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFFF6B6B), Color(0xFFEE5A24)],
                    begin: AlignmentDirectional.topEnd,
                    end: AlignmentDirectional.bottomStart,
                  ),
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFEE5A24).withValues(alpha: 0.25),
                      blurRadius: 8,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        PhosphorIconsBold.lockKey,
                        color: Colors.white,
                        size: 18,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            localizations.dailyClosing,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            tr('إدخال المبلغ الفعلي لمطابقته مع رصيد النظام  •  {p0} صندوق', {'p0': list.length}),
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Icon(
                      PhosphorIconsBold.caretLeft,
                      color: Colors.white,
                      size: 18,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Safes grid — 4 columns, slimmer cards (ratio 3.0 ≈ doubles
            // the rows visible per screen vs. the previous 1.8). Wrapped
            // in a Scrollbar with thumbVisibility:true so the operator
            // can SEE the list extends beyond the viewport instead of
            // assuming the visible cards are all of them.
            Expanded(
              child: Scrollbar(
                controller: _scrollController,
                thumbVisibility: true,
                child: GridView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsetsDirectional.only(end: 6),
                  gridDelegate:
                      const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 4,
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 10,
                    childAspectRatio: 3.0,
                  ),
                  itemCount: list.length,
                  itemBuilder: (context, index) {
                    final safe = list[index];
                    return _SafeClosingCard(
                      safe: safe,
                      onClosing: widget.onClosing,
                      closeTooltip: localizations.close,
                    );
                  },
                ),
              ),
            ),
          ],
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
    );
  }
}

/// Single safe card in the daily-closing grid.
///
/// Visual contract:
///   • Left edge tint (4px) keyed to safe type — cash green, click violet,
///     bank blue. Lets the operator scan the grid for "all the cash safes"
///     without reading every name.
///   • Type icon + name + balance laid out left-to-right (RTL flips it
///     visually). Balance uses tabular numbers so columns of figures
///     align across rows.
///   • Trailing close button is red when a balance exists, green check
///     when zero — same affordance as before, larger touch target.
class _SafeClosingCard extends StatelessWidget {
  const _SafeClosingCard({
    required this.safe,
    required this.onClosing,
    required this.closeTooltip,
  });

  final SafeData safe;
  final void Function(SafeData) onClosing;
  final String closeTooltip;

  @override
  Widget build(BuildContext context) {
    final isCash = safe.safeType == 'cash';
    final isClick = safe.safeType == 'click';
    final safeIcon = isCash
        ? PhosphorIconsBold.money
        : isClick
            ? PhosphorIconsBold.cellSignalFull
            : PhosphorIconsBold.bank;
    final safeColor = isCash
        ? AppColors.success
        : isClick
            ? const Color(0xFF7C3AED)
            : AppColors.info;
    final hasBalance = safe.balance.abs() > 0.001;

    return Material(
      color: Theme.of(context).cardColor,
      elevation: 1,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: () => onClosing(safe),
        borderRadius: BorderRadius.circular(10),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            // Subtle vertical edge tint keyed to safe type. RTL puts the
            // edge on the right visually, which lines up with the icon
            // also being on the right in this layout.
            border: Border(
              right: BorderSide(color: safeColor, width: 4),
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: safeColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(safeIcon, size: 18, color: safeColor),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      trData(safe.name),
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${NumberFormat('#,##0.00', 'ar').format(safe.balance)} ${AppConstants.currencySymbolEn}',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        fontFeatures: const [FontFeature.tabularFigures()],
                        color: hasBalance
                            ? AppColors.success
                            : AppColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (hasBalance)
                SizedBox(
                  width: 32,
                  height: 32,
                  child: IconButton(
                    onPressed: () => onClosing(safe),
                    icon: const Icon(PhosphorIconsBold.lockKey, size: 14),
                    style: IconButton.styleFrom(
                      backgroundColor: const Color(0xFFEE5A24),
                      foregroundColor: Colors.white,
                      padding: EdgeInsets.zero,
                    ),
                    tooltip: closeTooltip,
                  ),
                )
              else
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: AppColors.success.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    PhosphorIconsBold.check,
                    size: 16,
                    color: AppColors.success,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
