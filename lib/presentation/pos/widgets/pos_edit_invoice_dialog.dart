import 'package:picpos_erp/core/i18n/tr.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/constants/app_constants.dart';
import '../../../data/providers/providers.dart';
import '../providers/pos_notification_provider.dart';

/// Dialog for editing invoice payment details and notes
class PosEditInvoiceDialog extends ConsumerStatefulWidget {
  final SalesInvoiceData invoice;

  const PosEditInvoiceDialog({super.key, required this.invoice});

  /// Static helper to show the dialog
  static Future<void> show(
    BuildContext context, {
    required SalesInvoiceData invoice,
  }) async {
    return showDialog<void>(
      context: context,
      builder: (context) => PosEditInvoiceDialog(invoice: invoice),
    );
  }

  @override
  ConsumerState<PosEditInvoiceDialog> createState() =>
      _PosEditInvoiceDialogState();
}

class _PosEditInvoiceDialogState extends ConsumerState<PosEditInvoiceDialog> {
  late TextEditingController _notesController;
  late TextEditingController _cashController;
  late TextEditingController _bankController;
  late String _selectedPaymentMethod;

  /// Labels match the checkout dialog's chips (`pos_payment_dialogs.dart`) so a
  /// method is never called two different things on two screens.
  ///
  /// ── 'card' and 'click' were missing, and that was a crash ─────────────
  /// `DropdownButtonFormField` asserts that its value is among its items. With
  /// only {cash, transfer, credit, multiple} here, opening this dialog on any
  /// invoice saved as `card`, `click` or `mixed` — i.e. every bank or split
  /// sale — threw. The POS writes exactly those values, so the pencil icon in
  /// the previous-invoices dialog was broken for a large share of real
  /// invoices on BOTH tills. Adding the two keys plus the normalisation in
  /// [initState] is a fix for both, not a PicPos feature.
  ///
  /// Verified against `SalesPaymentCalculator.getSafeType`, which already
  /// accepts every key offered here, so the DAO can post all of them.
  final Map<String, String> _paymentMethods = {
    'cash': tr('نقدي'),
    'card': tr('بطاقة (بنك)'),
    'transfer': tr('تحويل'),
    'click': tr('كليك'),
    'credit': tr('آجل'),
    'multiple': tr('متعدد'),
  };

  /// Historic spellings the POS and this dialog disagree on.
  ///
  /// The checkout dialog maps its 'multiple' chip to `'mixed'` before saving,
  /// while this dialog writes `'multiple'`. Both are understood downstream, so
  /// normalising the stored column is a separate migration-shaped task; here we
  /// only need the dropdown to be able to render what it was handed.
  static const _methodAliases = {
    'mixed': 'multiple',
    'bank': 'transfer',
  };

  @override
  void initState() {
    super.initState();
    _notesController = TextEditingController(text: widget.invoice.notes ?? '');
    _cashController = TextEditingController(
      text: widget.invoice.cashPaid.toStringAsFixed(AppConstants.decimalPlaces),
    );
    _bankController = TextEditingController(
      text: widget.invoice.bankPaid.toStringAsFixed(AppConstants.decimalPlaces),
    );

    final stored = widget.invoice.paymentMethod;
    final normalized = _methodAliases[stored] ?? stored;
    if (_paymentMethods.containsKey(normalized)) {
      _selectedPaymentMethod = normalized;
    } else {
      // Truly unknown value (bad import, older build, hand-edited row): keep it
      // selectable and visible rather than asserting. Showing the raw string
      // also tells whoever reports the bug what the column actually holds.
      _paymentMethods[stored] = tr('غير معروف ({stored})', {'stored': stored});
      _selectedPaymentMethod = stored;
    }
  }

