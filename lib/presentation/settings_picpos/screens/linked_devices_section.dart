import 'dart:convert';

import 'package:qr_flutter/qr_flutter.dart';
import 'package:picpos_erp/core/i18n/tr.dart';
// إعدادات ربط PicPos تجمع السحابة والشبكة والتطبيقات دون نسخ تدفّقات الإقران.
// الإجراء للمدير (`system_admin` أو `*`)؛ غيره يرى إشعاراً للعرض فقط.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' hide TextDirection;
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
import '../widgets/database_encryption_block.dart';
import '../widgets/server_security_block.dart';
import '../widgets/settings_blocks.dart';

/// معرّفُ القسم في عمود الإعدادات.
const linkedDevicesSectionId = 'linked_devices';

String linkedDevicesSectionTitle() => tr('ربط التطبيقات والأجهزة');

String linkedDevicesSectionDesc() => tr('السحابة · الشبكة المحلية · تطبيقات PicPos');

String linkedDevicesSectionKeywords() => tr(
  'ربط أجهزة جهاز اقتران إقران موبايل تابلت هاتف مندوب مناديب إدارة كاشير مخازن سحابة شبكة فروع سيرفر TLS إلغاء الربط رمز',
);

String _fmt(DateTime? t) =>
    t == null ? '—' : DateFormat('yyyy-MM-dd HH:mm').format(t);

List<CloudRepDeviceView> _sortedRepDevices(List<CloudRepDeviceView> devices) =>
    [...devices]..sort((a, b) {
      if (a.revoked != b.revoked) return a.revoked ? 1 : -1;
      return (b.lastSeenAt ?? b.pairedAt ?? DateTime(0))
          .compareTo(a.lastSeenAt ?? a.pairedAt ?? DateTime(0));
    });

bool _isAdmin(WidgetRef ref) => ref
    .watch(currentUserPermissionsProvider)
    .maybeWhen(
      data: (codes) => codes.contains('system_admin') || codes.contains('*'),
      orElse: () => false,
    );

/// محتوى القسم كلُّه. [onOpenNetworkMode] يفتح حوارَ وضع الشبكة القائم.
class LinkedDevicesSection extends ConsumerWidget {
  const LinkedDevicesSection({super.key, required this.onOpenNetworkMode});

  final Future<void> Function() onOpenNetworkMode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!_isAdmin(ref)) {
      return SettingsBlockGrid(
        blocks: [
          SettingsBlockSpan(
            span: 12,
            child: SettingsBlock(
              key: const Key('ld_read_only'),
              title: linkedDevicesSectionTitle(),
              subtitle: tr('للعرض فقط — ربط الأجهزة وإلغاؤه لمدير النظام وحده'),
              tint: AppColors.info,
              child: const SizedBox.shrink(),
            ),
          ),
        ],
      );
    }
    return _ConnectionsOverview(onOpenNetworkMode: onOpenNetworkMode);
  }
}

class _ConnectionsOverview extends ConsumerStatefulWidget {
  const _ConnectionsOverview({required this.onOpenNetworkMode});
  final Future<void> Function() onOpenNetworkMode;

  @override
  ConsumerState<_ConnectionsOverview> createState() => _ConnectionsOverviewState();
}

class _ConnectionsOverviewState extends ConsumerState<_ConnectionsOverview> {
  final _cloudKey = GlobalKey();
  final _lanKey = GlobalKey();
  late Future<CloudLinkView> _cloud =
      ref.read(cloudLinkControllerProvider).load(includeSecret: false);

  Future<void> _openNetworkMode() async {
    await widget.onOpenNetworkMode();
    if (mounted) setState(() {});
  }

  void _reloadCloud() => setState(() {
    _cloud = ref.read(cloudLinkControllerProvider).load(includeSecret: false);
  });

