import 'package:ural_erp/core/i18n/tr.dart';
// ---------------------------------------------------------------------------
// الإعدادات › الأمان › «الأجهزة المرتبطة» (PicPos وحدَه).
//
// شكوى المالك: «التطبيق ليس به ربط أجهزة خارجية». الربطُ موجودٌ لكنّه
// متفرّق: اقترانُ الشبكة المحلّية تحت «إدارة البيانات › الربط بين الفروع
// والسيرفر»، وربطُ تطبيق المندوب تحت «التكاملات والخدمات»، ورموزُ اقتران
// المناديب من ملفّ الموظف. هذا القسمُ **واجهةٌ تجمعها ولا تنسخ منطقَها**:
//
//   • أجهزةُ الشبكة المحلّية — سجلُّ `lan_paired_devices` عبر
//     `LanPairingService` (‏`listDevices`/`revoke`)، و«اقتران جهاز جديد»
//     هو `LanPairingDialog.showServer` نفسُه، وحوارُ وضع الشبكة يُمرَّر من
//     شاشة الإعدادات (‏`_NetworkModeSettings` خاصٌّ بمكتبتها).
//   • تطبيقُ المندوب — `CloudLinkController` (‏الحالة، وأجهزةُ المناديب عبر
//     `GET /desktop/devices`، والإلغاءُ عبر `POST /desktop/devices/<id>/revoke`)،
//     وإصدارُ الرمز هو مسارُ لوحة المندوب نفسُه (`showRepPairingCodeFlow`).
//   • تطبيقا الإدارة والكاشير — بطاقةٌ إعلاميّةٌ بلا أفعال (M-1/M-5).
//
// الحارسُ حارسُ `CloudLinkSettingsBlock`: `system_admin` أو `*`؛ وغيرُه
// يرى إشعاراً للعرض فقط.
// ---------------------------------------------------------------------------

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/app_error_handler.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../data/providers/auth_providers.dart';
import '../../../domain/models/hr_employee_file.dart';
import '../../../services/api/lan_paired_devices_provider.dart';
import '../../../services/api/lan_pairing_service.dart';
import '../../../services/cloud_sync/cloud_link_api.dart';
import '../../../services/cloud_sync/cloud_link_controller.dart';
import '../../../services/network_service.dart';
import '../../hr_picpos/hr_picpos_providers.dart';
import '../../hr_picpos/widgets/rep_pairing_flow.dart';
import '../../picpos_shell/picpos_dialog.dart';
import '../../picpos_shell/picpos_surface.dart';
import '../../widgets/settings/lan_pairing_dialog.dart';
import '../widgets/cloud_link_settings_block.dart';
import '../widgets/settings_blocks.dart';
import 'cloud_link_settings_screen.dart';

/// معرّفُ القسم في عمود الإعدادات.
const linkedDevicesSectionId = 'linked_devices';

String linkedDevicesSectionTitle() => tr('الأجهزة المرتبطة');

String linkedDevicesSectionDesc() => tr('الكاشير · الفروع · تطبيق المندوب');

/// كلماتُ البحث — «ربط/أجهزة/اقتران/موبايل/تابلت/مندوب/كاشير/سحابة» تجده.
String linkedDevicesSectionKeywords() => tr(
    'ربط أجهزة جهاز اقتران إقران موبايل تابلت هاتف مندوب مناديب كاشير سحابة شبكة فروع سيرفر إلغاء الربط رمز');

String _fmt(DateTime? t) =>
    t == null ? '—' : DateFormat('yyyy-MM-dd HH:mm').format(t);

bool _isAdmin(WidgetRef ref) =>
    ref.watch(currentUserPermissionsProvider).maybeWhen(
          data: (codes) => codes.contains('system_admin') || codes.contains('*'),
          orElse: () => false,
        );

/// محتوى القسم كلُّه. [onOpenNetworkMode] يفتح حوارَ وضع الشبكة القائم.
class LinkedDevicesSection extends ConsumerWidget {
  const LinkedDevicesSection({super.key, required this.onOpenNetworkMode});

