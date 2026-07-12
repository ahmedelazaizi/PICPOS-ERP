import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/permissions/permission_codes.dart';
import '../../../data/providers/providers.dart';
import '../../widgets/searchable_dropdown.dart';
import 'package:ural_erp/core/constants/app_constants.dart';
import 'package:ural_erp/core/utils/number_utils.dart';

/// Payment method selection and processing widget
///
/// Features:
/// - Cash, Card, Credit, Mixed payment support
/// - Split payment input (cash + bank)
/// - Customer selection for credit sales
/// - Delivery mode integration
class PaymentSheet extends ConsumerStatefulWidget {
  final double total;
  final double subtotal;
  final double discount;
  final double tax;
  final String initialMethod;
  final int? selectedCustomerId;
  final Function(PaymentResult) onConfirm;
  final VoidCallback? onCancel;

  const PaymentSheet({
    super.key,
    required this.total,
    required this.subtotal,
    required this.discount,
    required this.tax,
    this.initialMethod = 'cash',
    this.selectedCustomerId,
    required this.onConfirm,
    this.onCancel,
  });

  @override
  ConsumerState<PaymentSheet> createState() => _PaymentSheetState();
}

class _PaymentSheetState extends ConsumerState<PaymentSheet> {
  late String _paymentMethod;
  final _cashController = TextEditingController();
  final _bankController = TextEditingController();
  final _clickController = TextEditingController(); // #18: Click transfer box
  int? _customerId;
  String? _customerName;


  /// Round total to JOD precision (3dp) for display and calculations.
  /// BUG-H02: was hardcoded 2dp, dropping fils on split payments.
  double get roundedTotal => NumberUtils.roundCurrency(widget.total);

  /// #20: Check if user has permission for a payment method
  bool _hasPermission(String permCode) {
    final auth = ref.read(authProvider);
    if (auth.isAdmin || auth.isManager) return true; // Admins bypass
    final permsAsync = ref.read(currentUserPermissionsProvider);
    final permissions = permsAsync.asData?.value ?? [];
    return permissions.contains(permCode) || permissions.isEmpty;
  }

  @override
  void initState() {
    super.initState();
    _paymentMethod = widget.initialMethod;
    _customerId = widget.selectedCustomerId;
  }

  @override
  void dispose() {
    _cashController.dispose();
    _bankController.dispose();
    _clickController.dispose();
    super.dispose();
  }

  bool get _isValid {
    if (_paymentMethod == 'credit' && _customerId == null) return false;
    if (_paymentMethod == 'mixed') {
      final cash = double.tryParse(_cashController.text) ?? 0;
      final bank = double.tryParse(_bankController.text) ?? 0;
      final click = double.tryParse(_clickController.text) ?? 0;
      // Allow if total is covered (with small tolerance for rounding)
      if (cash + bank + click < roundedTotal - 0.01) return false;
    }
    return true;
  }

