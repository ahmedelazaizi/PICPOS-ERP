import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:picpos_erp/core/i18n/tr.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../data/providers/providers.dart';
import '../../../services/db_encryption_actions.dart';
import '../../../services/db_key_boot.dart';
import '../../picpos_shell/picpos_dialog.dart';
import 'database_encryption_dialogs.dart';
import 'settings_blocks.dart';

/// هل تُعرَض كتلةُ التشفير؟ لا على الويب ولا مع PostgreSQL المتصل (لا ملفَّ
/// SQLite محليّ هناك). وضعُ العميل/المرآة/الاحتياط يفتح الملفَّ المحليَّ نفسَه
/// فتُعرَض.
final dbEncryptionSupportedProvider = Provider<bool>((ref) {
  if (kIsWeb) return false;
  try {
    return !ref.watch(databaseProvider).isPostgres;
  } catch (_) {
    return false;
  }
});

final dbEncryptionActionsProvider = Provider<DbEncryptionActions>((ref) {
  return ProductionDbEncryptionActions(
    audit: (action, description) async {
      final user = ref.read(authProvider).user;
      await ref.read(activityLoggerProvider).log(
            userId: user?.id,
            userName: user?.displayName ?? '',
            action: action,
            entityType: 'security',
            description: description,
          );
    },
  );
});

bool _isAdmin(WidgetRef ref) => ref
    .watch(currentUserPermissionsProvider)
    .maybeWhen(
      data: (codes) => codes.contains('system_admin') || codes.contains('*'),
      orElse: () => false,
    );

/// كتلةُ «تشفير قاعدة البيانات» في إعدادات الأمان — للمدير وحده.
///
/// الترقيةُ **يدويّة** وتُسجَّل كطلبٍ مؤجَّل يُنفَّذ قبل فتح أيّ مقبضٍ في الإقلاع
/// التالي؛ لا شيءَ هنا يغلق القاعدةَ الحيّة ولا يرحّل تلقائيًّا.
class DatabaseEncryptionBlock extends ConsumerStatefulWidget {
  const DatabaseEncryptionBlock({super.key, this.onPrintCode});

  /// يُحقَن في الاختبار بدل الطباعة الحقيقيّة.
  final Future<void> Function(String code)? onPrintCode;

  @override
  ConsumerState<DatabaseEncryptionBlock> createState() =>
      _DatabaseEncryptionBlockState();
}

