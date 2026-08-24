import 'package:flutter/material.dart';
import 'package:ural_erp/core/widgets/app_toast.dart';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:file_picker/file_picker.dart';
import '../../../core/theme/app_colors.dart';
import '../../picpos_shell/picpos_body_handle.dart';
import '../../picpos_shell/picpos_dialog.dart';
import '../../picpos_shell/picpos_panel_groups.dart';
import '../../settings_picpos/widgets/settings_blocks.dart';

import '../../../core/design_system/typography.dart';
import '../../../data/providers/providers.dart';

/// Dialog/Widget for company information and branding
class CompanyInfoWidget extends ConsumerStatefulWidget {
  /// شكلُ لوحة `PANELS.company` — مجموعاتٌ بعناوين بدل قائمةِ حقولٍ عارية.
  ///
  /// ⚠️ **والحقولُ الثلاثةُ الإضافيّةُ ليست تجميلاً**: البريدُ والهاتفُ
  /// الثاني ومفاتيحُ «ما يظهر في الفاتورة» **أعمدةٌ قائمةٌ** في
  /// `CompanySettings` يدعمها `saveReceiptSettings` منذ اليوم، وكانت
  /// تُحفَظ من مكانٍ آخر ولا تُعرَض هنا. فهي كشفُ ما هو موجود لا بناءُ جديد.
  final bool picposChrome;

  /// تسجّل فيه الحالةُ إجراءَ الحفظ ليبلغه زرُّ تذييل `PicPosDialog` — الزرُّ
  /// خرج من الجسم إلى التذييل، والمنطقُ بقي مكانَه.
  final PicPosBodyHandle? saveHandle;

  const CompanyInfoWidget({
    super.key,
    this.picposChrome = false,
    this.saveHandle,
  });

  @override
  ConsumerState<CompanyInfoWidget> createState() => _CompanyInfoWidgetState();
}

class _CompanyInfoWidgetState extends ConsumerState<CompanyInfoWidget> {
  final _nameController = TextEditingController();
  final _addressController = TextEditingController();
  final _phoneController = TextEditingController();
  final _taxIdController = TextEditingController();
  final _emailController = TextEditingController();
  final _phone2Controller = TextEditingController();
  final _footerController = TextEditingController();
  bool _showLogo = false;
  bool _showTaxDetails = true;
  bool _showQrCode = true;

  /// هل قُرئت الحقولُ الإضافيّةُ من `getReceiptSettings()` بنجاح؟
  ///
  /// ⚠️ **شرطٌ للحفظ لا زينة.** القراءةُ داخلَ `try/catch`، فلو أخفقت بقيت
  /// المتحكّماتُ فارغةً — وحفظٌ يمرّرها عندئذٍ **يمسح** البريدَ والهاتفَ
  /// الثانيَ ورسالةَ الشكر التي كانت محفوظة. وقبل هذا التعديل لم يكن الحفظُ
  /// يمسّها أصلاً فما كان يضيع شيء. فلا تُمرَّر إلّا إن قُرئت.
  bool _extrasLoaded = false;

  Uint8List? _selectedLogo;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    widget.saveHandle?.register(_saveSettings);
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final settingsRepo = ref.read(settingsRepositoryProvider);
    final name = await settingsRepo.getSetting('company_name');
    final address = await settingsRepo.getSetting('company_address');
    final phone = await settingsRepo.getSetting('company_phone');
    final taxId = await settingsRepo.getSetting('company_tax_id');

    String email = '';
    String phone2 = '';
    String footer = '';
    try {
      final rs = await settingsRepo.getReceiptSettings();
      final logoData = rs['logoImage'];
      if (logoData != null && logoData is Uint8List && logoData.isNotEmpty) {
        _selectedLogo = logoData;
      }
      // القيمُ التي كانت تُحفَظ ولا تُعرَض — تُقرأ من نفس المصدر الذي يقرأ
      // منه الطابعُ، فلا يظهر في الحوار غيرُ ما يُطبَع.
      email = (rs['companyEmail'] ?? '').toString();
      phone2 = (rs['companyPhone2'] ?? '').toString();
      footer = (rs['footerText'] ?? '').toString();
      _showLogo = rs['showLogo'] == true;
      _showTaxDetails = rs['showTaxDetails'] != false;
      _showQrCode = rs['showQrCode'] != false;
      _extrasLoaded = true;
    } catch (_) {}