  void _scrollTo(GlobalKey key) {
    final target = key.currentContext;
    if (target != null) Scrollable.ensureVisible(target,
        duration: const Duration(milliseconds: 250));
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<CloudLinkView>(
    future: _cloud,
    builder: (context, snapshot) {
      final cloudReady = snapshot.data?.enabled == true;
      final network = NetworkService.instance;
      final lanReady = switch (network.mode) {
        NetworkMode.server => network.isServerRunning,
        NetworkMode.client || NetworkMode.mirror =>
          (network.serverAddress ?? '').isNotEmpty,
        NetworkMode.standalone => false,
      };
      return SettingsBlockGrid(blocks: [
        SettingsBlockSpan(span: 12, child: KeyedSubtree(
          key: _cloudKey, child: CloudLinkSettingsBlock(onSettingsChanged: _reloadCloud))),
        SettingsBlockSpan(span: 12, child: KeyedSubtree(
          key: _lanKey,
          child: SettingsBlock(
            title: tr('الشبكة المحلية'),
            subtitle: tr('وضع الشبكة والأجهزة المقترنة'),
            tint: AppColors.primary,
            child: _LanDevicesBody(onOpenNetworkMode: _openNetworkMode),
          ),
        )),
        SettingsBlockSpan(span: 12, child: SettingsBlock(
          title: tr('التطبيقات'),
          subtitle: tr('تطبيقات PicPos وربط أجهزتها'),
          tint: AppColors.info,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            _appCard(tr('PicPos Van — تطبيق المندوب'), tr('يتطلب السحابة'),
                _CloudDevicesBody(key: ValueKey(cloudReady)),
                cloudReady ? null : _warning(_cloudKey)),
            _appCard(tr('PicPos إدارة — تطبيق الإدارة'), tr('يتطلب السحابة'),
                _AdminDevicesBody(key: ValueKey(cloudReady)),
                cloudReady ? null : _warning(_cloudKey)),
            _appCard(tr('PicPos كاشير'), tr('يتطلب الشبكة المحلية'),
                null, lanReady ? null : _warning(_lanKey)),
            _appCard(tr('PicPos مخازن'), tr('يتطلب الشبكة المحلية'),
                null, lanReady ? null : _warning(_lanKey)),
          ]),
        )),
        const SettingsBlockSpan(span: 12, child: ServerSecurityBlock()),
        const SettingsBlockSpan(span: 12, child: DatabaseEncryptionBlock()),
      ]);
    },
  );

  Widget _warning(GlobalKey destination) => Align(
    alignment: AlignmentDirectional.centerStart,
    child: ActionChip(
      label: Text(tr('الاتصال غير مهيأ — افتح الإعدادات')),
      onPressed: () => _scrollTo(destination),
    ),
  );

  Widget _appCard(String title, String connection, Widget? body,
      Widget? warning) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Container(
      decoration: BoxDecoration(
        color: context.picposField,
        border: Border.all(color: context.picposHairline),
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        Text('$connection · ${warning == null ? tr('مفعّل') : tr('غير مفعّل')}'),
        ?warning,
        if (body == null) Text(tr('قريباً')) else body,
      ]),
    ),
  );
}

// ═══════════════════════════════════════════════════════════════════════════
// 1. الشبكة المحلية
// ═══════════════════════════════════════════════════════════════════════════

class _LanDevicesBody extends ConsumerStatefulWidget {
  const _LanDevicesBody({required this.onOpenNetworkMode});
  final Future<void> Function() onOpenNetworkMode;

  @override
  ConsumerState<_LanDevicesBody> createState() => _LanDevicesBodyState();
}

class _LanDevicesBodyState extends ConsumerState<_LanDevicesBody> {
  late Future<List<LanPairingDevice>> _devices = _load();

  Future<List<LanPairingDevice>> _load() async {
    final all = await ref.read(lanPairedDevicesServiceProvider).listDevices();
    return [
      for (final d in all)
        if (d.isPaired) d,
    ];
  }

  void _reload() => setState(() {
    _devices = _load();
  });

  Future<void> _revoke(LanPairingDevice device) async {
    final ok = await showPicPosConfirm(
      context,
      icon: PhosphorIconsBold.linkBreak,
      title: tr('إلغاء الربط'),
      message: tr(
        'سيتوقف الجهاز «{name}» عن الاتصال بهذا الجهاز حتى يُقرن من جديد.',
        {'name': device.name.isEmpty ? device.deviceId : device.name},
      ),
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
    await widget.onOpenNetworkMode();
    if (mounted) _reload();
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
      NetworkMode.server =>
        ns.isServerRunning
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
          ],
        ),
        if (!canPair)
          Padding(
            padding: const EdgeInsets.only(top: 6, bottom: 10),
            child: _Muted(
              text: tr(
                'الاقتران متاح حين يعمل هذا الجهاز سيرفراً — شغّله من إعدادات الشبكة والربط.',
              ),
            ),
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
  const _CloudDevicesBody({super.key});

  @override
  ConsumerState<_CloudDevicesBody> createState() => _CloudDevicesBodyState();
}

class _CloudDevicesBodyState extends ConsumerState<_CloudDevicesBody> {
  late Future<CloudLinkView> _status = _loadStatus();
  late Future<List<CloudRepDeviceView>?> _devices = _loadDevices();