class _DatabaseEncryptionBlockState
    extends ConsumerState<DatabaseEncryptionBlock> {
  Future<DbEncryptionStatus>? _status;
  bool _busy = false;
  bool _codePrompted = false;

  DbEncryptionActions get _actions => ref.read(dbEncryptionActionsProvider);

  void _reload() {
    setState(() {
      _status = _actions.status();
    });
  }

  void _toast(String m, {bool error = false}) {
    if (mounted) {
      AppToast.show(context, m, type: error ? ToastType.error : ToastType.success);
    }
  }

  Future<void> _promptCode() async {
    final code = await _actions.pendingRecoveryCode();
    if (code == null || !mounted) return;
    final saved = await RecoveryCodeDialog.show(context, code,
        onPrint: widget.onPrintCode);
    if (saved) {
      await _actions.acknowledgeRecoveryCode();
      await _actions.audit(
          'db_recovery_code_acknowledged', tr('أكّد المدير حفظ رمز استرداد قاعدة البيانات'));
      if (mounted) _reload();
    } else {
      _codePrompted = false;
    }
  }

  Future<void> _upgrade() async {
    if (_busy) return;
    final decision = await showDialog<UpgradeDecision>(
      context: context,
      builder: (_) => UpgradeEncryptionDialog(actions: _actions),
    );
    if (decision == null || !mounted) return;
    setState(() => _busy = true);
    try {
      await _actions.requestMigration(spaceConfirmed: decision.spaceConfirmed);
      await _actions.audit('db_encryption_upgrade_requested',
          tr('سُجّل طلب ترقية تشفير قاعدة البيانات (ينفَّذ عند التشغيل التالي)'));
      _toast(tr('سُجّل الطلب. أعد تشغيل التطبيق لتنفيذ الترقية.'));
      _reload();
    } catch (e) {
      _toast(tr('تعذّر تسجيل الطلب: {e}', {'e': '$e'}), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _cancel() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await _actions.cancelRequest();
      await _actions.audit('db_encryption_upgrade_cancelled',
          tr('أُلغي طلب ترقية تشفير قاعدة البيانات'));
      _reload();
    } catch (e) {
      _toast(tr('تعذّر الإلغاء: {e}', {'e': '$e'}), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _export() async {
    if (_busy) return;
    final pw = await showDialog<String>(
      context: context,
      builder: (_) => const PortableExportDialog(),
    );
    if (pw == null || !mounted) return;
    final dir = await _actions.pickExportDirectory();
    if (dir == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final path = await _actions.exportPortable(password: pw, directory: dir);
      await _actions.audit('db_portable_export',
          tr('صُدّرت نسخة محمولة من قاعدة البيانات بكلمة مرور'));
      _toast(tr('تم التصدير: {path}', {'path': path}));
    } catch (e) {
      _toast(tr('تعذّر التصدير: {e}', {'e': '$e'}), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _rollback() async {
    if (_busy) return;
    final ok = await showPicPosConfirm(
      context,
      icon: PhosphorIconsBold.clockCounterClockwise,
      title: tr('الرجوع إلى ما قبل الترحيل'),
      message: tr(
          'ستُستعاد نسخة القاعدة المأخوذة قبل ترقية التشفير عند التشغيل التالي، وستفقد كل ما سُجّل بعد الترحيل. لا يُنصح بهذا إلا عند وجود مشكلة. هل تريد المتابعة؟'),
      confirmLabel: tr('جدولة الرجوع'),
      danger: true,
    );
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    try {
      final done = await _actions.scheduleRollback();
      if (done) {
        await _actions.audit('db_encryption_rollback_scheduled',
            tr('جُدول الرجوع إلى نسخة ما قبل ترحيل التشفير'));
        _toast(tr('جُدول الرجوع. أعد تشغيل التطبيق لتطبيقه.'));
      } else {
        _toast(tr('تعذّرت جدولة الرجوع: لا نسخة متاحة أو لا تُفتح.'),
            error: true);
      }
      _reload();
    } catch (e) {
      _toast(tr('تعذّرت جدولة الرجوع: {e}', {'e': '$e'}), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  static String _stateLabel(DbEncryptionState s) => switch (s) {
        DbEncryptionState.legacy => tr('مشتق من الجهاز'),
        DbEncryptionState.requested => tr('بانتظار إعادة التشغيل'),
        DbEncryptionState.pendingConfirm => tr('بانتظار تأكيد'),
        DbEncryptionState.migrated => tr('مفتاح عشوائي'),
        DbEncryptionState.unavailable => tr('غير متاح'),
      };

  static String _stateSub(DbEncryptionState s) => switch (s) {
        DbEncryptionState.legacy => tr(
            'القاعدة مشفّرة بمفتاح يُحسب من معرّف الجهاز. يُنصح بالترقية إلى مفتاح عشوائي.'),
        DbEncryptionState.requested => tr(
            'سُجّل طلب الترقية. يُنفَّذ عند تشغيل التطبيق التالي قبل فتح القاعدة.'),
        DbEncryptionState.pendingConfirm => tr(
            'تمت الترقية. تُؤكَّد نهائيًا عند التشغيل التالي ثم تُحذف النسخة المؤقتة.'),
        DbEncryptionState.migrated => tr(
            'القاعدة مشفّرة بمفتاح عشوائي محفوظ في حساب ويندوز مع رمز استرداد.'),
        DbEncryptionState.unavailable => tr('تعذّرت قراءة حالة التشفير.'),
      };

  static Color _stateTint(DbEncryptionState s) => switch (s) {
        DbEncryptionState.legacy => AppColors.warning,
        DbEncryptionState.requested ||
        DbEncryptionState.pendingConfirm =>
          AppColors.info,
        DbEncryptionState.migrated => AppColors.success,
        DbEncryptionState.unavailable => AppColors.error,
      };

  @override
  Widget build(BuildContext context) {
    if (!ref.watch(dbEncryptionSupportedProvider)) {
      return const SizedBox.shrink();
    }
    if (!_isAdmin(ref)) return const SizedBox.shrink();
    _status ??= _actions.status();
    return SettingsBlock(
      key: const Key('ld_db_encryption'),
      title: tr('تشفير قاعدة البيانات'),
      subtitle: tr('ترقية مفتاح التشفير ورمز الاسترداد والنسخة المحمولة'),
      tint: AppColors.primary,
      child: FutureBuilder<DbEncryptionStatus>(
        future: _status,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const SizedBox(height: 56);
          }
          final st = snap.data ??
              const DbEncryptionStatus(state: DbEncryptionState.unavailable);
          if (st.recoveryCodePending && !_codePrompted) {
            _codePrompted = true;
            WidgetsBinding.instance
                .addPostFrameCallback((_) => mounted ? _promptCode() : null);
          }
          final outcome = st.lastOutcome;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SettingsRowsBody(children: [
                SettingsValueRow(
                  key: const Key('dbenc_status'),
                  first: true,
                  icon: PhosphorIconsBold.lockKey,
                  title: tr('حالة التشفير'),
                  sub: _stateSub(st.state),
                  value: _stateLabel(st.state),
                  tint: _stateTint(st.state),
                ),
                if (outcome != null &&
                    outcome.kind != DbKeyBootOutcomeKind.migrated)
                  SettingsValueRow(
                    key: const Key('dbenc_outcome'),
                    icon: PhosphorIconsBold.warning,
                    title: tr('آخر محاولة ترحيل'),
                    sub: outcomeText(outcome),
                    tint: AppColors.warning,
                  ),
                if (st.recoveryCodePending)
                  SettingsValueRow(
                    key: const Key('dbenc_code_pending'),
                    icon: PhosphorIconsBold.key,
                    title: tr('رمز الاسترداد بانتظار التأكيد'),
                    sub: tr('اضغط لعرض الرمز وتأكيد حفظه'),
                    value: tr('عرض'),
                    tint: AppColors.warning,
                    onTap: _promptCode,
                  ),
                if (st.state == DbEncryptionState.migrated ||
                    st.state == DbEncryptionState.pendingConfirm)
                  SettingsValueRow(
                    key: const Key('dbenc_export_row'),
                    icon: PhosphorIconsBold.export,
                    title: tr('تصدير مفتاح محمول بكلمة مرور'),
                    sub: tr('نسخة من القاعدة تُفتح على أي جهاز بكلمة المرور وحدها'),
                    value: tr('تصدير'),
                    onTap: _busy ? null : _export,
                  ),
              ]),
              if (st.state == DbEncryptionState.legacy)
                SettingsDangerRow(
                  key: const Key('dbenc_upgrade_row'),
                  icon: PhosphorIconsBold.lockKey,
                  title: tr('ترقية التشفير'),
                  sub: tr('مفتاح عشوائي بدل المفتاح المشتق من الجهاز، يدويًا وبنسخة احتياطية مسبقة'),
                  actionLabel: tr('ترقية التشفير'),
                  onPressed: _busy ? () {} : _upgrade,
                ),
              if (st.state == DbEncryptionState.requested)
                SettingsDangerRow(
                  key: const Key('dbenc_cancel_row'),
                  icon: PhosphorIconsBold.x,
                  title: tr('إلغاء طلب الترقية'),
                  sub: tr('لم يُنفَّذ بعد؛ يمكن إلغاؤه قبل إعادة التشغيل'),
                  actionLabel: tr('إلغاء الطلب'),
                  onPressed: _busy ? () {} : _cancel,
                ),
              if (st.canRollback)
                SettingsDangerRow(
                  key: const Key('dbenc_rollback_row'),
                  icon: PhosphorIconsBold.clockCounterClockwise,
                  title: tr('الرجوع إلى ما قبل الترحيل'),
                  sub: tr('نسخة ما قبل الترقية متاحة حتى {date}',
                      {'date': st.preMigrationUntil.toString().split(' ').first}),
                  actionLabel: tr('الرجوع'),
                  onPressed: _busy ? () {} : _rollback,
                ),
            ],
          );
        },
      ),
    );
  }
}
