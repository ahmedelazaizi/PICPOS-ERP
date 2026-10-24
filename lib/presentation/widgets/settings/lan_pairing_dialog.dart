import 'package:picpos_erp/core/i18n/tr.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/app_toast.dart';
import '../../../data/providers/auth_providers.dart';
import '../../../services/permission_enforcer.dart';
import '../../../services/api/lan_pairing_service.dart';
import '../../../services/network_service.dart';
import 'lan_transport_section.dart';

/// Server-side pairing code dialog. QR rendering is intentionally omitted:
/// the dependency tree has no QR widget package, while the payload remains
/// available for copy/paste into a scanner or support tool.
class LanPairingDialog extends StatelessWidget {
  const LanPairingDialog({super.key, required this.offer, this.service, this.actorUserId});

  final PairingOffer offer;
  final LanPairingService? service;

  /// The signed-in user; the service re-checks devices_pair_manage for them.
  final int? actorUserId;

  static Future<void> showServer(BuildContext context) async {
    final actor = ProviderScope.containerOf(context).read(authProvider).user?.id;
    PairingOffer? issued;
    try {
      issued = await NetworkService.instance.issueLanPairingCode(actorUserId: actor);
    } on PermissionDeniedException catch (e) {
      if (context.mounted) AppToast.show(context, e.message, type: ToastType.error);
      return;
    }
    final offer = issued;
    if (offer == null) {
      if (context.mounted) {
        AppToast.show(context, tr('شغّل السيرفر أولاً'), type: ToastType.error);
      }
      return;
    }
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (_) => LanPairingDialog(
        offer: offer,
        service: NetworkService.instance.lanPairingService,
        actorUserId: actor,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final remaining = offer.expiresAt.difference(DateTime.now()).inMinutes;
    return AlertDialog(
      title:  Text(tr('إقران جهاز')),
      content: SizedBox(
        width: 430,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
             Text(tr('أدخل هذا الرمز في إعدادات الشبكة على الجهاز الجديد.')),
            const SizedBox(height: 16),
            SelectableText(
              offer.code,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 30, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              tr('صالح لمدة {p0} دقائق ولمرة واحدة', {'p0': remaining < 1 ? 1 : remaining}),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: offer.qrPayload));
                if (context.mounted) {
                  AppToast.show(context, tr('تم نسخ بيانات الإقران'));
                }
              },
              icon: const Icon(Icons.copy),
              label:  Text(tr('نسخ بيانات QR')),
            ),
            const LanTransportSection(),
            if (service != null) ...[
              const SizedBox(height: 12),
              TextField(
                keyboardType: TextInputType.number,
                decoration:  InputDecoration(
                  labelText: tr('مدة المفتاح القديم بالأيام (1–3650)'),
                  isDense: true,
                ),
                onSubmitted: (value) async {
                  final days = int.tryParse(value);
                  if (days != null) {
                    await service!.setLegacyTransitionDays(days);
                    if (context.mounted) {
                      AppToast.show(context, tr('تم حفظ مدة الانتقال'));
                    }
                  }
                },
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: () async {
                  await service!.endLegacyTransition();
                  if (context.mounted) {
                    AppToast.show(context, tr('تم إيقاف المفتاح القديم'));
                  }
                },
                child:  Text(tr('إنهاء فترة المفتاح القديم الآن')),
              ),
              const SizedBox(height: 18),
               Text(tr('الأجهزة المقترنة / غير المقترنة'),
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              FutureBuilder<List<LanPairingDevice>>(
                future: service!.listDevices(),
                builder: (context, snapshot) {
                  final devices = snapshot.data ?? const <LanPairingDevice>[];
                  if (devices.isEmpty) return  Text(tr('لا توجد أجهزة غير مقترنة'));
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
                                      tooltip: tr('إلغاء الإقران'),
                                      onPressed: () async {
                                        await service!.revoke(device.deviceId, actorUserId: actorUserId);
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
        TextButton(onPressed: () => Navigator.pop(context), child:  Text(tr('إغلاق'))),
      ],
    );
  }
}
