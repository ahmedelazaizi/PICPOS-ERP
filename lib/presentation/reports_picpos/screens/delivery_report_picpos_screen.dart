import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:picpos_erp/core/constants/app_constants.dart';
import 'package:picpos_erp/core/i18n/tr.dart';
import 'package:picpos_erp/core/permissions/permission_codes.dart';
import 'package:picpos_erp/core/theme/app_colors.dart';
import 'package:picpos_erp/data/providers/providers.dart';
import 'package:picpos_erp/services/client_write_interceptor.dart';
import '../../picpos_shell/picpos_content_card.dart';
import '../../picpos_shell/picpos_filter_strip.dart';
import '../../picpos_shell/picpos_hub_kpi.dart';
import '../../picpos_shell/picpos_screen_scaffold.dart';
import '../../picpos_shell/picpos_surface.dart';
import '../../widgets/branch_warehouse_filter.dart';
import '../../widgets/permission_guard.dart';
import '../../widgets/report_components.dart' show DateRangeFilter;
import '../../screens/reports/report_export_guard.dart';
import 'picpos_report_export.dart';

/// PicPos fork of delivery operations; repository calls and permission gates are unchanged.
class DeliveryReportPicposScreen extends ConsumerStatefulWidget {
  const DeliveryReportPicposScreen({super.key});

  @override
  ConsumerState<DeliveryReportPicposScreen> createState() =>
      _DeliveryReportPicposScreenState();
}

