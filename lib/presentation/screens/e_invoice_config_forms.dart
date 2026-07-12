part of 'e_invoice_dashboard_screen.dart';

// ═══════════════════════════════════════════════════════════════════════════
// CONFIG FORMS — نماذج الإعدادات
// ═══════════════════════════════════════════════════════════════════════════

class _EtaConfigForm extends StatefulWidget {
  final Function(Map<String, dynamic>) onSave;
  const _EtaConfigForm({required this.onSave});

  @override
  State<_EtaConfigForm> createState() => _EtaConfigFormState();
}

class _EtaConfigFormState extends State<_EtaConfigForm> {
  final _clientId = TextEditingController();
  final _clientSecret = TextEditingController();
  final _registrationNumber = TextEditingController();
  final _activityCode = TextEditingController();
  bool _isProduction = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TextField(
          controller: _clientId,
          decoration: const InputDecoration(labelText: 'Client ID'),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _clientSecret,
          decoration: const InputDecoration(labelText: 'Client Secret'),
          obscureText: true,
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _registrationNumber,
          decoration: const InputDecoration(labelText: 'رقم التسجيل الضريبي'),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _activityCode,
          decoration: const InputDecoration(labelText: 'كود النشاط (اختياري)'),
        ),
        const SizedBox(height: 8),
        SwitchListTile(
          title: const Text('بيئة الإنتاج'),
          subtitle: const Text('تشغيل: إنتاج / إيقاف: اختبار'),
          value: _isProduction,
          onChanged: (v) => setState(() => _isProduction = v),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            icon: const Icon(Icons.save),
            label: const Text('حفظ إعدادات ETA'),
            onPressed: () => widget.onSave({
              'clientId': _clientId.text,
              'clientSecret': _clientSecret.text,
              'registrationNumber': _registrationNumber.text,
              'activityCode': _activityCode.text.isNotEmpty
                  ? _activityCode.text
                  : null,
              'isProduction': _isProduction,
            }),
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _clientId.dispose();
    _clientSecret.dispose();
    _registrationNumber.dispose();
    _activityCode.dispose();
    super.dispose();
  }
}

class _JofotaraConfigForm extends StatefulWidget {
  final Function(Map<String, dynamic>) onSave;
  const _JofotaraConfigForm({required this.onSave});

  @override
  State<_JofotaraConfigForm> createState() => _JofotaraConfigFormState();
}

class _JofotaraConfigFormState extends State<_JofotaraConfigForm> {
  final _clientId = TextEditingController();
  final _clientSecret = TextEditingController();
  final _registrationNumber = TextEditingController();
  bool _isProduction = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TextField(
          controller: _clientId,
          decoration: const InputDecoration(labelText: 'Client ID'),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _clientSecret,
          decoration: const InputDecoration(labelText: 'Client Secret'),
          obscureText: true,
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _registrationNumber,
          decoration: const InputDecoration(
            labelText: 'رقم التسجيل الضريبي (TRN)',
          ),
        ),
        const SizedBox(height: 8),
        SwitchListTile(
          title: const Text('بيئة الإنتاج'),
          subtitle: const Text('تشغيل: إنتاج / إيقاف: اختبار'),
          value: _isProduction,
          onChanged: (v) => setState(() => _isProduction = v),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            icon: const Icon(Icons.save),
            label: const Text('حفظ إعدادات JOFOTARA'),
            onPressed: () => widget.onSave({
              'clientId': _clientId.text,
              'clientSecret': _clientSecret.text,
              'registrationNumber': _registrationNumber.text,
              'isProduction': _isProduction,
            }),
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _clientId.dispose();
    _clientSecret.dispose();
    _registrationNumber.dispose();
    super.dispose();
  }
}