  @override
  void dispose() {
    _notesController.dispose();
    _cashController.dispose();
    _bankController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        title: Row(
          children: [
            const Icon(
              PhosphorIconsBold.pencilSimple,
              color: AppColors.warning,
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                tr('تعديل فاتورة #{p0}', {'p0': widget.invoice.invoiceNumber}),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: 450,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Invoice Info
                _buildInvoiceInfoCard(),
                const SizedBox(height: 16),

                // Payment Method
                DropdownButtonFormField<String>(
                  initialValue: _selectedPaymentMethod,
                  // `isExpanded` + ellipsis: the fallback label for an unknown
                  // stored method embeds the raw column value, whose length we
                  // do not control. Without this the selected-item row
                  // overflowed the 450 px dialog instead of truncating.
                  isExpanded: true,
                  decoration:  InputDecoration(
                    labelText: tr('طريقة الدفع'),
                    prefixIcon: const Icon(PhosphorIconsBold.wallet),
                  ),
                  items: _paymentMethods.entries
                      .map(
                        (e) => DropdownMenuItem(
                          value: e.key,
                          child: Text(e.value, overflow: TextOverflow.ellipsis),
                        ),
                      )
                      .toList(),
                  onChanged: _handlePaymentMethodChange,
                ),

                // The split fields below only cover cash and bank. For 'click'
                // the DAO resolves the click safe from the method, so say so
                // rather than leaving the operator to wonder which field it is.
                if (_selectedPaymentMethod == 'click')
                   Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Row(
                      children: [
                        const Icon(PhosphorIconsBold.info,
                            size: 14, color: AppColors.info),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            tr('مبلغ كليك يُرحَّل بالكامل على صندوق كليك تلقائياً'),
                            style: const TextStyle(
                                fontSize: 11, color: AppColors.textMuted),
                          ),
                        ),
                      ],
                    ),
                  ),

                // Multiple payment fields
                if (_selectedPaymentMethod == 'multiple') ...[
                  const SizedBox(height: 16),
                   Text(
                    tr('تقسيم المبالغ:'),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _cashController,
                          keyboardType: TextInputType.number,
                          decoration:  InputDecoration(
                            labelText: tr('نقدي'),
                            prefixIcon: const Icon(
                              PhosphorIconsBold.money,
                              color: AppColors.success,
                            ),
                          ),
                          onChanged: (val) => _recalculateSplit(fromCash: true),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: _bankController,
                          keyboardType: TextInputType.number,
                          decoration:  InputDecoration(
                            labelText: tr('بطاقة/تحويل'),
                            prefixIcon: const Icon(
                              PhosphorIconsBold.creditCard,
                              color: AppColors.info,
                            ),
                          ),
                          onChanged: (val) =>
                              _recalculateSplit(fromCash: false),
                        ),
                      ),
                    ],
                  ),
                ],

                const SizedBox(height: 16),

                // Notes
                TextField(
                  controller: _notesController,
                  decoration:  InputDecoration(
                    labelText: tr('ملاحظات'),
                    prefixIcon: const Icon(PhosphorIconsBold.notepad),
                    hintText: tr('أضف ملاحظات اختيارية...'),
                  ),
                  maxLines: 2,
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child:  Text(tr('إلغاء')),
          ),
          ElevatedButton.icon(
            onPressed: _saveChanges,
            icon: const Icon(PhosphorIconsBold.check),
            label:  Text(tr('حفظ التغييرات')),
          ),
        ],
      ),
    );
  }

  Widget _buildInvoiceInfoCard() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
               Text(
                tr('الإجمالي:'),
                style: const TextStyle(color: AppColors.textMuted),
              ),
              Text(
                '${widget.invoice.total.toStringAsFixed(AppConstants.decimalPlaces)} ${AppConstants.currencySymbolAr}',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: AppColors.success,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
               Text(
                tr('المدفوع حالياً:'),
                style: const TextStyle(color: AppColors.textMuted),
              ),
              Text(
                '${widget.invoice.paid.toStringAsFixed(AppConstants.decimalPlaces)} ${AppConstants.currencySymbolAr}',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
               Text(
                tr('المتبقي:'),
                style: const TextStyle(color: AppColors.textMuted),
              ),
              Text(
                '${(widget.invoice.total - widget.invoice.paid).toStringAsFixed(AppConstants.decimalPlaces)} ${AppConstants.currencySymbolAr}',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: (widget.invoice.total - widget.invoice.paid) > 0
                      ? AppColors.error
                      : AppColors.success,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _handlePaymentMethodChange(String? value) {
    if (value == null) return;
    setState(() {
      _selectedPaymentMethod = value;
      final paid =
          widget.invoice.paid.toStringAsFixed(AppConstants.decimalPlaces);
      // Auto-fill amounts based on payment method
      if (value == 'cash' || value == 'credit') {
        _cashController.text = paid;
        _bankController.text = '0.00';
      } else if (value == 'transfer' || value == 'card') {
        // 'card' lands in the bank column exactly like 'transfer' — it was
        // absent from this branch only because it was absent from the dropdown.
        _cashController.text = '0.00';
        _bankController.text = paid;
      } else if (value == 'click') {
        // Deliberately leaves both fields at zero: the DAO derives the click
        // safe from the METHOD itself (`getDefaultSafeByType('click')`), and
        // these two fields only control cash and bank. Pre-filling one of them
        // would suggest the operator can steer the click amount from here.
        _cashController.text = '0.00';
        _bankController.text = '0.00';
      }
    });
  }

  void _recalculateSplit({required bool fromCash}) {
    final cash = double.tryParse(_cashController.text) ?? 0;
    final bank = double.tryParse(_bankController.text) ?? 0;

    if (fromCash) {
      final remaining = widget.invoice.paid - cash;
      _bankController.text = remaining.toStringAsFixed(AppConstants.decimalPlaces);
    } else {
      final remaining = widget.invoice.paid - bank;
      _cashController.text = remaining.toStringAsFixed(AppConstants.decimalPlaces);
    }
  }

  Future<void> _saveChanges() async {
    try {
      final cashAmount = double.tryParse(_cashController.text) ?? 0;
      final bankAmount = double.tryParse(_bankController.text) ?? 0;
      final salesRepo = ref.read(salesRepositoryProvider);

      await salesRepo.updateSalesInvoicePayment(
        widget.invoice.id,
        _selectedPaymentMethod,
        _notesController.text.isEmpty ? null : _notesController.text,
        newCashAmount: cashAmount,
        newBankAmount: bankAmount,
      );

      if (mounted) {
        Navigator.pop(context);
        showPosToast(
          context,
          ref,
          tr('تم تحديث الفاتورة والمبالغ بنجاح'),
          type: PosNotificationType.success,
        );
      }
    } catch (e) {
      if (mounted) {
        showPosToast(
          context,
          ref,
          tr('خطأ تحديث الفاتورة: {e}', {'e': e}),
          type: PosNotificationType.error,
        );
      }
    }
  }
}
