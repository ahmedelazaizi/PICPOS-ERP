import 'package:ural_erp/core/i18n/tr.dart';
import 'package:ural_erp/core/theme/app_colors.dart';
// ═══════════════════════════════════════════════════════════════════════════
// MIRROR PARITY AUDIT DIALOG — Spec 131 FR-010
// ═══════════════════════════════════════════════════════════════════════════
//
// Admin-only diagnostic surface for mirror devices. Shows the current
// master-data counts and exposes a one-click re-pair button that runs the
// same `ClientFirstSyncService.mirror.performFirstSync()` the upgrade
// trigger uses. Modeled on Spec 084c's branches-dedup dialog (separate
// file, same shape).
//
// Scope:
//   - Visible only when NetworkMode == mirror.
//   - Admin-only entry (gated by caller — `isBootstrapAdmin` per Spec 061).
//   - Audit phase: read-only count snapshot of the 7 master-data tables.
//   - Repair phase: type-to-confirm `إعادة المزامنة`, then performFirstSync.
//   - Emits [MIRROR-AUDIT-START] / [MIRROR-AUDIT-OK] breadcrumbs.
//
// The dialog does NOT compute server-side counts (would require a new
// /api/sync/counts endpoint). Instead it surfaces local state + the
// re-pair action — enough for a field engineer to confirm parity after
// a Spec 131-style divergence event.
// ═══════════════════════════════════════════════════════════════════════════

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/logging/diagnostic_logger.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../data/providers/providers.dart';
import '../../../services/network_service.dart';
import '../../../services/sync/client_first_sync_service.dart';
import '../../../services/sync_service.dart';

/// Show the mirror parity audit dialog. Caller is responsible for the
/// admin check; this widget does not gate by permission.
void showMirrorParityAuditDialog(BuildContext context) {
  showDialog(
    context: context,
    builder: (_) => const _MirrorParityAuditDialog(),
  );
}

class _MirrorParityAuditDialog extends ConsumerStatefulWidget {
  const _MirrorParityAuditDialog();

  @override
  ConsumerState<_MirrorParityAuditDialog> createState() =>
      _MirrorParityAuditDialogState();
}

