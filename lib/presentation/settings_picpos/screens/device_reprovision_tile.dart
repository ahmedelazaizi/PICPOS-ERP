// A1 (adoption contract §C.7-6): "Settings > Device > Re-provision this device"
// - the ONE way to change a device's mode after the first run. The mode chips of
// the network settings are display-only.
//
// Allowed only for a user with `settings_edit`, and ONLINE for a client / mirror
// (their pairing must be re-issued by the main). The decision is passed in
// ([allowed], [offlineBlocked]) so the widget is testable without providers.
import 'dart:io' show exit;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/tr.dart';
import '../../../core/permissions/permission_codes.dart';
import '../../../data/providers/providers.dart';
import '../../../services/network_service.dart';
import '../../picpos_shell/picpos_surface.dart';
import '../../screens/first_run/provisioning_providers.dart';
import '../../screens/first_run/reprovision_confirm_dialog.dart';

String deviceModeLabel(NetworkMode m) => switch (m) {
      NetworkMode.standalone => tr('مستقل'),
      NetworkMode.server => tr('سيرفر'),
      NetworkMode.client => tr('عميل'),
      NetworkMode.mirror => tr('مرآة'),
    };

/// The tile wired to the live providers (mode, `settings_edit`, connection).
class DeviceReprovisionSection extends ConsumerWidget {
  const DeviceReprovisionSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(syncRepositoryProvider).mode;
    final networked = mode == NetworkMode.client || mode == NetworkMode.mirror;
    return DeviceReprovisionTile(
      mode: mode,
      allowed:
          ref.watch(hasPermissionProvider(PermissionCodes.settingsEdit)).value ??
              false,
      offlineBlocked: networked && !ref.watch(serverConnectionLiveProvider),
    );
  }
}

class DeviceReprovisionTile extends ConsumerStatefulWidget {
  const DeviceReprovisionTile({
    super.key,
    required this.mode,
    required this.allowed,
    this.offlineBlocked = false,
    this.onRestart,
  });

  final NetworkMode mode;

  /// The signed-in user holds `settings_edit`.
  final bool allowed;

  /// A client / mirror that cannot reach the main right now.
  final bool offlineBlocked;
  final VoidCallback? onRestart;

  @override
  ConsumerState<DeviceReprovisionTile> createState() =>
      _DeviceReprovisionTileState();
}

class _DeviceReprovisionTileState extends ConsumerState<DeviceReprovisionTile> {
  bool _done = false;

  Future<void> _run() async {
    if (!await confirmReprovision(context)) return;
    await ref.read(provisioningActionsProvider).reprovision();
    if (mounted) setState(() => _done = true);
  }

  @override
  Widget build(BuildContext context) {
    final blocked = !widget.allowed || widget.offlineBlocked;
    return Container(
      key: const Key('device_reprovision_tile'),
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.picposCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.picposHairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            tr('وضع تشغيل هذا الجهاز: {p0}', {'p0': deviceModeLabel(widget.mode)}),
            key: const Key('device_reprovision_mode'),
            style: TextStyle(
              fontWeight: FontWeight.w800,
              color: context.picposText,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            tr('يُغيَّر الوضع من خيار واحد فقط: إعادة توفير هذا الجهاز، ثم يعود الإعداد الأول بعد إعادة التشغيل.'),
            style: TextStyle(color: context.picposMuted, fontSize: 12.5),
          ),
          const SizedBox(height: 10),
          if (_done) ...[
            Text(
              tr('تمت إعادة التوفير. أعد تشغيل البرنامج لبدء الإعداد من جديد.'),
              key: const Key('device_reprovision_done'),
              style: TextStyle(color: context.picposText),
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              key: const Key('device_reprovision_restart'),
              onPressed: widget.onRestart ?? () => exit(0),
              icon: const Icon(Icons.restart_alt),
              label: Text(tr('إعادة التشغيل الآن')),
            ),
          ] else ...[
            OutlinedButton.icon(
              key: const Key('device_reprovision_button'),
              onPressed: blocked ? null : _run,
              icon: const Icon(Icons.settings_backup_restore, size: 18),
              label: Text(tr('إعادة توفير هذا الجهاز')),
            ),
            if (!widget.allowed)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  tr('تتطلب صلاحية تعديل الإعدادات.'),
                  key: const Key('device_reprovision_denied'),
                  style: TextStyle(color: context.picposMuted, fontSize: 12),
                ),
              )
            else if (widget.offlineBlocked)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  tr('يلزم الاتصال بالسيرفر الرئيسي لإعادة توفير جهاز عميل أو مرآة.'),
                  key: const Key('device_reprovision_offline'),
                  style: TextStyle(color: context.picposMuted, fontSize: 12),
                ),
              ),
          ],
        ],
      ),
    );
  }
}
