// «PicPos مخازن» card of the linked-devices section (plan 2026-10-23, W1):
// pair a warehouse phone to ONE branch (QR v2 + one-time code), list the
// paired warehouse phones and revoke them. Every action goes through
// `LanPairingService`, which enforces `devices_pair_manage` itself; the UI
// only reflects the outcome.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:picpos_erp/core/i18n/tr.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../core/utils/app_error_handler.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../data/providers/auth_providers.dart';
import '../../../services/api/lan_paired_devices_provider.dart';
import '../../../services/api/lan_pairing_service.dart';
import '../../../services/network_service.dart';
import '../../picpos_shell/picpos_dialog.dart';

class WarehouseDevicesBody extends ConsumerStatefulWidget {
  const WarehouseDevicesBody({super.key});

  @override
  ConsumerState<WarehouseDevicesBody> createState() => _WarehouseDevicesBodyState();
}

class _WarehouseDevicesBodyState extends ConsumerState<WarehouseDevicesBody> {
  late Future<List<LanPairingDevice>> _devices = _load();

  int? get _actor => ref.read(authProvider).user?.id;

  Future<List<LanPairingDevice>> _load() async {
    final all = await ref.read(lanPairedDevicesServiceProvider).listDevicesFor(_actor);
    return [
      for (final d in all)
        if (d.isPaired && d.deviceKind == 'warehouse') d,
    ];
  }

  void _reload() => setState(() => _devices = _load());

  Future<void> _pair() async {
    final branches = await ref.read(userAccessibleBranchesProvider.future);
    if (!mounted) return;
    final branchId = await showDialog<int>(
      context: context,
      builder: (_) => SimpleDialog(
        title: Text(tr('اختر فرع الهاتف')),
        children: [
          for (final b in branches)
            SimpleDialogOption(
              key: Key('wd_branch_${b.id}'),
              onPressed: () => Navigator.pop(context, b.id),
              child: Text(b.name),
            ),
        ],
      ),
    );
    if (branchId == null || !mounted) return;
    try {
      final offer = await NetworkService.instance.issueLanPairingCode(
        actorUserId: _actor,
        deviceKind: 'warehouse',
        branchId: branchId,
      );
      if (!mounted) return;
      if (offer == null) {
        AppToast.show(context, tr('شغّل السيرفر أولاً'), type: ToastType.error);
        return;
      }
      await showDialog<void>(context: context, builder: (_) => _OfferDialog(offer: offer));
      if (mounted) _reload();
    } on StateError {
      if (!mounted) return;
      AppToast.show(context,
          tr('تطبيق المخازن يتطلب اتصالاً مشفّراً (TLS) على السيرفر — فعّله من إعدادات الشبكة'),
          type: ToastType.error);
    } catch (e, st) {
      if (mounted) AppErrorHandler.handle(context, e, st);
    }
  }

  Future<void> _revoke(LanPairingDevice d) async {
    final ok = await showPicPosConfirm(
      context,
      icon: Icons.link_off,
      title: tr('إلغاء الربط'),
      message: tr('سيُمسح هاتف المخازن «{name}» من بياناته المحلية عند أول اتصال.',
          {'name': d.name.isEmpty ? d.deviceId : d.name}),
      confirmLabel: tr('إلغاء الربط'),
      danger: true,
    );
    if (!ok || !mounted) return;
    try {
      await NetworkService.instance.revokeLanDevice(d.deviceId, actorUserId: _actor);
      if (!mounted) return;
      AppToast.show(context, tr('تم إلغاء ربط الجهاز'));
      _reload();
    } catch (e, st) {
      if (mounted) AppErrorHandler.handle(context, e, st);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ns = NetworkService.instance;
    final canPair = ns.mode == NetworkMode.server && ns.isServerRunning;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      FutureBuilder<List<LanPairingDevice>>(
        future: _devices,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) return const LinearProgressIndicator();
          if (snap.hasError) return Text(tr('تعذّر قراءة سجل الأجهزة المقترنة'));
          final devices = snap.data ?? const <LanPairingDevice>[];
          if (devices.isEmpty) return Text(tr('لا أجهزة مقترنة بعد'));
          return Column(children: [
            for (final d in devices)
              ListTile(
                key: Key('wd_${d.deviceId}'),
                dense: true,
                title: Text(d.name.isEmpty ? d.deviceId : d.name),
                subtitle: Text(tr('الفرع: {b}', {'b': d.branchId ?? '—'})),
                trailing: d.revoked
                    ? Text(tr('مُلغى'))
                    : IconButton(
                        key: Key('wd_revoke_${d.deviceId}'),
                        icon: const Icon(Icons.link_off),
                        tooltip: tr('إلغاء الربط'),
                        onPressed: () => _revoke(d),
                      ),
              ),
          ]);
        },
      ),
      const SizedBox(height: 8),
      Align(
        alignment: AlignmentDirectional.centerStart,
        child: FilledButton.icon(
          key: const Key('wd_pair'),
          onPressed: canPair ? _pair : null,
          icon: const Icon(Icons.qr_code_2, size: 16),
          label: Text(tr('إقران هاتف مخازن')),
        ),
      ),
    ]);
  }
}

class _OfferDialog extends StatelessWidget {
  const _OfferDialog({required this.offer});
  final PairingOffer offer;

  @override
  Widget build(BuildContext context) => PicPosDialog(
        icon: Icons.qr_code_2,
        title: tr('إقران هاتف مخازن'),
        width: 420,
        body: [
          Text(tr('امسح الرمز من تطبيق PicPos مخازن، أو أدخل الرمز يدوياً. صالح 10 دقائق ولمرة واحدة.')),
          const SizedBox(height: 12),
          // The QR must stay black-on-white to scan, in light and dark themes alike.
          Center(
            child: QrImageView(data: offer.qrPayload, size: 220, backgroundColor: Colors.white), // dark-ok: QR needs white
          ),
          const SizedBox(height: 8),
          Center(
            child: SelectableText(offer.code,
                textDirection: TextDirection.ltr,
                style: Theme.of(context).textTheme.headlineSmall),
          ),
        ],
        cancelLabel: tr('إغلاق'),
        onCancel: () => Navigator.pop(context),
      );
}