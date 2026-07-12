import 'package:flutter/material.dart';
import 'package:ural_erp/core/widgets/app_toast.dart';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:file_picker/file_picker.dart';
import '../../../core/theme/app_colors.dart';

import '../../../core/design_system/typography.dart';
import '../../../data/providers/providers.dart';
import '../../../services/client_write_interceptor.dart';

/// Dialog/Widget for company information and branding (Web Compatible)
class CompanyInfoWidget extends ConsumerStatefulWidget {
  const CompanyInfoWidget({super.key});

  @override
  ConsumerState<CompanyInfoWidget> createState() => _CompanyInfoWidgetState();
}

class _CompanyInfoWidgetState extends ConsumerState<CompanyInfoWidget> {
  final _nameController = TextEditingController();
  final _addressController = TextEditingController();
  final _phoneController = TextEditingController();
  final _taxIdController = TextEditingController();
  Uint8List? _selectedLogo;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final settingsRepo = ref.read(settingsRepositoryProvider);
    final name = await settingsRepo.getSetting('company_name');
    final address = await settingsRepo.getSetting('company_address');
    final phone = await settingsRepo.getSetting('company_phone');
    final taxId = await settingsRepo.getSetting('company_tax_id');

    try {
      final rs = await settingsRepo.getReceiptSettings();
      final logoData = rs['logoImage'];
      if (logoData != null && logoData is Uint8List && logoData.isNotEmpty) {
        _selectedLogo = logoData;
      }
    } catch (_) {}

    if (mounted) {
      setState(() {
        _nameController.text = name ?? '';
        _addressController.text = address ?? '';
        _phoneController.text = phone ?? '';
        _taxIdController.text = taxId ?? '';
        _isLoading = false;
      });
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _addressController.dispose();
    _phoneController.dispose();
    _taxIdController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Center(child: CircularProgressIndicator());

    return Directionality(
      textDirection: ui.TextDirection.rtl,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Company Logo Section
            _buildLogoSection(),
            const SizedBox(height: 16),
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'اسم الشركة',
                prefixIcon: Icon(PhosphorIconsBold.buildings),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _addressController,
              decoration: const InputDecoration(
                labelText: 'العنوان',
                prefixIcon: Icon(PhosphorIconsBold.mapPin),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _phoneController,
              decoration: const InputDecoration(
                labelText: 'رقم الهاتف',
                prefixIcon: Icon(PhosphorIconsBold.phone),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _taxIdController,
              decoration: const InputDecoration(
                labelText: 'الرقم الضريبي',
                prefixIcon: Icon(PhosphorIconsBold.identificationCard),
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: _saveSettings,
                child: const Text('حفظ التغييرات'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLogoSection() {
    final settingsRepo = ref.read(settingsRepositoryProvider);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          const Row(
            children: [
              Icon(PhosphorIconsBold.image, color: AppColors.primary, size: 18),
              SizedBox(width: 8),
              Text('شعار الشركة', style: AppTypography.h4),
            ],
          ),
          const SizedBox(height: 12),
          GestureDetector(
            onTap: _pickLogo,
            child: Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: AppColors.border,
                  width: 2,
                  style: BorderStyle.solid,
                ),
              ),
              child: _selectedLogo != null
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Image.memory(_selectedLogo!, fit: BoxFit.contain),
                    )
                  : FutureBuilder<String?>(
                      future: settingsRepo.getSetting('company_logo'),
                      builder: (ctx, snap) {
                        if (snap.hasData &&
                            snap.data != null &&
                            snap.data!.isNotEmpty) {
                          try {
                            final logoBytes = Uint8List.fromList(
                              snap.data!.codeUnits,
                            );
                            return ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: Image.memory(
                                logoBytes,
                                fit: BoxFit.contain,
                              ),
                            );
                          } catch (_) {}
                        }
                        return const Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              PhosphorIconsBold.uploadSimple,
                              size: 32,
                              color: AppColors.textMuted,
                            ),
                            SizedBox(height: 8),
                            Text(
                              'اضغط لاختيار',
                              style: TextStyle(
                                fontSize: 12,
                                color: AppColors.textMuted,
                              ),
                            ),
                          ],
                        );
                      },
                    ),
            ),
          ),
          if (_selectedLogo != null) ...[
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: () => setState(() => _selectedLogo = null),
              icon: const Icon(
                PhosphorIconsBold.trash,
                size: 16,
                color: AppColors.error,
              ),
              label: const Text(
                'إزالة الشعار',
                style: TextStyle(color: AppColors.error),
              ),
            ),
          ],
          const SizedBox(height: 8),
          const Text(
            'يظهر الشعار على الفواتير والإيصالات',
            style: TextStyle(fontSize: 11, color: AppColors.textMuted),
          ),
        ],
      ),
    );
  }

  Future<void> _pickLogo() async {
    final result = await FilePicker.pickFiles(
      type: FileType.image,
      allowMultiple: false,
      withData: true, // Important for web
    );
    if (result != null && result.files.isNotEmpty) {
      // Use bytes directly suitable for Web
      setState(() => _selectedLogo = result.files.first.bytes);
    }
  }

  Future<void> _saveSettings() async {
    final settingsRepo = ref.read(settingsRepositoryProvider);
    // Save to settings table (used by company info widget)
    await settingsRepo.saveSetting('company_name', _nameController.text);
    await settingsRepo.saveSetting('company_address', _addressController.text);
    await settingsRepo.saveSetting('company_phone', _phoneController.text);
    await settingsRepo.saveSetting('company_tax_id', _taxIdController.text);
    if (_selectedLogo != null) {
      await settingsRepo.saveSetting('company_logo', String.fromCharCodes(_selectedLogo!));
    }
    // Also sync to receiptSettings table (used by PDF/printing)
    await settingsRepo.saveReceiptSettings(
      companyName: _nameController.text,
      companyAddress: _addressController.text,
      companyPhone: _phoneController.text,
      taxNumber: _taxIdController.text,
      logoImage: _selectedLogo,
    );
    // ── Client mode: sync company info to server ──
    await ClientWriteInterceptor.saveSettings(<String, String>{
      'company_name': _nameController.text,
      'company_address': _addressController.text,
      'company_phone': _phoneController.text,
      'company_tax_id': _taxIdController.text,
    });
    if (mounted) {
      AppToast.show(context, 'تم حفظ معلومات الشركة', type: ToastType.success);
    }
  }
}

/// Helper method to show company info in a dialog
Future<void> showCompanyInfoDialog(BuildContext context) {
  return showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: const Row(
        children: [
          Icon(PhosphorIconsBold.buildings, color: AppColors.primary),
          SizedBox(width: 8),
          Text('معلومات الشركة'),
          Spacer(),
        ],
      ),
      content: const SizedBox(width: 450, child: CompanyInfoWidget()),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('إغلاق'),
        ),
      ],
    ),
  );
}
