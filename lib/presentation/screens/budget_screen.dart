// ignore_for_file: avoid_dynamic_calls
import 'package:ural_erp/core/constants/app_constants.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/theme/app_colors.dart';
import '../../data/providers/providers.dart';
import '../../domain/usecases/accounting/cashflow_forecast_usecase.dart';
import 'create_budget_dialog.dart';
import 'budget_details_dialog.dart';

/// Budget Management Screen — إدارة الموازنات
class BudgetScreen extends ConsumerStatefulWidget {
  const BudgetScreen({super.key});

  @override
  ConsumerState<BudgetScreen> createState() => _BudgetScreenState();
}

class _BudgetScreenState extends ConsumerState<BudgetScreen> {
  int _selectedTab = 0; // 0=budgets, 1=vs_actual, 2=forecast
  FiscalYearData? _selectedFiscalYear;
  List<FiscalYearData> _fiscalYears = [];

  @override
  void initState() {
    super.initState();
    _loadFiscalYears();
  }

  Future<void> _loadFiscalYears() async {
    final repo = ref.read(accountingRepositoryProvider);
    final years = await repo.getFiscalYears();
    if (mounted) {
      setState(() {
        _fiscalYears = years;
        if (years.isNotEmpty) {
          _selectedFiscalYear = years.firstWhere((y) => y.isCurrent, orElse: () => years.first);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AppColors.surface,
        body: Column(
          children: [
            _buildHeader(context),
            _buildTabBar(),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF4527A0), Color(0xFF7C4DFF)],
          begin: AlignmentDirectional.topEnd, end: AlignmentDirectional.bottomStart,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(12)),
            child: const Icon(PhosphorIconsBold.chartBar, color: Colors.white, size: 24),
          ),
          const SizedBox(width: 14),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('الموازنات والتنبؤ', style: GoogleFonts.cairo(fontSize: 20, fontWeight: FontWeight.w800, color: Colors.white)),
              Text('Budget vs Actual — التخطيط المالي والرقابة', style: GoogleFonts.cairo(fontSize: 11, color: Colors.white.withValues(alpha: 0.7))),
            ],
          ),
          const Spacer(),
          ElevatedButton.icon(
            onPressed: () => _showCreateBudgetDialog(context),
            icon: const Icon(PhosphorIconsBold.plus, size: 18),
            label: Text('موازنة جديدة', style: GoogleFonts.cairo(fontWeight: FontWeight.w700)),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white, foregroundColor: const Color(0xFF4527A0),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabBar() {
    return Container(
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.border))),
      child: Row(
        children: [
          _tab('الموازنات', PhosphorIconsBold.listBullets, 0),
          _tab('موازنة مقابل الفعلي', PhosphorIconsBold.chartLineUp, 1),
          _tab('توقعات التدفق النقدي', PhosphorIconsBold.trendUp, 2),
        ],
      ),
    );
  }

  Widget _tab(String label, IconData icon, int index) {
    final isActive = _selectedTab == index;
    return InkWell(
      onTap: () => setState(() => _selectedTab = index),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: isActive ? AppColors.primary : Colors.transparent, width: 2)),
        ),
        child: Row(
          children: [
            Icon(icon, size: 16, color: isActive ? AppColors.primary : AppColors.textMuted),
            const SizedBox(width: 8),
            Text(label, style: GoogleFonts.cairo(fontSize: 13, fontWeight: isActive ? FontWeight.w700 : FontWeight.w500, color: isActive ? AppColors.primary : AppColors.textMuted)),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    switch (_selectedTab) {
      case 1: return _buildBudgetVsActual();
      case 2: return _buildCashFlowForecast();
      default: return _buildBudgetsList();
    }
  }

  Widget _buildBudgetsList() {
    if (_fiscalYears.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(PhosphorIconsBold.calendarBlank, size: 64, color: AppColors.textMuted),
            const SizedBox(height: 16),
            Text('لا توجد سنوات مالية مسجلة', style: GoogleFonts.cairo(fontSize: 16, color: AppColors.textMuted)),
            const SizedBox(height: 8),
            Text('يجب إنشاء سنة مالية أولاً من إعدادات الفترات المالية', style: GoogleFonts.cairo(fontSize: 12, color: AppColors.textMuted)),
          ],
        ),
      );
    }
  
    final budgetRepo = ref.watch(budgetRepositoryProvider);
    final accountingRepo = ref.watch(accountingRepositoryProvider);
    return Column(
      children: [
        // Year filter bar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          decoration: BoxDecoration(
            color: AppColors.surface,
            border: Border(bottom: BorderSide(color: AppColors.border.withValues(alpha: 0.5))),
          ),
          child: Row(
            children: [
              Text('السنة:', style: GoogleFonts.cairo(fontWeight: FontWeight.w700)),
              const SizedBox(width: 12),
              SizedBox(
                width: 250,
                child: DropdownButtonFormField<FiscalYearData>(
                  initialValue: _selectedFiscalYear,
                  decoration: InputDecoration(
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  items: _fiscalYears.map((y) => DropdownMenuItem(value: y, child: Text(y.name, style: GoogleFonts.cairo()))).toList(),
                  onChanged: (v) => setState(() => _selectedFiscalYear = v),
                ),
              ),
            ],
          ),
        ),
        // Budget List
        Expanded(
          child: _selectedFiscalYear == null ? const SizedBox.shrink() : StreamBuilder<List<BudgetData>>(
            stream: Stream.fromFuture(budgetRepo.getBudgetsForYear(_selectedFiscalYear!.id)), // Wrapped in future for now, could be stream
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
              final budgets = snapshot.data ?? [];
              
              if (budgets.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(PhosphorIconsBold.chartBar, size: 64, color: AppColors.textMuted),
                      const SizedBox(height: 16),
                      Text('لا توجد موازنات في هذه السنة', style: GoogleFonts.cairo(fontSize: 16, color: AppColors.textMuted)),
                      const SizedBox(height: 8),
                      Text('أنشئ موازنة للنقر عليها وتعديل تفاصيلها الشهرية', style: GoogleFonts.cairo(fontSize: 12, color: AppColors.textMuted)),
                    ],
                  ),
                );
              }

              return ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: budgets.length,
                itemBuilder: (context, index) {
                  final budget = budgets[index];
                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8), side: const BorderSide(color: AppColors.border)),
                    elevation: 0,
                    child: InkWell(
                      onTap: () => _showBudgetDetailsDialog(context, budget),
                      borderRadius: BorderRadius.circular(8),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                              child: const Icon(PhosphorIconsBold.folderOpen, color: AppColors.primary, size: 20),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(budget.name ?? 'موازنة بدون اسم', style: GoogleFonts.cairo(fontSize: 14, fontWeight: FontWeight.w700)),
                                  FutureBuilder<Account?>(
                                    future: accountingRepo.getAccountById(budget.accountId),
                                    builder: (context, accSnap) {
                                      final acc = accSnap.data;
                                      return Text(acc != null ? '${acc.code} - ${acc.name}' : 'حساب #${budget.accountId}', style: GoogleFonts.cairo(fontSize: 12, color: AppColors.textMuted));
                                    }
                                  ),
                                ],
                              ),
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text('المبلغ السنوي', style: GoogleFonts.cairo(fontSize: 10, color: AppColors.textMuted)),
                                Text(budget.annualAmount.toStringAsFixed(AppConstants.decimalPlaces), style: GoogleFonts.jetBrainsMono(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.primaryDark)),
                              ],
                            ),
                            const SizedBox(width: 16),
                            const Icon(PhosphorIconsBold.caretLeft, size: 16, color: AppColors.textMuted),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Future<void> _showBudgetDetailsDialog(BuildContext context, BudgetData budget) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => BudgetDetailsDialog(budget: budget),
    );
    if (result == true) {
      // Refresh the budget list since amount or distribution might have changed
      setState(() {});
    }
  }

  Widget _buildBudgetVsActual() {
    if (_selectedFiscalYear == null) {
      return Center(child: Text('الرجاء اختيار السنة المالية أولاً', style: GoogleFonts.cairo()));
    }

    final repo = ref.watch(budgetRepositoryProvider);
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: (() async {
        try { 
          return await repo.getBudgetVsActualReport(_selectedFiscalYear!.id); 
        } catch (e) { 
          debugPrint('Error loading budget vs actual: $e');
          return <Map<String, dynamic>>[]; 
        }
      })(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final reportData = snapshot.data ?? [];
        
        if (reportData.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(PhosphorIconsBold.chartLineUp, size: 48, color: AppColors.textMuted),
                const SizedBox(height: 16),
                Text('لا توجد موازنات متاحة لهذه السنة المالية', style: GoogleFonts.cairo(color: AppColors.textMuted, fontSize: 16)),
              ],
            ),
          );
        }

        double grandTotalPlanned = 0;
        double grandTotalActual = 0;

        for (final row in reportData) {
          grandTotalPlanned += (row['totalPlanned'] as num?)?.toDouble() ?? 0;
          grandTotalActual += (row['totalActual'] as num?)?.toDouble() ?? 0;
        }

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Overall Summary
            Card(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    Row(
                      children: [
                        const Icon(PhosphorIconsBold.chartPieSlice, color: AppColors.primary, size: 24),
                        const SizedBox(width: 10),
                        Text('ملخص أداء الموازنة العام', style: GoogleFonts.cairo(fontSize: 16, fontWeight: FontWeight.w700)),
                      ],
                    ),
                    const SizedBox(height: 20),
                    _comparisonRow('إجمالي المخطط', grandTotalPlanned, AppColors.primary),
                    _comparisonRow('إجمالي الفعلي', grandTotalActual, AppColors.success),
                    const Divider(),
                    _comparisonRow('الانحراف الإجمالي', grandTotalActual - grandTotalPlanned, 
                        (grandTotalActual - grandTotalPlanned) > 0 ? AppColors.error : AppColors.success),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text('تحليل الحسابات التفصيلي', style: GoogleFonts.cairo(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.textMuted)),
            const SizedBox(height: 8),
            // Account Details
            ...reportData.map((row) {
              final planned = (row['totalPlanned'] as num?)?.toDouble() ?? 0;
              final actual = (row['totalActual'] as num?)?.toDouble() ?? 0;
              final variance = actual - planned;
              final utilization = planned > 0 ? (actual / planned) : 0.0;

              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(row['accountName']?.toString() ?? 'غير معروف', style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 14)),
                                Text(row['accountCode']?.toString() ?? '', style: GoogleFonts.jetBrainsMono(color: AppColors.textMuted, fontSize: 12)),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                            decoration: BoxDecoration(
                              color: utilization > 1.0 ? AppColors.error.withValues(alpha: 0.1) : AppColors.success.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              '${(utilization * 100).toStringAsFixed(1)}%',
                              style: GoogleFonts.jetBrainsMono(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: utilization > 1.0 ? AppColors.error : AppColors.success,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      LinearProgressIndicator(
                        value: utilization.clamp(0.0, 1.0),
                        backgroundColor: AppColors.border,
                        color: utilization > 1.0 ? AppColors.error : AppColors.primary,
                        minHeight: 8,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          _statItem('مخطط', planned, AppColors.textMuted),
                          _statItem('فعلي', actual, AppColors.textPrimary),
                          _statItem('انحراف', variance, variance > 0 ? AppColors.error : AppColors.success),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            }),
          ],
        );
      },
    );
  }

  Widget _statItem(String title, double value, Color valueColor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: GoogleFonts.cairo(fontSize: 10, color: AppColors.textMuted)),
        Text(value.toStringAsFixed(AppConstants.decimalPlaces), style: GoogleFonts.jetBrainsMono(fontSize: 12, fontWeight: FontWeight.bold, color: valueColor)),
      ],
    );
  }

  Widget _comparisonRow(String label, double value, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Container(width: 12, height: 12, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3))),
          const SizedBox(width: 10),
          Expanded(child: Text(label, style: GoogleFonts.cairo(fontSize: 13))),
          Text(value.toStringAsFixed(AppConstants.decimalPlaces), style: GoogleFonts.cairo(fontSize: 13, fontWeight: FontWeight.w700, color: color)),
        ],
      ),
    );
  }

  Widget _buildCashFlowForecast() {
    final useCase = ref.watch(cashFlowForecastUseCaseProvider);
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: useCase.execute(monthsAhead: 6),
      builder: (context, snapshot) {
        final data = snapshot.data ?? [];
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(PhosphorIconsBold.trendUp, color: AppColors.success, size: 24),
                        const SizedBox(width: 10),
                        Text('توقعات التدفق النقدي — 6 أشهر', style: GoogleFonts.cairo(fontSize: 16, fontWeight: FontWeight.w700)),
                      ],
                    ),
                    const SizedBox(height: 16),
                    if (data.isEmpty)
                      Text('لا تتوفر بيانات تاريخية كافية للتوقعات', style: GoogleFonts.cairo(color: AppColors.textMuted))
                    else
                      ...data.map((m) => Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Row(
                          children: [
                            Text(m['month'] ?? '', style: GoogleFonts.cairo(fontWeight: FontWeight.w600)),
                            const Spacer(),
                            _forecastChip('وارد', m['projectedInflows'] ?? 0, AppColors.success),
                            const SizedBox(width: 8),
                            _forecastChip('صادر', m['projectedOutflows'] ?? 0, AppColors.error),
                            const SizedBox(width: 8),
                            _forecastChip('صافي', m['projectedNet'] ?? 0,
                                (m['projectedNet'] ?? 0) >= 0 ? AppColors.success : AppColors.error),
                          ],
                        ),
                      )),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _forecastChip(String label, double value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)),
      child: Column(
        children: [
          Text(label, style: GoogleFonts.cairo(fontSize: 9, color: AppColors.textMuted)),
          Text(value.toStringAsFixed(0), style: GoogleFonts.cairo(fontSize: 11, fontWeight: FontWeight.w700, color: color)),
        ],
      ),
    );
  }

  Future<void> _showCreateBudgetDialog(BuildContext context) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => const CreateBudgetDialog(),
    );
    if (result == true) {
      // Reload or trigger rebuild to show the new budget
      setState(() {});
    }
  }
}