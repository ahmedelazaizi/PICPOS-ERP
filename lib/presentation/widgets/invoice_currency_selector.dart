// ═══════════════════════════════════════════════════════════════════════════
// F-07: Multi-Currency Invoice Selector Widget
// Adds currency selection + conversion to sales/purchase invoice dialogs
// ═══════════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../core/theme/app_colors.dart';

final _rateFmt = NumberFormat('#,##0.####');
final _currFmt = NumberFormat('#,##0.00');

/// Currency item for dropdown
class InvoiceCurrency {
  final int id;
  final String code;
  final String name;
  final String symbol;
  final double exchangeRate; // to base currency
  final DateTime rateDate;

  const InvoiceCurrency({
    required this.id,
    required this.code,
    required this.name,
    required this.symbol,
    required this.exchangeRate,
    required this.rateDate,
  });
}

/// Reusable currency selector for invoice create/edit screens
class InvoiceCurrencySelector extends StatelessWidget {
  final List<InvoiceCurrency> currencies;
  final InvoiceCurrency? selected;
  final String baseCurrencyCode;
  final ValueChanged<InvoiceCurrency?> onChanged;
  final double? invoiceTotal;

  const InvoiceCurrencySelector({
    super.key,
    required this.currencies,
    this.selected,
    required this.baseCurrencyCode,
    required this.onChanged,
    this.invoiceTotal,
  });

  @override
  Widget build(BuildContext context) {
    if (currencies.length <= 1) return const SizedBox.shrink();

    final isBase = selected == null || selected!.code == baseCurrencyCode;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: isBase ? Colors.transparent : AppColors.info.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(8),
        border: isBase ? null : Border.all(color: AppColors.info.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          const Icon(PhosphorIconsBold.currencyCircleDollar, size: 18, color: AppColors.textMuted),
          const SizedBox(width: 8),
          // Currency dropdown
          DropdownButtonHideUnderline(
            child: DropdownButton<InvoiceCurrency?>(
              value: selected,
              isDense: true,
              style: GoogleFonts.cairo(fontSize: 12, color: AppColors.textPrimary),
              items: [
                DropdownMenuItem<InvoiceCurrency?>(
                  value: null,
                  child: Text('$baseCurrencyCode (أساسية)', style: GoogleFonts.cairo(fontSize: 12)),
                ),
                ...currencies.where((c) => c.code != baseCurrencyCode).map(
                  (c) => DropdownMenuItem<InvoiceCurrency?>(
                    value: c,
                    child: Text('${c.code} — ${c.name}', style: GoogleFonts.cairo(fontSize: 12)),
                  ),
                ),
              ],
              onChanged: onChanged,
            ),
          ),
          const Spacer(),
          // Exchange rate display
          if (!isBase && selected != null) ...[
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  'سعر الصرف: ${_rateFmt.format(selected!.exchangeRate)}',
                  style: GoogleFonts.cairo(fontSize: 10, color: AppColors.textMuted),
                ),
                Text(
                  '1 ${selected!.code} = ${_rateFmt.format(selected!.exchangeRate)} $baseCurrencyCode',
                  style: GoogleFonts.cairo(fontSize: 9, color: AppColors.info),
                ),
              ],
            ),
          ],
          // Converted total
          if (!isBase && selected != null && invoiceTotal != null) ...[
            const SizedBox(width: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.info.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${selected!.symbol} ${_currFmt.format(invoiceTotal!)}',
                    style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.info),
                  ),
                  Text(
                    '≈ $baseCurrencyCode ${_currFmt.format(invoiceTotal! * selected!.exchangeRate)}',
                    style: GoogleFonts.cairo(fontSize: 10, color: AppColors.textMuted),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Compact inline rate badge for invoice line items
class ExchangeRateBadge extends StatelessWidget {
  final double rate;
  final String fromCurrency;
  final String toCurrency;

  const ExchangeRateBadge({
    super.key,
    required this.rate,
    required this.fromCurrency,
    required this.toCurrency,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.info.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        '1 $fromCurrency = ${_rateFmt.format(rate)} $toCurrency',
        style: GoogleFonts.cairo(fontSize: 9, color: AppColors.info),
      ),
    );
  }
}