  CloudLinkController get _controller => ref.read(cloudLinkControllerProvider);

  Future<CloudLinkView> _loadStatus() => _controller.load(includeSecret: false);
  Future<List<CloudRepDeviceView>?> _loadDevices() =>
      _controller.listRepDevices();

  void _reload() => setState(() {
    _status = _loadStatus();
    _devices = _loadDevices();
  });

  Future<void> _revoke(CloudRepDeviceView device) async {
    final ok = await showPicPosConfirm(
      context,
      icon: PhosphorIconsBold.linkBreak,
      title: tr('إلغاء الربط'),
      message: tr(
        'سيُسجَّل خروج تطبيق المندوب على هذا الهاتف وتُمسح بياناته المحلية، ولن يعمل حتى يُقرن برمز جديد.',
      ),
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
            if (v != null && enabled) ...[
              const SizedBox(height: 4),
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
          text: tr('تعذّر جلب هواتف المناديب من السحابة: {e}', {'e': reason}),
        );
      }
      final devices = snap.data ?? const <CloudRepDeviceView>[];
      final sorted = _sortedRepDevices(devices);
      return _CollapsibleDevices(
        title: tr('هواتف المناديب المقترنة'),
        tileKey: const Key('ld_rep_devices'),
        revokedCount: devices.where((d) => d.revoked).length,
        count: devices.length,
        children: [
          if (devices.isEmpty) _Muted(text: tr('لا هواتف مناديب مقترنة بعد')),
          for (final d in sorted.take(8)) _repRow(d),
          if (sorted.length > 8)
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton(
                key: const Key('ld_rep_show_all'),
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => _AllRepDevicesScreen(onRevoke: _revoke),
                  ),
                ),
                child: Text(tr('عرض الكل')),
              ),
            ),
        ],
      );
    },
  );

  Widget _repRow(CloudRepDeviceView d) => _DeviceRow(
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
  );
}

class _AllRepDevicesScreen extends ConsumerStatefulWidget {
  const _AllRepDevicesScreen({required this.onRevoke});
  final Future<void> Function(CloudRepDeviceView) onRevoke;

  @override
  ConsumerState<_AllRepDevicesScreen> createState() => _AllRepDevicesScreenState();
}

class _AllRepDevicesScreenState extends ConsumerState<_AllRepDevicesScreen> {
  late Future<List<CloudRepDeviceView>?> _devices =
      ref.read(cloudLinkControllerProvider).listRepDevices();
  String _query = '';

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(tr('هواتف المناديب المقترنة'))),
    body: FutureBuilder<List<CloudRepDeviceView>?>(
      future: _devices,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) return const _Loading();
        if (snapshot.hasError) {
          return _Muted(text: tr('تعذّر تحميل هواتف المناديب'));
        }
        final devices = _sortedRepDevices(snapshot.data ?? []);
        final filtered = devices.where((d) =>
            '${d.employeeName ?? ''} ${d.deviceName ?? ''}'
                .toLowerCase().contains(_query.toLowerCase())).toList();
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextField(
              onChanged: (query) => setState(() => _query = query),
              decoration: InputDecoration(labelText: tr('بحث باسم المندوب أو الجهاز')),
            ),
            const SizedBox(height: 12),
            for (final d in filtered)
              _DeviceRow(
                icon: PhosphorIconsBold.deviceMobile,
                title: [d.employeeName ?? tr('مندوب'), if ((d.deviceName ?? '').isNotEmpty) d.deviceName!].join(' · '),
                sub: tr('آخر ظهور: {t}', {'t': _fmt(d.lastSeenAt)}),
                revoked: d.revoked,
                revokeKey: Key('ld_all_revoke_${d.deviceId}'),
                onRevoke: () async {
                  await widget.onRevoke(d);
                  if (mounted) setState(() => _devices =
                      ref.read(cloudLinkControllerProvider).listRepDevices());
                },
              ),
          ],
        );
      },
    ),
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
            text: tr(
              'لا مناديب نشطون — حدّد وسم «مندوب» في ملف الموظف من شؤون الموظفين.',
            ),
          )
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
      child: Row(
        children: [
          Icon(
            icon,
            size: 18,
            color: revoked ? context.picposMuted : context.picposBrandInk,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: revoked ? context.picposMuted : context.picposText,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  sub,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11.5, color: context.picposMuted),
                ),
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
              child: Text(
                tr('ملغى'),
                style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                  color: AppColors.error,
                ),
              ),
            )
          else
            TextButton.icon(
              key: revokeKey,
              onPressed: onRevoke,
              style: TextButton.styleFrom(foregroundColor: AppColors.error),
              icon: const Icon(PhosphorIconsBold.linkBreak, size: 15),
              label: Text(tr('إلغاء الربط')),
            ),
        ],
      ),
    );
  }
}

