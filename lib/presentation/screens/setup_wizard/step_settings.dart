part of '../setup_wizard_screen.dart';

extension _SetupWizardSettingsExt on _SetupWizardScreenState {
  // ═══════════════════════════════════════════════════════════════════════
  // STEP 4: Tax & Settings
  // ═══════════════════════════════════════════════════════════════════════
  Widget _buildSettingsStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'الضرائب والإعدادات',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        const Text(
          'حدد إعدادات الضريبة. يمكنك تغييرها لاحقاً من الإعدادات.',
          style: TextStyle(color: AppColors.textMuted),
        ),
        const SizedBox(height: 32),
        SwitchListTile(
          title: const Text('تفعيل ضريبة القيمة المضافة'),
          subtitle: const Text('إضافة الضريبة تلقائياً على الفواتير'),
          value: _enableTax,
          activeThumbColor: AppColors.primary,
          onChanged: (v) => setState(() => _enableTax = v),
        ),
        if (_enableTax) ...[
          const SizedBox(height: 16),
          SizedBox(
            width: 200,
            child: _buildTextField(
              controller: TextEditingController(text: _taxRate.toString()),
              label: 'نسبة الضريبة %',
              hint: '14',
              icon: PhosphorIconsBold.percent,
              isNumber: true,
              onChanged: (v) {
                final rate = double.tryParse(v);
                if (rate != null) _taxRate = rate;
              },
            ),
          ),
        ],
        const SizedBox(height: 32),
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: AppColors.success.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.success.withValues(alpha: 0.2)),
          ),
          child: const Row(
            children: [
              Icon(PhosphorIconsBold.checkCircle,
                  color: AppColors.success, size: 32),
              SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'أنت جاهز للبدء!',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: AppColors.success,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'اضغط "إنهاء الإعداد" لحفظ بياناتك والانتقال للنظام.',
                      style: TextStyle(color: AppColors.textMuted),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // HELPERS
  // ═══════════════════════════════════════════════════════════════════════

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    String? hint,
    IconData? icon,
    bool isRequired = false,
    bool isNumber = false,
    bool isPassword = false,
    ValueChanged<String>? onChanged,
  }) {
    return TextField(
      controller: controller,
      keyboardType: isNumber ? TextInputType.number : TextInputType.text,
      obscureText: isPassword,
      onChanged: onChanged,
      decoration: InputDecoration(
        labelText: isRequired ? '$label *' : label,
        hintText: hint,
        prefixIcon: icon != null ? Icon(icon, size: 18) : null,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
    );
  }

  Widget _buildDropdown({
    required String label,
    required String value,
    required Map<String, String> items,
    required ValueChanged<String?> onChanged,
  }) {
    return DropdownButtonFormField<String>(
      initialValue: value,
      decoration: InputDecoration(
        labelText: label,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      items: items.entries.map((e) {
        return DropdownMenuItem(value: e.key, child: Text(e.value));
      }).toList(),
      onChanged: onChanged,
    );
  }
}