class _DeliveryReportPicposScreenState extends ConsumerState<DeliveryReportPicposScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  DateTime _from = DateRangeFilter.normalizeStart(DateTime.now().subtract(const Duration(days: 30)));
  DateTime _to = DateRangeFilter.normalizeEnd(DateTime.now());
  int? _regionId;
  int? _branchId;
  int? _warehouseId;
  List<int>? _branchWarehouses;
  List<int>? _regionWarehouses;
  Set<int>? _allowedBranches;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() { _tabs.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final scope = ref.watch(branchScopeProvider);
    if (scope.isLoading) return const Center(child: CircularProgressIndicator());
    if (scope.hasError) return Center(child: Text(tr('تعذر تحديد صلاحيات الفرع: {p0}', {'p0': scope.error})));
    _allowedBranches = scope.requireValue.hasFullAccess ? null : scope.requireValue.allowedBranchIds;
    final repo = ref.watch(reportingRepositoryProvider);
    final warehouseIds = _warehouseId == null ? (_branchWarehouses ?? _regionWarehouses) : [_warehouseId!];
    final report = repo.getDeliveryReport(from: _from, to: _to, warehouseIds: warehouseIds, allowedBranchIds: _allowedBranches);
    return PicPosScreenScaffold(
      title: tr('تقرير عمليات التوصيل'),
      subtitle: tr('إحصائيات المناديب ورسوم شركات التوصيل'),
      icon: PhosphorIconsBold.moped,
      headerActions: [
        buildReportExportAction(onExport: _exportToExcel),
        IconButton(tooltip: tr('تحديث'), icon: const Icon(PhosphorIconsBold.arrowClockwise), onPressed: () => setState(() {})),
      ],
      subHeader: Column(mainAxisSize: MainAxisSize.min, children: [
        PicPosFilterStrip(children: [
          PicPosFilterPill(icon: PhosphorIconsBold.calendarBlank, label: '${_date(_from)} → ${_date(_to)}', tabular: true, onTap: _pickRange),
          BranchWarehouseFilterBar(
            selectedRegionId: _regionId,
            selectedBranchId: _branchId,
            selectedWarehouseId: _warehouseId,
            onRegionChanged: (v) async {
              _regionId = v; _branchId = null; _warehouseId = null; _branchWarehouses = null;
              _regionWarehouses = v == null ? null : (await BranchWarehouseFilterBar.getRegionWarehouseIds(ref, v)).toList();
              if (mounted) setState(() {});
            },
            onBranchChanged: (v) async {
              _branchId = v; _warehouseId = null;
              _branchWarehouses = v == null ? null : (await BranchWarehouseFilterBar.getBranchWarehouseIds(ref, v)).toList();
              if (mounted) setState(() {});
            },
            onWarehouseChanged: (v) => setState(() => _warehouseId = v),
          ),
        ]),
        TabBar(controller: _tabs, labelColor: context.picposBrandInk, tabs: [
          Tab(text: tr('سجل العمليات'), icon: const Icon(PhosphorIconsBold.clipboardText)),
          Tab(text: tr('حسابات الشركات'), icon: const Icon(PhosphorIconsBold.handshake)),
        ]),
      ]),
      bodyPadding: EdgeInsets.zero,
      body: TabBarView(controller: _tabs, children: [
        _transactions(report),
        _companies(),
      ]),
    );
  }

  Widget _transactions(Future<List<Map<String, dynamic>>> future) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: future,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
        if (snap.hasError) return Center(child: Text(tr('خطأ: {p0}', {'p0': snap.error})));
        final data = snap.data ?? const <Map<String, dynamic>>[];
        final fees = data.fold<double>(0, (sum, item) => sum + (item['invoice'] as SalesInvoiceData).deliveryFee);
        if (data.isEmpty) return _empty(tr('لا توجد سجلات خلال هذه الفترة'), PhosphorIconsBold.moped);
        return Column(children: [
          Padding(padding: const EdgeInsets.all(12), child: PicPosHubKpiRow(items: [
            PicPosHubKpi(icon: PhosphorIconsBold.moped, label: tr('إجمالي العمليات'), value: data.length.toString(), tint: AppColors.primary, vs: tr('في الفترة المختارة')),
            PicPosHubKpi(icon: PhosphorIconsBold.money, label: tr('إجمالي الرسوم'), value: '${fees.toStringAsFixed(AppConstants.decimalPlaces)} ${AppConstants.currencySymbolEn}', tint: AppColors.success, vs: tr('رسوم التوصيل')),
          ])),
          Expanded(child: ListView.builder(itemCount: data.length, itemBuilder: (context, i) => _transactionCard(data[i]))),
        ]);
      },
    );
  }

  Widget _transactionCard(Map<String, dynamic> item) {
    final invoice = item['invoice'] as SalesInvoiceData;
    final courier = item['courier'] as Courier?;
    final company = item['company'] as DeliveryCompany?;
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(16, 4, 16, 4),
      child: PicPosContentCard(child: ListTile(
        leading: Icon(PhosphorIconsBold.receipt, color: context.picposBrandInk),
        title: Row(children: [Expanded(child: Text(tr('الفاتورة: {p0}', {'p0': invoice.invoiceNumber}))), Text('${invoice.deliveryFee.toStringAsFixed(AppConstants.decimalPlaces)} ${AppConstants.currencySymbolEn}', style: const TextStyle(color: AppColors.success, fontWeight: FontWeight.bold))]),
        subtitle: Text('${tr('التاريخ: {p0}', {'p0': DateFormat('yyyy-MM-dd HH:mm').format(invoice.invoiceDate)})}\n${tr('المندوب: {p0}', {'p0': courier?.name ?? tr('غير محدد')})}\n${tr('الشركة: {p0}', {'p0': company?.name ?? tr('بدون شركة')})}'),
        trailing: _status(invoice.deliveryStatus ?? 'pending'),
      )),
    );
  }

  Widget _companies() {
    return ref.watch(allDeliveryPartiesProvider).when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text(tr('خطأ: {p0}', {'p0': e}))),
      data: (companies) {
        if (companies.isEmpty) return _empty(tr('لا توجد شركات توصيل مسجلة في النظام'), PhosphorIconsBold.buildings);
        return ListView.builder(padding: const EdgeInsets.all(16), itemCount: companies.length, itemBuilder: (context, i) {
          final company = companies[i];
          return Padding(padding: const EdgeInsets.only(bottom: 10), child: PicPosContentCard(child: ListTile(
            leading: Icon(PhosphorIconsBold.buildings, color: context.picposBrandInk),
            title: Text(company.name),
            subtitle: Text(tr('الرصيد الحالي: {p0} {p1}', {'p0': company.balance.toStringAsFixed(AppConstants.decimalPlaces), 'p1': AppConstants.currencySymbolEn})),
            trailing: PermissionGuard(permission: PermissionCodes.reportsDeliveryRecon, allowManagerOverride: true, actionName: tr('تسوية حساب شركة توصيل'), onGranted: () => _reconcile(company), child: TextButton.icon(onPressed: () => _reconcile(company), icon: const Icon(PhosphorIconsBold.checkCircle), label: Text(tr('تسوية')))),
          )));
        });
      },
    );
  }

  Future<void> _exportToExcel() async {
    final repo = ref.read(reportingRepositoryProvider);
    final warehouseIds = _warehouseId == null ? (_branchWarehouses ?? _regionWarehouses) : [_warehouseId!];
    final data = await repo.getDeliveryReport(
      from: _from,
      to: _to,
      warehouseIds: warehouseIds,
      allowedBranchIds: _allowedBranches,
    );
    if (!mounted) return;
    await exportPicPosReport(
      context: context,
      ref: ref,
      title: tr('تقرير عمليات التوصيل'),
      headers: [tr('رقم الفاتورة'), tr('التاريخ'), tr('المندوب'), tr('الشركة'), tr('رسوم التوصيل'), tr('الحالة')],
      rows: [
        for (final item in data)
          () {
            final invoice = item['invoice'] as SalesInvoiceData;
            final courier = item['courier'] as Courier?;
            final company = item['company'] as DeliveryCompany?;
            return [
              invoice.invoiceNumber,
              DateFormat('yyyy-MM-dd HH:mm').format(invoice.invoiceDate),
              courier?.name ?? tr('غير محدد'),
              company?.name ?? tr('بدون شركة'),
              invoice.deliveryFee,
              invoice.deliveryStatus ?? 'pending',
            ];
          }(),
      ],
      periodFrom: _from,
      periodTo: _to,
      branchId: _branchId,
      scopedBranchIds: _allowedBranches,
    );
  }

  Future<void> _reconcile(Party company) async {
    final amount = TextEditingController(text: company.balance.abs().toString());
    final notes = TextEditingController();
    await showDialog<void>(context: context, builder: (dialogContext) => Directionality(textDirection: ui.TextDirection.rtl, child: AlertDialog(
      title: Text(tr('تسوية حساب - {p0}', {'p0': company.name})),
      content: Column(mainAxisSize: MainAxisSize.min, children: [TextField(controller: amount, decoration: InputDecoration(labelText: tr('المبلغ المطلوب'))), TextField(controller: notes, decoration: InputDecoration(labelText: tr('ملاحظات إضافية')))]),
      actions: [TextButton(onPressed: () => Navigator.pop(dialogContext), child: Text(tr('إلغاء'))), ElevatedButton(onPressed: () async {
        final value = double.tryParse(amount.text) ?? 0;
        if (value <= 0) return;
        final description = tr('تسوية حساب شركة توصيل: {p0}\n{p1}', {'p0': company.name, 'p1': notes.text});
        final intercepted = await ClientWriteInterceptor.createExpense(amount: value, category: 'delivery_recon', description: description);
        if (intercepted == null) await ref.read(treasuryRepositoryProvider).createPaymentVoucher(amount: value, category: 'delivery_recon', description: description, partyId: company.id);
        if (dialogContext.mounted) Navigator.pop(dialogContext);
      }, child: Text(tr('تأكيد التسوية')))],
    )));
  }

  Widget _status(String status) {
    final color = switch (status) { 'delivered' => AppColors.success, 'out_for_delivery' => AppColors.info, _ => AppColors.warning };
    final label = switch (status) { 'delivered' => tr('تم التوصيل'), 'out_for_delivery' => tr('قيد التوصيل'), _ => tr('قيد التجهيز') };
    return Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(999)), child: Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold)));
  }

  Widget _empty(String text, IconData icon) => Center(child: Column(mainAxisSize: MainAxisSize.min, children: [Icon(icon, size: 48, color: context.picposMuted), const SizedBox(height: 10), Text(text, style: TextStyle(color: context.picposMuted))]));
  Future<void> _pickRange() async {
    final picked = await showDateRangePicker(context: context, firstDate: DateTime(2020), lastDate: DateTime.now().add(const Duration(days: 1)), initialDateRange: DateTimeRange(start: _from, end: _to));
    if (picked != null) setState(() { _from = DateRangeFilter.normalizeStart(picked.start); _to = DateRangeFilter.normalizeEnd(picked.end); });
  }
  String _date(DateTime d) => '${d.year}/${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}';
}
