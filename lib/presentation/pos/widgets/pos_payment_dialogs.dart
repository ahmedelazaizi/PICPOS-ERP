// ignore_for_file: avoid_dynamic_calls
part of 'pos_dialogs.dart';

// ═══════════════════════════════════════════════════════════════════════════
// PRIVATE DIALOG WIDGETS
// ═══════════════════════════════════════════════════════════════════════════

class _PaymentDialog extends StatefulWidget {
  final double totalAmount;
  final String initialMethod;

  /// Methods the cashier may pick. `null` ⇒ all of them, which is the UralCash
  /// till's behaviour and the default, so that screen renders exactly as before.
  final Set<String>? allowedMethods;

  const _PaymentDialog({
    required this.totalAmount,
    this.initialMethod = 'cash',
    this.allowedMethods,
  });

  @override
  State<_PaymentDialog> createState() => _PaymentDialogState();
}

class _PaymentDialogState extends State<_PaymentDialog> {
  late TextEditingController _cashController;
  late TextEditingController _cardController;
  late TextEditingController _clickController;
  double _cashAmount = 0;
  double _cardAmount = 0;
  double _clickAmount = 0;
  late String _selectedMethod;
  int? _selectedCustomerId;
  String? _selectedCustomerName;

  /// Display order — also the fallback order when [_PaymentDialog.allowedMethods]
  /// excludes the requested initial method.
  static const _methodOrder = ['cash', 'card', 'click', 'credit', 'multiple'];

  bool _isAllowed(String method) =>
      widget.allowedMethods == null || widget.allowedMethods!.contains(method);

  bool get _hasAnyAllowedMethod =>
      widget.allowedMethods == null || _methodOrder.any(_isAllowed);

  @override
  void initState() {
    super.initState();
    _selectedMethod = widget.initialMethod;
    // A caller may ask for 'cash' while the cashier only has the card
    // permission. Land on the first method they DO have rather than opening
    // with a selected-but-unrenderable chip.
    if (!_isAllowed(_selectedMethod)) {
      _selectedMethod = _methodOrder.firstWhere(
        _isAllowed,
        orElse: () => widget.initialMethod,
      );
    }
    _cashAmount = widget.totalAmount;
    _cardAmount = 0;
    _clickAmount = 0;
    _cashController = TextEditingController(
      text: _cashAmount.toStringAsFixed(AppConstants.decimalPlaces),
    );
    _cardController = TextEditingController(text: '0.00');
    _clickController = TextEditingController(text: '0.00');
    // Auto-initialize multiple payment mode if pre-selected
    if (_selectedMethod == 'multiple') {
      _selectMethod('multiple');
    }
  }

  @override
  void dispose() {
    _cashController.dispose();
    _cardController.dispose();
    _clickController.dispose();
    super.dispose();
  }

  bool _isUpdating = false;
  bool _isSubmitting = false;

  /// Recalculate: when bank or click changes, auto-adjust cash to fill remainder
  void _recalculate({String? changedField}) {
    if (_isUpdating) return;
    _isUpdating = true;

    _cardAmount = double.tryParse(_cardController.text) ?? 0;
    _clickAmount = double.tryParse(_clickController.text) ?? 0;

    if (changedField == 'card' || changedField == 'click') {
      // Auto-adjust cash to fill remaining amount
      final otherTotal = _cardAmount + _clickAmount;
      _cashAmount = (widget.totalAmount - otherTotal).clamp(0.0, double.infinity);
      _cashController.text = _cashAmount.toStringAsFixed(AppConstants.decimalPlaces);
    } else {
      // Cash was edited manually — just read its value
      _cashAmount = double.tryParse(_cashController.text) ?? 0;
    }

    _isUpdating = false;
    setState(() {});
  }

  bool get _isValid {
    if (_selectedMethod == 'credit' && _selectedCustomerId == null) return false;
    if (_selectedMethod == 'multiple') {
      final total = _cashAmount + _cardAmount + _clickAmount;
      if (total < widget.totalAmount - 0.01) return false;
    }
    return true;
  }

