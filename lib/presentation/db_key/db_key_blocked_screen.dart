import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:picpos_erp/core/config/brand.dart';
import 'package:picpos_erp/core/i18n/tr.dart';
import 'package:picpos_erp/core/theme/app_colors.dart';
import 'package:picpos_erp/services/db_key_blocked_actions.dart';
import 'package:picpos_erp/services/db_key_types.dart';

/// تطبيقٌ أدنى يعرض شاشةَ الحجب وحدَها (كما `FatalSetupErrorApp`): يُشغَّل من
/// `main` قبل إنشاء أيّ قاعدة، فلا تُنشأ قاعدةٌ فارغةٌ فوق بيانات المستخدم.
class DbKeyBlockedApp extends StatelessWidget {
  const DbKeyBlockedApp({
    super.key,
    required this.resolution,
    required this.actions,
  });

  final DbKeyUnavailable resolution;
  final DbKeyBlockedActions actions;

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: Brand.name,
        debugShowCheckedModeBanner: false,
        locale: const Locale('ar'),
        supportedLocales: const [Locale('ar'), Locale('en')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        builder: (context, child) => Directionality(
          textDirection: TextDirection.rtl,
          child: child ?? const SizedBox.shrink(),
        ),
        theme: ThemeData(
          useMaterial3: true,
          fontFamily: 'Cairo',
          colorScheme: ColorScheme.fromSeed(
            seedColor: AppColors.error,
            brightness: Brightness.light,
          ),
        ),
        home: DbKeyBlockedScreen(resolution: resolution, actions: actions),
      );
}

String dbKeyReasonText(DbKeyUnavailableReason r) => switch (r) {
      DbKeyUnavailableReason.keyMissing => tr(
          'مفتاح تشفير القاعدة غير موجود في هذا الحساب على هذا الجهاز (حساب ويندوز آخر أو اعتماد محذوف).'),
      DbKeyUnavailableReason.wrongKey =>
        tr('المفتاح المحفوظ لا يفتح ملف القاعدة.'),
      DbKeyUnavailableReason.storeFailure =>
        tr('تعذّرت قراءة التخزين الآمن للنظام أو الكتابة فيه.'),
      DbKeyUnavailableReason.plaintextDatabase =>
        tr('ملف القاعدة بصيغة غير مشفّرة غير مدعومة في هذا المسار.'),
      DbKeyUnavailableReason.databaseMissingKeyinfoPresent => tr(
          'ملف القاعدة مفقود بينما سجلّ المفتاح يشير إلى قاعدة مرحَّلة كانت هنا.'),
      DbKeyUnavailableReason.recoveryFailed =>
        tr('رمز الاسترداد غير صحيح أو لا يفتح هذه القاعدة.'),
      DbKeyUnavailableReason.noCandidateOpens =>
        tr('لا يوجد مفتاح معروف يفتح ملف القاعدة.'),
    };

class DbKeyBlockedScreen extends StatefulWidget {
  const DbKeyBlockedScreen({
    super.key,
    required this.resolution,
    required this.actions,
  });

  final DbKeyUnavailable resolution;
  final DbKeyBlockedActions actions;

  @override
  State<DbKeyBlockedScreen> createState() => _DbKeyBlockedScreenState();
}

class _DbKeyBlockedScreenState extends State<DbKeyBlockedScreen> {
  late DbKeyUnavailable _res = widget.resolution;
  final _code = TextEditingController();
  bool _busy = false;
  bool _opened = false; // أمكن فتحُ القاعدة؛ يلزم إعادة تشغيل التطبيق
  bool _hasRollback = false;
  String? _message;
  bool _messageIsError = false;

  @override
  void initState() {
    super.initState();
    widget.actions.hasRollbackSource().then((v) {
      if (mounted) setState(() => _hasRollback = v || _res.preMigrationCopyAvailable);
    }).catchError((_) {});
  }

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  void _note(String m, {bool error = false}) {
    _message = m;
    _messageIsError = error;
  }