class _ListTitle extends StatelessWidget {
  const _ListTitle({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 6, bottom: 8),
    child: Text(
      text,
      style: TextStyle(
        fontSize: 12.5,
        fontWeight: FontWeight.w800,
        color: context.picposText,
      ),
    ),
  );
}

class _Muted extends StatelessWidget {
  const _Muted({super.key, required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Text(
      text,
      style: TextStyle(fontSize: 12, color: context.picposMuted),
    ),
  );
}

class _AdminDevicesBody extends ConsumerStatefulWidget {
  const _AdminDevicesBody({super.key});

  @override
  ConsumerState<_AdminDevicesBody> createState() => _AdminDevicesBodyState();
}

class _AdminDevicesBodyState extends ConsumerState<_AdminDevicesBody> {
  late Future<List<({String globalId, String name})>> _users = _api
      .adminUsers();
  late Future<List<Map<String, dynamic>>> _devices = _api.listAdminDevices();
  String? _selected;

  CloudLinkController get _api => ref.read(cloudLinkControllerProvider);

  void _reload() => setState(() {
    _users = _api.adminUsers();
    _devices = _api.listAdminDevices();
  });

  Future<void> _setPassword() async {
    final password = TextEditingController();
    final entered = await showDialog<String>(
      context: context,
      builder: (dialogContext) => PicPosDialog(
        icon: PhosphorIconsBold.lockKey,
        title: tr('تفعيل تطبيق الإدارة'),
        body: [
          TextField(
            controller: password,
            obscureText: true,
            decoration: InputDecoration(
              labelText: tr('كلمة مرور الجوال (٨ أحرف على الأقل)'),
            ),
          ),
        ],
        primaryAction: PicPosDialogAction(
          label: tr('تفعيل'),
          onPressed: () => Navigator.pop(dialogContext, password.text),
        ),
      ),
    );
    password.dispose();
    if (entered == null || !mounted) return;
    if (entered.length < 8) {
      AppToast.show(context, tr('كلمة مرور الجوال يجب ألا تقل عن ٨ أحرف'));
      return;
    }
    try {
      await _api.setAdminMobilePassword(_selected!, entered);
      if (mounted) AppToast.show(context, tr('تم تفعيل تطبيق الإدارة'));
      _reload();
    } catch (error, stack) {
      if (mounted) AppErrorHandler.handle(context, error, stack);
    }
  }

  Future<void> _pair() async {
    try {
      final offer = await _api.issueAdminPairingCode(_selected!);
      if (!mounted) return;
      final qr = jsonEncode({
        'v': 1,
        'cloudUrl': offer['cloudUrl'],
        'cloudCode': offer['code'],
        'desktopSigningKey': offer['desktopSigningKey'],
      });
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => PicPosDialog(
          icon: PhosphorIconsBold.qrCode,
          title: tr('ربط جوال'),
          cancelLabel: tr('إغلاق'),
          body: [
            QrImageView(data: qr, size: 240),
            SelectableText(
              '${offer['code']}',
              textDirection: TextDirection.ltr,
            ),
            SelectableText(
              '${offer['cloudUrl']}',
              textDirection: TextDirection.ltr,
            ),
          ],
        ),
      );
      _reload();
    } catch (error, stack) {
      if (mounted) AppErrorHandler.handle(context, error, stack);
    }
  }

  Future<void> _disable() async {
    final confirmed = await showPicPosConfirm(
      context,
      icon: PhosphorIconsBold.linkBreak,
      title: tr('إلغاء تفعيل تطبيق الإدارة'),
      message: tr(
        'سيُلغى وصول المستخدم إلى تطبيق الإدارة وتُلغى أجهزته المقترنة.',
      ),
      confirmLabel: tr('إلغاء التفعيل'),
      danger: true,
    );
    if (!confirmed || !mounted) return;
    try {
      await _api.disableAdminMobile(_selected!);
      if (mounted) AppToast.show(context, tr('تم إلغاء التفعيل'));
      _reload();
    } catch (error, stack) {
      if (mounted) AppErrorHandler.handle(context, error, stack);
    }
  }

