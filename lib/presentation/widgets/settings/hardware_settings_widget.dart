import 'package:flutter/material.dart';
import 'package:ural_erp/core/widgets/app_toast.dart';
import 'dart:ui' as ui;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../core/theme/app_colors.dart';

import '../../../core/config/app_config.dart';
import '../../../data/providers/providers.dart';
import '../../../services/scale_service.dart';
import '../../../services/cash_drawer_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
// ── Part files (mixin-based extraction) ─────────────────────────────────
part 'hardware/hardware_scale.dart';

/// Widget for managing hardware devices (Scanner, Printer, Scale)
class HardwareSettingsWidget extends ConsumerStatefulWidget {
  const HardwareSettingsWidget({super.key});

  @override
  ConsumerState<HardwareSettingsWidget> createState() =>
      _HardwareSettingsWidgetState();
}

class _HardwareSettingsWidgetState extends ConsumerState<HardwareSettingsWidget>
    with _HardwareScaleMixin {
  bool _autoPrint = false;
  bool _scannerSound = true;
  bool _showTaxButtonInPOS = true;
  bool _showDiscountButtonInPOS = true;
  bool _showDrawerButtonInPOS = true;
  bool _showExpenseButtonInPOS = true;
  bool _showWorkOrderButton = false;
  bool _showDeliveryButton = false;
  bool _showReturnButtonInPOS = true;
  bool _showHoldButtonInPOS = true;
  bool _showExchangeButtonInPOS = true;
  bool _showBarcodeInPOS = true;
  bool _showSearchInPOS = true;
  bool _showSaveOnlyInPOS = true;
  bool _showSubtotalInPOS = true;
  bool _showAddCustomerInPOS = true;
  bool _showProductSortInPOS = true;
  bool _showProductImagesInPOS = true;
  bool _posCartRatioLocked = false;
  double _posCartRatioValue = 0.6;
  double _productNameFontSize = 12.0;
  double _productPriceFontSize = 14.0;
  String _receiptCodeType = 'barcode';
  String _receiptFooter = '';

  // Cash drawer
  String? _cashDrawerPrinter;

  // Scale — mixin fields
  @override String? selectedScalePort;
  @override int selectedBaudRate = 9600;
  @override late bool scaleConnected;
  @override late List<String> availablePorts;
  @override final List<int> baudRates = [2400, 4800, 9600, 19200, 38400, 57600, 115200];
  @override String scaleModel = 'auto';
  @override String scaleReadType = 'auto';
  @override int scaleDataBits = 8;
  @override String scaleHandshake = 'none';
  @override String scaleParity = 'none';
  @override String scaleStopBits = 'one';
  @override int scaleWaitTime = 30;
  @override double scaleMinWeight = 0.0;
  @override double scaleWeightAlert = 0.0;
  @override ScaleConnectionType scaleConnectionType = ScaleConnectionType.serial;
  @override String scaleTcpHost = '';
  @override int scaleTcpPort = 4001;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    scaleConnected = ScaleService.instance.isConnected;
    availablePorts = ScaleService.getAvailablePorts();
    _loadSettings();
    _tryScaleAutoConnect();
  }

  Future<void> _tryScaleAutoConnect() async {
    if (!scaleConnected) {
      final connected = await ScaleService.instance.autoConnect();
      if (mounted && connected) setState(() => scaleConnected = true);
    }
  }

  Future<void> _loadSettings() async {
    final settingsRepo = ref.read(settingsRepositoryProvider);
    final autoPrint = await settingsRepo.getSetting('auto_print_receipt');
    final scannerSound = await settingsRepo.getSetting('scanner_sound');
    final receiptFooter = await settingsRepo.getSetting('receipt_footer');
    final showTax = await settingsRepo.getSetting('show_tax_button_pos');
    final showDiscount = await settingsRepo.getSetting('show_discount_button_pos');
    final showDrawer = await settingsRepo.getSetting('show_drawer_button_pos');
    final showExpense = await settingsRepo.getSetting('show_expense_button_pos');
    final codeType = await settingsRepo.getSetting('receipt_code_type');
    final workOrder = await settingsRepo.getSetting('show_work_order_button');
    final delivery = await settingsRepo.getSetting('show_delivery_button');
    final cashDrawer = await settingsRepo.getSetting('cash_drawer_printer');
    final showReturn = await settingsRepo.getSetting('show_return_button_pos');
    final showHold = await settingsRepo.getSetting('show_hold_button_pos');
    final showExchange = await settingsRepo.getSetting('show_exchange_button_pos');
    final showBarcode = await settingsRepo.getSetting('pos_show_barcode');
    final showSearch = await settingsRepo.getSetting('pos_show_search');
    final showSaveOnly = await settingsRepo.getSetting('pos_show_save_only');
    final showSubtotal = await settingsRepo.getSetting('pos_show_subtotal');
    final showAddCustomer = await settingsRepo.getSetting('pos_show_add_customer');
    final showProductSort = await settingsRepo.getSetting('pos_show_product_sort');
    final cartRatioLocked = await settingsRepo.getSetting('pos_cart_ratio_locked');
    final cartRatioValue = await settingsRepo.getSetting('pos_cart_ratio_value');
    final showProductImages = await settingsRepo.getSetting('pos_show_product_images');
    final productNameFont = await settingsRepo.getSetting('pos_product_name_font_size');
    final productPriceFont = await settingsRepo.getSetting('pos_product_price_font_size');

    final scaleSettings = await ScaleService.instance.getSavedSettings();
    final savedPort = scaleSettings['port'] as String?;
    final savedBaudRate = scaleSettings['baudRate'] as int? ?? 9600;
    final savedConnType = scaleSettings['connectionType'] as String? ?? 'serial';
    final savedTcpHost = scaleSettings['tcpHost'] as String? ?? '';
    final savedTcpPort = scaleSettings['tcpPort'] as int? ?? 4001;

    final prefs = await SharedPreferences.getInstance();
    final scModel = prefs.getString('scale_model') ?? 'auto';
    final scReadType = prefs.getString('scale_read_type') ?? 'auto';
    final scDataBits = prefs.getInt('scale_data_bits') ?? 8;
    final scHandshake = prefs.getString('scale_handshake') ?? 'none';
    final scParity = prefs.getString('scale_parity') ?? 'none';
    final scStopBits = prefs.getString('scale_stop_bits') ?? 'one';
    final scWaitTime = prefs.getInt('scale_wait_time') ?? 30;
    final scMinWeight = prefs.getDouble('scale_min_weight') ?? 0.0;
    final scWeightAlert = prefs.getDouble('scale_weight_alert') ?? 0.0;

    if (mounted) {
      setState(() {
        _autoPrint = autoPrint == 'true';
        _scannerSound = scannerSound != 'false';
        _receiptFooter = receiptFooter ?? '';
        _showTaxButtonInPOS = showTax != 'false';
        _showDiscountButtonInPOS = showDiscount != 'false';
        _showDrawerButtonInPOS = showDrawer != 'false';
        _showExpenseButtonInPOS = showExpense != 'false';
        _receiptCodeType = codeType ?? 'barcode';
        _showWorkOrderButton = workOrder == 'true';
        _showDeliveryButton =
            delivery != null ? delivery == 'true' : AppConfig.features.deliveryEnabled;
        _cashDrawerPrinter = cashDrawer;
        _showReturnButtonInPOS = showReturn != 'false';
        _showHoldButtonInPOS = showHold != 'false';
        _showExchangeButtonInPOS = showExchange != 'false';
        _showBarcodeInPOS = showBarcode != 'false';
        _showSearchInPOS = showSearch != 'false';
        _showSaveOnlyInPOS = showSaveOnly != 'false';
        _showSubtotalInPOS = showSubtotal != 'false';
        _showAddCustomerInPOS = showAddCustomer != 'false';
        _showProductSortInPOS = showProductSort != 'false';
        _showProductImagesInPOS = showProductImages != 'false';
        _posCartRatioLocked = cartRatioLocked == 'true';
        if (cartRatioValue != null) {
          final parsed = double.tryParse(cartRatioValue);
          if (parsed != null && parsed >= 0.3 && parsed <= 0.7) _posCartRatioValue = parsed;
        }
        if (productNameFont != null) {
          final parsed = double.tryParse(productNameFont);
          if (parsed != null && parsed >= 10 && parsed <= 24) _productNameFontSize = parsed;
        }
        if (productPriceFont != null) {
          final parsed = double.tryParse(productPriceFont);
          if (parsed != null && parsed >= 10 && parsed <= 24) _productPriceFontSize = parsed;
        }
        if (savedPort != null && availablePorts.contains(savedPort)) selectedScalePort = savedPort;
        selectedBaudRate = savedBaudRate;
        scaleConnectionType = savedConnType == 'tcp' ? ScaleConnectionType.tcp : ScaleConnectionType.serial;
        scaleTcpHost = savedTcpHost;
        scaleTcpPort = savedTcpPort;
        scaleModel = scModel;
        scaleReadType = scReadType;
        scaleDataBits = scDataBits;
        scaleHandshake = scHandshake;
        scaleParity = scParity;
        scaleStopBits = scStopBits;
        scaleWaitTime = scWaitTime;
        scaleMinWeight = scMinWeight;
        scaleWeightAlert = scWeightAlert;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Center(child: CircularProgressIndicator());

    return Directionality(
      textDirection: ui.TextDirection.rtl,
      child: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              child: Column(children: [
                _buildScannerSection(), const SizedBox(height: 16),
                _buildPrinterSection(), const SizedBox(height: 16),
                _buildCashDrawerSection(), const SizedBox(height: 16),
                buildScaleSection(), const SizedBox(height: 16),
              ]),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity, height: 48,
            child: ElevatedButton(onPressed: _saveSettings, child: const Text('حفظ الإعدادات')),
          ),
        ],
      ),
    );
  }

  // ── Scanner Section ────────────────────────────────────────────────

  Widget _buildScannerSection() {
    return buildSectionCard(
      title: 'ماسح الباركود', icon: PhosphorIconsBold.barcode, iconColor: AppColors.primary,
      children: [
        SwitchListTile(title: const Text('صوت عند المسح'), subtitle: const Text('تشغيل صوت عند مسح باركود بنجاح'), value: _scannerSound, onChanged: (v) => setState(() => _scannerSound = v), contentPadding: EdgeInsets.zero),
        const Divider(),
        const Text('ملاحظة: ماسح الباركود USB يعمل تلقائياً', style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
      ],
    );
  }

  // ── Printer Section ────────────────────────────────────────────────

  Widget _buildPrinterSection() {
    return buildSectionCard(
      title: 'الطابعة الحرارية', icon: PhosphorIconsBold.printer, iconColor: AppColors.warning,
      children: [
        SwitchListTile(title: const Text('طباعة تلقائية'), subtitle: const Text('طباعة الفاتورة تلقائياً بعد كل عملية بيع'), value: _autoPrint, onChanged: (v) => setState(() => _autoPrint = v), contentPadding: EdgeInsets.zero),
        const Divider(),
        TextField(
          decoration: const InputDecoration(labelText: 'نص ذيل الفاتورة', hintText: 'شكراً لزيارتكم'),
          controller: TextEditingController(text: _receiptFooter)..selection = TextSelection.fromPosition(TextPosition(offset: _receiptFooter.length)),
          onChanged: (v) => _receiptFooter = v, maxLines: 2,
        ),
        const Divider(),
        DropdownButtonFormField<String>(
          initialValue: _receiptCodeType,
          decoration: const InputDecoration(labelText: 'نوع الكود على الإيصال', prefixIcon: Icon(PhosphorIconsBold.qrCode)),
          items: const [
            DropdownMenuItem(value: 'barcode', child: Text('باركود')),
            DropdownMenuItem(value: 'qr_code', child: Text('QR كود')),
            DropdownMenuItem(value: 'none', child: Text('بدون')),
          ],
          onChanged: (v) => setState(() => _receiptCodeType = v ?? 'barcode'),
        ),
      ],
    );
  }

  // ── Cash Drawer Section ────────────────────────────────────────────

  Widget _buildCashDrawerSection() {
    return buildSectionCard(
      title: 'درج النقد', icon: PhosphorIconsBold.wallet, iconColor: AppColors.warning,
      children: [
        const Text('درج النقد يتصل بالطابعة الحرارية عبر كابل RJ12. حدد الطابعة لإرسال أمر الفتح.', style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
        const SizedBox(height: 12),
        TextField(
          decoration: const InputDecoration(labelText: 'اسم الطابعة (للدرج)', hintText: 'مثال: POS58 أو XP-58', prefixIcon: Icon(PhosphorIconsBold.printer)),
          controller: TextEditingController(text: _cashDrawerPrinter ?? '')..selection = TextSelection.collapsed(offset: _cashDrawerPrinter?.length ?? 0),
          onChanged: (v) => _cashDrawerPrinter = v.isEmpty ? null : v,
        ),
        const SizedBox(height: 12),
        SizedBox(width: double.infinity, child: ElevatedButton.icon(
          onPressed: _testCashDrawer, icon: const Icon(PhosphorIconsBold.wallet, size: 16), label: const Text('اختبار فتح الدرج'),
          style: ElevatedButton.styleFrom(backgroundColor: AppColors.warning),
        )),
      ],
    );
  }

  Future<void> _testCashDrawer() async {
    if (mounted) {
      final cashDrawer = CashDrawerService();
      final success = await cashDrawer.openDrawer(printerName: _cashDrawerPrinter);
      if (mounted) AppToast.show(context, success ? 'تم فتح الدرج بنجاح' : 'فشل فتح الدرج - تأكد من اسم الطابعة', type: ToastType.error);
    }
  }


  // ── Helper: Section Card ──────────────────────────────────────────

  @override
  Widget buildSectionCard({required String title, required IconData icon, required Color iconColor, required List<Widget> children}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [Icon(icon, color: iconColor, size: 20), const SizedBox(width: 8), Text(title, style: const TextStyle(fontWeight: FontWeight.bold))]),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }

  @override
  Widget buildStatusBadge(String text, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, color: color, size: 14), const SizedBox(width: 4),
        Text(text, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.bold)),
      ]),
    );
  }

  // ── Save Settings ─────────────────────────────────────────────────

  Future<void> _saveSettings() async {
    final settingsRepo = ref.read(settingsRepositoryProvider);
    await settingsRepo.saveSetting('auto_print_receipt', _autoPrint.toString());
    await settingsRepo.saveSetting('scanner_sound', _scannerSound.toString());
    await settingsRepo.saveSetting('receipt_footer', _receiptFooter);
    await settingsRepo.saveSetting('show_tax_button_pos', _showTaxButtonInPOS.toString());
    await settingsRepo.saveSetting('receipt_code_type', _receiptCodeType);
    await settingsRepo.saveSetting('show_work_order_button', _showWorkOrderButton.toString());
    await settingsRepo.saveSetting('show_delivery_button', _showDeliveryButton.toString());
    await settingsRepo.saveSetting('show_discount_button_pos', _showDiscountButtonInPOS.toString());
    await settingsRepo.saveSetting('show_drawer_button_pos', _showDrawerButtonInPOS.toString());
    await settingsRepo.saveSetting('show_expense_button_pos', _showExpenseButtonInPOS.toString());
    await settingsRepo.saveSetting('show_return_button_pos', _showReturnButtonInPOS.toString());
    await settingsRepo.saveSetting('show_hold_button_pos', _showHoldButtonInPOS.toString());
    await settingsRepo.saveSetting('show_exchange_button_pos', _showExchangeButtonInPOS.toString());
    await settingsRepo.saveSetting('pos_show_barcode', _showBarcodeInPOS.toString());
    await settingsRepo.saveSetting('pos_show_search', _showSearchInPOS.toString());
    await settingsRepo.saveSetting('pos_show_save_only', _showSaveOnlyInPOS.toString());
    await settingsRepo.saveSetting('pos_show_subtotal', _showSubtotalInPOS.toString());
    await settingsRepo.saveSetting('pos_show_add_customer', _showAddCustomerInPOS.toString());
    await settingsRepo.saveSetting('pos_show_product_sort', _showProductSortInPOS.toString());
    await settingsRepo.saveSetting('pos_show_product_images', _showProductImagesInPOS.toString());
    await settingsRepo.saveSetting('pos_product_name_font_size', _productNameFontSize.toString());
    await settingsRepo.saveSetting('pos_product_price_font_size', _productPriceFontSize.toString());
    await settingsRepo.saveSetting('pos_cart_ratio_locked', _posCartRatioLocked.toString());
    await settingsRepo.saveSetting('pos_cart_ratio_value', _posCartRatioValue.toString());
    if (_cashDrawerPrinter != null) await settingsRepo.saveSetting('cash_drawer_printer', _cashDrawerPrinter!);

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('scale_model', scaleModel);
    await prefs.setString('scale_read_type', scaleReadType);
    await prefs.setInt('scale_data_bits', scaleDataBits);
    await prefs.setString('scale_handshake', scaleHandshake);
    await prefs.setString('scale_parity', scaleParity);
    await prefs.setString('scale_stop_bits', scaleStopBits);
    await prefs.setInt('scale_wait_time', scaleWaitTime);
    await prefs.setDouble('scale_min_weight', scaleMinWeight);
    await prefs.setDouble('scale_weight_alert', scaleWeightAlert);

    ref.invalidate(showTaxButtonInPOSProvider);
    ref.invalidate(showDiscountButtonInPOSProvider);
    ref.invalidate(showDrawerButtonInPOSProvider);
    ref.invalidate(showExpenseButtonInPOSProvider);
    ref.invalidate(receiptCodeTypeProvider);
    ref.invalidate(showWorkOrderButtonProvider);
    ref.invalidate(showDeliveryButtonProvider);
    ref.invalidate(showReturnButtonInPOSProvider);
    ref.invalidate(showHoldButtonInPOSProvider);
    ref.invalidate(showExchangeButtonInPOSProvider);
    ref.invalidate(showBarcodeInPOSProvider);
    ref.invalidate(showSearchInPOSProvider);
    ref.invalidate(showSaveOnlyInPOSProvider);
    ref.invalidate(showSubtotalInPOSProvider);
    ref.invalidate(showAddCustomerInPOSProvider);
    ref.invalidate(showProductSortInPOSProvider);
    ref.invalidate(showProductImagesProvider);
    ref.invalidate(productNameFontSizeProvider);
    ref.invalidate(productPriceFontSizeProvider);
    ref.invalidate(posCartRatioLockedProvider);
    ref.invalidate(posCartRatioValueProvider);

    if (mounted) AppToast.show(context, 'تم حفظ الإعدادات بنجاح', type: ToastType.success);
  }
}

/// Helper method to show hardware settings in a dialog
Future<void> showHardwareSettingsDialog(BuildContext context) {
  return showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: const Row(children: [
        Icon(PhosphorIconsBold.printer, color: AppColors.info),
        SizedBox(width: 8),
        Text('إعدادات الأجهزة'),
      ]),
      content: const SizedBox(width: 500, height: 600, child: HardwareSettingsWidget()),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء'))],
    ),
  );
}