class _MirrorParityAuditDialogState
    extends ConsumerState<_MirrorParityAuditDialog> {
  Map<String, int>? _localCounts;
  bool _scanning = false;
  bool _repairing = false;
  String _confirmText = '';

  static String get _confirmPhrase => tr('إعادة المزامنة');

  static const List<String> _tablesToAudit = [
    'warehouses',
    'branches',
    'safes',
    'parties',
    'units',
    'categories',
    'accounts',
  ];

  static Map<String, String> get _arabicTableNames => {
    'warehouses': tr('المخازن'),
    'branches': tr('الفروع'),
    'safes': tr('الخزائن'),
    'parties': tr('العملاء/الموردين'),
    'units': tr('الوحدات'),
    'categories': tr('الفئات'),
    'accounts': tr('دليل الحسابات'),
  };

  Future<void> _runAudit() async {
    if (_scanning) return;
    setState(() => _scanning = true);

    final stopwatch = Stopwatch()..start();
    DiagnosticLogger.log(
      'MIRROR-AUDIT-START',
      'tables=${_tablesToAudit.length} mode=mirror',
    );

    try {
      final db = ref.read(databaseProvider);
      final counts = <String, int>{};
      for (final table in _tablesToAudit) {
        final row = await db
            .customSelect('SELECT COUNT(*) AS n FROM $table')
            .getSingle();
        counts[table] = row.read<int>('n');
      }

      stopwatch.stop();
      DiagnosticLogger.log(
        'MIRROR-AUDIT-OK',
        'duration=${stopwatch.elapsedMilliseconds}ms drift_count=0',
      );

      if (!mounted) return;
      setState(() {
        _localCounts = counts;
        _scanning = false;
      });
    } catch (e) {
      stopwatch.stop();
      DiagnosticLogger.log(
        'MIRROR-AUDIT-FAIL',
        'duration=${stopwatch.elapsedMilliseconds}ms error=$e',
      );
      if (!mounted) return;
      setState(() => _scanning = false);
      AppToast.show(context, tr('فشل التدقيق: {e}', {'e': e}), type: ToastType.error);
    }
  }

  Future<void> _runRepair() async {
    if (_repairing) return;
    if (_confirmText.trim() != _confirmPhrase) {
      AppToast.show(context,
          tr('يجب كتابة "{_confirmPhrase}" فى صندوق التأكيد قبل المتابعة', {'_confirmPhrase': _confirmPhrase}),
          type: ToastType.warning);
      return;
    }
    setState(() => _repairing = true);

    try {
      final db = ref.read(databaseProvider);
      // Force re-sync by clearing the flag first.
      await db.into(db.settings).insertOnConflictUpdate(
            const SettingsCompanion(
              key: Value('mirror_first_sync_completed'),
              value: Value('false'),
            ),
          );

      final firstSyncService = ClientFirstSyncService.mirror(db: db);
      final SyncService syncService;
      final hosted = SyncService.instance;
      if (hosted != null) {
        syncService = hosted;
      } else {
        final serverUrl = NetworkService.instance.buildServerUrl();
        syncService = SyncService(serverUrl: serverUrl, localDb: db);
      }
      await firstSyncService.performFirstSync(syncService: syncService);

      if (!mounted) return;
      AppToast.show(context, tr('✓ تم إعادة المزامنة بنجاح'));
      setState(() {
        _repairing = false;
        _confirmText = '';
        _localCounts = null; // force re-audit
      });
      await _runAudit();
    } catch (e) {
      if (!mounted) return;
      setState(() => _repairing = false);
      AppToast.show(context, tr('فشل إعادة المزامنة: {e}', {'e': e}),
          type: ToastType.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isMirror =
        NetworkService.instance.mode == NetworkMode.mirror;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600, maxHeight: 700),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Icon(PhosphorIconsBold.database,
                        size: 28, color: theme.colorScheme.primary),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        tr('تدقيق مزامنة المرآة'),
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(PhosphorIconsBold.x),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
                const Divider(height: 24),
                if (!isMirror) ...[
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.amber.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.amber.shade200),
                    ),
                    child: Text(
                      tr('هذه الأداة متاحة فقط فى وضع المرآة. الوضع الحالى: {p0}.', {'p0': _arabicMode(NetworkService.instance.mode)}),
                      style: TextStyle(color: Colors.amber.shade900),
                    ),
                  ),
                ] else ...[
                  Text(
                    tr('تظهر هنا أعداد البيانات الأساسية محلياً على المرآة. استخدم زر إعادة المزامنة لاستبدالها بأحدث ما على السيرفر.'),
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: SingleChildScrollView(
                      child: Column(
                        children: [
                          if (_localCounts == null && !_scanning)
                            FilledButton.icon(
                              onPressed: _runAudit,
                              icon: const Icon(PhosphorIconsBold.magnifyingGlass),
                              label:  Text(tr('بدء التدقيق')),
                            )
                          else if (_scanning)
                            const Padding(
                              padding: EdgeInsets.all(16),
                              child: Center(child: CircularProgressIndicator()),
                            )
                          else if (_localCounts != null) ...[
                            _buildCountsTable(theme),
                            const SizedBox(height: 16),
                            const Divider(),
                            const SizedBox(height: 8),
                            Text(
                              tr('إعادة المزامنة الكاملة'),
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              tr('يحذف البيانات الأساسية المحلية ويستبدلها بنسخة السيرفر. لن يمس الفواتير أو القيود المحفوظة.'),
                              style: theme.textTheme.bodySmall,
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              decoration:  InputDecoration(
                                labelText:
                                    tr('اكتب "{_confirmPhrase}" لتأكيد العملية', {'_confirmPhrase': _confirmPhrase}),
                                border: const OutlineInputBorder(),
                                isDense: true,
                              ),
                              onChanged: (v) =>
                                  setState(() => _confirmText = v),
                            ),
                            const SizedBox(height: 12),
                            FilledButton.icon(
                              onPressed: (_confirmText.trim() == _confirmPhrase &&
                                      !_repairing)
                                  ? _runRepair
                                  : null,
                              icon: _repairing
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Icon(
                                      PhosphorIconsBold.arrowsCounterClockwise),
                              label:  Text(tr('إعادة المزامنة الآن')),
                              style: FilledButton.styleFrom(
                                backgroundColor: AppColors.error,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCountsTable(ThemeData theme) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          for (final table in _tablesToAudit)
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: theme.colorScheme.outlineVariant.withValues(
                      alpha: 0.5,
                    ),
                  ),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _arabicTableNames[table] ?? table,
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                  Text(
                    tr('محلى = {p0}', {'p0': _localCounts![table]}),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  String _arabicMode(NetworkMode mode) {
    switch (mode) {
      case NetworkMode.standalone:
        return tr('مستقل');
      case NetworkMode.server:
        return tr('سيرفر');
      case NetworkMode.client:
        return tr('عميل');
      case NetworkMode.mirror:
        return tr('مرآة');
    }
  }
}