  void _selectMethod(String method) {
    setState(() {
      _selectedMethod = method;
      if (method == 'multiple') {
        _cashAmount = widget.totalAmount;
        _cardAmount = 0;
        _clickAmount = 0;
        _cashController.text = _cashAmount.toStringAsFixed(AppConstants.decimalPlaces);
        _cardController.text = '0.00';
        _clickController.text = '0.00';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final paidTotal = _cashAmount + _cardAmount + _clickAmount;
    final changeDue = paidTotal - widget.totalAmount;
    final remaining = widget.totalAmount - paidTotal;
    final isPaidEnough = _selectedMethod == 'multiple' ? remaining <= 0.001 : true;
    final canConfirm =
        _isValid && isPaidEnough && !_isSubmitting && _hasAnyAllowedMethod;

    return AlertDialog(
      title: const Row(
        children: [
          Icon(PhosphorIconsBold.wallet, color: AppColors.primary),
          SizedBox(width: 8),
          Text('إتمام البيع'),
        ],
      ),
      content: SingleChildScrollView(
        child: SizedBox(
          width: 450,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Total Header
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'المطلوب',
                      style: TextStyle(color: Colors.white, fontSize: 16),
                    ),
                    Text(
                      '${widget.totalAmount.toStringAsFixed(AppConstants.decimalPlaces)} ${AppConstants.currencySymbolEn}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // Payment Method Selection — hide when opened directly for multi-payment
              if (widget.initialMethod != 'multiple') ...[
                const Text(
                  'طريقة الدفع:',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                const SizedBox(height: 10),
                // No permitted method at all: say so instead of showing an
                // empty Wrap above a live confirm button. `canConfirm` also
                // gates on `_hasAnyAllowedMethod`, so the button is dead too.
                if (!_hasAnyAllowedMethod)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.error.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.error),
                    ),
                    child: const Row(
                      children: [
                        Icon(PhosphorIconsBold.lockKey,
                            color: AppColors.error, size: 18),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'لا تملك صلاحية أي طريقة دفع — راجع المدير',
                            style: TextStyle(
                                color: AppColors.error,
                                fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (_selectedMethod != 'multiple') ...[
                        if (_isAllowed('cash'))
                          _buildMethodChip('cash', 'نقدي', PhosphorIconsBold.money, AppColors.success),
                        if (_isAllowed('card'))
                          _buildMethodChip('card', 'بطاقة (بنك)', PhosphorIconsBold.creditCard, AppColors.info),
                        if (_isAllowed('click'))
                          _buildMethodChip('click', 'كليك', PhosphorIconsBold.cursorClick, const Color(0xFF7E57C2)),
                        if (_isAllowed('credit'))
                          _buildMethodChip('credit', 'آجل', PhosphorIconsBold.timer, AppColors.warning),
                      ],
                      if (_isAllowed('multiple'))
                        _buildMethodChip('multiple', 'متعدد', PhosphorIconsBold.splitVertical, AppColors.primary),
                    ],
                  ),
                const SizedBox(height: 20),
              ],

              // Multiple payment fields
              if (_selectedMethod == 'multiple') ...[
                TextField(
                  controller: _cashController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: 'نقدي',
                    prefixIcon: const Icon(PhosphorIconsBold.money, color: AppColors.success),
                    suffixText: AppConstants.currencySymbolEn,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    filled: true,
                    fillColor: AppColors.success.withValues(alpha: 0.05),
                    helperText: 'يتم احتسابه تلقائياً عند تعديل الخانات الأخرى',
                    helperStyle: const TextStyle(fontSize: 10, color: AppColors.textMuted),
                  ),
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  onChanged: (_) => _recalculate(changedField: 'cash'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _cardController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: 'بطاقة (بنك)',
                    prefixIcon: const Icon(PhosphorIconsBold.creditCard, color: AppColors.info),
                    suffixText: AppConstants.currencySymbolEn,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    filled: true,
                    fillColor: AppColors.info.withValues(alpha: 0.05),
                  ),
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  autofocus: true,
                  onChanged: (_) => _recalculate(changedField: 'card'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _clickController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: 'كليك',
                    prefixIcon: const Icon(PhosphorIconsBold.cursorClick, color: Color(0xFF7E57C2)),
                    suffixText: AppConstants.currencySymbolEn,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    filled: true,
                    fillColor: const Color(0xFF7E57C2).withValues(alpha: 0.05),
                  ),
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  onChanged: (_) => _recalculate(changedField: 'click'),
                ),
                const SizedBox(height: 16),

                // Summary for multiple
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('إجمالي المدفوع:'),
                      Text(
                        '${paidTotal.toStringAsFixed(AppConstants.decimalPlaces)} ${AppConstants.currencySymbolEn}',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                    ],
                  ),
                ),

                if (changeDue > 0.01)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.success.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.success),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('الباقي للعميل (فكة):', style: TextStyle(fontWeight: FontWeight.bold)),
                        Text(
                          '${changeDue.toStringAsFixed(AppConstants.decimalPlaces)} ${AppConstants.currencySymbolEn}',
                          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.success),
                        ),
                      ],
                    ),
                  ),

