import 'package:picpos_erp/core/i18n/tr.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:intl/intl.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../data/providers/providers.dart';
import '../sales_invoices_notifier.dart';
import 'sales_items_table.dart';

class SalesInvoiceForm extends ConsumerWidget {
  final Function() onSaveComplete;

  const SalesInvoiceForm({super.key, required this.onSaveComplete});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(salesInvoicesFormProvider);
    final notifier = ref.read(salesInvoicesFormProvider.notifier);
    final currencyFormat = NumberFormat.currency(symbol: '', decimalDigits: AppConstants.decimalPlaces);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header & Mode Info
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                state.isReturnMode
                    ? tr('إنشاء مرتجع مبيعات')
                    : tr('فاتورة ضريبة مبيعات'),
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: AppColors.primary,
                ),
              ),
              if (state.isReturnMode)
                 Chip(
                  label: Text(tr('وضع المرتجع (Return Mode)')),
                  backgroundColor: AppColors.error,
                  labelStyle: const TextStyle(color: Colors.white),
                ),
            ],
          ),
          const SizedBox(height: 24),

          // Main Grid: Left (Form Inputs) | Right (Summary)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Left Section: Items and Customer
              Expanded(
                flex: 3,
                child: Column(
                  children: [
                    // Customer & Warehouse Selector
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Row(
                          children: [
                             Text(
                              tr('العميل:'),
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: ref
                                  .watch(allCustomersProvider)
                                  .when(
                                    data: (customers) {
                                      final selected = state.selectedCustomerId != null
                                          ? customers.where((c) => c.id == state.selectedCustomerId).firstOrNull
                                          : null;
                                      return Autocomplete<Party>(
                                        initialValue: TextEditingValue(
                                          text: selected?.name ?? tr('عميل نقدي'),
                                        ),
                                        optionsBuilder: (textValue) {
                                          final q = textValue.text.toLowerCase().trim();
                                          if (q.isEmpty || q == 'عميل نقدي') return customers;
                                          return customers.where((c) =>
                                              c.name.toLowerCase().contains(q) ||
                                              (c.phone?.contains(textValue.text) ?? false));
                                        },
                                        displayStringForOption: (c) => c.name,
                                        fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
                                          return TextField(
                                            controller: controller,
                                            focusNode: focusNode,
                                            decoration: InputDecoration(
                                              hintText: tr('ابحث عن العميل...'),
                                              border: const OutlineInputBorder(),
                                              isDense: true,
                                              suffixIcon: state.selectedCustomerId != null
                                                  ? IconButton(
                                                      icon: const Icon(Icons.close, size: 16),
                                                      onPressed: () {
                                                        controller.text = tr('عميل نقدي');
                                                        notifier.selectCustomer(null);
                                                      },
                                                    )
                                                  : null,
                                            ),
                                          );
                                        },
                                        onSelected: (customer) {
                                          notifier.selectCustomer(customer.id);
                                        },
                                      );
                                    },
                                    loading: () =>
                                        const LinearProgressIndicator(),
                                    error: (e, _) => Text('Error: $e'),
                                  ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // The specialized Items Table
                    const SalesItemsTable(),
                  ],
                ),
              ),

              const SizedBox(width: 24),

              // Right Section: Financial Summary & Actions
              Expanded(
                flex: 1,
                child: Column(
                  children: [
                    // Financial Summary Card
                    Card(
                      elevation: 4,
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                             Text(
                              tr('ملخص الفاتورة'),
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            const Divider(height: 24),
                            _summaryRow(
                              tr('الإجمالي الفرعي'),
                              currencyFormat.format(state.subtotal),
                            ),
                            const SizedBox(height: 12),
                            _inputRow(
                              tr('الخصم'),
                              state.discount,
                              (val) => notifier.updateDiscount(val),
                            ),
                            const SizedBox(height: 12),
                            // Per-line tax: invoice-level tax is the sum of
                            // each cart row's own taxAmount. Toggling happens
                            // per row in the items table, so here we only
                            // display the rolled-up total.
                            _summaryRow(
                              tr('إجمالي الضريبة'),
                              currencyFormat.format(state.calculatedTax),
                            ),
                            const Divider(height: 24),
                            _summaryRow(
                              tr('الصافي الكلي'),
                              currencyFormat.format(state.grandTotal),
                              isBold: true,
                              color: AppColors.primary,
                            ),
                            const SizedBox(height: 24),

                            // Payment Method
                             Text(
                              tr('طريقة الدفع:'),
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(height: 8),
                            DropdownButtonFormField<String>(
                              initialValue: state.paymentMethod,
                              decoration: const InputDecoration(
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                              items:  [
                                DropdownMenuItem(
                                  value: tr('نقدي'),
                                  child: Text(tr('نقدي')),
                                ),
                                DropdownMenuItem(
                                  value: tr('تحويل'),
                                  child: Text(tr('تحويل')),
                                ),
                                DropdownMenuItem(
                                  value: tr('آجل'),
                                  child: Text(tr('آجل')),
                                ),
                              ],
                              onChanged: (val) {
                                notifier.updatePaymentMethod(val ?? tr('نقدي'));
                                // Auto-zero paid when switching to credit
                                if (val == 'آجل') {
                                  notifier.updatePaidAmount(0);
                                }
                              },
                            ),
                            const SizedBox(height: 16),

                            // Paid Amount
                             Text(
                              tr('المبلغ المدفوع:'),
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(height: 8),
                            TextFormField(
                              key: ValueKey('paid_${state.paymentMethod}_${state.grandTotal}'),
                              initialValue: state.paymentMethod != 'آجل' && state.paidAmount <= 0
                                  ? state.grandTotal.toStringAsFixed(AppConstants.decimalPlaces)
                                  : '${state.paidAmount}',
                              keyboardType: TextInputType.number,
                              enabled: state.paymentMethod != 'آجل',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: state.paymentMethod == 'آجل'
                                    ? Colors.grey
                                    : Colors.green,
                              ),
                              decoration: InputDecoration(
                                border: const OutlineInputBorder(),
                                isDense: true,
                                prefixIcon: const Icon(
                                  PhosphorIconsBold.money,
                                  color: Colors.green,
                                ),
                                hintText: state.paymentMethod == 'آجل' ? tr('آجل — لا يوجد دفع') : null,
                              ),
                              onChanged: (val) => notifier.updatePaidAmount(
                                double.tryParse(val) ?? 0,
                              ),
                            ),
                            const SizedBox(height: 24),

                            // Notes
                             Text(
                              tr('ملاحظات:'),
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(height: 8),
                            TextFormField(
                              maxLines: 2,
                              decoration: const InputDecoration(
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                              onChanged: (val) => notifier.updateNotes(val),
                            ),
                            const SizedBox(height: 16),

                            // Cost Center Selector
                             Text(
                              tr('مركز التكلفة:'),
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(height: 8),
                            FutureBuilder<List<CostCenter>>(
                              future: ref.read(accountingRepositoryProvider).getActiveCostCenters(),
                              builder: (context, snapshot) {
                                final centers = snapshot.data ?? [];
                                if (centers.isEmpty) return const SizedBox.shrink();
                                return DropdownButtonFormField<int?>(
                                  initialValue: state.costCenterId,
                                  decoration: const InputDecoration(
                                    border: OutlineInputBorder(),
                                    isDense: true,
                                    prefixIcon: Icon(PhosphorIconsLight.target, size: 20),
                                  ),
                                  items: [
                                     DropdownMenuItem<int?>(value: null, child: Text(tr('بدون مركز تكلفة'))),
                                    ...centers.map((cc) => DropdownMenuItem<int?>(
                                      value: cc.id,
                                      child: Text(trData(cc.name)),
                                    )),
                                  ],
                                  onChanged: (v) => notifier.setCostCenter(v),
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 16),

                    // Actions
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton.icon(
                        onPressed: state.isLoading
                            ? null
                            : () async {
                                final result = await notifier.saveInvoice();
                                if (result != null) {
                                  onSaveComplete();
                                }
                              },
                        icon: state.isLoading
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(PhosphorIconsBold.floppyDisk),
                        label:  Text(tr('حفظ الفاتورة')),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.success,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _summaryRow(
    String label,
    String value, {
    bool isBold = false,
    Color? color,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _inputRow(
    String label,
    double initialValue,
    Function(double) onChanged,
  ) {
    return Row(
      children: [
        Expanded(child: Text(label)),
        SizedBox(
          width: 80,
          child: TextFormField(
            initialValue: '$initialValue',
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            decoration: const InputDecoration(
              isDense: true,
              contentPadding: EdgeInsets.all(8),
              border: OutlineInputBorder(),
            ),
            onChanged: (val) => onChanged(double.tryParse(val) ?? 0),
          ),
        ),
      ],
    );
  }
}
