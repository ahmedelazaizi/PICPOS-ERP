import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/widgets/app_toast.dart';
import '../../../services/api/lan_pairing_service.dart';
import '../../../services/network_service.dart';

/// Server-side pairing code dialog. QR rendering is intentionally omitted:
/// the dependency tree has no QR widget package, while the payload remains
/// available for copy/paste into a scanner or support tool.
class LanPairingDialog extends StatelessWidget {
  const LanPairingDialog({super.key, required this.offer, this.service});

  final PairingOffer offer;
  final LanPairingService? service;

  static Future<void> showServer(BuildContext context) async {
    final offer = NetworkService.instance.issueLanPairingCode();
    if (offer == null) {
      if (context.mounted) {
        AppToast.show(context, 'شغّل السيرفر أولاً', type: ToastType.error);
      }
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (_) => LanPairingDialog(
        offer: offer,
        service: NetworkService.instance.lanPairingService,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final remaining = offer.expiresAt.difference(DateTime.now()).inMinutes;
    return AlertDialog(
      title: const Text('إقران جهاز'),
      content: SizedBox(
        width: 430,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('أدخل هذا الرمز في إعدادات الشبكة على الجهاز الجديد.'),
            const SizedBox(height: 16),
            SelectableText(
              offer.code,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 30, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'صالح لمدة ${remaining < 1 ? 1 : remaining} دقائق ولمرة واحدة',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: offer.qrPayload));
                if (context.mounted) {
                  AppToast.show(context, 'تم نسخ بيانات الإقران');
                }
              },
              icon: const Icon(Icons.copy),
              label: const Text('نسخ بيانات QR'),
            ),
            if (service != null) ...[
              const SizedBox(height: 12),
              TextField(
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'مدة المفتاح القديم بالأيام (1–3650)',
                  isDense: true,
                ),
                onSubmitted: (value) async {
                  final days = int.tryParse(value);
                  if (days != null) {
                    await service!.setLegacyTransitionDays(days);
                    if (context.mounted) {
                      AppToast.show(context, 'تم حفظ مدة الانتقال');
                    }
                  }
                },
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: () async {
                  await service!.endLegacyTransition();
                  if (context.mounted) {
                    AppToast.show(context, 'تم إيقاف المفتاح القديم');
                  }
                },
                child: const Text('إنهاء فترة المفتاح القديم الآن'),
              ),
              const SizedBox(height: 18),
              const Text('الأجهزة المقترنة / غير المقترنة',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              FutureBuilder<List<LanPairingDevice>>(
                future: service!.listDevices(),
                builder: (context, snapshot) {
                  final devices = snapshot.data ?? const <LanPairingDevice>[];
                  if (devices.isEmpty) return const Text('لا توجد أجهزة غير مقترنة');
                  return Column(
                    children: devices
                        .map((device) => ListTile(
                              dense: true,
                              title: Text(device.name),
                              subtitle: Text(
                                '${device.deviceId}  ${device.ip ?? ''}  '
                                '${device.isPaired ? 'مقترن' : 'غير مقترن'}',
                              ),
                              trailing: device.isPaired && !device.revoked
                                  ? IconButton(
                                      icon: const Icon(Icons.block),
                                      tooltip: 'إلغاء الإقران',
                                      onPressed: () async {
                                        await service!.revoke(device.deviceId);
                                        if (context.mounted) {
                                          Navigator.pop(context);
                                          await showServer(context);
                                        }
                                      },
                                    )
                                  : null,
                            ))
                        .toList(),
                  );
                },
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('إغلاق')),
      ],
    );
  }
}