                if (!isPaidEnough)
                  Container(
                    margin: const EdgeInsets.only(top: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.error.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.error),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('المتبقي للدفع:', style: TextStyle(color: AppColors.error)),
                        Text(
                          '${remaining.toStringAsFixed(AppConstants.decimalPlaces)} ${AppConstants.currencySymbolEn}',
                          style: const TextStyle(color: AppColors.error, fontWeight: FontWeight.bold, fontSize: 18),
                        ),
                      ],
                    ),
                  ),
              ],

              // Credit customer selector
              if (_selectedMethod == 'credit') ...[
                Consumer(
                  builder: (ctx, ref, _) {
                    final customersAsync = ref.watch(allCustomersProvider);
                    return customersAsync.when(
                      loading: () => const LinearProgressIndicator(),
                      error: (e, _) => Text('خطأ: $e'),
                      data: (customers) => SearchableDropdown<Party>(
                        items: customers,
                        value: customers.where((c) => c.id == _selectedCustomerId).firstOrNull,
                        hint: 'اختر العميل',
                        label: 'العميل *',
                        searchHint: 'بحث عن عميل...',
                        isRequired: true,
                        labelBuilder: (c) => c.name,
                        onChanged: (customer) {
                          setState(() {
                            _selectedCustomerId = customer?.id;
                            _selectedCustomerName = customer?.name;
                          });
                        },
                      ),
                    );
                  },
                ),
               const SizedBox(height: 8),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSubmitting ? null : () => Navigator.pop(context),
          child: const Text('إلغاء'),
        ),
        ElevatedButton(
          onPressed: canConfirm
              ? () {
                  setState(() => _isSubmitting = true);
                  double totalPaid = widget.totalAmount;
                  double? cashAmt;
                  double? bankAmt;

                  double? clickAmt;
                  if (_selectedMethod == 'multiple') {
                    cashAmt = double.tryParse(_cashController.text) ?? 0;
                    bankAmt = double.tryParse(_cardController.text) ?? 0;
                    clickAmt = double.tryParse(_clickController.text) ?? 0;
                    totalPaid = cashAmt + bankAmt + clickAmt;
                  } else if (_selectedMethod == 'credit') {
                    totalPaid = 0;
                  }

                  Navigator.pop(
                    context,
                    PaymentResult(
                      method: _selectedMethod == 'multiple' ? 'mixed' : _selectedMethod,
                      total: totalPaid,
                      cashAmount: cashAmt,
                      bankAmount: bankAmt,
                      clickAmount: clickAmt,
                      customerId: _selectedCustomerId,
                      customerName: _selectedCustomerName,
                    ),
                  );
                }
              : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.success,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          ),
          child: _isSubmitting
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : Text(
                  _selectedMethod == 'credit' ? 'تسجيل آجل' : 'إتمام الدفع',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
        ),
      ],
    );
  }

  Widget _buildMethodChip(String method, String label, IconData icon, Color color) {
    final isSelected = _selectedMethod == method;
    return FilterChip(
      selected: isSelected,
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: isSelected ? Colors.white : color),
          const SizedBox(width: 6),
          Text(label),
        ],
      ),
      onSelected: (_) => _selectMethod(method),
      selectedColor: color,
      backgroundColor: color.withValues(alpha: 0.08),
      labelStyle: TextStyle(
        color: isSelected ? Colors.white : color,
        fontWeight: FontWeight.bold,
      ),
      side: BorderSide(color: isSelected ? color : color.withValues(alpha: 0.3)),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    );
  }
}

