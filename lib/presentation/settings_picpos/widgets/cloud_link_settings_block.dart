import 'package:ural_erp/core/i18n/tr.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/theme/app_colors.dart';
import '../../../data/providers/auth_providers.dart';
import '../../../services/cloud_sync/cloud_link_controller.dart';
import '../screens/cloud_link_settings_screen.dart';
import 'settings_blocks.dart';

/// Settings › Integrations — the company cloud link (I-3: desktop ↔ cloud,
/// rep app). Admin-only: hidden for everyone else.
class CloudLinkSettingsBlock extends ConsumerStatefulWidget {
  const CloudLinkSettingsBlock({super.key});

  @override
  ConsumerState<CloudLinkSettingsBlock> createState() =>
      _CloudLinkSettingsBlockState();
}

class _CloudLinkSettingsBlockState
    extends ConsumerState<CloudLinkSettingsBlock> {
  late Future<CloudLinkView> _status = _load();

  Future<CloudLinkView> _load() =>
      ref.read(cloudLinkControllerProvider).load(includeSecret: false);

  @override
  Widget build(BuildContext context) {
    final isAdmin = ref.watch(currentUserPermissionsProvider).maybeWhen(
          data: (codes) => codes.contains('system_admin') || codes.contains('*'),
          orElse: () => false,
        );
    if (!isAdmin) return const SizedBox.shrink();
    return SettingsBlock(
      title: tr('ربط السحابة — تطبيق المندوب'),
      subtitle: tr('بيانات المناديب صعوداً والمستندات الميدانية نزولاً'),
      tint: AppColors.info,
      child: FutureBuilder<CloudLinkView>(
        future: _status,
        builder: (context, snap) {
          final v = snap.data;
          return SettingsRowsBody(children: [
            SettingsValueRow(
              first: true,
              icon: PhosphorIconsBold.cloud,
              title: tr('ربط الشركة بالسحابة'),
              sub: v == null ? null : cloudLinkStatusLine(v),
              value: v == null || !v.enabled
                  ? tr('غير مفعّل')
                  : tr('تعارضات: {n}', {'n': v.conflicts.length}),
              tint: v != null && v.conflicts.isNotEmpty
                  ? AppColors.warning
                  : AppColors.info,
              onTap: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const CloudLinkSettingsScreen()),
                );
                if (mounted) setState(() => _status = _load());
              },
            ),
          ]);
        },
      ),
    );
  }
}

/// «Last sync …» line shared by the block and the screen.
String cloudLinkStatusLine(CloudLinkView v) {
  final last = v.lastSyncAt == null
      ? tr('لم تتم بعد')
      : DateFormat('yyyy-MM-dd HH:mm').format(v.lastSyncAt!);
  return tr('آخر مزامنة: {t}', {'t': last});
}