    if (mounted) {
      setState(() {
        _nameController.text = name ?? '';
        _addressController.text = address ?? '';
        _phoneController.text = phone ?? '';
        _taxIdController.text = taxId ?? '';
        _emailController.text = email;
        _phone2Controller.text = phone2;
        _footerController.text = footer;
        _isLoading = false;
      });
    }
  }

  @override
  void dispose() {
    widget.saveHandle?.register(null);
    _nameController.dispose();
    _addressController.dispose();
    _phoneController.dispose();
    _taxIdController.dispose();
    _emailController.dispose();
    _phone2Controller.dispose();
    _footerController.dispose();
    super.dispose();
  }

  /// جسمُ لوحة `PANELS.company` — ثلاثُ مجموعاتٍ كما في التصميم.
  ///
  /// ⚠️ **وحقلان من التصميم غائبان عن عمد**: «الاسم القانوني» و«السجل
  /// التجاري» **لا عمودَ لهما** في `CompanySettings`. وإضافتُهما هجرةُ
  /// قاعدةٍ لا حقلاً في نموذج، فحقلٌ لا يُحفَظ أسوأُ من غيابه. بقيّةُ حقول
  /// التصميم كلُّها أعمدةٌ قائمةٌ يحفظها `saveReceiptSettings`.
  ///
  /// و«رسالة الشكر» في التصميم مفتاحٌ، وهي في القاعدة **نصٌّ** (`footerText`)
  /// — فرُسمت حقلَ نصٍّ لا مفتاحاً: مفتاحٌ يخفي النصَّ الذي يُطبَع فعلاً.
  List<Widget> _picposGroups() {
    return [
      PicPosPanelGroup(
        label: 'هويّة الشركة',
        hint: 'تظهر في ترويسة كل فاتورة وتقرير مطبوع',
        child: _buildLogoSection(),
      ),
      const SizedBox(height: 20),
      PicPosPanelGroup(
        label: 'البيانات الأساسية',
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            PicPosDialogRow(children: [
              _field(_nameController, 'الاسم التجاري',
                  PhosphorIconsBold.buildings),
              _field(_taxIdController, 'الرقم الضريبي',
                  PhosphorIconsBold.identificationCard),
            ]),
            const SizedBox(height: 12),
            PicPosDialogRow(children: [
              _field(_phoneController, 'الهاتف', PhosphorIconsBold.phone),
              _field(_phone2Controller, 'هاتف ثانٍ',
                  PhosphorIconsBold.phoneCall),
            ]),
            const SizedBox(height: 12),
            PicPosDialogRow(children: [
              _field(_emailController, 'البريد الإلكتروني',
                  PhosphorIconsBold.envelope),
              _field(_addressController, 'العنوان الكامل',
                  PhosphorIconsBold.mapPin),
            ]),
          ],
        ),
      ),
      const SizedBox(height: 20),
      PicPosPanelGroup(
        label: 'ما يظهر في الفاتورة',
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            PicPosPanelBox(
              children: [
                SettingsSwitchRow(
                  first: true,
                  icon: PhosphorIconsBold.image,
                  title: 'شعار الشركة',
                  sub: 'يُطبَع في ترويسة الفاتورة',
                  value: _showLogo,
                  onChanged: (v) => setState(() => _showLogo = v),
                ),
                SettingsSwitchRow(
                  icon: PhosphorIconsBold.receipt,
                  title: 'الرقم الضريبي',
                  sub: 'إلزامي للفاتورة الإلكترونية',
                  value: _showTaxDetails,
                  onChanged: (v) => setState(() => _showTaxDetails = v),
                ),
                SettingsSwitchRow(
                  icon: PhosphorIconsBold.qrCode,
                  title: 'رمز QR',
                  sub: 'يُولَّد على الفاتورة المطبوعة',
                  value: _showQrCode,
                  onChanged: (v) => setState(() => _showQrCode = v),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _field(_footerController, 'رسالة التذييل',
                PhosphorIconsBold.chatText),
          ],
        ),
      ),
    ];
  }

  Widget _field(TextEditingController c, String label, IconData icon) {
    return TextField(
      controller: c,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
        isDense: true,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Center(child: CircularProgressIndicator());

    if (widget.picposChrome) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: _picposGroups(),
      );
    }

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
    );
    if (result != null && result.files.single.path != null) {
      final file = File(result.files.single.path!);
      final bytes = await file.readAsBytes();
      setState(() => _selectedLogo = bytes);
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
      companyPhone2: _extrasLoaded ? _phone2Controller.text : null,
      companyEmail: _extrasLoaded ? _emailController.text : null,
      taxNumber: _taxIdController.text,
      footerText: _extrasLoaded ? _footerController.text : null,
      showLogo: _extrasLoaded ? _showLogo : null,
      showTaxDetails: _extrasLoaded ? _showTaxDetails : null,
      showQrCode: _extrasLoaded ? _showQrCode : null,
      logoImage: _selectedLogo,
    );
    if (mounted) {
      AppToast.show(context, 'تم حفظ معلومات الشركة', type: ToastType.success);
    }
  }
}

/// Helper method to show company info in a dialog
///
/// [picpos] `true` ⇒ لوحةُ `PANELS.company` بغلاف `PicPosDialog`. الافتراضُ
/// `false` فحوارُ UralCash يبقى كما هو.
Future<void> showCompanyInfoDialog(BuildContext context,
    {bool picpos = false}) {
  if (picpos) return _showCompanyInfoPicpos(context);
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

/// لوحةُ `PANELS.company` بغلاف PicPos.
///
/// ⚠️ **الوصلةُ تُملَك في `StatefulBuilder` لا تُبنى في كلّ إطار** — لو
/// أُنشئت داخلَ `builder` لتركت الجسمَ مسجَّلاً على وصلةٍ متروكةٍ فيموت زرُّ
/// الحفظ بعد أوّلِ إعادةِ بناء.
Future<void> _showCompanyInfoPicpos(BuildContext context) {
  final handle = PicPosBodyHandle();
  return showDialog(
    context: context,
    builder: (ctx) => ValueListenableBuilder<bool>(
      valueListenable: handle.isReady,
      builder: (_, ready, _) => PicPosDialog(
        icon: PhosphorIconsBold.buildings,
        title: 'معلومات الشركة',
        subtitle: 'تظهر في ترويسة كل فاتورة وتقرير مطبوع',
        width: 760,
        primaryAction: PicPosDialogAction(
          label: 'حفظ البيانات',
          icon: PhosphorIconsBold.check,
          onPressed: ready ? handle.invoke : null,
        ),
        body: [CompanyInfoWidget(picposChrome: true, saveHandle: handle)],
      ),
    ),
  ).whenComplete(handle.dispose);
}
