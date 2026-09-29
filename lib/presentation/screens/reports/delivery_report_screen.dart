import 'package:ural_erp/core/i18n/tr.dart';
// ignore_for_file: avoid_dynamic_calls
import 'dart:async';
import 'package:flutter/material.dart';
// دفعة ١٢ — حارس reports_delivery_recon على زرار «تسوية».
import '../../../core/permissions/permission_codes.dart';
import '../../widgets/permission_guard.dart';
import 'package:ural_erp/core/widgets/app_toast.dart';
import 'dart:ui' as ui;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_state_view.dart';
import '../../../core/widgets/shimmer_loading.dart';
import '../../../core/logging/diagnostic_logger.dart';
import '../../../data/providers/providers.dart';
import '../../../core/constants/app_constants.dart';
import '../../../services/client_write_interceptor.dart';
import '../../widgets/branch_warehouse_filter.dart';
import '../../widgets/report_components.dart' show DateRangeFilter;
import '../../widgets/report_filter_bar.dart';
import 'report_export_guard.dart';

class DeliveryReportScreen extends ConsumerStatefulWidget {
  const DeliveryReportScreen({super.key});

  @override
  ConsumerState<DeliveryReportScreen> createState() =>
      _DeliveryReportScreenState();
}

class _DeliveryReportScreenState extends ConsumerState<DeliveryReportScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  // Spec 065: defaults are full-day-inclusive (D3-006).
  DateTime _fromDate = DateRangeFilter.normalizeStart(
      DateTime.now().subtract(const Duration(days: 30)));
  DateTime _toDate = DateRangeFilter.normalizeEnd(DateTime.now());

  DateTimeRange get _dateRange => DateTimeRange(start: _fromDate, end: _toDate);
  int? _selectedRegionId; // Feature 017
  int? _selectedBranchId;
  int? _selectedWarehouseId;
  List<int>? _branchWarehouseIds;
  List<int>? _regionWarehouseIds;

  // Spec 151 Track-3: the logged-in user's branch authorization scope — an
  // AUTH CAP distinct from the user-chosen warehouse/branch/region filter.
  // null = full access (admin/financial-manager/mirror/userId=1). This screen
  // builds its report future inside build(), so the scope is resolved there
  // (loading/error guard) and threaded into both the on-screen query and the
  // Excel export copy.
  Set<int>? _allowedBranchIds;

  // Feature 058: one-time guard for the no-branch-assigned inline notice.
  bool _noBranchNoticeShown = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    Future.microtask(() async {
      // Feature 058: seed _selectedBranchId from the device's active branch
      // BEFORE the first data fetch (FR-001 + FR-002).
      if (_selectedBranchId == null) {
        final activeBranchId = await ref.read(activeBranchIdProvider.future);
        if (!mounted) return;
        if (activeBranchId != null) {
          setState(() => _selectedBranchId = activeBranchId);
          // H13 · بذرُ الاسم وحدَه كان يخلّي القائمةَ تقول فرعاً والأرقامَ
          // تقول شركة: نطاقُ الاستعلام (`_branchWarehouseIds`) كان يُحلّ في
          // `onBranchChanged` فقط، فيفضل `null` على أوّل تحميل.
          // (‏هذه الشاشةُ وحدَها تخزّن النطاقَ `List` لا `Set`.)
          _branchWarehouseIds =
              (await BranchWarehouseFilterBar.getBranchWarehouseIds(
                      ref, activeBranchId))
                  .toList();
        } else if (!_noBranchNoticeShown) {
          _noBranchNoticeShown = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar( SnackBar(
              content: Text(tr('لم يتم تعيين فرع لهذا المستخدم — يتم عرض كل الفروع')),
              duration: const Duration(seconds: 6),
            ));
          });
        }
      }
      // #Forensic Log: Report View
      try {
        final user = ref.read(authProvider).user;
        ref.read(activityLoggerProvider).logReportView(user?.id ?? 0, user?.displayName ?? tr('مجهول'), tr('تقرير التوصيل'));
      } catch (_) {}
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Spec 151 Track-3: resolve the auth-level branch scope BEFORE building the
    // report future. The report MUST NOT render (even a flash) while the scope
    // is unknown — a restricted user briefly seeing an unscoped report is
    // itself the leak this fix closes.
    final scopeAsync = ref.watch(branchScopeProvider);
    if (scopeAsync.isLoading) {
      return const Directionality(
        textDirection: ui.TextDirection.rtl,
        child: Scaffold(body: Center(child: CircularProgressIndicator())),
      );
    }
    if (scopeAsync.hasError) {
      return Directionality(
        textDirection: ui.TextDirection.rtl,
        child: Scaffold(
          body: Center(child: Text(tr('تعذر تحديد صلاحيات الفرع: {p0}', {'p0': scopeAsync.error}))),
        ),
      );
    }
    final scope = scopeAsync.requireValue;
    _allowedBranchIds = scope.hasFullAccess ? null : scope.allowedBranchIds;

    final repo = ref.watch(reportingRepositoryProvider);

    // Build warehouseIds from filter state.
    // Feature 017 — region branch added so the region dropdown isn't a no-op.
    List<int>? warehouseIds;
    if (_selectedWarehouseId != null) {
      warehouseIds = [_selectedWarehouseId!];
    }

    final reportFuture = repo.getDeliveryReport(
      from: _fromDate,
      to: _toDate,
      warehouseIds: warehouseIds ?? _branchWarehouseIds ?? _regionWarehouseIds,
      allowedBranchIds: _allowedBranchIds,
    );
    final companiesAsync = ref.watch(allDeliveryPartiesProvider);

    return Directionality(
      textDirection: ui.TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          title:  Text(tr('تقرير عمليات التحصيل')),
          bottom: TabBar(
            controller: _tabController,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            indicatorColor: Colors.white,
            tabs:  [
              Tab(
                text: tr('سجل العمليات'),
                icon: const Icon(PhosphorIconsBold.clipboardText),
              ),
              Tab(
                text: tr('حسابات الشركات'),
                icon: const Icon(PhosphorIconsBold.handshake),
              ),
            ],
          ),
          actions: [
            buildReportExportAction(onExport: _exportToExcel),
            buildReportPrintAsExportAction(onExport: _exportToExcel),
            IconButton(
              icon: const Icon(PhosphorIconsBold.calendar),
              onPressed: _selectDateRange,
              tooltip: tr('تغيير الفترة'),
            ),
          ],
        ),
        body: TabBarView(
          controller: _tabController,
          children: [
            // Tab 1: Transaction Log
            Column(
              children: [
                // Spec 076: unified two-row filter bar.
                ReportFilterBar(
                  selectedRange:
                      DateTimeRange(start: _fromDate, end: _toDate),
                  onRangeChanged: (start, end) {
                    setState(() {
                      _fromDate = start;
                      _toDate = end;
                    });
                  },
                  trailing: [
                    BranchWarehouseFilterBar(
                      selectedRegionId: _selectedRegionId,
                      selectedBranchId: _selectedBranchId,
                      selectedWarehouseId: _selectedWarehouseId,
                      onRegionChanged: (v) async {
                        _selectedRegionId = v;
                        _selectedBranchId = null;
                        _selectedWarehouseId = null;
                        _branchWarehouseIds = null;
                        if (v != null) {
                          final ids = await BranchWarehouseFilterBar.getRegionWarehouseIds(ref, v);
                          _regionWarehouseIds = ids.toList();

                          // Spec 079 / B1+FR-003: warn when region selection yields zero

                          // warehouses (data-integrity hint for the operator).

                          final regionIdsCheck = _regionWarehouseIds;

                          if (regionIdsCheck != null && regionIdsCheck.isEmpty) {

                            unawaited(DiagnosticLogger.log(

                              'FILTER-WARN',

                              'Region \$v selected but no warehouses linked. '

                              'Check that branches in this region have a regionId, '

                              'and their warehouses have branchId set.',

                            ));

                          }

                        } else {
                          _regionWarehouseIds = null;
                        }
                        setState(() {});
                      },
                      onBranchChanged: (v) async {
                        _selectedBranchId = v;
                        _selectedWarehouseId = null;
                        if (v != null) {
                          final ids = await BranchWarehouseFilterBar.getBranchWarehouseIds(ref, v);
                          _branchWarehouseIds = ids.toList();
                        } else {
                          _branchWarehouseIds = null;
                        }
                        setState(() {});
                      },
                      onWarehouseChanged: (v) {
                        setState(() => _selectedWarehouseId = v);
                      },
                    ),
                  ],
                ),
                _buildSummaryBar(reportFuture),
                Expanded(child: _buildReportList(reportFuture)),
              ],
            ),
            // Tab 2: Company Reconciliation
            _buildReconciliationTab(companiesAsync),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryBar(Future<List<Map<String, dynamic>>> reportFuture) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: reportFuture,
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const SizedBox.shrink();
        final data = snapshot.data!;
        final totalDeliveries = data.length;
        final totalFees = data.fold<double>(
          0,
          (sum, item) =>
              sum + (item['invoice'] as SalesInvoiceData).deliveryFee,
        );

        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.1),
            border: const Border(
              bottom: BorderSide(color: AppColors.primary, width: 0.1),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildSummaryItem(
                tr('إجمالي العمليات'),
                totalDeliveries.toString(),
                PhosphorIconsBold.moped,
                Colors.blue,
              ),
              _buildSummaryItem(
                tr('إجمالي الرسوم'),
                '${totalFees.toStringAsFixed(AppConstants.decimalPlaces)} ${AppConstants.currencySymbolEn}',
                PhosphorIconsBold.money,
                Colors.green,
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSummaryItem(
    String label,
    String value,
    IconData icon,
    Color color,
  ) {
    return Column(
      children: [
        Icon(icon, color: color, size: 28),
        const SizedBox(height: 8),
        Text(
          label,
          style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
        ),
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

  Widget _buildReportList(Future<List<Map<String, dynamic>>> reportFuture) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: reportFuture,
      builder: (context, snapshot) {
        final data = snapshot.data ?? [];
        return AppStateView(
          isLoading: snapshot.connectionState == ConnectionState.waiting,
          error: snapshot.hasError ? tr('خطأ: {p0}', {'p0': snapshot.error}) : null,
          isEmpty: data.isEmpty,
          emptyMessage: tr('لا توجد سجلات خلال هذه الفترة'),
          emptyIcon: PhosphorIconsBold.moped,
          child: ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: data.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final item = data[index];
              final invoice = item['invoice'] as SalesInvoiceData;
              final courier = item['courier'] as Courier?;
              final company = item['company'] as DeliveryCompany?;

              return Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: Colors.grey.withValues(alpha: 0.2)),
                ),
                child: ListTile(
                  title: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        tr('الفاتورة: {p0}', {'p0': invoice.invoiceNumber}),
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      Text(
                        '${invoice.deliveryFee.toStringAsFixed(AppConstants.decimalPlaces)} ${AppConstants.currencySymbolEn}',
                        style: const TextStyle(
                          color: AppColors.success,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 4),
                      Text(
                        tr('التاريخ: {p0}', {'p0': DateFormat('yyyy-MM-dd HH:mm').format(invoice.invoiceDate)}),
                      ),
                      Text(tr('المندوب: {p0}', {'p0': courier?.name ?? "غير محدد"})),
                      Text(tr('الشركة: {p0}', {'p0': company?.name ?? "بدون شركة"})),
                      const SizedBox(height: 4),
                      _buildStatusBadge(invoice.deliveryStatus ?? 'pending'),
                    ],
                  ),
                ),
              );
            },
          ), // ListView.separated
        ); // AppStateView
      },
    );
  }

  Widget _buildReconciliationTab(AsyncValue<List<Party>> companiesAsync) {
    return companiesAsync.when(
      data: (companies) {
        if (companies.isEmpty) {
          return  Center(
            child: Text(tr('لا توجد شركات توصيل مسجلة في النظام')),
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: companies.length,
          itemBuilder: (context, index) {
            final company = companies[index];
            final balance = company.balance;
            return Card(
              margin: const EdgeInsets.only(bottom: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: ListTile(
                contentPadding: const EdgeInsets.all(16),
                leading: CircleAvatar(
                  backgroundColor: AppColors.primary.withValues(alpha: 0.1),
                  child: const Icon(
                    PhosphorIconsBold.buildings,
                    color: AppColors.primary,
                  ),
                ),
                title: Text(
                  company.name,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
                subtitle: Text(
                  tr('الرصيد الحالي: {p0} {p1}', {'p0': balance.toStringAsFixed(AppConstants.decimalPlaces), 'p1': AppConstants.currencySymbolEn}),
                ),
                // reports_delivery_recon — مش عرض تقرير: الديالوج اللي
                // بيفتحه بيعمل حركة فلوس حقيقية (سند صرف + قيد في الأستاذ
                // عبر `ClientWriteInterceptor.createExpense`). الوصول للشاشة
                // بـ`reports_view` مش بديل عن تصريح بتحريك فلوس.
                //
                // الحارس على زرار «تسوية» نفسه — أنضف نقطة واحدة، لأن
                // الديالوج مالوش طريق تاني غيرها.
                trailing: PermissionGuard(
                  permission: PermissionCodes.reportsDeliveryRecon,
                  allowManagerOverride: true,
                  actionName: tr('تسوية حساب شركة توصيل'),
                  onGranted: () => _showReconciliationDialog(company),
                  child: ElevatedButton.icon(
                    onPressed: () => _showReconciliationDialog(company),
                    icon: const Icon(PhosphorIconsBold.checkCircle),
                    label:  Text(tr('تسوية')),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: balance > 0 ? Colors.green : Colors.grey,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
      loading: () => Padding(
        padding: const EdgeInsets.all(16),
        child: ShimmerLoading.list(itemCount: 6),
      ),
      error: (e, s) => Center(child: Text(tr('خطأ: {e}', {'e': e}))),
    );
  }

  Future<void> _showReconciliationDialog(Party company) async {
    final amountController = TextEditingController(
      text: company.balance.abs().toString(),
    );
    final notesController = TextEditingController();

    return showDialog(
      context: context,
      builder: (context) => Directionality(
        textDirection: ui.TextDirection.rtl,
        child: AlertDialog(
          title: Text(tr('تسوية حساب - {p0}', {'p0': company.name})),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: amountController,
                decoration: InputDecoration(
                  labelText: tr('المبلغ المطلوب'),
                  suffixText: AppConstants.currencySymbolEn,
                ),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: notesController,
                decoration:  InputDecoration(labelText: tr('ملاحظات إضافية')),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child:  Text(tr('إلغاء')),
            ),
            ElevatedButton(
              onPressed: () async {
                final amount = double.tryParse(amountController.text) ?? 0;
                if (amount <= 0) return;

                // Track as treasury entry — route through interceptor for client sync.
                // partyId is passed so createPaymentVoucher updates parties.balance
                // and posts the GL atomically (Dr: delivery_recon / Cr: Cash).
                // When the interceptor fires, the server owns the full operation
                // (balance + GL), so we must NOT call adjustPartyBalance here.
                final desc = tr('تسوية حساب شركة توصيل: {p0}\n{p1}', {'p0': company.name, 'p1': notesController.text});
                final intercepted = await ClientWriteInterceptor.createExpense(
                  amount: amount,
                  category: 'delivery_recon',
                  description: desc,
                );
                if (intercepted == null) {
                  final treasuryRepo = ref.read(treasuryRepositoryProvider);
                  await treasuryRepo.createPaymentVoucher(
                    amount: amount,
                    category: 'delivery_recon',
                    description: desc,
                    partyId: company.id,
                  );
                }

                if (context.mounted) {
                  Navigator.pop(context);
                }
                if (context.mounted) {
                  AppToast.show(context, tr('تمت التسوية المالية بنجاح'));
                }
              },
              child:  Text(tr('تأكيد التسوية')),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusBadge(String status) {
    Color color = Colors.grey;
    String label = status;
    switch (status) {
      case 'pending':
        color = Colors.orange;
        label = tr('قيد التجهيز');
        break;
      case 'out_for_delivery':
        color = Colors.blue;
        label = tr('قيد التوصيل');
        break;
      case 'delivered':
        color = Colors.green;
        label = tr('تم التوصيل');
        break;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Future<void> _selectDateRange() async {
    final DateTimeRange? picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      initialDateRange: _dateRange,
      locale: const Locale('ar'),
    );
    if (picked != null) {
      setState(() {
        _fromDate = DateRangeFilter.normalizeStart(picked.start);
        _toDate = DateRangeFilter.normalizeEnd(picked.end); // FIL-6: end-of-day
      });
    }
  }

  Future<void> _exportToExcel() async {
    try {
      final repo = ref.read(reportingRepositoryProvider);
      // Feature 017 — same scope cascade as the live report so Excel
      // export honours the region selection too.
      List<int>? warehouseIds;
      if (_selectedWarehouseId != null) {
        warehouseIds = [_selectedWarehouseId!];
      } else if (_branchWarehouseIds != null) {
        warehouseIds = _branchWarehouseIds!.toList();
      } else if (_regionWarehouseIds != null) {
        warehouseIds = _regionWarehouseIds!.toList();
      }
      final data = await repo.getDeliveryReport(
        from: _fromDate,
        to: _toDate,
        warehouseIds: warehouseIds,
        allowedBranchIds: _allowedBranchIds,
      );
      if (data.isEmpty) {
        if (mounted) AppToast.show(context, tr('لا توجد بيانات للتصدير'), type: ToastType.error);
        return;
      }
      final service = ref.read(excelServiceProvider);
      final path = await service.exportReport(
      periodFrom: _fromDate,
      periodTo: _toDate,
      branchId: _selectedBranchId,
      scopedBranchIds:
          (await ref.read(branchScopeProvider.future)).allowedBranchIds,
        title: tr('تقرير عمليات التحصيل'),
        headers: [
          tr('رقم الفاتورة'),
          tr('التاريخ'),
          tr('المندوب'),
          tr('الشركة'),
          tr('رسوم التوصيل'),
          tr('الحالة'),
        ],
        rows: data.map<List<dynamic>>((item) {
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
        }).toList(),
      );
      if (path != null && mounted) {
        AppToast.show(context, tr('تم تصدير التقرير بنجاح: \$path'), type: ToastType.success);
        try {
          final user = ref.read(authProvider).user;
          ref.read(activityLoggerProvider).logReportExport(user?.id ?? 0, user?.displayName ?? tr('مجهول'), tr('تقرير التوصيل'), 'Excel');
        } catch (_) {}
      }
    } catch (e) {
      if (mounted) AppToast.show(context, tr('خطأ في التصدير: \$e'), type: ToastType.error);
    }
  }
}