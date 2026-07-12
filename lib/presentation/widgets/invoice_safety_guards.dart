// ═══════════════════════════════════════════════════════════════════════════
// Invoice Safety Guards (U-06, U-08, U-09)
// Pre-checkout validation utilities for POS and Sales Invoices
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../core/theme/app_colors.dart';
import '../../domain/entities/party_entity.dart';

final _currFmt = NumberFormat('#,##0.00');

/// U-08: Credit Limit Warning Banner
/// Shows a prominent banner when the selected customer has exceeded their credit limit.
class CreditLimitWarningBanner extends StatelessWidget {
  final PartyEntity? customer;
  final double invoiceTotal;

  const CreditLimitWarningBanner({
    super.key,
    required this.customer,
    this.invoiceTotal = 0,
  });

  @override
  Widget build(BuildContext context) {
    if (customer == null || customer!.creditLimit <= 0) {
      return const SizedBox.shrink();
    }

    final afterSale = customer!.balance + invoiceTotal;
    final willExceed = afterSale > customer!.creditLimit;
    final alreadyExceeded = customer!.creditExceeded;

    if (!alreadyExceeded && !willExceed) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: alreadyExceeded
            ? Colors.red.shade50
            : Colors.orange.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: alreadyExceeded
              ? Colors.red.shade200
              : Colors.orange.shade200,
        ),
      ),
      child: Row(
        children: [
          Icon(
            alreadyExceeded
                ? PhosphorIconsBold.warningCircle
                : PhosphorIconsBold.warning,
            color: alreadyExceeded ? Colors.red : Colors.orange,
            size: 20,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  alreadyExceeded
                      ? '⛔ الحد الائتماني متجاوز!'
                      : '⚠️ هذه الفاتورة ستتجاوز الحد الائتماني',
                  style: GoogleFonts.cairo(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: alreadyExceeded ? Colors.red.shade700 : Colors.orange.shade800,
                  ),
                ),
                Text(
                  'الحد: ${_currFmt.format(customer!.creditLimit)} | '
                  'الرصيد الحالي: ${_currFmt.format(customer!.balance)} | '
                  'المتاح: ${_currFmt.format(customer!.availableCredit)}',
                  style: GoogleFonts.cairo(
                    fontSize: 10,
                    color: AppColors.textMuted,
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

/// U-06: Invoice Finalization Confirmation Dialog
/// Shows a summary of the invoice before final submission.
class InvoiceConfirmationDialog {
  /// Show confirmation dialog before finalizing an invoice/sale.
  /// Returns true if user confirms, false/null if cancelled.
  static Future<bool?> show(
    BuildContext context, {
    required int itemCount,
    required double subtotal,
    required double discount,
    required double tax,
    required double total,
    required String paymentMethod,
    String? customerName,
    double? cashAmount,
    double? bankAmount,
  }) {
    final paymentLabel = switch (paymentMethod) {
      'cash' => 'نقدي',
      'bank' => 'بنك / شبكة',
      'credit' => 'آجل',
      'multiple' => 'مقسم',
      _ => paymentMethod,
    };

    return showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: ui.TextDirection.rtl,
        child: AlertDialog(
          title: Row(
            children: [
              const Icon(PhosphorIconsBold.receipt, color: AppColors.primary, size: 24),
              const SizedBox(width: 8),
              Text('تأكيد الفاتورة', style: GoogleFonts.cairo(fontWeight: FontWeight.w700)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Summary card
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  children: [
                    if (customerName != null && customerName.isNotEmpty)
                      _summaryRow('العميل', customerName),
                    _summaryRow('عدد الأصناف', '$itemCount'),
                    _summaryRow('المبلغ الفرعي', _currFmt.format(subtotal)),
                    if (discount > 0)
                      _summaryRow('الخصم', '- ${_currFmt.format(discount)}', valueColor: AppColors.error),
                    if (tax > 0)
                      _summaryRow('الضريبة', _currFmt.format(tax)),
                    const Divider(height: 16),
                    _summaryRow('الإجمالي', _currFmt.format(total),
                        isBold: true, valueColor: AppColors.primary),
                    const SizedBox(height: 4),
                    _summaryRow('طريقة الدفع', paymentLabel),
                    if (paymentMethod == 'multiple' && cashAmount != null && bankAmount != null) ...[
                      _summaryRow('  نقدي', _currFmt.format(cashAmount)),
                      _summaryRow('  بنك', _currFmt.format(bankAmount)),
                    ],
                  ],
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء'),
            ),
            ElevatedButton.icon(
              onPressed: () => Navigator.pop(ctx, true),
              icon: const Icon(PhosphorIconsBold.checkCircle, size: 18),
              label: Text('تأكيد الحفظ', style: GoogleFonts.cairo(fontWeight: FontWeight.w700)),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.success,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  static Widget _summaryRow(String label, String value, {bool isBold = false, Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: GoogleFonts.cairo(fontSize: 12, color: AppColors.textMuted)),
          Text(
            value,
            style: GoogleFonts.cairo(
              fontSize: isBold ? 14 : 12,
              fontWeight: isBold ? FontWeight.w700 : FontWeight.w500,
              color: valueColor ?? AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

/// U-09: Duplicate Invoice Number Warning
/// Checks if an invoice number already exists before finalization.
class DuplicateInvoiceGuard {
  /// Check for duplicate invoice numbers and warn the user.
  /// Returns true if safe to proceed (no duplicate or user chose to continue).
  static Future<bool> check(
    BuildContext context, {
    required String invoiceNumber,
    required Future<bool> Function(String) existsChecker,
  }) async {
    final exists = await existsChecker(invoiceNumber);
    if (!exists) return true;

    if (!context.mounted) return false;

    final proceed = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: ui.TextDirection.rtl,
        child: AlertDialog(
          title: Row(
            children: [
              const Icon(PhosphorIconsBold.warningCircle, color: Colors.orange, size: 24),
              const SizedBox(width: 8),
              Text('رقم فاتورة مكرر', style: GoogleFonts.cairo(fontWeight: FontWeight.w700)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'رقم الفاتورة "$invoiceNumber" موجود مسبقاً في النظام.',
                style: GoogleFonts.cairo(fontSize: 13),
              ),
              const SizedBox(height: 8),
              Text(
                'هل تريد المتابعة رغم ذلك؟',
                style: GoogleFonts.cairo(fontSize: 12, color: AppColors.textMuted),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('لا، تعديل الرقم'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.orange, foregroundColor: Colors.white),
              child: const Text('نعم، متابعة'),
            ),
          ],
        ),
      ),
    );

    return proceed == true;
  }
}