  Future<void> _revoke(String deviceId) async {
    final confirmed = await showPicPosConfirm(
      context,
      icon: PhosphorIconsBold.linkBreak,
      title: tr('إلغاء الربط'),
      message: tr('لن يتمكن هذا الهاتف من الوصول إلى تطبيق الإدارة.'),
      confirmLabel: tr('إلغاء الربط'),
      danger: true,
    );
    if (!confirmed || !mounted) return;
    try {
      await _api.revokeAdminDevice(deviceId);
      _reload();
    } catch (error, stack) {
      if (mounted) AppErrorHandler.handle(context, error, stack);
    }
  }

  @override
  Widget build(BuildContext context) => SettingsRowsBody(
    children: [
      FutureBuilder<List<({String globalId, String name})>>(
        future: _users,
        builder: (context, snapshot) {
          if (snapshot.hasError)
            return _Muted(text: tr('تعذّر تحميل المستخدمين'));
          final users = snapshot.data ?? [];
          return DropdownButtonFormField<String>(
            initialValue: _selected,
            decoration: InputDecoration(labelText: tr('مستخدم تطبيق الإدارة')),
            items: [
              for (final user in users)
                DropdownMenuItem(value: user.globalId, child: Text(user.name)),
            ],
            onChanged: (selected) => setState(() => _selected = selected),
          );
        },
      ),
      Wrap(
        spacing: 8,
        children: [
          FilledButton(
            onPressed: _selected == null ? null : _setPassword,
            child: Text(tr('تفعيل تطبيق الإدارة')),
          ),
          OutlinedButton(
            onPressed: _selected == null ? null : _pair,
            child: Text(tr('ربط جوال')),
          ),
          TextButton(
            onPressed: _selected == null ? null : _disable,
            child: Text(tr('إلغاء التفعيل')),
          ),
        ],
      ),
      FutureBuilder<List<Map<String, dynamic>>>(
        future: _devices,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) return const _Loading();
          if (snapshot.hasError)
            return _Muted(text: tr('تعذّر تحميل هواتف الإدارة'));
          final devices = snapshot.data ?? [];
          final sorted = [...devices]..sort((a, b) {
            if ((a['revoked'] == true) != (b['revoked'] == true)) {
              return a['revoked'] == true ? 1 : -1;
            }
            DateTime? seen(Map<String, dynamic> device) {
              final timestamp = device['lastSeenAt'];
              return timestamp is String ? DateTime.tryParse(timestamp)
                  : timestamp is num
                      ? DateTime.fromMillisecondsSinceEpoch(timestamp.toInt())
                      : null;
            }
            return (seen(b) ?? DateTime(0))
                .compareTo(seen(a) ?? DateTime(0));
          });
          return _CollapsibleDevices(
            title: tr('هواتف الإدارة المقترنة'),
            tileKey: const Key('ld_admin_devices'),
            count: devices.length,
            revokedCount: devices.where((d) => d['revoked'] == true).length,
            children: [
              if (devices.isEmpty) _Muted(text: tr('لا هواتف إدارة مقترنة بعد')),
              for (final device in sorted)
                _DeviceRow(
                  icon: PhosphorIconsBold.deviceMobile,
                  title: '${device['deviceName'] ?? device['deviceId']}',
                  sub: '${device['userGlobalId'] ?? ''}',
                  revoked: device['revoked'] == true,
                  revokeKey: Key('ld_admin_revoke_${device['deviceId']}'),
                  onRevoke: () => _revoke('${device['deviceId']}'),
                ),
            ],
          );
        },
      ),
    ],
  );
}

class _CollapsibleDevices extends StatelessWidget {
  const _CollapsibleDevices({
    required this.title,
    required this.tileKey,
    required this.count,
    required this.revokedCount,
    required this.children,
  });

  final String title;
  final Key tileKey;
  final int count;
  final int revokedCount;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: context.picposField,
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: context.picposHairline),
    ),
    child: ExpansionTile(
      key: tileKey,
      initiallyExpanded: false,
      title: Text('$title ($count)',
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700,
              color: context.picposText)),
      subtitle: Text(tr('نشط: {active} · ملغى: {revoked}', {
        'active': count - revokedCount,
        'revoked': revokedCount,
      }), style: TextStyle(fontSize: 11, color: context.picposMuted)),
      childrenPadding: const EdgeInsets.symmetric(horizontal: 8),
      children: children,
    ),
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
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
    ),
  );
}
