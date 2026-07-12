import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:ural_erp/core/utils/friendly_error.dart';
import 'package:ural_erp/core/widgets/app_toast.dart';
import 'package:ural_erp/presentation/widgets/dialogs/app_confirm_dialog.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/providers/providers.dart';

/// شاشة تعارضات المزامنة — Sync Conflicts Dashboard
/// تعرض سجل التعارضات بين الفروع/العملاء مع إمكانية حلها
class SyncConflictsScreen extends ConsumerStatefulWidget {
  const SyncConflictsScreen({super.key});

  @override
  ConsumerState<SyncConflictsScreen> createState() =>
      _SyncConflictsScreenState();
}

class _SyncConflictsScreenState extends ConsumerState<SyncConflictsScreen> {
  List<SyncConflictLogItem> _conflicts = [];
  List<String> _tableNames = [];
  String? _selectedTable;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadConflicts();
  }

  Future<void> _loadConflicts() async {
    setState(() => _isLoading = true);
    try {
      final db = ref.read(databaseProvider);
      final dao = db.auditDashboardDao;
      final conflicts =
          await dao.getSyncConflicts(tableName: _selectedTable, limit: 200);
      final tables = await dao.getConflictTableNames();

      if (mounted) {
        setState(() {
          _conflicts = conflicts;
          _tableNames = tables;
          _isLoading = false;
        });
      }
    } catch (e) {
      // BUG-U08: don't fail silently — the operator must know the screen could
      // not load conflicts (otherwise they assume sync is healthy).
      if (mounted) {
        setState(() => _isLoading = false);
        AppToast.show(context, friendlyError(e, context: 'SYNC-CONFLICTS'),
            type: ToastType.error);
      }
    }
  }

  Color _resolutionColor(String resolution) {
    switch (resolution) {
      case 'server_wins':
        return Colors.blue;
      case 'client_wins':
        return Colors.green;
      case 'merged':
        return Colors.orange;
      case 'skipped':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  String _resolutionLabel(String resolution) {
    switch (resolution) {
      case 'server_wins':
        return 'السيرفر';
      case 'client_wins':
        return 'العميل';
      case 'merged':
        return 'دمج';
      case 'skipped':
        return 'معلّق';
      default:
        return resolution;
    }
  }

  // BUG-U35: map raw DB table names to Arabic module labels for display.
  String _tableLabel(String table) {
    final t = table.toLowerCase();
    if (t.contains('product')) return 'المنتجات';
    if (t.contains('customer') || t.contains('part')) return 'العملاء/الموردون';
    if (t.contains('sale') || t.contains('invoice')) return 'الفواتير';
    if (t.contains('journal')) return 'القيود المحاسبية';
    if (t.contains('purchase')) return 'المشتريات';
    if (t.contains('branch')) return 'الفروع';
    if (t.contains('warehouse')) return 'المخازن';
    if (t.contains('account')) return 'الحسابات';
    if (t.contains('safe') || t.contains('treasury')) return 'الخزائن';
    if (t.contains('stock') || t.contains('inventory')) return 'المخزون';
    if (t.contains('setting')) return 'الإعدادات';
    return table; // unknown -> raw name
  }

  IconData _tableIcon(String table) {
    if (table.contains('product')) return PhosphorIconsBold.package;
    if (table.contains('part') || table.contains('customer')) {
      return PhosphorIconsBold.users;
    }
    if (table.contains('sale') || table.contains('invoice')) {
      return PhosphorIconsBold.receipt;
    }
    if (table.contains('journal')) return PhosphorIconsBold.bookOpen;
    if (table.contains('purchase')) return PhosphorIconsBold.shoppingCart;
    return PhosphorIconsBold.database;
  }

  Future<void> _resolveConflict(SyncConflictLogItem conflict, String resolution) async {
    // BUG-U06: this overwrites production data — confirm and spell out which
    // side wins before applying.
    final choice = _resolutionLabel(resolution);
    final ok = await AppConfirmDialog.show(
      context,
      title: 'تأكيد حل التعارض',
      message:
          'سيتم اعتماد بيانات "$choice" والكتابة فوق النسخة الأخرى نهائياً. هل تريد المتابعة؟',
      confirmLabel: 'اعتماد',
      isDangerous: true,
    );
    if (!ok || !mounted) return;
    final db = ref.read(databaseProvider);
    await db.auditDashboardDao.resolveConflict(conflict.id, resolution);
    await _loadConflicts();
  }

  void _showConflictDetails(SyncConflictLogItem conflict) {
    Map<String, dynamic>? clientData;
    Map<String, dynamic>? serverData;

    try {
      clientData = jsonDecode(conflict.clientPayload) as Map<String, dynamic>?;
    } catch (_) {}
    try {
      if (conflict.serverPayload != null) {
        serverData =
            jsonDecode(conflict.serverPayload!) as Map<String, dynamic>?;
      }
    } catch (_) {}

    showDialog(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: Row(
            children: [
              Icon(_tableIcon(conflict.conflictTable), color: AppColors.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text('تفاصيل التعارض — ${conflict.conflictTable}',
                    style: const TextStyle(fontSize: 16)),
              ),
            ],
          ),
          content: SizedBox(
            width: 600,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildInfoRow('السجل', conflict.recordId),
                  _buildInfoRow('الحالة', _resolutionLabel(conflict.resolution)),
                  if (conflict.reason != null)
                    _buildInfoRow('السبب', conflict.reason!),
                  if (conflict.clientId != null)
                    _buildInfoRow('العميل', conflict.clientId!),
                  _buildInfoRow('التاريخ', conflict.detectedAt.toString()),
                  const SizedBox(height: 16),
                  const Divider(),
                  const Text('📤 بيانات العميل',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.green.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
                    ),
                    child: SelectableText(
                      clientData != null
                          ? const JsonEncoder.withIndent('  ')
                              .convert(clientData)
                          : conflict.clientPayload,
                      style: const TextStyle(
                          fontFamily: 'monospace', fontSize: 11),
                    ),
                  ),
                  if (serverData != null || conflict.serverPayload != null) ...[
                    const SizedBox(height: 12),
                    const Text('📥 بيانات السيرفر',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.blue.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.blue.withValues(alpha: 0.3)),
                      ),
                      child: SelectableText(
                        serverData != null
                            ? const JsonEncoder.withIndent('  ')
                                .convert(serverData)
                            : conflict.serverPayload ?? '',
                        style: const TextStyle(
                            fontFamily: 'monospace', fontSize: 11),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            if (conflict.resolution == 'skipped') ...[
              TextButton.icon(
                onPressed: () {
                  Navigator.pop(ctx);
                  _resolveConflict(conflict, 'server_wins');
                },
                icon: const Icon(PhosphorIconsBold.cloudArrowDown, size: 16),
                label: const Text('قبول السيرفر'),
              ),
              TextButton.icon(
                onPressed: () {
                  Navigator.pop(ctx);
                  _resolveConflict(conflict, 'client_wins');
                },
                icon: const Icon(PhosphorIconsBold.desktopTower, size: 16),
                label: const Text('قبول العميل'),
              ),
            ],
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('إغلاق'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text('$label:',
                style: TextStyle(
                    fontWeight: FontWeight.bold, color: Colors.grey[700])),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final unresolvedCount =
        _conflicts.where((c) => c.resolution == 'skipped').length;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          title: Row(
            children: [
              const Text('تعارضات المزامنة'),
              if (unresolvedCount > 0) ...[
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.red,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text('$unresolvedCount',
                      style:
                          const TextStyle(color: Colors.white, fontSize: 12)),
                ),
              ],
            ],
          ),
          actions: [
            if (_tableNames.isNotEmpty)
              PopupMenuButton<String?>(
                icon: const Icon(PhosphorIconsBold.funnel),
                tooltip: 'فلتر حسب الجدول',
                onSelected: (table) {
                  setState(() => _selectedTable = table);
                  _loadConflicts();
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(value: null, child: Text('الكل')),
                  ..._tableNames.map((t) => PopupMenuItem(
                        value: t,
                        child: Row(
                          children: [
                            Icon(_tableIcon(t), size: 16),
                            const SizedBox(width: 8),
                            Text(_tableLabel(t)),
                          ],
                        ),
                      )),
                ],
              ),
            IconButton(
              icon: const Icon(PhosphorIconsBold.arrowClockwise),
              onPressed: _loadConflicts,
              tooltip: 'تحديث',
            ),
          ],
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _conflicts.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(PhosphorIconsBold.checkCircle,
                            size: 64, color: Colors.green[300]),
                        const SizedBox(height: 16),
                        const Text('لا توجد تعارضات',
                            style: TextStyle(fontSize: 18)),
                        const SizedBox(height: 4),
                        Text('جميع البيانات متزامنة بنجاح',
                            style: TextStyle(color: Colors.grey[500])),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _conflicts.length,
                    itemBuilder: (context, index) {
                      final c = _conflicts[index];
                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor:
                                _resolutionColor(c.resolution).withValues(alpha: 0.15),
                            child: Icon(_tableIcon(c.conflictTable),
                                color: _resolutionColor(c.resolution),
                                size: 20),
                          ),
                          title: Text(
                            '${_tableLabel(c.conflictTable)} — ${c.recordId}',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          subtitle: Text(
                            '${_resolutionLabel(c.resolution)} • ${c.detectedAt.toString().substring(0, 16)}',
                          ),
                          trailing: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: _resolutionColor(c.resolution)
                                  .withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              _resolutionLabel(c.resolution),
                              style: TextStyle(
                                color: _resolutionColor(c.resolution),
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                          ),
                          onTap: () => _showConflictDetails(c),
                        ),
                      );
                    },
                  ),
      ),
    );
  }
}