  Future<void> _run(Future<void> Function() body) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await body();
    } catch (e) {
      if (mounted) {
        setState(() => _note(tr('تعذّر تنفيذ الإجراء: {e}', {'e': '$e'}), error: true));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _apply(DbKeyResolution r) {
    if (r is DbKeyReady) {
      _opened = true;
      _note(tr('أمكن فتح القاعدة. أغلق التطبيق وأعد تشغيله.'));
    } else if (r is DbKeyUnavailable) {
      _res = r;
      _note(dbKeyReasonText(r.reason), error: true);
    }
  }

  Future<void> _retry() => _run(() async {
        final r = await widget.actions.retry();
        if (mounted) setState(() => _apply(r));
      });

  Future<void> _recover() => _run(() async {
        final code = _code.text.trim();
        if (code.isEmpty) return;
        final r = await widget.actions.recoverWithCode(code);
        if (!mounted) return;
        setState(() {
          _apply(r);
          if (r is DbKeyReady) _code.clear();
        });
      });

  Future<void> _rollback() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        key: const Key('dbkey_rollback_confirm'),
        title: Text(tr('استعادة من نسخة ما قبل الترحيل')),
        content: Text(tr(
            'ستعود القاعدة إلى حالتها قبل ترقية التشفير. ستفقد كل ما سُجّل بعد الترحيل (يبقى محفوظًا في ملف جانبي ولا يُحذف). هل تريد المتابعة؟')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(tr('إلغاء')),
          ),
          FilledButton(
            key: const Key('dbkey_rollback_yes'),
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(tr('استعادة')),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await _run(() async {
      final r = await widget.actions.rollbackToPreMigration();
      switch (r) {
        case DbKeyRollbackResult.done:
          final next = await widget.actions.retry();
          if (mounted) setState(() => _apply(next));
        case DbKeyRollbackResult.scheduledRestart:
          if (mounted) {
            setState(() {
              _opened = true;
              _note(tr('جُدولت الاستعادة. أغلق التطبيق وأعد تشغيله لتطبيقها.'));
            });
          }
        case DbKeyRollbackResult.unavailable:
          if (mounted) {
            setState(() => _note(
                tr('لا توجد نسخة ما قبل الترحيل متاحة للاستعادة.'),
                error: true));
          }
      }
    });
  }

  Future<void> _diagnostics() => _run(() async {
        final path = await widget.actions.exportDiagnostics(_res);
        if (mounted) {
          setState(() => _note(
              tr('حُفظ السجل التشخيصي (وجرى نسخ المسار): {path}', {'path': path})));
        }
        // نسخُ المسار للحافظة أفضلُ جهدٍ ولا يحجب الرسالة.
        unawaited(Clipboard.setData(ClipboardData(text: path)).catchError((_) {}));
      });

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      key: const Key('dbkey_blocked_screen'),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
              ),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(children: [
                      const Icon(Icons.lock_outline,
                          color: AppColors.error, size: 32),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          tr('تعذّر فتح قاعدة البيانات المشفّرة'),
                          style: text.titleLarge
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                      ),
                    ]),
                    const SizedBox(height: 12),
                    Text(
                      tr('لم يُنشأ أي ملف جديد ولم تُحذف بياناتك: أُوقف الإقلاع حمايةً لها.'),
                      style: text.bodyMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      dbKeyReasonText(_res.reason),
                      key: const Key('dbkey_reason'),
                      style: text.bodyMedium?.copyWith(
                          color: AppColors.error, fontWeight: FontWeight.w700),
                    ),
                    if (_message != null) ...[
                      const SizedBox(height: 12),
                      Container(
                        key: const Key('dbkey_message'),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: (_messageIsError
                                  ? AppColors.error
                                  : AppColors.success)
                              .withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(_message!),
                      ),
                    ],
                    const SizedBox(height: 16),
                    if (_res.canRecoverWithCode && !_opened) ...[
                      Text(tr('رمز الاسترداد'),
                          style: text.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 6),
                      Row(children: [
                        Expanded(
                          child: TextField(
                            key: const Key('dbkey_code_field'),
                            controller: _code,
                            enabled: !_busy,
                            textDirection: TextDirection.ltr,
                            textCapitalization: TextCapitalization.characters,
                            decoration: const InputDecoration(
                              hintText: 'XXXX-XXXX-XXXX-XXXX-XXXX-XXXX',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                            onSubmitted: (_) => _recover(),
                          ),
                        ),
                        const SizedBox(width: 8),
                        FilledButton(
                          key: const Key('dbkey_recover_btn'),
                          onPressed: _busy ? null : _recover,
                          child: Text(tr('استرداد')),
                        ),
                      ]),
                      const SizedBox(height: 16),
                    ],
                    if (_opened)
                      FilledButton.icon(
                        key: const Key('dbkey_exit_btn'),
                        onPressed: widget.actions.exitApp,
                        icon: const Icon(Icons.power_settings_new),
                        label: Text(tr('إغلاق التطبيق')),
                      )
                    else
                      Wrap(spacing: 8, runSpacing: 8, children: [
                        OutlinedButton.icon(
                          key: const Key('dbkey_retry_btn'),
                          onPressed: _busy ? null : _retry,
                          icon: const Icon(Icons.refresh),
                          label: Text(tr('إعادة المحاولة')),
                        ),
                        if (_hasRollback)
                          OutlinedButton.icon(
                            key: const Key('dbkey_rollback_btn'),
                            onPressed: _busy ? null : _rollback,
                            icon: const Icon(Icons.history),
                            label: Text(tr('استعادة من نسخة ما قبل الترحيل')),
                          ),
                        OutlinedButton.icon(
                          key: const Key('dbkey_diag_btn'),
                          onPressed: _busy ? null : _diagnostics,
                          icon: const Icon(Icons.description_outlined),
                          label: Text(tr('تصدير سجل تشخيصي')),
                        ),
                      ]),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
