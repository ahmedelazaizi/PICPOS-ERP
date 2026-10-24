import 'package:flutter/material.dart';
import 'package:picpos_erp/core/i18n/tr.dart';

import '../../../core/widgets/app_toast.dart';
import '../../../services/lan_tls/lan_tls_manager.dart';
import '../../../services/network_service.dart';

/// SEC-007: shows the LAN transport security state next to the pairing code and
/// holds the two operator controls - the explicit legacy-HTTP opt-out and the
/// certificate rotation. Changes apply the next time the server starts.
class LanTransportSection extends StatefulWidget {
  const LanTransportSection({super.key});

  @override
  State<LanTransportSection> createState() => _LanTransportSectionState();
}

class _LanTransportSectionState extends State<LanTransportSection> {
  final _ns = NetworkService.instance;
  String? _fingerprint;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final fp = _ns.serverCertFingerprint ?? await _ns.lanTransport.manager.storedFingerprint();
    if (mounted) setState(() => _fingerprint = fp);
  }

  @override
  Widget build(BuildContext context) {
    final legacy = _ns.lanTransport.mode == LanTransportMode.legacyHttp;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Divider(),
        Text(
          legacy
              ? tr('⚠️ النقل على الشبكة المحلية: HTTP غير مشفَّر (خيار قديم)')
              : tr('🔒 النقل على الشبكة المحلية: HTTPS مع تثبيت بصمة الشهادة'),
          style: TextStyle(fontWeight: FontWeight.bold, color: legacy ? Colors.orange : Colors.green),
        ),
        if (!legacy && _fingerprint != null) ...[
          const SizedBox(height: 4),
          Text(tr('بصمة شهادة الخادم (SHA-256)'), style: const TextStyle(fontSize: 11)),
          SelectableText(_fingerprint!, style: const TextStyle(fontSize: 10, fontFamily: 'monospace')),
        ],
        SwitchListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: Text(tr('السماح بـ HTTP غير مشفَّر (خيار قديم — غير موصى به)')),
          subtitle: Text(tr('يسري عند إعادة تشغيل الخادم')),
          value: legacy,
          onChanged: (v) async {
            _ns.lanTransport.setLegacyHttp(v);
            await _ns.saveSettings();
            await _refresh();
          },
        ),
        if (!legacy)
          TextButton.icon(
            icon: const Icon(Icons.autorenew, size: 16),
            label: Text(tr('تدوير الشهادة (يتطلب إعادة إقران كل الأجهزة)')),
            onPressed: () async {
              await _ns.lanTransport.manager.rotate();
              await _refresh();
              if (context.mounted) {
                AppToast.show(context, tr('تم تدوير الشهادة. أعد تشغيل الخادم ثم أعد إقران الأجهزة.'));
              }
            },
          ),
      ],
    );
  }
}