  final VoidCallback onOpenNetworkMode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!_isAdmin(ref)) {
      return SettingsBlockGrid(
        blocks: [
          SettingsBlockSpan(
            span: 12,
            child: SettingsBlock(
              key: const Key('ld_read_only'),
              title: tr('الأجهزة المرتبطة'),
              subtitle: tr('للعرض فقط — ربط الأجهزة وإلغاؤه لمدير النظام وحده'),
              tint: AppColors.info,
              child: const SizedBox.shrink(),
            ),
          ),
        ],
      );
    }
    return SettingsBlockGrid(
      blocks: [
        SettingsBlockSpan(
          span: 12,
          child: SettingsBlock(
            title: tr('أجهزة الشبكة المحلية (كاشير/فروع)'),
            subtitle: tr('أجهزةٌ تتصل بهذا الجهاز عبر الشبكة المحلية'),
            tint: AppColors.primary,
            child: _LanDevicesBody(onOpenNetworkMode: onOpenNetworkMode),
          ),
        ),
        SettingsBlockSpan(
          span: 12,
          child: SettingsBlock(
            title: tr('تطبيق المندوب (السحابة)'),
            subtitle: tr('هواتف المناديب المقترنة عبر الربط السحابي'),
            tint: AppColors.info,
            child: const _CloudDevicesBody(),
          ),
        ),
        SettingsBlockSpan(
          span: 12,
          child: SettingsBlock(
            key: const Key('ld_coming_soon'),
            title: tr('تطبيقات الإدارة والكاشير (قريبًا)'),
            subtitle: tr('موبايل وتابلت'),
            tint: AppColors.warning,
            child: Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(18, 0, 18, 16),
              child: Text(
                tr('تطبيقا الإدارة (M-1) والكاشير (M-5) للموبايل والتابلت قيد التطوير، وسيظهر ربطهما هنا عند صدورهما.'),
                style: TextStyle(fontSize: 12.5, color: context.picposMuted),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// 1. الشبكة المحلية
// ═══════════════════════════════════════════════════════════════════════════

class _LanDevicesBody extends ConsumerStatefulWidget {
  const _LanDevicesBody({required this.onOpenNetworkMode});
  final VoidCallback onOpenNetworkMode;

  @override
  ConsumerState<_LanDevicesBody> createState() => _LanDevicesBodyState();
}

class _LanDevicesBodyState extends ConsumerState<_LanDevicesBody> {
  late Future<List<LanPairingDevice>> _devices = _load();

  Future<List<LanPairingDevice>> _load() async {
    final all = await ref.read(lanPairedDevicesServiceProvider).listDevices();
    return [for (final d in all) if (d.isPaired) d];
  }

  void _reload() => setState(() => _devices = _load());

  Future<void> _revoke(LanPairingDevice device) async {
    final ok = await showPicPosConfirm(
      context,
      icon: PhosphorIconsBold.linkBreak,
      title: tr('إلغاء الربط'),
      message: tr('سيتوقف الجهاز «{name}» عن الاتصال بهذا الجهاز حتى يُقرن من جديد.',
          {'name': device.name.isEmpty ? device.deviceId : device.name}),
      confirmLabel: tr('إلغاء الربط'),
      danger: true,
    );
    if (!ok || !mounted) return;
    try {
      await ref.read(lanPairedDevicesServiceProvider).revoke(device.deviceId);
      if (!mounted) return;
      AppToast.show(context, tr('تم إلغاء ربط الجهاز'));
      _reload();
    } catch (e, st) {
      if (mounted) AppErrorHandler.handle(context, e, st);
    }
  }

  Future<void> _openNetworkMode() async {
    widget.onOpenNetworkMode();
  }

  @override
  Widget build(BuildContext context) {
    final ns = NetworkService.instance;
    final mode = ns.mode;
    final modeLabel = switch (mode) {
      NetworkMode.server => tr('سيرفر رئيسي'),
      NetworkMode.client => tr('عميل مرتبط'),
      NetworkMode.mirror => tr('مرآة'),
      NetworkMode.standalone => tr('مستقل'),
    };
    final address = switch (mode) {
      NetworkMode.server => ns.isServerRunning
          ? ns.buildServerUrl()
          : tr('السيرفر متوقف — المنفذ {port}', {'port': ns.serverPort}),
      NetworkMode.client || NetworkMode.mirror =>
        (ns.serverAddress ?? '').isEmpty
            ? tr('لم يُحدَّد عنوان السيرفر')
            : '${ns.serverAddress}:${ns.serverPort}',
      NetworkMode.standalone => tr('لا ربط شبكي — جهاز مستقل'),
    };
    final canPair = mode == NetworkMode.server && ns.isServerRunning;
    return SettingsRowsBody(
      children: [
        SettingsValueRow(
          key: const Key('ld_lan_mode'),
          first: true,
          icon: PhosphorIconsBold.wifiHigh,
          title: tr('وضع هذا الجهاز'),
          sub: address,
          value: modeLabel,
          tint: AppColors.primary,
          onTap: _openNetworkMode,
        ),
        const SizedBox(height: 4),
        _ListTitle(text: tr('الأجهزة المقترنة')),
        FutureBuilder<List<LanPairingDevice>>(
          future: _devices,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const _Loading();
            }
            if (snap.hasError) {
              return _Muted(text: tr('تعذّر قراءة سجل الأجهزة المقترنة'));
            }
            final devices = snap.data ?? const <LanPairingDevice>[];
            if (devices.isEmpty) {
              return _Muted(text: tr('لا أجهزة مقترنة بعد'));
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final d in devices)
                  _DeviceRow(
                    key: Key('ld_lan_${d.deviceId}'),
                    icon: PhosphorIconsBold.desktop,
                    title: d.name.isEmpty ? d.deviceId : d.name,
                    sub: [
                      tr('آخر ظهور: {t}', {'t': _fmt(d.lastSeenAt)}),
                      tr('اقترن: {t}', {'t': _fmt(d.pairedAt)}),
                    ].join(' · '),
                    revoked: d.revoked,
                    revokeKey: Key('ld_lan_revoke_${d.deviceId}'),
                    onRevoke: () => _revoke(d),
                  ),
              ],
            );
          },
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 10,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            FilledButton.icon(
              key: const Key('ld_lan_pair'),
              onPressed: !canPair
                  ? null
                  : () async {
                      await LanPairingDialog.showServer(context);
                      if (mounted) _reload();
                    },
              icon: const Icon(PhosphorIconsBold.plus, size: 16),
              label: Text(tr('اقتران جهاز جديد')),
            ),
            OutlinedButton.icon(
              key: const Key('ld_network_mode'),
              onPressed: _openNetworkMode,
              icon: const Icon(PhosphorIconsBold.wifiHigh, size: 16),
              label: Text(tr('إعدادات الشبكة والربط')),
            ),
          ],
        ),
        if (!canPair)
          Padding(
            padding: const EdgeInsets.only(top: 6, bottom: 10),
            child: _Muted(
                text: tr('الاقتران متاح حين يعمل هذا الجهاز سيرفراً — شغّله من إعدادات الشبكة والربط.')),
          )
        else
          const SizedBox(height: 10),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// 2. تطبيق المندوب (السحابة)
// ═══════════════════════════════════════════════════════════════════════════

class _CloudDevicesBody extends ConsumerStatefulWidget {
  const _CloudDevicesBody();

  @override
  ConsumerState<_CloudDevicesBody> createState() => _CloudDevicesBodyState();
}

class _CloudDevicesBodyState extends ConsumerState<_CloudDevicesBody> {
  late Future<CloudLinkView> _status = _loadStatus();
  late Future<List<CloudRepDeviceView>?> _devices = _loadDevices();

  CloudLinkController get _controller => ref.read(cloudLinkControllerProvider);

  Future<CloudLinkView> _loadStatus() => _controller.load(includeSecret: false);
  Future<List<CloudRepDeviceView>?> _loadDevices() => _controller.listRepDevices();

  void _reload() => setState(() {
        _status = _loadStatus();
        _devices = _loadDevices();
      });

  Future<void> _openCloudSettings() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const CloudLinkSettingsScreen()),
    );
    if (mounted) _reload();
  }

  Future<void> _revoke(CloudRepDeviceView device) async {
    final ok = await showPicPosConfirm(
      context,
      icon: PhosphorIconsBold.linkBreak,
      title: tr('إلغاء الربط'),
      message: tr('سيُسجَّل خروج تطبيق المندوب على هذا الهاتف وتُمسح بياناته المحلية، ولن يعمل حتى يُقرن برمز جديد.'),
      confirmLabel: tr('إلغاء الربط'),
      danger: true,
    );
    if (!ok || !mounted) return;
    try {
      await _controller.revokeRepDevice(device.deviceId);
      if (!mounted) return;
      AppToast.show(context, tr('تم إلغاء ربط الجهاز'));
      _reload();
    } catch (e, st) {
      if (mounted) AppErrorHandler.handle(context, e, st);
    }
  }

  Future<void> _issueForRep() async {
    final gid = await showDialog<String>(
      context: context,
      builder: (_) => const _RepPickerDialog(),
    );
    if (gid == null || !mounted) return;
    await showRepPairingCodeFlow(context, _controller, gid);
    if (mounted) _reload();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<CloudLinkView>(
      future: _status,
      builder: (context, snap) {
        final v = snap.data;
        final enabled = v?.enabled ?? false;
        return SettingsRowsBody(
          children: [
            SettingsValueRow(
              key: const Key('ld_cloud_status'),
              first: true,
              icon: PhosphorIconsBold.cloud,
              title: tr('ربط الشركة بالسحابة'),
              sub: v == null
                  ? null
                  : enabled
                      ? (v.url.isEmpty ? tr('لم يُحدَّد عنوان السيرفر') : v.url)
                      : tr('فعّل الربط السحابي لإدارة هواتف المناديب'),
              value: v == null
                  ? null
                  : enabled
                      ? tr('مفعّل')
                      : tr('غير مفعّل'),
              tint: enabled ? AppColors.success : AppColors.textMuted,
              onTap: _openCloudSettings,
            ),
            if (v != null && enabled)
              SettingsValueRow(
                key: const Key('ld_cloud_sync'),
                icon: PhosphorIconsBold.arrowsClockwise,
                title: tr('المزامنة'),
                sub: cloudLinkStatusLine(v),
                value: tr('مُرحَّلة: {p} · تعارضات: {c}',
                    {'p': v.posted, 'c': v.conflicts.length}),
                tint: v.conflicts.isNotEmpty ? AppColors.warning : AppColors.info,
                onTap: _openCloudSettings,
              ),
            if (v != null && enabled) ...[
              const SizedBox(height: 4),
              _ListTitle(text: tr('هواتف المناديب المقترنة')),
              _cloudDevices(),
            ],
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  key: const Key('ld_rep_issue'),
                  onPressed: enabled ? _issueForRep : null,
                  icon: const Icon(PhosphorIconsBold.deviceMobile, size: 16),
                  label: Text(tr('إصدار رمز اقتران لمندوب')),
                ),
                OutlinedButton.icon(
                  key: const Key('ld_cloud_settings'),
                  onPressed: _openCloudSettings,
                  icon: const Icon(PhosphorIconsBold.gear, size: 16),
                  label: Text(tr('إعدادات الربط السحابي')),
                ),
              ],
            ),
            const SizedBox(height: 14),
          ],
        );
      },
    );
  }

  Widget _cloudDevices() => FutureBuilder<List<CloudRepDeviceView>?>(
        future: _devices,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const _Loading();
          }
          if (snap.hasError) {
            final e = snap.error;
            final reason = e is CloudLinkException ? e.code : '$e';
            return _Muted(
                key: const Key('ld_cloud_error'),
                text: tr('تعذّر جلب هواتف المناديب من السحابة: {e}', {'e': reason}));
          }
          final devices = snap.data ?? const <CloudRepDeviceView>[];
          if (devices.isEmpty) {
            return _Muted(text: tr('لا هواتف مناديب مقترنة بعد'));
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final d in devices)
                _DeviceRow(
                  key: Key('ld_cloud_${d.deviceId}'),
                  icon: PhosphorIconsBold.deviceMobile,
                  title: [
                    d.employeeName ?? tr('مندوب'),
                    if ((d.deviceName ?? '').isNotEmpty) d.deviceName!,
                  ].join(' · '),
                  sub: [
                    tr('آخر ظهور: {t}', {'t': _fmt(d.lastSeenAt)}),
                    tr('اقترن: {t}', {'t': _fmt(d.pairedAt)}),
                  ].join(' · '),
                  revoked: d.revoked,
                  revokeKey: Key('ld_cloud_revoke_${d.deviceId}'),
                  onRevoke: () => _revoke(d),
                ),
            ],
          );
        },
      );
}

