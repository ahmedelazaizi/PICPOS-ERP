import 'package:ural_erp/core/i18n/tr.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../data/providers/auth_providers.dart';
import '../../../services/cloud_sync/cloud_link_controller.dart';
import '../widgets/cloud_link_settings_block.dart';

/// Company cloud link (I-3): credentials, test connection, sync now, status
/// and the cloud sync conflicts list with retry. Admin-only (the entry row
/// is hidden for non-admins).
class CloudLinkSettingsScreen extends ConsumerStatefulWidget {
  const CloudLinkSettingsScreen({super.key});

  @override
  ConsumerState<CloudLinkSettingsScreen> createState() =>
      _CloudLinkSettingsScreenState();
}

class _CloudLinkSettingsScreenState
    extends ConsumerState<CloudLinkSettingsScreen> {
  final _url = TextEditingController();
  final _linkId = TextEditingController();
  final _secret = TextEditingController();
  final _interval = TextEditingController(text: '5');
  bool _enabled = false;
  bool _busy = false;
  CloudLinkView? _view;

  CloudLinkController get _ctrl => ref.read(cloudLinkControllerProvider);

  @override
  void initState() {
    super.initState();
    _reload(fillForm: true);
  }

  @override
  void dispose() {
    _url.dispose();
    _linkId.dispose();
    _secret.dispose();
    _interval.dispose();
    super.dispose();
  }

  Future<void> _reload({bool fillForm = false}) async {
    final v = await _ctrl.load();
    if (!mounted) return;
    setState(() {
      _view = v;
      if (fillForm) {
        _enabled = v.enabled;
        _url.text = v.url;
        _linkId.text = v.linkId;
        _interval.text = '${v.intervalMinutes}';
      }
    });
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } catch (e) {
      if (mounted) {
        AppToast.show(context, tr('تعذّر تنفيذ العملية: {error}', {'error': '$e'}),
            type: ToastType.error);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
      await _reload();
    }
  }

  Future<void> _save() => _run(() async {
        await _ctrl.save(
          enabled: _enabled,
          url: _url.text,
          linkId: _linkId.text,
          secret: _secret.text,
          intervalMinutes: int.tryParse(_interval.text.trim()) ?? 5,
          postingUserId: ref.read(authProvider).user?.id,
        );
        _secret.clear();
        if (mounted) AppToast.show(context, tr('تم الحفظ'));
      });

  Future<void> _test() => _run(() async {
        final r = await _ctrl.testConnection(
            url: _url.text, linkId: _linkId.text, secret: _secret.text);
        final company = r['company'];
        final name = company is Map ? '${company['name']}' : '';
        if (mounted) {
          AppToast.show(context, tr('متصل: {name}', {'name': name}));
        }
      });

  Future<void> _sync({bool full = false}) => _run(() async {
        final r = await _ctrl.syncNow(fullPush: full);
        if (!mounted) return;
        if (r == null) {
          AppToast.show(context, tr('إعدادات الربط غير مكتملة'),
              type: ToastType.warning);
        } else if (!r.ok) {
          AppToast.show(context, tr('فشلت المزامنة: {error}', {'error': r.error}),
              type: ToastType.error);
        } else {
          AppToast.show(
              context,
              tr('اكتملت المزامنة: رُحّل {posted}، تعارض {conflicts}',
                  {'posted': r.posted, 'conflicts': r.conflicts}));
        }
      });

  static String _kindLabel(String kind) => switch (kind) {
        'sales_invoice' => tr('فاتورة مبيعات'),
        'sales_return' => tr('مرتجع مبيعات'),
        'collection' => tr('سند قبض'),
        'visit' => tr('زيارة عميل'),
        _ => kind,
      };

  @override
  Widget build(BuildContext context) {
    final v = _view;
    return Scaffold(
      appBar: AppBar(title: Text(tr('ربط الشركة بالسحابة'))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SwitchListTile(
            value: _enabled,
            onChanged: (x) => setState(() => _enabled = x),
            title: Text(tr('تفعيل الربط')),
            subtitle: Text(tr('المستندات الميدانية تُرحَّل باسم المستخدم الحالي')),
          ),
          TextField(
            controller: _url,
            decoration: InputDecoration(labelText: tr('عنوان السيرفر السحابي')),
          ),
          TextField(
            controller: _linkId,
            decoration: InputDecoration(labelText: tr('معرّف الربط')),
          ),
          TextField(
            controller: _secret,
            obscureText: true,
            decoration: InputDecoration(
              labelText: tr('مفتاح الربط'),
              helperText: v != null && v.hasSecret
                  ? tr('اتركه فارغاً للإبقاء على المفتاح المحفوظ')
                  : null,
            ),
          ),
          TextField(
            controller: _interval,
            keyboardType: TextInputType.number,
            decoration:
                InputDecoration(labelText: tr('الفاصل الزمني للمزامنة (دقائق)')),
          ),
          const SizedBox(height: 16),
          Wrap(spacing: 8, runSpacing: 8, children: [
            FilledButton(onPressed: _busy ? null : _save, child: Text(tr('حفظ'))),
            OutlinedButton(
                onPressed: _busy ? null : _test, child: Text(tr('اختبار الاتصال'))),
            OutlinedButton(
                onPressed: _busy ? null : () => _sync(), child: Text(tr('مزامنة الآن'))),
            TextButton(
                onPressed: _busy ? null : () => _sync(full: true),
                child: Text(tr('دفع كامل للبيانات'))),
          ]),
          if (_busy) const Padding(
            padding: EdgeInsets.only(top: 12),
            child: LinearProgressIndicator(),
          ),
          const Divider(height: 32),
          Text(tr('الحالة'), style: Theme.of(context).textTheme.titleMedium),
          if (v != null) ...[
            ListTile(dense: true, title: Text(cloudLinkStatusLine(v))),
            ListTile(
                dense: true,
                title: Text(tr('مستندات مرحّلة: {n}', {'n': v.posted}))),
            if (v.lastError != null)
              ListTile(
                dense: true,
                title: Text(tr('آخر خطأ: {error}', {'error': v.lastError})),
                textColor: AppColors.error,
              ),
          ],
          const Divider(height: 32),
          Text(tr('تعارضات المزامنة السحابية'),
              style: Theme.of(context).textTheme.titleMedium),
          if (v == null || v.conflicts.isEmpty)
            ListTile(dense: true, title: Text(tr('لا توجد تعارضات')))
          else
            for (final c in v.conflicts)
              ListTile(
                title: Text('${_kindLabel(c.kind)} ${c.cloudNumber ?? ''}'),
                subtitle: Text([
                  c.reason ?? '',
                  tr('المحاولات: {n}', {'n': c.attempts}),
                  if (c.updatedAt != null)
                    DateFormat('yyyy-MM-dd HH:mm').format(c.updatedAt!),
                ].join(' · ')),
                trailing: c.retryRequested
                    ? Text(tr('ستُعاد المحاولة في المزامنة القادمة'))
                    : TextButton(
                        onPressed: _busy
                            ? null
                            : () => _run(() async {
                                  await _ctrl.retry(c.globalId);
                                  await _ctrl.syncNow();
                                }),
                        child: Text(tr('إعادة المحاولة')),
                      ),
              ),
        ],
      ),
    );
  }
}
