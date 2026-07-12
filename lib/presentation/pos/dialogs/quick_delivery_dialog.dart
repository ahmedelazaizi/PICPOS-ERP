import 'package:flutter/material.dart';
import 'package:ural_erp/core/widgets/app_toast.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../core/theme/app_colors.dart';

import '../../../data/providers/providers.dart';
import 'package:ural_erp/core/constants/app_constants.dart';

/// Dialog for quick delivery order entry
///
/// Features:
/// - Phone number search to find existing customer
/// - Customer name, address entry
/// - Delivery fee configuration
/// - Courier selection
class QuickDeliveryDialog extends ConsumerStatefulWidget {
  final String? initialPhone;
  final String? initialName;
  final String? initialAddress;
  final double initialFee;
  final int? initialCourierId;
  final bool isDeliveryModeActive;
  final void Function({
    required String customerName,
    required String customerPhone,
    required String customerAddress,
    required double deliveryFee,
    required int? courierId,
    required int? customerId,
  })
  onConfirm;
  final VoidCallback? onCancelDelivery;

  const QuickDeliveryDialog({
    super.key,
    this.initialPhone,
    this.initialName,
    this.initialAddress,
    this.initialFee = 0,
    this.initialCourierId,
    this.isDeliveryModeActive = false,
    required this.onConfirm,
    this.onCancelDelivery,
  });

  /// Show the quick delivery dialog
  static Future<void> show({
    required BuildContext context,
    required WidgetRef ref,
    String? initialPhone,
    String? initialName,
    String? initialAddress,
    double initialFee = 0,
    int? initialCourierId,
    bool isDeliveryModeActive = false,
    required void Function({
      required String customerName,
      required String customerPhone,
      required String customerAddress,
      required double deliveryFee,
      required int? courierId,
      required int? customerId,
    })
    onConfirm,
    VoidCallback? onCancelDelivery,
  }) {
    return showDialog(
      context: context,
      builder: (ctx) => QuickDeliveryDialog(
        initialPhone: initialPhone,
        initialName: initialName,
        initialAddress: initialAddress,
        initialFee: initialFee,
        initialCourierId: initialCourierId,
        isDeliveryModeActive: isDeliveryModeActive,
        onConfirm:
            ({
              required String customerName,
              required String customerPhone,
              required String customerAddress,
              required double deliveryFee,
              required int? courierId,
              required int? customerId,
            }) {
              Navigator.pop(ctx);
              onConfirm(
                customerName: customerName,
                customerPhone: customerPhone,
                customerAddress: customerAddress,
                deliveryFee: deliveryFee,
                courierId: courierId,
                customerId: customerId,
              );
            },
        onCancelDelivery: onCancelDelivery != null
            ? () {
                Navigator.pop(ctx);
                onCancelDelivery();
              }
            : null,
      ),
    );
  }

  @override
  ConsumerState<QuickDeliveryDialog> createState() =>
      _QuickDeliveryDialogState();
}

class _QuickDeliveryDialogState extends ConsumerState<QuickDeliveryDialog> {
  late final TextEditingController _phoneController;
  late final TextEditingController _nameController;
  late final TextEditingController _addressController;
  late final TextEditingController _feeController;

  int? _selectedCourierId;
  int? _foundCustomerId;
  bool _isSearching = false;
  List<Courier> _couriers = [];

  @override
  void initState() {
    super.initState();
    _phoneController = TextEditingController(text: widget.initialPhone ?? '');
    _nameController = TextEditingController(text: widget.initialName ?? '');
    _addressController = TextEditingController(
      text: widget.initialAddress ?? '',
    );
    _feeController = TextEditingController(
      text: widget.initialFee.toStringAsFixed(AppConstants.decimalPlaces),
    );
    _selectedCourierId = widget.initialCourierId;
    _loadData();
  }

  Future<void> _loadData() async {
    final partiesRepo = ref.read(partiesRepositoryProvider);
    final settingsRepo = ref.read(settingsRepositoryProvider);
    final deliveryRepo = ref.read(deliveryRepositoryProvider);

    // Load couriers
    _couriers = await deliveryRepo.getCouriers();

    // Load default delivery fee if not set
    if (widget.initialFee == 0) {
      final defaultFee = await settingsRepo.getSetting('default_delivery_fee');
      if (defaultFee != null) {
        _feeController.text = defaultFee;
      }
    }

    if (mounted) setState(() {});
  }

