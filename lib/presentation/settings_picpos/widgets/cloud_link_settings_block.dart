import 'package:picpos_erp/core/i18n/tr.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../services/cloud_sync/cloud_link_controller.dart';
import '../screens/cloud_link_settings_screen.dart';
import '../screens/cloud_sync_conflicts_screen.dart';
import 'settings_blocks.dart';

/// Company cloud link overview in the connections section (admin-only parent).
class CloudLinkSettingsBlock extends ConsumerStatefulWidget {
  const CloudLinkSettingsBlock({super.key, this.onSettingsChanged});

  final VoidCallback? onSettingsChanged;

  @override
  ConsumerState<CloudLinkSettingsBlock> createState() =>
      _CloudLinkSettingsBlockState();
}

class _CloudLinkSettingsBlockState
    extends ConsumerState<CloudLinkSettingsBlock> {
  late Future<CloudLinkView> _status = _load();
  bool _busy = false;

  Future<CloudLinkView> _load() =>
      ref.read(cloudLinkControllerProvider).load(includeSecret: false);

  void _reload() {
    if (mounted) setState(() {
      _status = _load();
    });
  }

  Future<void> _openSettings() async {
    await Navigator.push(context,
        MaterialPageRoute<void>(builder: (_) => const CloudLinkSettingsScreen()));
    _reload();
    widget.onSettingsChanged?.call();
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } catch (error) {
      if (mounted) AppToast.show(context,
          tr('تعذّر تنفيذ العملية: {error}', {'error': '$error'}),
          type: ToastType.error);
    } finally {
      if (mounted) setState(() => _busy = false);
      _reload();
    }
  }

  Future<void> _test(CloudLinkView view) => _run(() async {
    final response = await ref.read(cloudLinkControllerProvider).testConnection(
        url: view.url, linkId: view.linkId, secret: '');
    final company = response['company'];
    if (mounted) AppToast.show(context, tr('متصل: {name}',
        {'name': company is Map ? '${company['name']}' : ''}));
  });

  Future<void> _sync({bool full = false}) => _run(() async {
    final response = await ref.read(cloudLinkControllerProvider)
        .syncNow(fullPush: full);
    if (!mounted) return;
    if (response == null) {
      AppToast.show(context, tr('إعدادات الربط غير مكتملة'),
          type: ToastType.warning);
    } else if (!response.ok) {
      AppToast.show(context,
          tr('فشلت المزامنة: {error}', {'error': response.error}),
          type: ToastType.error);
    } else {
      AppToast.show(context,
          tr('اكتملت المزامنة: رُحّل {posted}، تعارض {conflicts}',
              {'posted': response.posted, 'conflicts': response.conflicts}));
    }
  });

  @override
  Widget build(BuildContext context) => SettingsBlock(
    title: tr('الاتصال بالسحابة'),
    subtitle: tr('إعدادات الشركة والمزامنة وتعارضاتها'),
    tint: AppColors.info,
    child: FutureBuilder<CloudLinkView>(
      future: _status,
      builder: (context, snapshot) {
        final view = snapshot.data;
        return SettingsRowsBody(children: [
          SettingsValueRow(
            first: true,
            icon: PhosphorIconsBold.cloud,
            title: tr('ربط الشركة بالسحابة'),
            sub: view == null ? null : '${view.linkId} · ${cloudLinkStatusLine(view)}',
            value: view?.enabled == true ? tr('مفعّل') : tr('غير مفعّل'),
            tint: view?.enabled == true ? AppColors.success : AppColors.info,
            onTap: _openSettings,
          ),
          if (snapshot.hasError)
            Text(tr('تعذّر تنفيذ العملية: {error}',
                {'error': '${snapshot.error}'})),
          if (view?.lastError != null)
            Text(tr('آخر خطأ: {error}', {'error': view!.lastError}),
                style: const TextStyle(color: AppColors.error)),
          SettingsValueRow(
            icon: PhosphorIconsBold.warning,
            title: view == null || view.conflicts.isEmpty
                ? tr('لا توجد تعارضات')
                : tr('تعارضات المزامنة: {n} — عرض',
                    {'n': view.conflicts.length}),
            tint: view != null && view.conflicts.isNotEmpty
                ? AppColors.warning : AppColors.info,
            onTap: view == null || view.conflicts.isEmpty ? null : () async {
              await Navigator.push(context, MaterialPageRoute<void>(
                builder: (_) => CloudSyncConflictsScreen(conflicts: view.conflicts)));
              _reload();
            },
          ),
          Wrap(spacing: 8, runSpacing: 8, children: [
            OutlinedButton(onPressed: _openSettings,
                child: Text(tr('إعدادات الربط السحابي'))),
            OutlinedButton(onPressed: _busy || view == null ? null : () => _test(view),
                child: Text(tr('اختبار الاتصال'))),
            OutlinedButton(onPressed: _busy || view?.enabled != true ? null : () => _sync(),
                child: Text(tr('مزامنة الآن'))),
            TextButton(onPressed: _busy || view?.enabled != true
                ? null : () => _sync(full: true),
                child: Text(tr('دفع كامل للبيانات'))),
          ]),
        ]);
      },
    ),
  );
}

/// «Last sync …» line shared by the block and the screen.
String cloudLinkStatusLine(CloudLinkView v) {
  final last = v.lastSyncAt == null
      ? tr('لم تتم بعد')
      : DateFormat('yyyy-MM-dd HH:mm').format(v.lastSyncAt!);
  return tr('آخر مزامنة: {t}', {'t': last});
}