/// اختيارُ مندوبٍ (‏موظّفٌ نشطٌ بوسم «مندوب» وله معرّفٌ عام) لإصدار رمزه.
class _RepPickerDialog extends ConsumerStatefulWidget {
  const _RepPickerDialog();

  @override
  ConsumerState<_RepPickerDialog> createState() => _RepPickerDialogState();
}

class _RepPickerDialogState extends ConsumerState<_RepPickerDialog> {
  String? _gid;

  @override
  Widget build(BuildContext context) {
    final profiles = ref.watch(hrProfilesProvider);
    final reps = [
      for (final p in profiles.value ?? const <EmployeeProfile>[])
        if (p.isRep && p.isActive && (p.globalId ?? '').isNotEmpty) p,
    ];
    return PicPosDialog(
      icon: PhosphorIconsBold.deviceMobile,
      title: tr('إصدار رمز اقتران لمندوب'),
      width: 520,
      onCancel: () => Navigator.pop(context),
      primaryAction: PicPosDialogAction(
        label: tr('متابعة'),
        onPressed: _gid == null ? null : () => Navigator.pop(context, _gid),
      ),
      body: [
        if (profiles.isLoading)
          const _Loading()
        else if (reps.isEmpty)
          _Muted(
              key: const Key('ld_rep_none'),
              text: tr('لا مناديب نشطون — حدّد وسم «مندوب» في ملف الموظف من شؤون الموظفين.'))
        else
          DropdownButtonFormField<String>(
            key: const Key('ld_rep_picker'),
            initialValue: _gid,
            isExpanded: true,
            decoration: InputDecoration(labelText: tr('المندوب')),
            items: [
              for (final r in reps)
                DropdownMenuItem(
                  value: r.globalId,
                  child: Text(trData(r.name), overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: (v) => setState(() => _gid = v),
          ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// قطعٌ مشتركة
// ═══════════════════════════════════════════════════════════════════════════

class _DeviceRow extends StatelessWidget {
  const _DeviceRow({
    super.key,
    required this.icon,
    required this.title,
    required this.sub,
    required this.revoked,
    required this.revokeKey,
    required this.onRevoke,
  });

  final IconData icon;
  final String title;
  final String sub;
  final bool revoked;
  final Key revokeKey;
  final VoidCallback onRevoke;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsetsDirectional.fromSTEB(12, 8, 8, 8),
      decoration: BoxDecoration(
        color: context.picposField,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(children: [
        Icon(icon,
            size: 18,
            color: revoked ? context.picposMuted : context.picposBrandInk),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: revoked ? context.picposMuted : context.picposText)),
              const SizedBox(height: 2),
              Text(sub,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11.5, color: context.picposMuted)),
            ],
          ),
        ),
        const SizedBox(width: 8),
        if (revoked)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.error.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(tr('ملغى'),
                style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                    color: AppColors.error)),
          )
        else
          TextButton.icon(
            key: revokeKey,
            onPressed: onRevoke,
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            icon: const Icon(PhosphorIconsBold.linkBreak, size: 15),
            label: Text(tr('إلغاء الربط')),
          ),
      ]),
    );
  }
}

class _ListTitle extends StatelessWidget {
  const _ListTitle({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 6, bottom: 8),
        child: Text(text,
            style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
                color: context.picposText)),
      );
}

class _Muted extends StatelessWidget {
  const _Muted({super.key, required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Text(text,
            style: TextStyle(fontSize: 12, color: context.picposMuted)),
      );
}

class _Loading extends StatelessWidget {
  const _Loading();

  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Center(
          child: SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2)),
        ),
      );
}
