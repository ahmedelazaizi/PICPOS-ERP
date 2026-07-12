part of '../setup_wizard_screen.dart';

extension _SetupWizardCompanyInfoExt on _SetupWizardScreenState {
  // ═══════════════════════════════════════════════════════════════════════
  // STEP 1: Company Info
  // ═══════════════════════════════════════════════════════════════════════
  Widget _buildCompanyInfoStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'معلومات الشركة',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        const Text(
          'أدخل بيانات شركتك الأساسية — ستظهر في الفواتير والتقارير.',
          style: TextStyle(color: AppColors.textMuted),
        ),
        const SizedBox(height: 32),
        _buildTextField(
          controller: _companyNameController,
          label: 'اسم الشركة / المحل',
          hint: 'مثال: سوبر ماركت النيل',
          icon: PhosphorIconsBold.storefront,
          isRequired: true,
        ),
        const SizedBox(height: 20),
        _buildTextField(
          controller: _companyPhoneController,
          label: 'رقم الهاتف',
          hint: '01xxxxxxxxx',
          icon: PhosphorIconsBold.phone,
        ),
        const SizedBox(height: 20),
        _buildTextField(
          controller: _companyAddressController,
          label: 'العنوان',
          hint: 'القاهرة، مصر',
          icon: PhosphorIconsBold.mapPin,
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              child: _buildDropdown(
                label: 'نوع النشاط',
                value: _businessType,
                items: const {
                  'retail': 'تجزئة (سوبر ماركت)',
                  'restaurant': 'مطعم / كافيه',
                  'wholesale': 'جملة وتوزيع',
                  'manufacturing': 'تصنيع',
                  'services': 'خدمات',
                  'other': 'أخرى',
                },
                onChanged: (v) => setState(() => _businessType = v!),
              ),
            ),
            const SizedBox(width: 20),
            Expanded(
              child: _buildDropdown(
                label: 'العملة',
                value: _currency,
                items: const {
                  'EGP': 'جنيه مصري (EGP)',
                  'SAR': 'ريال سعودي (SAR)',
                  'AED': 'درهم إماراتي (AED)',
                  'JOD': 'دينار أردني (JOD)',
                  'KWD': 'دينار كويتي (KWD)',
                  'USD': 'دولار أمريكي (USD)',
                },
                onChanged: (v) => setState(() => _currency = v!),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
