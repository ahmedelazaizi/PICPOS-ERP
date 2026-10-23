import 'package:picpos_erp/core/i18n/tr.dart';
import 'package:picpos_erp/core/theme/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:intl/intl.dart';
import '../../data/providers/providers.dart';
import '../../core/widgets/app_toast.dart';
import '../../domain/models/report_filter_condition.dart';
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

  /// السقفُ الذي اقتُطع عنده آخرُ تشغيل، أو `null` إن كان التقريرُ كاملاً.
  int? _truncatedAt;

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
                          tooltip: tr('رجوع'),
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
                      // العنوانُ مرن لا طبيعيّ الحجم: الشريطُ الجانبيّ مثبَّتٌ
                      // على ٣٢٠ بكسل مهما اتّسعت النافذة، فعنوانٌ بلا حدٍّ مع
                      // زرٍّ بجانبه يفيض أفقياً بخطٍّ أعرضَ قليلاً أو بعد
                      // ظهور زرّ الرجوع.
                      Expanded(
                        child: Text(tr('التقارير المخصصة'),
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.bold)),
                      ),
                      const SizedBox(width: 8),
                      FilledButton.icon(
                        onPressed: () => _showCreateReportDialog(repo),
                        icon: const Icon(Icons.add, size: 18),
                        label:  Text(tr('جديد')),
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
                                Text(tr('لا توجد تقارير مخصصة'), style: theme.textTheme.bodyMedium),
                                const SizedBox(height: 8),
                                Text(tr('أنشئ تقريرك الأول'),
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
                      Text(tr('اختر تقريرًا أو أنشئ واحدًا جديدًا'), style: theme.textTheme.bodyLarge),
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
           PopupMenuItem(
            value: 'delete',
            child: Row(children: [
              const Icon(Icons.delete, size: 18, color: AppColors.error),
              const SizedBox(width: 8),
              Text(tr('حذف'), style: const TextStyle(color: AppColors.error)),
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
              Text(tr('الكيان: {p0} | {p1} سجل', {'p0': _entityLabel(report.sourceEntity), 'p1': _results.length}),
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
              label: Text(_running ? tr('تشغيل...') : tr('تشغيل التقرير')),
            ),
          ]),
        ),
        if (_truncatedAt != null)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            color: Colors.orange.withValues(alpha: 0.15),
            child: Row(children: [
              const Icon(PhosphorIconsBold.warning,
                  size: 18, color: Colors.orange),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  tr('التقرير مقتطع عند {_truncatedAt} صف — البيانات أكثر من ذلك. الإجماليات المحسوبة من هذا الجدول ناقصة؛ ضيّق الفترة أو أضف فلتراً.', {'_truncatedAt': _truncatedAt}),
                  style: theme.textTheme.bodySmall
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
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
                    Text(tr('اضغط "تشغيل التقرير" لعرض النتائج'), style: theme.textTheme.bodyLarge),
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
      // القصُّ يُلتقط أثناء التنفيذ ويُعرَض **لافتةً ثابتة** لا رسالةً عابرة:
      // هو صفةٌ للتقرير المعروض لا حدثٌ لحظي، ومن يفوّت الرسالة يجمع أعمدةَ
      // تقريرٍ ناقصٍ ويقدّمها إجمالياً للفترة.
      int? truncatedAt;
      final results = await repo.executeReport(
        report.id,
        allowedBranchIds: scope.allowedBranchIds,
        onRowLimitReached: (limit) => truncatedAt = limit,
      );
      if (!mounted) return;
      setState(() {
        _results = results;
        _truncatedAt = truncatedAt;
        _running = false;
      });
      if (results.isEmpty && !scope.hasFullAccess) {
        AppToast.show(
            context,
            tr('مفيش نتائج — بعض مصادر البيانات مش مدعومة للمستخدمين المحصورين بفرع'),
            type: ToastType.info);
      }
    } catch (e) {
      setState(() => _running = false);
      if (mounted) AppToast.show(context, tr('خطأ: {e}', {'e': e}), type: ToastType.error);
    }
  }

  Future<void> _showCreateReportDialog(IReportingRepository repo) async {
    final nameCtrl = TextEditingController();
    String sourceEntity = 'products';
    final selectedColumns = <String>[];
    final conditions = <ReportFilterCondition>[];

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final fields = repo.getAvailableFields(sourceEntity);
          return AlertDialog(
            title:  Row(children: [
              const Icon(PhosphorIconsBold.plus, color: Colors.indigo),
              const SizedBox(width: 8),
              Text(tr('تقرير مخصص جديد')),
            ]),
            content: SizedBox(
              width: 500,
              height: 450,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                TextField(
                  controller: nameCtrl,
                  decoration:  InputDecoration(
                      labelText: tr('اسم التقرير'), border: const OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: sourceEntity,
                  decoration:  InputDecoration(
                      labelText: tr('الكيان'), border: const OutlineInputBorder()),
                  items:  [
                    DropdownMenuItem(value: 'products', child: Text(tr('الأصناف'))),
                    DropdownMenuItem(value: 'parties', child: Text(tr('العملاء/الموردين'))),
                    DropdownMenuItem(value: 'sales_invoices', child: Text(tr('فواتير المبيعات'))),
                    DropdownMenuItem(value: 'purchase_invoices', child: Text(tr('فواتير المشتريات'))),
                    DropdownMenuItem(value: 'journal_entries', child: Text(tr('قيود اليومية'))),
                  ],
                  onChanged: (v) {
                    if (v != null) {
                      setDialogState(() {
                        sourceEntity = v;
                        selectedColumns.clear();
                        // الشروطُ تُمسح مع الكيان: حقولُها من قائمةِ الكيان
                        // السابق، فلو بقيت لرُفض التقريرُ كلُّه عند التنفيذ.
                        conditions.clear();
                      });
                    }
                  },
                ),
                const SizedBox(height: 12),
                // تبويبان بدل حشرِ قسمٍ ثانٍ في ٤٥٠ بكسل: الأعمدةُ والفلاتر
                // كلاهما قائمةٌ تطول بعدد الحقول.
                Expanded(
                  child: DefaultTabController(
                    length: 2,
                    child: Column(children: [
                      TabBar(tabs: [
                         Tab(text: tr('الأعمدة')),
                        Tab(text: conditions.isEmpty
                            ? tr('الفلاتر')
                            : tr('الفلاتر ({p0})', {'p0': conditions.length})),
                      ]),
                      Expanded(
                        child: TabBarView(children: [
                          _buildColumnsTab(fields, selectedColumns,
                              setDialogState),
                          _buildFiltersTab(
                              repo, ctx, fields, conditions, setDialogState),
                        ]),
                      ),
                    ]),
                  ),
                ),
              ]),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child:  Text(tr('إلغاء'))),
              FilledButton(
                onPressed: () async {
                  if (nameCtrl.text.isEmpty || selectedColumns.isEmpty) {
                    AppToast.show(ctx, tr('يرجى ملء الاسم واختيار أعمدة'), type: ToastType.error);
                    return;
                  }
                  // شرطٌ بلا قيمة يُرفَض هنا لا بعد الحفظ: المحرِّك يرفض
                  // التقريرَ **كلَّه** لشرطٍ واحدٍ فاسد، فيُحفَظ تقريرٌ لا
                  // يُنتج صفاً واحداً أبداً بلا سببٍ ظاهر للمستخدم.
                  final incomplete = conditions.indexWhere((c) => !c.isComplete);
                  if (incomplete >= 0) {
                    AppToast.show(ctx,
                        tr('الشرط رقم {p0} ناقص — اختر حقلاً وقيمة', {'p0': incomplete + 1}),
                        type: ToastType.error);
                    return;
                  }
                  // columns is a comma-separated string
                  await repo.createCustomReport(
                    name: nameCtrl.text,
                    sourceEntity: sourceEntity,
                    columns: selectedColumns.join(', '),
                    filters: encodeReportFilters(conditions),
                  );
                  if (ctx.mounted) Navigator.pop(ctx);
                  _loadReports();
                },
                child:  Text(tr('إنشاء')),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildColumnsTab(List<Map<String, String>> fields,
      List<String> selectedColumns, StateSetter setDialogState) {
    return ListView(
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
    );
  }

  Widget _buildFiltersTab(
      IReportingRepository repo,
      BuildContext ctx,
      List<Map<String, String>> fields,
      List<ReportFilterCondition> conditions,
      StateSetter setDialogState) {
    return Column(children: [
      Expanded(
        child: conditions.isEmpty
            ?  Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(tr('بلا شروط — التقرير يشمل كل الصفوف'),
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.grey)),
                ),
              )
            : ListView.builder(
                itemCount: conditions.length,
                itemBuilder: (_, i) => _buildConditionRow(
                    repo, ctx, fields, conditions, i, setDialogState),
              ),
      ),
      Align(
        alignment: AlignmentDirectional.centerStart,
        child: TextButton.icon(
          icon: const Icon(PhosphorIconsBold.plus, size: 16),
          label:  Text(tr('إضافة شرط')),
          onPressed: fields.isEmpty
              ? null
              : () => setDialogState(() => conditions.add(
                  ReportFilterCondition.forField(fields.first, repo.getFilterOperators))),
        ),
      ),
    ]);
  }

  Widget _buildConditionRow(
      IReportingRepository repo,
      BuildContext ctx,
      List<Map<String, String>> fields,
      List<ReportFilterCondition> conditions,
      int index,
      StateSetter setDialogState) {
    final c = conditions[index];
    final ops = repo.getFilterOperators(c.type);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(children: [
        Row(children: [
          Expanded(
            flex: 4,
            child: DropdownButtonFormField<String>(
              initialValue: c.field,
              isExpanded: true,
              decoration:  InputDecoration(
                  labelText: tr('الحقل'),
                  isDense: true,
                  border: const OutlineInputBorder()),
              items: fields
                  .map((f) => DropdownMenuItem(
                      value: f['key'],
                      child: Text(f['label']!, overflow: TextOverflow.ellipsis)))
                  .toList(),
              onChanged: (v) {
                if (v == null) return;
                final f = fields.firstWhere((e) => e['key'] == v);
                // تغييرُ الحقل يعيد ضبطَ العامل والقيمة: عواملُ النصّ ليست
                // عواملَ الرقم، والقيمةُ المكتوبة لا تليق بالنوع الجديد.
                setDialogState(() =>
                    conditions[index] = ReportFilterCondition.forField(f, repo.getFilterOperators));
              },
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            flex: 3,
            child: DropdownButtonFormField<String>(
              initialValue: ops.any((o) => o['op'] == c.op) ? c.op : null,
              isExpanded: true,
              decoration:  InputDecoration(
                  labelText: tr('العامل'),
                  isDense: true,
                  border: const OutlineInputBorder()),
              items: ops
                  .map((o) => DropdownMenuItem(
                      value: o['op'],
                      child: Text(o['label']!, overflow: TextOverflow.ellipsis)))
                  .toList(),
              onChanged: (v) =>
                  setDialogState(() => conditions[index] = c.copyWith(op: v)),
            ),
          ),
          IconButton(
            tooltip: tr('حذف الشرط'),
            icon: const Icon(PhosphorIconsBold.trash, size: 18, color: AppColors.error),
            onPressed: () => setDialogState(() => conditions.removeAt(index)),
          ),
        ]),
        const SizedBox(height: 6),
        _buildValueField(ctx, conditions, index, setDialogState),
      ]),
    );
  }

  /// حقلُ القيمة **بحسب نوع الحقل**: منتقي تاريخ للتواريخ ومفتاحٌ للمنطقيّ
  /// ولوحةُ أرقام للأرقام. وليس تجميلاً: قيمةٌ لا تليق بالنوع يرفضها المحرِّك
  /// فيُرفَض التقريرُ كلُّه، والمستخدمُ لا يرى إلا صفراً من الصفوف.
  Widget _buildValueField(BuildContext ctx, List<ReportFilterCondition> conditions,
      int index, StateSetter setDialogState) {
    final c = conditions[index];
    switch (c.type) {
      case 'boolean':
        return SwitchListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: Text(c.value == 'true' ? tr('نعم') : tr('لا')),
          value: c.value == 'true',
          onChanged: (v) => setDialogState(
              () => conditions[index] = c.copyWith(value: '$v')),
        );
      case 'date':
        final picked = DateTime.tryParse(c.value);
        return OutlinedButton.icon(
          icon: const Icon(PhosphorIconsBold.calendarBlank, size: 16),
          label: Text(picked == null
              ? tr('اختر التاريخ')
              : DateFormat('yyyy-MM-dd').format(picked)),
          onPressed: () async {
            final d = await showDatePicker(
              context: ctx,
              initialDate: picked ?? DateTime.now(),
              firstDate: DateTime(2000),
              lastDate: DateTime(2100),
            );
            if (d == null) return;
            setDialogState(() => conditions[index] =
                c.copyWith(value: DateFormat('yyyy-MM-dd').format(d)));
          },
        );
      default:
        return TextFormField(
          // المفتاحُ يحمل الحقلَ لا الترتيبَ وحدَه: `initialValue` لا يُطبَّق
          // إلا على أوّل بناء، فبلا مفتاحٍ يتغيّر يبقى النصُّ المكتوبُ لحقلٍ
          // سابقٍ معروضاً بعد تبديل الحقل — بينما القيمةُ المخزَّنة صارت فارغة.
          key: ValueKey('rf-$index-${c.field}'),
          initialValue: c.value,
          keyboardType: c.type == 'number'
              ? const TextInputType.numberWithOptions(decimal: true, signed: true)
              : TextInputType.text,
          decoration: const InputDecoration(
              labelText: 'القيمة', isDense: true, border: OutlineInputBorder()),
          onChanged: (v) => conditions[index] = c.copyWith(value: v),
        );
    }
  }

  String _entityLabel(String t) => {
    'products': tr('الأصناف'),
    'parties': tr('العملاء/الموردين'),
    'sales_invoices': tr('فواتير المبيعات'),
    'purchase_invoices': tr('فواتير المشتريات'),
    'journal_entries': tr('قيود اليومية'),
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