  /// Simply update state when any payment field changes — no auto-fill
  void _onFieldChanged(String _) {
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 10,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: AppColors.border,
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Totals Summary
          _buildTotalsSummary(),
          const SizedBox(height: 16),

          // Payment Methods
          _buildPaymentMethods(),
          const SizedBox(height: 16),

          // Split Payment Fields (if mixed)
          if (_paymentMethod == 'mixed') ...[
            _buildSplitPaymentFields(),
            const SizedBox(height: 16),
          ],

          // Customer Selection (if credit)
          if (_paymentMethod == 'credit') ...[
            _buildCustomerSelector(),
            const SizedBox(height: 16),
          ],

          // Confirm Button
          SizedBox(
            width: double.infinity,
            height: 56,
            child: FilledButton.icon(
              onPressed: (_isValid && !_isSubmitting) ? _confirm : null,
              icon: _isSubmitting 
                  ? const SizedBox(
                      width: 20, height: 20, 
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)
                    )
                  : const Icon(PhosphorIconsBold.checkCircle),
              label: Text(_getConfirmLabel()),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.success,
                textStyle: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTotalsSummary() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          _buildRow('إجمالي الأصناف', widget.subtotal),
          if (widget.discount > 0)
            _buildRow('الخصم', -widget.discount, color: AppColors.error),
          if (widget.tax > 0) _buildRow('الضريبة', widget.tax),
          const Divider(),
          _buildRow('الإجمالي', widget.total, isTotal: true),
        ],
      ),
    );
  }

  Widget _buildRow(
    String label,
    double value, {
    Color? color,
    bool isTotal = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontWeight: isTotal ? FontWeight.bold : FontWeight.normal,
            ),
          ),
          Text(
            '${value.toStringAsFixed(AppConstants.decimalPlaces)} ${AppConstants.currencySymbolEn}',
            style: TextStyle(
              fontWeight: isTotal ? FontWeight.bold : FontWeight.w500,
              fontSize: isTotal ? 18 : 14,
              color: color ?? (isTotal ? AppColors.primary : null),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPaymentMethods() {
    // #20: Permission-gated payment method chips
    final methods = <Widget>[];
    // When mixed is selected, only show the mixed chip (other methods are hidden)
    if (_paymentMethod != 'mixed') {
      if (_hasPermission(PermissionCodes.posPaymentCash)) {
        methods.add(_buildMethodChip('cash', 'نقدي', PhosphorIconsBold.money));
      }
      if (_hasPermission(PermissionCodes.posPaymentCard)) {
        methods.add(_buildMethodChip('card', 'بطاقة (بنك)', PhosphorIconsBold.creditCard));
      }
      if (_hasPermission(PermissionCodes.posPaymentTransfer)) {
        methods.add(_buildMethodChip('click', 'كليك', PhosphorIconsBold.cellSignalFull));
      }
      if (_hasPermission(PermissionCodes.posPaymentCredit)) {
        methods.add(_buildMethodChip('credit', 'آجل', PhosphorIconsBold.timer));
      }
    }
    if (_hasPermission(PermissionCodes.posPaymentMultiple)) {
      methods.add(_buildMethodChip('mixed', 'متعدد', PhosphorIconsBold.splitVertical));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'طريقة الدفع:',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: methods,
        ),
      ],
    );
  }

  Widget _buildMethodChip(String method, String label, IconData icon) {
    final isSelected = _paymentMethod == method;
    return FilterChip(
      selected: isSelected,
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 16,
            color: isSelected ? Colors.white : AppColors.textMuted,
          ),
          const SizedBox(width: 4),
          Text(label),
        ],
      ),
      onSelected: (selected) {
        setState(() {
          _paymentMethod = method;
          if (method == 'mixed') {
            // Initialize all fields to 0 when switching to mixed
            _cashController.text = '0';
            _bankController.text = '0';
            _clickController.text = '0';
          }
        });
      },
      selectedColor: AppColors.primary,
      labelStyle: TextStyle(color: isSelected ? Colors.white : null),
    );
  }

  Widget _buildSplitPaymentFields() {
    final cash = double.tryParse(_cashController.text) ?? 0;
    final bank = double.tryParse(_bankController.text) ?? 0;
    final click = double.tryParse(_clickController.text) ?? 0;
    final totalPaid = cash + bank + click;
    final remaining = roundedTotal - totalPaid;
    final difference = totalPaid - roundedTotal;
    final hasDifference = difference.abs() > 0.01;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Remaining amount display
        Container(
          width: double.infinity,
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: remaining.abs() < 0.01
                ? AppColors.success.withValues(alpha: 0.1)
                : AppColors.warning.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: remaining.abs() < 0.01 ? AppColors.success : AppColors.warning,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                remaining.abs() < 0.01 ? 'تم تغطية المبلغ بالكامل ✓' : 'المتبقي:',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: remaining.abs() < 0.01 ? AppColors.success : AppColors.warning,
                ),
              ),
              if (remaining.abs() >= 0.01)
                Text(
                  '${remaining.toStringAsFixed(AppConstants.decimalPlaces)} ${AppConstants.currencySymbolEn}',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                    color: remaining < 0 ? AppColors.error : AppColors.warning,
                  ),
                ),
            ],
          ),
        ),
        // hint text
        if (remaining.abs() >= 0.01)
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Text(
              'أدخل قيمة الدفع في الخانات التالية وزعها كما يقرر العميل',
              style: TextStyle(fontSize: 11, color: AppColors.textMuted),
            ),
          ),
        // Cash field
        _buildPaymentField('نقدي', _cashController, PhosphorIconsBold.money),
        const SizedBox(height: 10),
        // Bank field
        _buildPaymentField('بطاقة (بنك)', _bankController, PhosphorIconsBold.creditCard),
        const SizedBox(height: 10),
        // Click field
        _buildPaymentField('كليك', _clickController, PhosphorIconsBold.cellSignalFull),
        // Show difference warning if there's a discrepancy
        if (hasDifference &&
            (_cashController.text.isNotEmpty ||
                _bankController.text.isNotEmpty ||
                _clickController.text.isNotEmpty))
          Container(
            margin: const EdgeInsets.only(top: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: difference > 0
                  ? AppColors.success.withValues(alpha: 0.1)
                  : AppColors.error.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: difference > 0 ? AppColors.success : AppColors.error,
                width: 1.5,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  difference > 0
                      ? PhosphorIconsBold.arrowUp
                      : PhosphorIconsBold.arrowDown,
                  color: difference > 0 ? AppColors.success : AppColors.error,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    difference > 0
                        ? 'باقي (يتم الإرجاع): ${difference.toStringAsFixed(AppConstants.decimalPlaces)} ${AppConstants.currencySymbolEn}'
                        : 'نقص: ${difference.abs().toStringAsFixed(AppConstants.decimalPlaces)} ${AppConstants.currencySymbolEn}',
                    style: TextStyle(
                      color: difference > 0
                          ? AppColors.success
                          : AppColors.error,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildPaymentField(String label, TextEditingController controller, IconData icon) {
    return TextField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, size: 18),
        suffixText: AppConstants.currencySymbolEn,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      ),
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      textAlign: TextAlign.center,
      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
      onChanged: _onFieldChanged,
    );
  }

  Widget _buildCustomerSelector() {
    final customersAsync = ref.watch(allCustomersProvider);

    return customersAsync.when(
      loading: () => const LinearProgressIndicator(),
      error: (e, _) => Text('خطأ: $e'),
      data: (customers) => SearchableDropdown<Party>(
        items: customers,
        value: customers.where((c) => c.id == _customerId).firstOrNull,
        hint: 'اختر العميل',
        label: 'العميل *',
        searchHint: 'بحث عن عميل...',
        isRequired: true,
        labelBuilder: (c) => c.name,
        onChanged: (customer) {
          setState(() {
            _customerId = customer?.id;
            _customerName = customer?.name;
          });
        },
      ),
    );
  }

  String _getConfirmLabel() {
    switch (_paymentMethod) {
      case 'credit':
        return 'تسجيل آجل';
      case 'delivery':
        return 'تأكيد التوصيل';
      default:
        return 'تأكيد الدفع';
    }
  }

  bool _isSubmitting = false;

  void _confirm() {
    if (_isSubmitting) return;
    setState(() => _isSubmitting = true);
    
    double paidAmount = widget.total;
    double? cashAmount;
    double? bankAmount;
    double? clickAmount;

    if (_paymentMethod == 'credit') {
      paidAmount = 0;
    } else if (_paymentMethod == 'mixed') {
      cashAmount = double.tryParse(_cashController.text) ?? 0;
      bankAmount = double.tryParse(_bankController.text) ?? 0;
      clickAmount = double.tryParse(_clickController.text) ?? 0;
      paidAmount = cashAmount + bankAmount + clickAmount;
    } else if (_paymentMethod == 'click') {
      // #18: Full amount to click transfer box
      clickAmount = paidAmount;
    }

    widget.onConfirm(
      PaymentResult(
        method: _paymentMethod,
        total: paidAmount,
        cashAmount: cashAmount,
        bankAmount: bankAmount,
        clickAmount: clickAmount,
        customerId: _customerId,
        customerName: _customerName,
      ),
    );
  }
}

/// Result of payment method selection
class PaymentResult {
  final String method;
  final double total;
  final double? cashAmount;
  final double? bankAmount;
  final double? clickAmount; // #18: Click transfer amount
  final int? customerId;
  final String? customerName;

  const PaymentResult({
    required this.method,
    required this.total,
    this.cashAmount,
    this.bankAmount,
    this.clickAmount,
    this.customerId,
    this.customerName,
  });
}
