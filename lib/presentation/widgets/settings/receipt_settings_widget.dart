import 'package:picpos_erp/core/i18n/tr.dart';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:picpos_erp/core/widgets/app_toast.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:file_picker/file_picker.dart';
import '../../../core/theme/app_colors.dart';
import '../../../services/client_write_interceptor.dart';

import '../../settings/providers/settings_controller.dart';

/// Widget for customizing receipt/invoice print settings
class ReceiptSettingsWidget extends ConsumerStatefulWidget {
  const ReceiptSettingsWidget({super.key});

  @override
  ConsumerState<ReceiptSettingsWidget> createState() =>
      _ReceiptSettingsWidgetState();
}

class _ReceiptSettingsWidgetState extends ConsumerState<ReceiptSettingsWidget> {
  // Controllers
  final _companyNameController = TextEditingController();
  final _companyAddressController = TextEditingController();
  final _companyPhoneController = TextEditingController();
  final _companyPhone2Controller = TextEditingController();
  final _companyEmailController = TextEditingController();
  final _taxNumberController = TextEditingController();
  final _headerTextController = TextEditingController();
  final _footerTextController = TextEditingController();
  final _termsTextController = TextEditingController();
  final _currencyController = TextEditingController();

  // 6.1: Receipt template
  String _selectedTemplate = 'standard';

  // Display options
  bool _showLogo = false;
  bool _showQrCode = true;
  bool _showBarcode = false;
  bool _showTaxDetails = true;
  bool _showItemCode = false;
  bool _showSalesperson = true;
  bool _showCustomerInfo = true;

  // Font sizes and paper
  int _headerFontSize = 14;
  int _bodyFontSize = 10;
  int _footerFontSize = 9;
  int _paperWidth = 80;

  // Logo image
  Uint8List? _logoImage;

  bool _isLoading = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    await ref.read(settingsControllerProvider.notifier).loadReceiptSettings();
    final data = ref.read(settingsControllerProvider).receiptSettings;

    if (data.isEmpty) return;

