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

  final Map<String, String> _paymentMethods = {
    'cash': 'نقدي',
    'transfer': 'تحويل',
    'credit': 'آجل',
    'multiple': 'متعدد',
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
    _selectedPaymentMethod = widget.invoice.paymentMethod;
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
            Text('تعديل فاتورة #${widget.invoice.invoiceNumber}'),
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
                  decoration: const InputDecoration(
                    labelText: 'طريقة الدفع',
                    prefixIcon: Icon(PhosphorIconsBold.wallet),
                  ),
                  items: _paymentMethods.entries
                      .map(
                        (e) => DropdownMenuItem(
                          value: e.key,
                          child: Text(e.value),
                        ),
                      )
                      .toList(),
                  onChanged: _handlePaymentMethodChange,
                ),

                // Multiple payment fields
                if (_selectedPaymentMethod == 'multiple') ...[
                  const SizedBox(height: 16),
                  const Text(
                    'تقسيم المبالغ:',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _cashController,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'نقدي',
                            prefixIcon: Icon(
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
                          decoration: const InputDecoration(
                            labelText: 'بطاقة/تحويل',
                            prefixIcon: Icon(
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
                  decoration: const InputDecoration(
                    labelText: 'ملاحظات',
                    prefixIcon: Icon(PhosphorIconsBold.notepad),
                    hintText: 'أضف ملاحظات اختيارية...',
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
            child: const Text('إلغاء'),
          ),
          ElevatedButton.icon(
            onPressed: _saveChanges,
            icon: const Icon(PhosphorIconsBold.check),
            label: const Text('حفظ التغييرات'),
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
              const Text(
                'الإجمالي:',
                style: TextStyle(color: AppColors.textMuted),
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
              const Text(
                'المدفوع حالياً:',
                style: TextStyle(color: AppColors.textMuted),
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
              const Text(
                'المتبقي:',
                style: TextStyle(color: AppColors.textMuted),
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
      // Auto-fill amounts based on payment method
      if (value == 'cash' || value == 'credit') {
        _cashController.text = widget.invoice.paid.toStringAsFixed(AppConstants.decimalPlaces);
        _bankController.text = '0.00';
      } else if (value == 'transfer') {
        _cashController.text = '0.00';
        _bankController.text = widget.invoice.paid.toStringAsFixed(AppConstants.decimalPlaces);
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
          'تم تحديث الفاتورة والمبالغ بنجاح',
          type: PosNotificationType.success,
        );
      }
    } catch (e) {
      if (mounted) {
        showPosToast(
          context,
          ref,
          'خطأ تحديث الفاتورة: $e',
          type: PosNotificationType.error,
        );
      }
    }
  }
}
