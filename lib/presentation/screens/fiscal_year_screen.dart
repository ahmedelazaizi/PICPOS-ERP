import 'package:ural_erp/core/constants/app_constants.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart' hide TextDirection;
import '../../core/config/business_profile_provider.dart';
import '../../core/theme/app_colors.dart';
import '../picpos_shell/picpos_surface.dart';
import '../../data/providers/providers.dart';
import '../../domain/repositories/accounting_repository.dart';
import '../../core/widgets/app_toast.dart';
import '../../core/permissions/permission_codes.dart';
import '../widgets/fiscal_year_gate_dialog.dart';

/// هل [permissions] تسمح بإعادة فتح فترة محاسبية مقفلة؟
///
/// `modify_closed_period` كود فصل سلطات (segregation of duties) — لا يوجد
/// أي تجاوز إداري هنا (لا `system_admin` ولا `*`)، عكس أغلب أكواد الحارس
/// التانية. مستخرجة top-level عشان تتفحص من غير تركيب الشاشة كلها.
@visibleForTesting
bool canReopenClosedPeriod(List<String> permissions) {
  return permissions.contains(PermissionCodes.modifyClosedPeriod);
}

/// Fiscal Year Management Screen — IAS 1 compliant period tracking
class FiscalYearScreen extends ConsumerStatefulWidget {
  const FiscalYearScreen({super.key});

  @override
  ConsumerState<FiscalYearScreen> createState() => _FiscalYearScreenState();
}

class _FiscalYearScreenState extends ConsumerState<FiscalYearScreen> {
  int? _expandedYearId;
  final _dateFormat = DateFormat('yyyy/MM/dd');
  final Set<int> _savingPeriodIds = {};