// ignore: unused_element
class _SelectionCard extends StatelessWidget {
  final bool isSelected;
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _SelectionCard({
    required this.isSelected,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.primary.withValues(alpha: 0.1)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? AppColors.primary : AppColors.border,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Column(
          children: [
            Icon(
              icon,
              color: isSelected ? AppColors.primary : AppColors.textMuted,
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                color: isSelected ? AppColors.primary : AppColors.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}


class _WeightInputDialog extends StatefulWidget {
  final ProductEntity product;
  final double pricePerUnit;
  final TextEditingController weightController;

  const _WeightInputDialog({
    required this.product,
    required this.pricePerUnit,
    required this.weightController,
  });

  @override
  State<_WeightInputDialog> createState() => _WeightInputDialogState();
}

class _WeightInputDialogState extends State<_WeightInputDialog> {
  double _liveWeight = 0;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          const Icon(PhosphorIconsBold.scales, color: AppColors.warning),
          const SizedBox(width: 8),
          Expanded(
            child: Text(widget.product.name, overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'سعر الكيلو: ${widget.pricePerUnit.toStringAsFixed(AppConstants.decimalPlaces)} ${AppConstants.currencySymbolEn}',
          ),
          const SizedBox(height: 16),

          // Live Weight Display (when scale connected)
          if (ScaleService.instance.isConnected) ...[
            StreamBuilder<double>(
              stream: ScaleService.instance.weightStream,
              builder: (context, snapshot) {
                _liveWeight = snapshot.data ?? 0.0;
                return Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.success.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.success),
                  ),
                  child: Column(
                    children: [
                      const Text(
                        'الوزن من الميزان',
                        style: TextStyle(fontSize: 12),
                      ),
                      Text(
                        '${_liveWeight.toStringAsFixed(3)} كجم',
                        style: const TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                          color: AppColors.success,
                        ),
                      ),
                      Text(
                        '${(_liveWeight * widget.pricePerUnit).toStringAsFixed(AppConstants.decimalPlaces)} ${AppConstants.currencySymbolEn}',
                        style: const TextStyle(
                          fontSize: 16,
                          color: AppColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
            const SizedBox(height: 16),
            const Divider(),
            const Text('أو أدخل الوزن يدوياً:', style: TextStyle(fontSize: 12)),
            const SizedBox(height: 8),
          ],

          // Manual Weight Input
          TextField(
            controller: widget.weightController,
            decoration: const InputDecoration(
              labelText: 'الوزن (كجم)',
              suffixText: 'كجم',
              prefixIcon: Icon(PhosphorIconsBold.scales),
            ),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            autofocus: !ScaleService.instance.isConnected,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('إلغاء'),
        ),
        ElevatedButton(
          onPressed: () {
            double weight;
            if (widget.weightController.text.isNotEmpty) {
              weight = double.tryParse(widget.weightController.text) ?? 0;
            } else {
              weight = _liveWeight;
            }

            if (weight > 0) {
              Navigator.pop(context, weight);
            }
          },
          child: const Text('إضافة'),
        ),
      ],
    );
  }
}

class _DeliveryOptionsDialog extends StatefulWidget {
  final List<dynamic> companies;
  final List<dynamic> couriers;
  final int? initialCompanyId;
  final int? initialCompanyPartyId; // #Phase2
  final int? initialCourierId;
  final double initialFee;
  final String initialStatus;

  const _DeliveryOptionsDialog({
    required this.companies,
    required this.couriers,
    this.initialCompanyId,
    this.initialCompanyPartyId,
    this.initialCourierId,
    required this.initialFee,
    required this.initialStatus,
  });

  @override
  State<_DeliveryOptionsDialog> createState() => _DeliveryOptionsDialogState();
}

class _DeliveryOptionsDialogState extends State<_DeliveryOptionsDialog> {
  late int? _companyId;
  late int? _companyPartyId; // #Phase2
  late int? _courierId;
  late double _fee;
  late String _status;
  late final TextEditingController _feeController;

  @override
  void initState() {
    super.initState();
    _companyId = widget.initialCompanyId;
    _companyPartyId = widget.initialCompanyPartyId; // #Phase2
    _courierId = widget.initialCourierId;
    _fee = widget.initialFee;
    _status = widget.initialStatus;
    _feeController = TextEditingController(text: _fee.toString());
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        title: const Row(
          children: [
            Icon(PhosphorIconsBold.moped, color: AppColors.primary),
            SizedBox(width: 8),
            Text('بيانات التوصيل'),
          ],
        ),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SearchableDropdown(
                items: widget.companies,
                value: widget.companies
                    .where((c) => c.id == _companyPartyId)
                    .firstOrNull,
                hint: 'شركة التوصيل',
                label: 'شركة التوصيل',
                searchHint: 'ابحث عن شركة...',
                labelBuilder: (c) => c.name,
                onChanged: (c) => setState(() => _companyPartyId = c?.id),
              ),
              const SizedBox(height: 12),
              SearchableDropdown(
                items: widget.couriers,
                value: widget.couriers
                    .where((c) => c.id == _courierId)
                    .firstOrNull,
                hint: 'المندوب / السائق',
                label: 'المندوب / السائق',
                searchHint: 'ابحث عن مندوب...',
                labelBuilder: (c) => c.name,
                onChanged: (c) => setState(() => _courierId = c?.id),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _feeController,
                decoration: InputDecoration(
                  labelText: 'رسوم التوصيل',
                  suffixText: AppConstants.currencySymbolEn,
                  prefixIcon: const Icon(PhosphorIconsBold.money),
                ),
                keyboardType: TextInputType.number,
                onChanged: (v) => _fee = double.tryParse(v) ?? 0,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _status,
                decoration: const InputDecoration(labelText: 'حالة الطلب'),
                items: const [
                  DropdownMenuItem(
                    value: 'pending',
                    child: Text('قيد التجهيز'),
                  ),
                  DropdownMenuItem(
                    value: 'out_for_delivery',
                    child: Text('خرج للتوصيل'),
                  ),
                  DropdownMenuItem(
                    value: 'delivered',
                    child: Text('تم التوصيل'),
                  ),
                ],
                onChanged: (v) => setState(() => _status = v ?? 'pending'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(
              context,
              DeliveryData(
                companyId: _companyId,
                companyPartyId: _companyPartyId, // #Phase2
                courierId: _courierId,
                fee: _fee,
                status: _status,
              ),
            ),
            child: const Text('تأكيد'),
          ),
        ],
      ),
    );
  }
}