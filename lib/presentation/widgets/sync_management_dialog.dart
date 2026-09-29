import 'package:ural_erp/core/i18n/tr.dart';
// ignore_for_file: avoid_dynamic_calls
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../core/theme/app_colors.dart';
import '../../data/providers/providers.dart';
import '../../services/delta_pull_service.dart';
import '../../services/sync/sync_worker.dart';
import '../../services/sync_event_bus.dart';

class SyncManagementDialog extends ConsumerStatefulWidget {
  const SyncManagementDialog({super.key});

  static Future<void> show(BuildContext context) {
    return showDialog(
      context: context,
      builder: (context) => const SyncManagementDialog(),
    );
  }

  @override
  ConsumerState<SyncManagementDialog> createState() => _SyncManagementDialogState();
}

class _SyncManagementDialogState extends ConsumerState<SyncManagementDialog> {
  bool _reconciling = false;

  @override
  Widget build(BuildContext context) {
    final syncState = ref.watch(syncWorkerProvider);
    final db = ref.watch(databaseProvider);

    return DefaultTabController(
      length: 3,
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: Row(
            children: [
              const Icon(PhosphorIconsBold.cloudArrowUp, color: AppColors.primary),
              const SizedBox(width: 12),
               Text(tr('إدارة المزامنة')),
              const Spacer(),
              // Delta pull progress indicator
              ValueListenableBuilder<bool>(
                valueListenable: SyncEventBus.instance.isPulling,
                builder: (_, pulling, _) {
                  if (!pulling) return const SizedBox.shrink();
                  return  Tooltip(
                    message: tr('جارٍ سحب التحديثات من السيرفر...'),
                    child: const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.info,
                      ),
                    ),
                  );
                },
              ),
              if (syncState.isSyncing) ...[
                const SizedBox(width: 8),
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ],
            ],
          ),
          content: SizedBox(
            width: 620,
            height: 540,
            child: Column(
              children: [
                // Summary stats row
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildStat(
                        tr('بانتظار الإرسال'),
                        '${syncState.pendingCount}',
                        AppColors.warning,
                      ),
                      _buildStat(
                        tr('آخر إرسال'),
                        _formatTime(syncState.lastSyncTime),
                        AppColors.success,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                // Tab bar
                 TabBar(
                  tabs: [
                    Tab(
                      icon: const Icon(PhosphorIconsBold.cloudArrowUp, size: 14),
                      text: tr('الصادر'),
                    ),
                    Tab(
                      icon: const Icon(PhosphorIconsBold.warning, size: 14),
                      text: tr('التعارضات'),
                    ),
                    Tab(
                      icon: const Icon(PhosphorIconsBold.cloudArrowDown, size: 14),
                      text: tr('مزامنة واردة'),
                    ),
                  ],
                  labelStyle: const TextStyle(fontSize: 12),
                ),
                const SizedBox(height: 4),
                // Tab views
                Expanded(
                  child: TabBarView(
                    children: [
                      const _OutboxTab(),
                      _ConflictsTab(db: db),
                      const _DeltaPullTab(),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child:  Text(tr('إغلاق')),
            ),
            OutlinedButton.icon(
              onPressed: _reconciling ? null : () async {
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => Directionality(
                    textDirection: TextDirection.rtl,
                    child: AlertDialog(
                      title:  Text(tr('تأكيد مطابقة المزامنة')),
                      content: const Text(
                        'هذا الإجراء يضع كل العناصر المعلّقة/الفاشلة/دائمة الفشل '
                        'كـ"تم مزامنتها" بدون إعادة إرسالها للسيرفر.\n\n'
                        'استخدمه فقط بعد أن تتحقّق يدوياً من أن البيانات فعلاً '
                        'موجودة على السيرفر. هل أنت متأكد؟',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child:  Text(tr('إلغاء')),
                        ),
                        ElevatedButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.warning,
                          ),
                          child:  Text(tr('نعم، تأكيد المطابقة')),
                        ),
                      ],
                    ),
                  ),
                );
                if (confirmed != true || !context.mounted) return;
                setState(() => _reconciling = true);
                try {
                  final n = await db.markAllAsSyncedReconciled();
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(tr('تمت المطابقة — {n} سطر تم تعليمه كمزامَن', {'n': n})),
                      ),
                    );
                  }
                } finally {
                  if (mounted) setState(() => _reconciling = false);
                }
              },
              icon: const Icon(PhosphorIconsBold.checkCircle),
              label:  Text(tr('مطابقة الكل')),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.warning,
                side: const BorderSide(color: AppColors.warning),
              ),
            ),
            ElevatedButton.icon(
              onPressed: syncState.isSyncing
                  ? null
                  : () =>
                      ref.read(syncWorkerProvider.notifier).processOutbox(),
              icon: const Icon(PhosphorIconsBold.cloudArrowUp),
              label:  Text(tr('مزامنة الآن')),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStat(String label, String value, Color color) {
    return Column(
      children: [
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
        Text(
          value,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }

  String _formatTime(DateTime? time) {
    if (time == null) return tr('أبداً');
    return '${time.hour}:${time.minute.toString().padLeft(2, '0')}';
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Tab 0 — Outbox (pending / failed items)
// ═══════════════════════════════════════════════════════════════════════════

class _OutboxTab extends ConsumerWidget {
  const _OutboxTab();

  /// L4: classify error message into a user-friendly category chip.
  static String _categorizeError(String? error) {
    if (error == null) return tr('❓ خطأ');
    final s = error.toLowerCase();
    if (s.contains('authorization') || s.contains('cross-branch')) return tr('🔒 صلاحية');
    if (s.contains('not found') || s.contains('strict mapping')) return tr('🗺️ خريطة بيانات');
    if (s.contains('غير متوفر') || s.contains('validation error')) return tr('⚠️ بيانات');
    if (s.contains('connection') || s.contains('timeout') || s.contains('socket')) return tr('🌐 شبكة');
    if (s.contains('401') || s.contains('unauthorized') || s.contains('expired token')) return tr('🔑 مصادقة');
    if (s.contains('shift not found')) return tr('🕐 وردية');
    if (s.contains('item missing')) return tr('📦 منتج');
    return tr('❓ خطأ');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final syncRepo = ref.watch(syncRepositoryProvider);

    return StreamBuilder<List<SyncOutboxItem>>(
      stream: syncRepo.watchPendingItems(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final allItems = snapshot.data!;
        // L4: split by status — dead-letter items get their own banner with
        // a bulk retry button. Pending stay above unchanged.
        final deadLetterItems = allItems.where((i) => i.status == 'dead_letter').toList();
        final pendingItems = allItems.where((i) => i.status != 'dead_letter').toList();

        if (allItems.isEmpty) {
          return  Center(
            child: Text(
              tr('لا توجد عناصر بانتظار المزامنة'),
              style: const TextStyle(color: Colors.grey),
            ),
          );
        }

        return CustomScrollView(
          slivers: [
            // ── Dead-letter banner with bulk retry button ──
            if (deadLetterItems.isNotEmpty) ...[
              SliverToBoxAdapter(
                child: Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.error.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: [
                      const Icon(PhosphorIconsBold.warningCircle, color: AppColors.error),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          tr('{p0} عملية فشلت نهائياً — تحتاج مراجعة الأدمن', {'p0': deadLetterItems.length}),
                          style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.error),
                        ),
                      ),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.error,
                          foregroundColor: Colors.white,
                        ),
                        icon: const Icon(PhosphorIconsBold.arrowsClockwise, size: 16),
                        label:  Text(tr('إعادة محاولة الكل')),
                        onPressed: () async {
                          final count = await syncRepo.retryAllDeadLetterItems();
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(tr('تمت إعادة جدولة {count} عملية للمحاولة', {'count': count})),
                                backgroundColor: AppColors.success,
                              ),
                            );
                          }
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ],
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  // Show dead-letter first (red), then pending (yellow/grey)
                  final orderedItems = [...deadLetterItems, ...pendingItems];
                  final item = orderedItems[index];
                  return _buildItemTile(context, item, syncRepo);
                },
                childCount: allItems.length,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildItemTile(BuildContext context, SyncOutboxItem item, dynamic syncRepo) {
    final isDeadLetter = item.status == 'dead_letter';
    final isFailed = isDeadLetter || item.status == 'failed' || item.attempts > 0;
    final statusColor = isDeadLetter
        ? AppColors.error
        : (isFailed ? AppColors.warning : Colors.grey);
    final category = isFailed ? _categorizeError(item.lastError) : null;

    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        backgroundColor: statusColor.withValues(alpha: 0.15),
        child: Icon(
          _mapTableIcon(item.targetTable),
          color: statusColor,
          size: 20,
        ),
      ),
      title: Row(
        children: [
          Expanded(
            child: Text(
              '${_mapTableTitle(item.targetTable)} #${item.recordId}',
            ),
          ),
          if (category != null) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: statusColor.withValues(alpha: 0.4)),
              ),
              child: Text(
                category,
                style: TextStyle(fontSize: 10, color: statusColor, fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(width: 4),
          ],
          if (isDeadLetter)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.error.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: AppColors.error.withValues(alpha: 0.4)),
              ),
              child:  Text(
                tr('فشل نهائي'),
                style: const TextStyle(fontSize: 10, color: AppColors.error, fontWeight: FontWeight.bold),
              ),
            ),
        ],
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            tr('العملية: {p0} | المحاولات: {p1}', {'p0': _mapOperationTitle(item.operation), 'p1': item.attempts}),
          ),
          if (item.lastError != null)
            Text(
              tr('خطأ: {p0}', {'p0': item.lastError!.replaceAll('DEAD_LETTER: ', '')}),
              style: TextStyle(
                color: isDeadLetter ? AppColors.error : AppColors.warning,
                fontSize: 11,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
        ],
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(PhosphorIconsBold.arrowsClockwise, color: AppColors.info),
            tooltip: tr('إعادة محاولة'),
            onPressed: () async {
              await syncRepo.retryItem(item.id);
            },
          ),
          IconButton(
            icon: const Icon(PhosphorIconsBold.trash, color: AppColors.error),
            tooltip: tr('حذف'),
            onPressed: () async {
              await syncRepo.deleteItem(item.id);
            },
          ),
        ],
      ),
    );
  }

  String _mapTableTitle(String table) {
    switch (table) {
      case 'sales':
      case 'sales_invoices':
        return tr('فاتورة مبيعات');
      case 'sales_returns':
        return tr('مرتجع مبيعات');
      case 'purchase_invoices':
      case 'purchases':
        return tr('فاتورة مشتريات');
      case 'shifts':
        return tr('وردية');
      case 'expenses':
        return tr('مصروف');
      case 'receipts':
        return tr('قبض');
      case 'held_orders':
        return tr('طلب محفوظ');
      case 'parties':
        return tr('عميل / مورد');
      case 'products':
        return tr('صنف');
      case 'units':
        return tr('وحدة');
      default:
        return table;
    }
  }

  IconData _mapTableIcon(String table) {
    switch (table) {
      case 'sales':
      case 'sales_invoices':
      case 'sales_returns':
        return PhosphorIconsBold.receipt;
      case 'purchases':
      case 'purchase_invoices':
        return PhosphorIconsBold.truck;
      case 'shifts':
        return PhosphorIconsBold.clock;
      case 'expenses':
        return PhosphorIconsBold.arrowDown;
      case 'receipts':
        return PhosphorIconsBold.arrowUp;
      default:
        return PhosphorIconsBold.shoppingBag;
    }
  }

  String _mapOperationTitle(String op) {
    switch (op) {
      case 'insert':
        return tr('إضافة');
      case 'update':
        return tr('تعديل');
      case 'delete':
        return tr('حذف');
      case 'open':
        return tr('فتح');
      case 'close':
        return tr('إغلاق');
      default:
        return op;
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Tab 1 — Conflicts log
// ═══════════════════════════════════════════════════════════════════════════

class _ConflictsTab extends StatelessWidget {
  final AppDatabase db;
  const _ConflictsTab({required this.db});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<SyncConflictLogItem>>(
      future: db.auditDashboardDao.getSyncConflicts(limit: 50),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final conflicts = snapshot.data!;
        if (conflicts.isEmpty) {
          return  Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  PhosphorIconsBold.checkCircle,
                  color: AppColors.success,
                  size: 40,
                ),
                const SizedBox(height: 12),
                Text(
                  tr('لا توجد تعارضات مسجّلة'),
                  style: const TextStyle(color: Colors.grey),
                ),
              ],
            ),
          );
        }
        return ListView.separated(
          itemCount: conflicts.length,
          separatorBuilder: (_, _) => const Divider(),
          itemBuilder: (context, i) {
            final c = conflicts[i];
            final isClientWins = c.resolution == 'client_wins';
            final color = isClientWins ? AppColors.info : AppColors.warning;
            return ListTile(
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(
                backgroundColor: color.withValues(alpha: 0.15),
                child: Icon(
                  PhosphorIconsBold.warning,
                  color: color,
                  size: 18,
                ),
              ),
              title: Text(
                '${c.conflictTable} #${c.recordId}',
                style: const TextStyle(fontSize: 13),
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _mapResolution(c.resolution),
                    style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                  if (c.reason != null)
                    Text(
                      c.reason!,
                      style: const TextStyle(fontSize: 11, color: Colors.grey),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
              trailing: Text(
                _formatDate(c.detectedAt),
                style: const TextStyle(fontSize: 11, color: Colors.grey),
              ),
            );
          },
        );
      },
    );
  }

  String _mapResolution(String r) {
    switch (r) {
      case 'client_wins':
        return tr('البيانات المحلية أحدث — تم الاحتفاظ بها');
      case 'server_wins':
        return tr('السيرفر أحدث — تم التحديث');
      case 'skipped':
        return tr('تعارض — تم التخطي');
      case 'merged':
        return tr('تم الدمج');
      default:
        return r;
    }
  }

  String _formatDate(DateTime? time) {
    if (time == null) return '';
    return '${time.day}/${time.month} '
        '${time.hour}:${time.minute.toString().padLeft(2, '0')}';
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Tab 2 — Delta Pull watermarks + controls
// ═══════════════════════════════════════════════════════════════════════════

class _DeltaPullTab extends StatefulWidget {
  const _DeltaPullTab();

  @override
  State<_DeltaPullTab> createState() => _DeltaPullTabState();
}

class _DeltaPullTabState extends State<_DeltaPullTab> {
  Map<String, DateTime?>? _watermarks;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final wm = await DeltaPullService.instance.getAllWatermarks();
    if (mounted) setState(() => _watermarks = wm);
  }

  @override
  Widget build(BuildContext context) {
    if (_watermarks == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return Column(
      children: [
        Expanded(
          child: ListView(
            children: _watermarks!.entries.map((entry) {
              final wm = entry.value;
              return ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  wm != null
                      ? PhosphorIconsBold.cloudCheck
                      : PhosphorIconsBold.cloudSlash,
                  color: wm != null ? AppColors.success : Colors.grey,
                  size: 18,
                ),
                title: Text(entry.key, style: const TextStyle(fontSize: 13)),
                trailing: Text(
                  wm != null ? _formatDate(wm) : tr('لم تتم بعد'),
                  style: TextStyle(
                    fontSize: 12,
                    color: wm != null ? AppColors.success : Colors.grey,
                  ),
                ),
              );
            }).toList(),
          ),
        ),
        const Divider(),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _busy
                      ? null
                      : () async {
                          setState(() => _busy = true);
                          await DeltaPullService.instance.resetWatermarks();
                          await _load();
                          setState(() => _busy = false);
                        },
                  icon: _busy
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child:
                              CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(PhosphorIconsBold.arrowsCounterClockwise),
                  label:  Text(tr('إعادة ضبط')),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.warning,
                    side: const BorderSide(color: AppColors.warning),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _busy
                      ? null
                      : () async {
                          setState(() => _busy = true);
                          await DeltaPullService.instance.pullAll();
                          await _load();
                          setState(() => _busy = false);
                        },
                  icon: const Icon(PhosphorIconsBold.cloudArrowDown),
                  label:  Text(tr('سحب الآن')),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.info,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _formatDate(DateTime time) =>
      '${time.day}/${time.month} '
      '${time.hour}:${time.minute.toString().padLeft(2, '0')}';
}