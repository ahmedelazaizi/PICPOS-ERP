import 'package:flutter/material.dart';
import 'package:picpos_erp/core/i18n/tr.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../services/api/lan_pairing_service.dart';
import '../../../services/permission_enforcer.dart';

/// SEC-006 / G-3: the owner's switch for the legacy shared LAN bearer, with
/// the telemetry (device, user-agent, last seen, accepted/refused) that says
/// when it is safe to turn it off. The service re-checks
/// `devices_pair_manage` for [actorUserId].
class LegacyTokenSection extends StatefulWidget {
  const LegacyTokenSection({
    super.key,
    required this.service,
    required this.actorUserId,
  });

  final LanPairingService service;
  final int? actorUserId;

  @override
  State<LegacyTokenSection> createState() => _LegacyTokenSectionState();
}

class _LegacyTokenSectionState extends State<LegacyTokenSection> {
  late Future<_Snapshot> _load = _read();

  Future<_Snapshot> _read() async => _Snapshot(
        await widget.service.legacyTokenEnabled(),
        await widget.service.legacyUsage(),
        LegacyTokenTelemetry.instance.attempts,
      );

  Future<void> _toggle(bool on) async {
    try {
      await widget.service
          .setLegacyTokenEnabled(on, actorUserId: widget.actorUserId);
      if (mounted) AppToast.show(context, tr('تم تحديث إعداد المفتاح القديم'));
    } on PermissionDeniedException catch (e) {
      if (mounted) AppToast.show(context, e.message, type: ToastType.error);
    }
    if (mounted) {
      setState(() {
        _load = _read();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_Snapshot>(
      future: _load,
      builder: (context, snap) {
        final s = snap.data;
        if (s == null) return const SizedBox.shrink();
        final theme = Theme.of(context);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SwitchListTile(
              key: const Key('legacy_token_toggle'),
              contentPadding: EdgeInsets.zero,
              title: Text(tr('المفتاح المشترك القديم للشبكة')),
              subtitle: Text(s.enabled
                  ? tr('مفعّل: الأجهزة غير المقترنة تعمل به')
                  : tr('مُعطَّل: يُرفض بخطأ 401')),
              value: s.enabled,
              onChanged: _toggle,
            ),
            if (s.enabled && s.usage.inUse)
              Text(
                tr('تحذير: {p0} جهاز ما زال يعمل بالمفتاح القديم وسينقطع عند الإيقاف',
                    {'p0': s.usage.deviceCount}),
                key: const Key('legacy_token_warning'),
                style: const TextStyle(color: AppColors.warning),
              ),
            if (s.attempts.isEmpty)
              Text(tr('لا توجد محاولات بالمفتاح القديم منذ تشغيل السيرفر'),
                  style: theme.textTheme.bodySmall)
            else
              for (final a in s.attempts.take(10))
                ListTile(
                  key: Key('legacy_attempt_${a.deviceId}'),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(a.name.isEmpty ? a.deviceId : a.name),
                  subtitle: Text(
                    '${a.deviceId} · ${a.ip} · ${a.userAgent}\n'
                    '${tr('آخر ظهور')}: ${a.lastSeen?.toLocal().toString().split('.').first ?? '-'}',
                  ),
                  isThreeLine: true,
                  trailing: Text(tr('مقبول {p0} · مرفوض {p1}',
                      {'p0': a.accepted, 'p1': a.refused})),
                ),
          ],
        );
      },
    );
  }
}

class _Snapshot {
  const _Snapshot(this.enabled, this.usage, this.attempts);
  final bool enabled;
  final LegacyUsage usage;
  final List<LegacyAttempt> attempts;
}
