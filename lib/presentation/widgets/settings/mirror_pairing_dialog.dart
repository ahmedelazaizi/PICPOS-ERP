import 'package:picpos_erp/core/i18n/tr.dart';
// ═══════════════════════════════════════════════════════════════════════════
// MIRROR PAIRING DIALOG — Spec 097
// ═══════════════════════════════════════════════════════════════════════════
//
// Inline dialog launched from Developer Tools' _ChangeModeSection when the
// operator selects "مرآة" on an install that has never been paired (or
// whose MirrorState was wiped). Collects HQ host, port, admin username and
// password, then delegates to [MirrorPairingService] for the actual
// handshake + verify-admin call.
//
// Returns `true` from `Navigator.pop` on success — the caller (Dev Tools)
// then proceeds with `ConfigService.changeMode(DeploymentMode.mirror)`.
// Returns `false`/null on cancel or failure — caller MUST NOT flip the mode.
// ═══════════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/theme/app_colors.dart';
import '../../../services/mirror_pairing_service.dart';
import '../../../services/network_service.dart';

class MirrorPairingDialog extends StatefulWidget {
  const MirrorPairingDialog({super.key});

  /// Convenience helper — show the dialog and return `true` iff pairing
  /// succeeded. Callers should gate their mode-flip on this result.
  static Future<bool> show(BuildContext context) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const MirrorPairingDialog(),
    );
    return result ?? false;
  }

  @override
  State<MirrorPairingDialog> createState() => _MirrorPairingDialogState();
}

class _MirrorPairingDialogState extends State<MirrorPairingDialog> {
  late final TextEditingController _hostCtl;
  late final TextEditingController _portCtl;
  final _usernameCtl = TextEditingController();
  final _passwordCtl = TextEditingController();

  // Guard declared OUTSIDE the StatefulBuilder so concurrent taps cannot
  // double-fire the pairing call (ENGINEERING_GUIDELINES.md R2).
  bool _busy = false;
  String? _status;
  bool _statusIsError = true;

  @override
  void initState() {
    super.initState();
    final ns = NetworkService.instance;
    _hostCtl = TextEditingController(text: ns.serverAddress ?? '');
    _portCtl = TextEditingController(text: '${ns.serverPort}');
  }

  @override
  void dispose() {
    _hostCtl.dispose();
    _portCtl.dispose();
    _usernameCtl.dispose();
    _passwordCtl.dispose();
    super.dispose();
  }

  Future<void> _pair() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _status = null;
    });

    final host = _hostCtl.text.trim();
    final port = int.tryParse(_portCtl.text.trim()) ?? 8080;

    final result = await MirrorPairingService.instance.pair(
      host: host,
      port: port,
      adminUsername: _usernameCtl.text.trim(),
      adminPassword: _passwordCtl.text,
      // Spec 151 P1-8b — Dev Tools mirror re-pair: mint an admin session token
      // so the forced first-sync that follows pulls all-branch transactions.
      acquireAdminSession: true,
    );

    if (!mounted) return;

    if (result.isSuccess) {
      // Wipe password from memory before popping.
      _passwordCtl.clear();
      Navigator.of(context).pop(true);
      return;
    }

    setState(() {
      _busy = false;
      _status = result.message;
      _statusIsError = result.outcome != MirrorPairingOutcome.missingFields;
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title:  Row(
        children: [
          const Icon(PhosphorIconsBold.copy, size: 20),
          const SizedBox(width: 8),
          Text(tr('ربط الجهاز كمرآة')),
        ],
      ),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
             Text(
              tr('وضع المرآة: نسخة محلية متصلة بـ HQ-Server. الكتابة تُرسَل فوراً للسيرفر وتُعرَض على الجهاز. متاح لحساب المدير فقط.'),
              style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _hostCtl,
              enabled: !_busy,
              decoration:  InputDecoration(
                labelText: tr('عنوان HQ-Server'),
                hintText: tr('192.168.1.100 أو https://abc.ngrok-free.app'),
                border: const OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _portCtl,
              enabled: !_busy,
              keyboardType: TextInputType.number,
              decoration:  InputDecoration(
                labelText: tr('المنفذ'),
                hintText: '8080',
                border: const OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _usernameCtl,
              enabled: !_busy,
              decoration:  InputDecoration(
                labelText: tr('اسم المدير على HQ-Server'),
                border: const OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _passwordCtl,
              enabled: !_busy,
              obscureText: true,
              decoration:  InputDecoration(
                labelText: tr('كلمة مرور المدير'),
                border: const OutlineInputBorder(),
                isDense: true,
              ),
            ),
            if (_status != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: _statusIsError
                      ? const Color(0xFFFFEBEE)
                      : const Color(0xFFFFF8E1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  children: [
                    Icon(
                      _statusIsError
                          ? PhosphorIconsBold.warningCircle
                          : PhosphorIconsBold.info,
                      size: 16,
                      color: _statusIsError
                          ? const Color(0xFFC62828)
                          : const Color(0xFFEF6C00),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _status!,
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (_busy) ...[
              const SizedBox(height: 12),
               Row(
                children: [
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    tr('جارٍ الاتصال بـ HQ-Server والتحقق من المدير…'),
                    style: const TextStyle(fontSize: 12),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(false),
          child:  Text(tr('إلغاء')),
        ),
        ElevatedButton.icon(
          onPressed: _busy ? null : _pair,
          icon: const Icon(PhosphorIconsBold.linkSimple, size: 16),
          label:  Text(tr('ربط')),
        ),
      ],
    );
  }
}