  @override
  Widget build(BuildContext context) {
    final accountingRepo = ref.watch(accountingRepositoryProvider);

    return Directionality(
      textDirection: TextDirection.rtl,
      // لا تجاوزَ للخلفيّة: الثيمُ يعرّف `scaffoldBackgroundColor` للوضعَين.
      child: Scaffold(
        body: Column(
          children: [
            _buildHeader(context),
            Expanded(
              child: StreamBuilder<List<FiscalYearData>>(
                stream: accountingRepo.watchFiscalYears(),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final years = snapshot.data!;
                  if (years.isEmpty) {
                    return _buildEmptyState(context);
                  }
                  return ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: years.length,
                    itemBuilder: (context, index) =>
                        _buildYearCard(context, accountingRepo, years[index]),
                  );
                },
              ),
            ),
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
          colors: [AppColors.primaryDark, AppColors.primary],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(PhosphorIconsBold.calendar, color: Colors.white, size: 24),
          ),
          const SizedBox(width: 14),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('السنوات المالية',
                  style: GoogleFonts.cairo(fontSize: 20, fontWeight: FontWeight.w800, color: Colors.white)),
              Text('IAS 1 — إدارة الفترات المحاسبية',
                  style: GoogleFonts.cairo(fontSize: 11, color: Colors.white.withValues(alpha: 0.7))),
            ],
          ),
          const Spacer(),
          ElevatedButton.icon(
            onPressed: () => _guardedCreateYear(context),
            icon: const Icon(PhosphorIconsBold.lockSimpleOpen, size: 18),
            label: Text('سنة مالية جديدة', style: GoogleFonts.cairo(fontWeight: FontWeight.w700)),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: AppColors.primary,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
                const Icon(PhosphorIconsBold.calendarBlank, size: 64, color: AppColors.textMuted),
          const SizedBox(height: 16),
          Text('لا توجد سنوات مالية', style: GoogleFonts.cairo(fontSize: 16, color: AppColors.textMuted)),
          const SizedBox(height: 8),
          Text('أنشئ أول سنة مالية لبدء المحاسبة',
              style: GoogleFonts.cairo(fontSize: 12, color: AppColors.textMuted)),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: () => _guardedCreateYear(context),
            icon: const Icon(PhosphorIconsBold.lockSimpleOpen, size: 16),
            label: Text('إنشاء سنة مالية', style: GoogleFonts.cairo()),
          ),
        ],
      ),
    );
  }

  Widget _buildYearCard(BuildContext context, IAccountingRepository repo, FiscalYearData year) {
    final isExpanded = _expandedYearId == year.id;
    final isCurrent = year.isCurrent;
    final isClosed = year.isClosed;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: isCurrent ? 2 : 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isCurrent ? AppColors.primary : (isClosed ? AppColors.error.withValues(alpha: 0.3) : context.picposHairline),
          width: isCurrent ? 2 : 1,
        ),
      ),
      child: Column(
        children: [
          // Year Header
          InkWell(
            onTap: () => setState(() => _expandedYearId = isExpanded ? null : year.id),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isCurrent
                    ? AppColors.primary.withValues(alpha: 0.04)
                    : (isClosed ? AppColors.error.withValues(alpha: 0.02) : null),
                borderRadius: isExpanded
                    ? const BorderRadius.vertical(top: Radius.circular(12))
                    : BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  // Status Icon
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: isClosed
                          ? AppColors.error.withValues(alpha: 0.1)
                          : (isCurrent
                              ? AppColors.success.withValues(alpha: 0.1)
                              : AppColors.warning.withValues(alpha: 0.1)),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      isClosed ? PhosphorIconsBold.lock : (isCurrent ? PhosphorIconsBold.checkCircle : PhosphorIconsBold.clock),
                      color: isClosed ? AppColors.error : (isCurrent ? AppColors.success : AppColors.warning),
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(year.name, style: GoogleFonts.cairo(fontSize: 16, fontWeight: FontWeight.w700)),
                            const SizedBox(width: 8),
                            _buildStatusBadge(isClosed, isCurrent),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${_dateFormat.format(year.startDate)} — ${_dateFormat.format(year.endDate)}',
                          style: GoogleFonts.cairo(fontSize: 12, color: AppColors.textMuted),
                        ),
                      ],
                    ),
                  ),
                  if (!isClosed) ...[
                    IconButton(
                      icon: const Icon(PhosphorIconsBold.lockSimple, size: 18, color: AppColors.error),
                      tooltip: 'إقفال السنة',
                       onPressed: () => _confirmCloseYear(context, repo, year),
                    ),
                  ],
                  AnimatedRotation(
                    turns: isExpanded ? 0.25 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: const Icon(PhosphorIconsBold.caretLeft, size: 16),
                  ),
                ],
              ),
            ),
          ),

          // Expanded: Periods + Summary
          if (isExpanded) ...[
            const Divider(height: 1),
            // Summary Row
            FutureBuilder<Map<String, double>>(
              future: repo.getYearSummary(year.id),
              builder: (context, snapshot) {
                final data = snapshot.data;
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  color: context.picposField,
                  child: Row(
                    children: [
                      _summaryChip('الإيرادات', data?['revenue'] ?? 0, AppColors.success),
                      const SizedBox(width: 12),
                      _summaryChip('المصروفات', data?['expenses'] ?? 0, AppColors.error),
                      const SizedBox(width: 12),
                      _summaryChip(
                        'صافي الربح',
                        data?['netProfit'] ?? 0,
                        (data?['netProfit'] ?? 0) >= 0 ? AppColors.success : AppColors.error,
                      ),
                    ],
                  ),
                );
              },
            ),
            const Divider(height: 1),
            // Periods
            StreamBuilder<List<AccountingPeriodData>>(
              stream: repo.watchAccountingPeriods(year.id),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Padding(
                    padding: EdgeInsets.all(16),
                    child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                  );
                }
                final periods = snapshot.data!;
                if (periods.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        Text('لا توجد فترات محاسبية', style: GoogleFonts.cairo(color: AppColors.textMuted)),
                        const SizedBox(height: 8),
                        if (!year.isClosed)
                          TextButton.icon(
                            onPressed: _savingPeriodIds.contains(-year.id) ? null : () async {
                              setState(() => _savingPeriodIds.add(-year.id));
                              try {
                                await repo.generatePeriodsForYear(year.id, year.startDate, year.endDate);
                              } finally {
                                if (mounted) setState(() => _savingPeriodIds.remove(-year.id));
                              }
                            },
                            icon: const Icon(PhosphorIconsBold.plus, size: 14),
                            label: Text('توليد 12 فترة شهرية', style: GoogleFonts.cairo()),
                          ),
                      ],
                    ),
                  );
                }
                return Column(
                  children: periods.map((period) => _buildPeriodTile(context, repo, period, year.isClosed)).toList(),
                );
              },
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStatusBadge(bool isClosed, bool isCurrent) {
    final label = isClosed ? 'مقفلة' : (isCurrent ? 'نشطة' : 'مفتوحة');
    final color = isClosed ? AppColors.error : (isCurrent ? AppColors.success : AppColors.warning);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(label, style: GoogleFonts.cairo(fontSize: 10, color: color, fontWeight: FontWeight.w700)),
    );
  }

  Widget _summaryChip(String label, double value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.15)),
        ),
        child: Column(
          children: [
            Text(label, style: GoogleFonts.cairo(fontSize: 10, color: AppColors.textMuted)),
            Text(
              value.toStringAsFixed(AppConstants.decimalPlaces),
              style: GoogleFonts.cairo(fontSize: 13, fontWeight: FontWeight.w700, color: color),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPeriodTile(BuildContext context, IAccountingRepository repo, AccountingPeriodData period, bool yearClosed) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: context.picposHairline.withValues(alpha: 0.5))),
      ),
      child: Row(
        children: [
          Icon(
            period.isClosed ? PhosphorIconsBold.lockSimple : PhosphorIconsBold.calendarBlank,
            size: 16,
            color: period.isClosed ? AppColors.error : AppColors.success,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(period.name, style: GoogleFonts.cairo(fontSize: 13, fontWeight: FontWeight.w600)),
          ),
          Text(
            '${_dateFormat.format(period.startDate)} — ${_dateFormat.format(period.endDate)}',
            style: GoogleFonts.cairo(fontSize: 11, color: AppColors.textMuted),
          ),
          const SizedBox(width: 12),
          _buildStatusBadge(period.isClosed, false),
          if (!yearClosed) ...[
            const SizedBox(width: 8),
            if (!period.isClosed)
              IconButton(
                icon: const Icon(PhosphorIconsBold.lockSimple, size: 14),
                tooltip: 'إقفال الفترة',
                onPressed: _savingPeriodIds.contains(period.id) ? null : () async {
                  setState(() => _savingPeriodIds.add(period.id));
                  try {
                    await repo.closeAccountingPeriod(period.id, 1);
                    if (context.mounted) {
                      AppToast.show(context, 'تم إقفال فترة ${period.name}');
                    }
                  } finally {
                    if (mounted) setState(() => _savingPeriodIds.remove(period.id));
                  }
                },
              )
            else
              IconButton(
                icon: const Icon(PhosphorIconsBold.lockSimpleOpen, size: 14),
                tooltip: 'إعادة فتح الفترة',
                onPressed: _savingPeriodIds.contains(period.id) ? null : () async {
                  // فحص صريح بلا أي استثناء للمدير — `modify_closed_period`
                  // كود فصل سلطات (segregation of duties)، فمينفعش يتفتح
                  // بكلمة مرور مدير زي بقية الأزرار. الصلاحية لازم تتمنح
                  // صراحة للمستخدم اللي هيعمل الفعل، مفيش باب خلفي.
                  final perms =
                      ref.read(currentUserPermissionsProvider).asData?.value ??
                          const <String>[];
                  if (!canReopenClosedPeriod(perms)) {
                    if (context.mounted) {
                      AppToast.show(
                        context,
                        'ليس لديك صلاحية إعادة فتح فترة مقفلة',
                        type: ToastType.error,
                      );
                    }
                    return;
                  }
                  setState(() => _savingPeriodIds.add(period.id));
                  try {
                    await repo.reopenAccountingPeriod(period.id);
                    if (context.mounted) {
                      AppToast.show(context, 'تم إعادة فتح فترة ${period.name}');
                    }
                  } finally {
                    if (mounted) setState(() => _savingPeriodIds.remove(period.id));
                  }
                },
              ),
          ],
        ],
      ),
    );
  }

  void _showCreateYearDialog(BuildContext context) {
    final nameCtrl = TextEditingController();
    DateTime startDate = DateTime(DateTime.now().year, 1, 1);
    DateTime endDate = DateTime(DateTime.now().year, 12, 31);
    bool saving = false;

    showDialog(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: StatefulBuilder(builder: (ctx, setDialogState) {
          return AlertDialog(
            title: Row(
              children: [
                const Icon(PhosphorIconsBold.calendarPlus, color: AppColors.primary, size: 20),
                const SizedBox(width: 8),
                Text('سنة مالية جديدة', style: GoogleFonts.cairo(fontWeight: FontWeight.w700)),
              ],
            ),
            content: SizedBox(
              width: 400,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameCtrl,
                    decoration: InputDecoration(
                      labelText: 'اسم السنة',
                      hintText: '${DateTime.now().year}',
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: InkWell(
                          onTap: () async {
                            final picked = await showDatePicker(
                              context: ctx,
                              initialDate: startDate,
                              firstDate: DateTime(2020),
                              lastDate: DateTime(2050),
                            );
                            if (picked != null) setDialogState(() => startDate = picked);
                          },
                          child: InputDecorator(
                            decoration: const InputDecoration(labelText: 'من تاريخ'),
                            child: Text(_dateFormat.format(startDate)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: InkWell(
                          onTap: () async {
                            final picked = await showDatePicker(
                              context: ctx,
                              initialDate: endDate,
                              firstDate: DateTime(2020),
                              lastDate: DateTime(2050),
                            );
                            if (picked != null) setDialogState(() => endDate = picked);
                          },
                          child: InputDecorator(
                            decoration: const InputDecoration(labelText: 'إلى تاريخ'),
                            child: Text(_dateFormat.format(endDate)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
              ElevatedButton(
                onPressed: saving ? null : () async {
                  setDialogState(() => saving = true);
                  final name = nameCtrl.text.trim().isEmpty
                      ? '${startDate.year}'
                      : nameCtrl.text.trim();
                  try {
                    final repo = ref.read(accountingRepositoryProvider);
                    final yearId = await repo.createFiscalYear(
                      name: name,
                      startDate: startDate,
                      endDate: endDate,
                    );
                    // Auto-generate monthly periods
                    await repo.generatePeriodsForYear(yearId, startDate, endDate);
                    if (ctx.mounted) Navigator.pop(ctx);
                    if (context.mounted) {
                      AppToast.show(context, 'تم إنشاء السنة المالية $name مع الفترات الشهرية');
                    }
                  } catch (e) {
                    setDialogState(() => saving = false);
                    if (context.mounted) {
                      AppToast.show(context, 'خطأ: ${e.toString()}', type: ToastType.error);
                    }
                  }
                },
                child: const Text('إنشاء'),
              ),
            ],
          );
        }),
      ),
    );
  }

  /// Opens a developer-password dialog before allowing a new fiscal year to be created.
  Future<void> _guardedCreateYear(BuildContext context) async {
    final passwordCtrl = TextEditingController();
    bool obscure = true;
    String? errorText;

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: StatefulBuilder(builder: (ctx, setDs) {
          return AlertDialog(
            title: Row(
              children: [
                const Icon(PhosphorIconsBold.lock, color: AppColors.warning, size: 20),
                const SizedBox(width: 8),
                Text('تأكيد صلاحية المطور', style: GoogleFonts.cairo(fontWeight: FontWeight.w700)),
              ],
            ),
            content: SizedBox(
              width: 360,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.warning.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.warning.withValues(alpha: 0.3)),
                    ),
                    child: Text(
                      'فتح سنة مالية جديدة عملية حساسة تؤثر على جميع القيود والتقارير المحاسبية. '
                      'يُسمح فقط للمطور بتنفيذ هذه العملية.',
                      style: GoogleFonts.cairo(fontSize: 12, color: AppColors.warning),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: passwordCtrl,
                    obscureText: obscure,
                    autofocus: true,
                    decoration: InputDecoration(
                      labelText: 'كلمة مرور المطور',
                      prefixIcon: const Icon(PhosphorIconsBold.key, size: 18),
                      errorText: errorText,
                      suffixIcon: IconButton(
                        icon: Icon(obscure ? PhosphorIconsBold.eye : PhosphorIconsBold.eyeSlash, size: 18),
                        onPressed: () => setDs(() => obscure = !obscure),
                      ),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onSubmitted: (_) async => _verifyAndConfirm(ctx, setDs, passwordCtrl, (v) => errorText = v),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.warning, foregroundColor: Colors.white),
                onPressed: () async => _verifyAndConfirm(ctx, setDs, passwordCtrl, (v) => errorText = v),
                child: Text('تأكيد', style: GoogleFonts.cairo()),
              ),
            ],
          );
        }),
      ),
    );

    if (confirmed == true && context.mounted) {
      _showCreateYearDialog(context);
    }
  }

  Future<void> _verifyAndConfirm(
    BuildContext ctx,
    void Function(void Function()) setDs,
    TextEditingController ctrl,
    void Function(String?) setError,
  ) async {
    final input = ctrl.text.trim();
    if (input.isEmpty) {
      setDs(() => setError('يرجى إدخال كلمة المرور'));
      return;
    }

    final devAuth = ref.read(developerAuthServiceProvider);
    if (!devAuth.isConfigured) {
      setDs(() => setError('لم يتم إعداد كلمة مرور المطور. يرجى التواصل مع الدعم الفني.'));
      return;
    }
    if (await devAuth.verify(input)) {
      if (ctx.mounted) Navigator.pop(ctx, true);
      return;
    }
    setDs(() => setError('كلمة المرور غير صحيحة'));
  }

  void _confirmCloseYear(BuildContext context, IAccountingRepository repo, FiscalYearData year) {
    bool saving = false;
    showDialog(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: StatefulBuilder(builder: (ctx, setDialogState) {
          return AlertDialog(
            title: const Text('تأكيد إقفال السنة المالية'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('هل أنت متأكد من إقفال السنة "${year.name}"؟'),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.warning.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      const Icon(PhosphorIconsBold.warning, color: AppColors.warning, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'سيتم ترحيل الأرباح/الخسائر إلى الأرباح المحتجزة وإغلاق جميع حسابات الإيرادات والمصروفات، ثم إنشاء سنة مالية جديدة مع أرصدة افتتاحية تلقائياً',
                          style: GoogleFonts.cairo(fontSize: 11, color: AppColors.warning),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
              ElevatedButton(
                onPressed: saving ? null : () async {
                  setDialogState(() => saving = true);
                  try {
                    await repo.closeFiscalYear(year.id, 1);
                    if (ctx.mounted) Navigator.pop(ctx);
                    if (context.mounted) {
                      AppToast.show(context, 'تم إقفال السنة المالية ${year.name}');
                    }
                  } catch (e) {
                    setDialogState(() => saving = false);
                    if (ctx.mounted) Navigator.pop(ctx);
                    if (context.mounted) {
                      AppToast.show(context, 'خطأ: ${e.toString()}', type: ToastType.error);
                    }
                  }
                },
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
                child: const Text('إقفال'),
              ),
            ],
          );
        }),
      ),
    );
  }
}
