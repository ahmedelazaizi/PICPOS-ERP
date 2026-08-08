import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:intl/intl.dart';
import '../../data/providers/providers.dart';
import '../../core/widgets/app_toast.dart';
import '../../domain/repositories/reporting_repository.dart';

/// Report Builder Screen — التقارير المخصصة
class ReportBuilderScreen extends ConsumerStatefulWidget {
  const ReportBuilderScreen({super.key});

  @override
  ConsumerState<ReportBuilderScreen> createState() => _ReportBuilderScreenState();
}

class _ReportBuilderScreenState extends ConsumerState<ReportBuilderScreen> {
  List<CustomReportData> _reports = [];
  CustomReportData? _selectedReport;
  List<Map<String, dynamic>> _results = [];
  bool _loading = true;
  bool _running = false;

  final _fmt = NumberFormat('#,##0.00', 'ar');

  @override
  void initState() {
    super.initState();
    _loadReports();
  }

  Future<void> _loadReports() async {
    setState(() => _loading = true);
    final repo = ref.read(reportingRepositoryProvider);
    final reports = await repo.getCustomReports();
    setState(() { _reports = reports; _loading = false; });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final repo = ref.watch(reportingRepositoryProvider);

    return Scaffold(
      body: Row(
        children: [
          // ─── Reports List ───
          SizedBox(
            width: 320,
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerLow,
                    border: Border(bottom: BorderSide(color: theme.dividerColor)),
                  ),
                  child: Row(
                    children: [
                      // Spec 057: back button — only when pushed onto navigator.
                      if (Navigator.canPop(context)) ...[
                        IconButton(
                          tooltip: 'رجوع',
                          icon: const Icon(PhosphorIconsBold.caretRight,
                              size: 20),
                          onPressed: () => Navigator.pop(context),
                          padding: EdgeInsets.zero,
                          constraints:
                              const BoxConstraints.tightFor(width: 32, height: 32),
                        ),
                        const SizedBox(width: 4),
                      ],
                      Icon(PhosphorIconsBold.chartBar, color: theme.colorScheme.primary),
                      const SizedBox(width: 8),
                      Text('التقارير المخصصة',
                          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                      const Spacer(),
                      FilledButton.icon(
                        onPressed: () => _showCreateReportDialog(repo),
                        icon: const Icon(Icons.add, size: 18),
                        label: const Text('جديد'),
                        style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8)),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: _loading
                      ? const Center(child: CircularProgressIndicator())
                      : _reports.isEmpty
                          ? Center(
                              child: Column(mainAxisSize: MainAxisSize.min, children: [
                                Icon(PhosphorIconsBold.chartBar,
                                    size: 48,
                                    color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.3)),
                                const SizedBox(height: 12),
                                Text('لا توجد تقارير مخصصة', style: theme.textTheme.bodyMedium),
                                const SizedBox(height: 8),
                                Text('أنشئ تقريرك الأول',
                                    style: theme.textTheme.bodySmall
                                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                              ]),
                            )
                          : ListView.builder(
                              itemCount: _reports.length,
                              itemBuilder: (ctx, i) => _buildReportTile(
                                  theme, _reports[i], _selectedReport?.id == _reports[i].id, repo),
                            ),
                ),
              ],
            ),
          ),
          VerticalDivider(width: 1, color: theme.dividerColor),
          Expanded(
            child: _selectedReport == null
                ? Center(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Icon(PhosphorIconsBold.arrowLeft,
                          size: 48,
                          color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.3)),
                      const SizedBox(height: 12),
                      Text('اختر تقريرًا أو أنشئ واحدًا جديدًا', style: theme.textTheme.bodyLarge),
                    ]),
                  )
                : _buildResultsPanel(theme, repo),
          ),
        ],
      ),
    );
  }

  Widget _buildReportTile(ThemeData theme, CustomReportData report, bool sel, IReportingRepository repo) {
    return ListTile(
      selected: sel,
      selectedTileColor: theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
      onTap: () => setState(() { _selectedReport = report; _results = []; }),
      leading: CircleAvatar(
        backgroundColor: theme.colorScheme.primaryContainer,
        child: Icon(_entityIcon(report.sourceEntity), size: 18, color: theme.colorScheme.onPrimaryContainer),
      ),
      title: Text(report.name, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(_entityLabel(report.sourceEntity), style: theme.textTheme.bodySmall),
      trailing: PopupMenuButton<String>(
        icon: const Icon(Icons.more_vert, size: 18),
        onSelected: (action) async {
          if (action == 'delete') {
            await repo.deleteCustomReport(report.id);
            _loadReports();
            if (_selectedReport?.id == report.id) {
              setState(() { _selectedReport = null; _results = []; });
            }
          }
        },
        itemBuilder: (ctx) => [
          const PopupMenuItem(
            value: 'delete',
            child: Row(children: [
              Icon(Icons.delete, size: 18, color: Colors.red),
              SizedBox(width: 8),
              Text('حذف', style: TextStyle(color: Colors.red)),
            ]),
          ),
        ],
      ),
    );
  }

  Widget _buildResultsPanel(ThemeData theme, IReportingRepository repo) {
    final report = _selectedReport!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerLow,
            border: Border(bottom: BorderSide(color: theme.dividerColor)),
          ),
          child: Row(children: [
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(report.name,
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 2),
              Text('الكيان: ${_entityLabel(report.sourceEntity)} | ${_results.length} سجل',
                  style: theme.textTheme.bodySmall),
            ]),
            const Spacer(),
            FilledButton.icon(
              onPressed: _running ? null : () => _executeReport(repo, report),
              icon: _running
                  ? const SizedBox(
                      width: 16, height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.play_arrow, size: 18),
              label: Text(_running ? 'تشغيل...' : 'تشغيل التقرير'),
            ),
          ]),
        ),
        Expanded(
          child: _results.isEmpty
              ? Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Icon(PhosphorIconsBold.play,
                        size: 48,
                        color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.3)),
                    const SizedBox(height: 12),
                    Text('اضغط "تشغيل التقرير" لعرض النتائج', style: theme.textTheme.bodyLarge),
                  ]),
                )
              : _buildResultsTable(theme),
        ),
      ],
    );
  }

  Widget _buildResultsTable(ThemeData theme) {
    if (_results.isEmpty) return const SizedBox.shrink();
    final columns = _results.first.keys.toList();
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: DataTable(
            headingRowColor: WidgetStateProperty.all(theme.colorScheme.surfaceContainerLow),
            columns: columns
                .map((c) => DataColumn(
                    label: Text(_fmtCol(c), style: const TextStyle(fontWeight: FontWeight.bold))))
                .toList(),
            rows: _results.map((row) {
              return DataRow(
                cells: columns.map((c) {
                  final v = row[c];
                  final s = v == null ? '—' : v is double ? _fmt.format(v) : v.toString();
                  return DataCell(Text(s, maxLines: 2));
                }).toList(),
              );
            }).toList(),
          ),
        ),
      ),
    );
  }

  Future<void> _executeReport(IReportingRepository repo, CustomReportData report) async {
    setState(() => _running = true);
    try {
      // منشئ التقارير بيقرا **أي** جدول بأي أعمدة، فمن غير الحصر ده مستخدم
      // محصور بفرع كان يقدر يبني تقريراً على sales_invoices أو parties ويشوف
      // الشركة كلها. الحصر بيتطبّق جوّه الاستعلام لكل كيان على حدة، وكيان
      // مالوش فلتر مدعوم بيرجّع فاضي بدل ما يتساب يسرّب.
      final scope = await ref.read(branchScopeProvider.future);
      final results = await repo.executeReport(report.id,
          allowedBranchIds: scope.allowedBranchIds);
      if (!mounted) return;
      setState(() { _results = results; _running = false; });
      if (results.isEmpty && !scope.hasFullAccess) {
        AppToast.show(
            context,
            'مفيش نتائج — بعض مصادر البيانات مش مدعومة للمستخدمين المحصورين بفرع',
            type: ToastType.info);
      }
    } catch (e) {
      setState(() => _running = false);
      if (mounted) AppToast.show(context, 'خطأ: $e', type: ToastType.error);
    }
  }

  Future<void> _showCreateReportDialog(IReportingRepository repo) async {
    final nameCtrl = TextEditingController();
    String sourceEntity = 'products';
    final selectedColumns = <String>[];

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final fields = repo.getAvailableFields(sourceEntity);
          return AlertDialog(
            title: const Row(children: [
              Icon(PhosphorIconsBold.plus, color: Colors.indigo),
              SizedBox(width: 8),
              Text('تقرير مخصص جديد'),
            ]),
            content: SizedBox(
              width: 500,
              height: 450,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(
                      labelText: 'اسم التقرير', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: sourceEntity,
                  decoration: const InputDecoration(
                      labelText: 'الكيان', border: OutlineInputBorder()),
                  items: const [
                    DropdownMenuItem(value: 'products', child: Text('الأصناف')),
                    DropdownMenuItem(value: 'parties', child: Text('العملاء/الموردين')),
                    DropdownMenuItem(value: 'sales_invoices', child: Text('فواتير المبيعات')),
                    DropdownMenuItem(value: 'purchase_invoices', child: Text('فواتير المشتريات')),
                    DropdownMenuItem(value: 'journal_entries', child: Text('قيود اليومية')),
                  ],
                  onChanged: (v) {
                    if (v != null) {
                      setDialogState(() {
                        sourceEntity = v;
                        selectedColumns.clear();
                      });
                    }
                  },
                ),
                const SizedBox(height: 16),
                const Align(
                  alignment: Alignment.centerRight,
                  child: Text('اختر الأعمدة:', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: ListView(
                    children: fields.map((f) {
                      final key = f['key']!;
                      final label = f['label']!;
                      return CheckboxListTile(
                        dense: true,
                        title: Text(label),
                        subtitle: Text(key, style: const TextStyle(fontSize: 11, color: Colors.grey)),
                        value: selectedColumns.contains(key),
                        onChanged: (v) {
                          setDialogState(() {
                            if (v == true) {
                              selectedColumns.add(key);
                            } else {
                              selectedColumns.remove(key);
                            }
                          });
                        },
                      );
                    }).toList(),
                  ),
                ),
              ]),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
              FilledButton(
                onPressed: () async {
                  if (nameCtrl.text.isEmpty || selectedColumns.isEmpty) {
                    AppToast.show(ctx, 'يرجى ملء الاسم واختيار أعمدة', type: ToastType.error);
                    return;
                  }
                  // columns is a comma-separated string
                  await repo.createCustomReport(
                    name: nameCtrl.text,
                    sourceEntity: sourceEntity,
                    columns: selectedColumns.join(', '),
                  );
                  if (ctx.mounted) Navigator.pop(ctx);
                  _loadReports();
                },
                child: const Text('إنشاء'),
              ),
            ],
          );
        },
      ),
    );
  }

  String _entityLabel(String t) => {
    'products': 'الأصناف',
    'parties': 'العملاء/الموردين',
    'sales_invoices': 'فواتير المبيعات',
    'purchase_invoices': 'فواتير المشتريات',
    'journal_entries': 'قيود اليومية',
  }[t] ?? t;

  IconData _entityIcon(String t) => {
    'products': PhosphorIconsBold.package,
    'parties': PhosphorIconsBold.usersThree,
    'sales_invoices': PhosphorIconsBold.receipt,
    'purchase_invoices': PhosphorIconsBold.shoppingCart,
    'journal_entries': PhosphorIconsBold.notebook,
  }[t] ?? PhosphorIconsBold.chartBar;

  String _fmtCol(String c) =>
      c.replaceAll('_', ' ').split(' ').map((w) => w.isEmpty ? w : w[0].toUpperCase() + w.substring(1)).join(' ');
}