  Future<void> _searchCustomer() async {
    if (_phoneController.text.isEmpty) return;

    setState(() => _isSearching = true);

    final partiesRepo = ref.read(partiesRepositoryProvider);
    final phone = _phoneController.text;
    final customers = await partiesRepo.searchCustomerByPhone(phone);

    if (customers.isNotEmpty) {
      final customer = customers.first;
      setState(() {
        _nameController.text = customer.name;
        _addressController.text = customer.address ?? '';
        _foundCustomerId = customer.id;
        _isSearching = false;
      });
    } else {
      setState(() => _isSearching = false);
      if (mounted) {
        AppToast.show(context, 'لم يتم العثور على عميل - أدخل البيانات يدوياً');
      }
    }
  }

  @override
  void dispose() {
    _phoneController.dispose();
    _nameController.dispose();
    _addressController.dispose();
    _feeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        title: const Row(
          children: [
            Icon(PhosphorIconsBold.truck, color: AppColors.warning),
            SizedBox(width: 8),
            Text('توصيل سريع 🚚'),
          ],
        ),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildPhoneField(),
              const SizedBox(height: 12),
              _buildNameField(),
              const SizedBox(height: 12),
              _buildAddressField(),
              const SizedBox(height: 12),
              _buildFeeField(),
              const SizedBox(height: 12),
              _buildCourierDropdown(),
            ],
          ),
        ),
        actions: _buildActions(),
      ),
    );
  }

  Widget _buildPhoneField() {
    return TextField(
      controller: _phoneController,
      keyboardType: TextInputType.phone,
      decoration: InputDecoration(
        labelText: '📱 رقم الهاتف',
        suffixIcon: _isSearching
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : IconButton(
                icon: const Icon(PhosphorIconsBold.magnifyingGlass),
                onPressed: _searchCustomer,
              ),
        border: const OutlineInputBorder(),
      ),
    );
  }

  Widget _buildNameField() {
    return TextField(
      controller: _nameController,
      decoration: const InputDecoration(
        labelText: '👤 اسم العميل',
        border: OutlineInputBorder(),
      ),
    );
  }

  Widget _buildAddressField() {
    return TextField(
      controller: _addressController,
      maxLines: 2,
      decoration: const InputDecoration(
        labelText: '📍 العنوان',
        border: OutlineInputBorder(),
      ),
    );
  }

  Widget _buildFeeField() {
    return TextField(
      controller: _feeController,
      keyboardType: TextInputType.number,
      decoration: InputDecoration(
        labelText: '💰 رسوم التوصيل',
        suffixText: AppConstants.currencySymbolEn,
        border: const OutlineInputBorder(),
      ),
    );
  }

  Widget _buildCourierDropdown() {
    return DropdownButtonFormField<int?>(
      initialValue: _selectedCourierId,
      decoration: const InputDecoration(
        labelText: '🚗 المندوب (اختياري)',
        border: OutlineInputBorder(),
      ),
      items: [
        const DropdownMenuItem(value: null, child: Text('بدون مندوب')),
        ..._couriers.map(
          (c) => DropdownMenuItem(value: c.id, child: Text(c.name)),
        ),
      ],
      onChanged: (value) => setState(() => _selectedCourierId = value),
    );
  }

  List<Widget> _buildActions() {
    return [
      // Cancel Delivery button (if already in delivery mode)
      if (widget.isDeliveryModeActive && widget.onCancelDelivery != null)
        TextButton.icon(
          onPressed: widget.onCancelDelivery,
          icon: const Icon(PhosphorIconsBold.x, color: AppColors.error),
          label: const Text(
            'إلغاء التوصيل',
            style: TextStyle(color: AppColors.error),
          ),
        ),
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('إغلاق'),
      ),
      ElevatedButton.icon(
        onPressed: _onConfirm,
        icon: const Icon(PhosphorIconsBold.check),
        label: const Text('تأكيد ✓'),
        style: ElevatedButton.styleFrom(backgroundColor: AppColors.success),
      ),
    ];
  }

  void _onConfirm() {
    // Validate required fields
    if (_nameController.text.isEmpty || _addressController.text.isEmpty) {
      AppToast.show(
        context,
        'يرجى إدخال اسم العميل والعنوان',
        type: ToastType.error,
      );
      return;
    }

    widget.onConfirm(
      customerName: _nameController.text,
      customerPhone: _phoneController.text,
      customerAddress: _addressController.text,
      deliveryFee: double.tryParse(_feeController.text) ?? 0,
      courierId: _selectedCourierId,
      customerId: _foundCustomerId,
    );
  }
}