    setState(() {
      _companyNameController.text = data['companyName'] ?? '';
      _companyAddressController.text = data['companyAddress'] ?? '';
      _companyPhoneController.text = data['companyPhone'] ?? '';
      _companyPhone2Controller.text = data['companyPhone2'] ?? '';
      _companyEmailController.text = data['companyEmail'] ?? '';
      _taxNumberController.text = data['taxNumber'] ?? '';
      _headerTextController.text = data['headerText'] ?? '';
      _footerTextController.text = data['footerText'] ?? '';
      _termsTextController.text = data['termsText'] ?? '';
      _currencyController.text = data['currencySymbol'] ?? '';

      _showLogo = data['showLogo'] ?? false;
      _showQrCode = data['showQrCode'] ?? true;
      _showBarcode = data['showBarcode'] ?? false;
      _showTaxDetails = data['showTaxDetails'] ?? true;
      _showItemCode = data['showItemCode'] ?? false;
      _showSalesperson = data['showSalesperson'] ?? true;
      _showCustomerInfo = data['showCustomerInfo'] ?? true;

      _headerFontSize = data['headerFontSize'] ?? 14;
      _bodyFontSize = data['bodyFontSize'] ?? 10;
      _footerFontSize = data['footerFontSize'] ?? 9;
      _paperWidth = data['paperWidth'] ?? 80;

      _logoImage = data['logoImage'];
      _isLoading = false;
    });
  }

  Future<void> _saveSettings() async {
    setState(() => _isSaving = true);

    try {
      final success = await ref.read(settingsControllerProvider.notifier).saveReceiptSettings({
        'companyName': _companyNameController.text,
        'companyAddress': _companyAddressController.text,
        'companyPhone': _companyPhoneController.text,
        'companyPhone2': _companyPhone2Controller.text,
        'companyEmail': _companyEmailController.text,
        'taxNumber': _taxNumberController.text,
        'headerText': _headerTextController.text,
        'footerText': _footerTextController.text,
        'termsText': _termsTextController.text,
        'logoImage': _logoImage,
        'showLogo': _showLogo,
        'showQrCode': _showQrCode,
        'showBarcode': _showBarcode,
        'showTaxDetails': _showTaxDetails,
        'showItemCode': _showItemCode,
        'showSalesperson': _showSalesperson,
        'showCustomerInfo': _showCustomerInfo,
        'headerFontSize': _headerFontSize,
        'bodyFontSize': _bodyFontSize,
        'footerFontSize': _footerFontSize,
        'paperWidth': _paperWidth,
        'currencySymbol': _currencyController.text,
      });

      if (mounted && success) {
        // ── Client mode: sync receipt settings to server ──
        await ClientWriteInterceptor.saveSettings(<String, String>{
          'receipt_companyName': _companyNameController.text,
          'receipt_companyAddress': _companyAddressController.text,
          'receipt_companyPhone': _companyPhoneController.text,
          'receipt_taxNumber': _taxNumberController.text,
          'receipt_headerText': _headerTextController.text,
          'receipt_footerText': _footerTextController.text,
          'receipt_showQrCode': _showQrCode.toString(),
          'receipt_showBarcode': _showBarcode.toString(),
          'receipt_showTaxDetails': _showTaxDetails.toString(),
          'receipt_paperWidth': _paperWidth.toString(),
          'receipt_currencySymbol': _currencyController.text,
        });
        if (!mounted) return;
        AppToast.show(
          context,
          tr('تم حفظ إعدادات الإيصال بنجاح'),
          type: ToastType.success,
        );
      }
    } catch (e) {
      if (mounted) {
        AppToast.show(context, tr('خطأ في الحفظ: {e}', {'e': e}), type: ToastType.error);
      }
    } finally {
      setState(() => _isSaving = false);
    }
  }

  Future<void> _pickLogo() async {
    final result = await FilePicker.pickFiles(
      type: FileType.image,
      allowMultiple: false,
    );

    if (result != null && result.files.single.bytes != null) {
      setState(() {
        _logoImage = result.files.single.bytes;
        _showLogo = true;
      });
    }
  }

  @override
  void dispose() {
    _companyNameController.dispose();
    _companyAddressController.dispose();
    _companyPhoneController.dispose();
    _companyPhone2Controller.dispose();
    _companyEmailController.dispose();
    _taxNumberController.dispose();
    _headerTextController.dispose();
    _footerTextController.dispose();
    _termsTextController.dispose();
    _currencyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 6.1: Template Selection Section
          _buildSectionHeader(tr('قالب الإيصال'), PhosphorIconsLight.layout),
          const SizedBox(height: 12),
          Row(
            children: [
              _buildTemplateOption(
                'minimal',
                tr('بسيط'),
                PhosphorIconsLight.textAlignLeft,
              ),
              const SizedBox(width: 8),
              _buildTemplateOption(
                'standard',
                tr('قياسي'),
                PhosphorIconsLight.listDashes,
              ),
              const SizedBox(width: 8),
              _buildTemplateOption(
                'detailed',
                tr('مفصّل'),
                PhosphorIconsLight.listChecks,
              ),
              const SizedBox(width: 8),
              _buildTemplateOption(
                'elegant',
                tr('أنيق'),
                PhosphorIconsLight.sparkle,
              ),
            ],
          ),
          const Divider(height: 32),

          // Company Information Section
          _buildSectionHeader(tr('معلومات الشركة'), PhosphorIconsLight.buildings),
          const SizedBox(height: 12),
          _buildTextField(
            _companyNameController,
            tr('اسم الشركة'),
            PhosphorIconsLight.storefront,
          ),
          const SizedBox(height: 8),
          _buildTextField(
            _companyAddressController,
            tr('العنوان'),
            PhosphorIconsLight.mapPin,
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _buildTextField(
                  _companyPhoneController,
                  tr('الهاتف 1'),
                  PhosphorIconsLight.phone,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildTextField(
                  _companyPhone2Controller,
                  tr('الهاتف 2'),
                  PhosphorIconsLight.phone,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _buildTextField(
                  _companyEmailController,
                  tr('البريد الإلكتروني'),
                  PhosphorIconsLight.envelope,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildTextField(
                  _taxNumberController,
                  tr('الرقم الضريبي'),
                  PhosphorIconsLight.identificationCard,
                ),
              ),
            ],
          ),

          const Divider(height: 32),

          // Header & Footer Section
          _buildSectionHeader(
            tr('الرأس والتذييل'),
            PhosphorIconsLight.textAlignCenter,
          ),
          const SizedBox(height: 12),
          _buildTextField(
            _headerTextController,
            tr('نص الترحيب (الرأس)'),
            PhosphorIconsLight.chatText,
          ),
          const SizedBox(height: 8),
          _buildTextField(
            _footerTextController,
            tr('نص الشكر (التذييل)'),
            PhosphorIconsLight.handHeart,
          ),
          const SizedBox(height: 8),
          _buildTextField(
            _termsTextController,
            tr('شروط الدفع (اختياري)'),
            PhosphorIconsLight.notepad,
            maxLines: 2,
          ),

          const Divider(height: 32),

          // Logo Section
          _buildSectionHeader(tr('الشعار'), PhosphorIconsLight.image),
          const SizedBox(height: 12),
          Row(
            children: [
              if (_logoImage != null)
                Container(
                  width: 80,
                  height: 80,
                  margin: const EdgeInsetsDirectional.only(end: 16),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.memory(_logoImage!, fit: BoxFit.contain),
                  ),
                ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    OutlinedButton.icon(
                      onPressed: _pickLogo,
                      icon: const Icon(PhosphorIconsLight.upload, size: 18),
                      label: Text(
                        _logoImage != null ? tr('تغيير الشعار') : tr('اختيار شعار'),
                      ),
                    ),
                    if (_logoImage != null)
                      TextButton(
                        onPressed: () => setState(() {
                          _logoImage = null;
                          _showLogo = false;
                        }),
                        child:  Text(
                          tr('حذف الشعار'),
                          style: const TextStyle(color: AppColors.error, fontSize: 12),
                        ),
                      ),
                  ],
                ),
              ),
              Switch(
                value: _showLogo,
                onChanged: _logoImage != null
                    ? (v) => setState(() => _showLogo = v)
                    : null,
              ),
               Text(tr('إظهار الشعار'), style: const TextStyle(fontSize: 12)),
            ],
          ),

          const Divider(height: 32),

          // Display Options Section
          _buildSectionHeader(tr('خيارات العرض'), PhosphorIconsLight.eye),
          const SizedBox(height: 12),
          Wrap(
            spacing: 16,
            runSpacing: 8,
            children: [
              _buildSwitch(
                tr('كود QR'),
                _showQrCode,
                (v) => setState(() => _showQrCode = v),
              ),
              _buildSwitch(
                tr('باركود'),
                _showBarcode,
                (v) => setState(() => _showBarcode = v),
              ),
              _buildSwitch(
                tr('تفاصيل الضريبة'),
                _showTaxDetails,
                (v) => setState(() => _showTaxDetails = v),
              ),
              _buildSwitch(
                tr('كود المنتج'),
                _showItemCode,
                (v) => setState(() => _showItemCode = v),
              ),
              _buildSwitch(
                tr('البائع'),
                _showSalesperson,
                (v) => setState(() => _showSalesperson = v),
              ),
              _buildSwitch(
                tr('معلومات العميل'),
                _showCustomerInfo,
                (v) => setState(() => _showCustomerInfo = v),
              ),
            ],
          ),

          const Divider(height: 32),

          // Font Sizes & Paper Section
          _buildSectionHeader(tr('أحجام الخطوط والورق'), PhosphorIconsLight.textT),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildNumberField(
                  tr('خط العنوان'),
                  _headerFontSize,
                  (v) => setState(() => _headerFontSize = v),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildNumberField(
                  tr('خط النص'),
                  _bodyFontSize,
                  (v) => setState(() => _bodyFontSize = v),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildNumberField(
                  tr('خط التذييل'),
                  _footerFontSize,
                  (v) => setState(() => _footerFontSize = v),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<int>(
                  initialValue: _paperWidth,
                  decoration:  InputDecoration(
                    labelText: tr('عرض الورق (مم)'),
                    prefixIcon: const Icon(PhosphorIconsLight.file, size: 18),
                    isDense: true,
                  ),
                  items:  [
                    DropdownMenuItem(value: 58, child: Text(tr('58 مم'))),
                    DropdownMenuItem(value: 80, child: Text(tr('80 مم'))),
                  ],
                  onChanged: (v) => setState(() => _paperWidth = v ?? 80),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildTextField(
                  _currencyController,
                  tr('رمز العملة'),
                  PhosphorIconsLight.currencyCircleDollar,
                ),
              ),
            ],
          ),

          const SizedBox(height: 24),

          // Save Button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _isSaving ? null : _saveSettings,
              icon: _isSaving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(PhosphorIconsBold.floppyDisk, size: 18),
              label: Text(_isSaving ? tr('جاري الحفظ...') : tr('حفظ الإعدادات')),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 18, color: AppColors.primary),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }

  Widget _buildTextField(
    TextEditingController controller,
    String label,
    IconData icon, {
    int maxLines = 1,
  }) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, size: 18),
        isDense: true,
      ),
    );
  }

  Widget _buildSwitch(String label, bool value, ValueChanged<bool> onChanged) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Switch(value: value, onChanged: onChanged),
        Text(label, style: const TextStyle(fontSize: 12)),
      ],
    );
  }

  Widget _buildNumberField(
    String label,
    int value,
    ValueChanged<int> onChanged,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
        const SizedBox(height: 4),
        Row(
          children: [
            IconButton(
              onPressed: value > 6 ? () => onChanged(value - 1) : null,
              icon: const Icon(PhosphorIconsLight.minus, size: 16),
              iconSize: 16,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            ),
            Container(
              width: 32,
              alignment: Alignment.center,
              child: Text(
                '$value',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            IconButton(
              onPressed: value < 24 ? () => onChanged(value + 1) : null,
              icon: const Icon(PhosphorIconsLight.plus, size: 16),
              iconSize: 16,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            ),
          ],
        ),
      ],
    );
  }

  // 6.1: Template option builder
  Widget _buildTemplateOption(String value, String label, IconData icon) {
    final isSelected = _selectedTemplate == value;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _selectedTemplate = value),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          decoration: BoxDecoration(
            color: isSelected ? AppColors.primary.withValues(alpha: 0.1) : null,
            border: Border.all(
              color: isSelected ? AppColors.primary : AppColors.border,
              width: isSelected ? 2 : 1,
            ),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            children: [
              Icon(
                icon,
                color: isSelected ? AppColors.primary : AppColors.textMuted,
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: isSelected ? FontWeight.bold : null,
                  color: isSelected ? AppColors.primary : null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
