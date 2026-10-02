part of '../setup_wizard_screen.dart';

extension _SetupWizardSettingsExt on _SetupWizardScreenState {
  // ═══════════════════════════════════════════════════════════════════════
  // STEP 4: Tax & Settings
  //
  // بندُ المالك ٦: انتقل إلى «العملة والضريبة» (`step_currency_tax.dart`):
  // تفعيلُ الضريبة ونسبتُها (‏من قائمةٍ مسموحة) وشمولُ الأسعار وبلدُ الفوترة.
  // وبطاقةُ «أنت جاهز للبدء!» صارت خطوةَ «المراجعة والبدء» كاملة.
  // ═══════════════════════════════════════════════════════════════════════

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
    Key? key,
  }) {
    return TextField(
      key: key,
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

  // ignore: unused_element
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
