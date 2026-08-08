import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../data/providers/providers.dart';
import '../hr_notifier.dart';
import '../../../../domain/repositories/hr_repository_interface.dart';
import '../../../../../../../core/constants/app_constants.dart';

/// HR Dashboard — Analytics Overview Tab
class HRDashboardTab extends ConsumerWidget {
  const HRDashboardTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hrRepo = ref.watch(hrRepositoryProvider);

    return FutureBuilder<List<Employee>>(
      // H6 — المزوّد المحصور لا القراءة المباشرة (شوف hrEmployeesProvider).
      future: ref.watch(hrEmployeesProvider.future),
      builder: (context, empSnap) {
        if (!empSnap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final employees = empSnap.data!;
        final active = employees.where((e) => e.isActive).toList();
        final inactive = employees.where((e) => !e.isActive).toList();

        return Directionality(
          textDirection: TextDirection.rtl,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // ── Summary Cards ──────────────────────────────
              _buildSummaryRow(active, inactive, employees),
              const SizedBox(height: 16),

              // ── Role Distribution ──────────────────────────
              _buildRoleDistribution(active),
              const SizedBox(height: 16),

              // ── Salary Overview ────────────────────────────
              _buildSalaryOverview(hrRepo, active),
              const SizedBox(height: 16),

              // ── Attendance Today ───────────────────────────
              _buildTodayAttendance(hrRepo, active),
              const SizedBox(height: 16),

              // ── Pending Leaves ─────────────────────────────
              _buildPendingLeaves(hrRepo),
              const SizedBox(height: 16),

              // ── Salary Type Breakdown ──────────────────────
              _buildSalaryTypeBreakdown(active),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSummaryRow(
      List<Employee> active, List<Employee> inactive, List<Employee> all) {
    return Row(
      children: [
        _kpiCard('إجمالي الموظفين', '${all.length}', PhosphorIconsBold.users,
            const Color(0xFF2563EB)),
        const SizedBox(width: 10),
        _kpiCard('نشط', '${active.length}', PhosphorIconsBold.userCheck,
            const Color(0xFF059669)),
        const SizedBox(width: 10),
        _kpiCard('غير نشط', '${inactive.length}', PhosphorIconsBold.userMinus,
            const Color(0xFFDC2626)),
        const SizedBox(width: 10),
        _kpiCard(
            'إجمالي الرواتب',
            '${active.fold(0.0, (s, e) => s + e.salary).toStringAsFixed(0)} ${AppConstants.currencySymbolEn}',
            PhosphorIconsBold.wallet,
            const Color(0xFF7C3AED)),
      ],
    );
  }

  Widget _kpiCard(String label, String value, IconData icon, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.15)),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.06),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(height: 10),
            Text(value,
                style: GoogleFonts.cairo(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: color)),
            Text(label,
                style: GoogleFonts.cairo(
                    fontSize: 11, color: AppColors.textMuted)),
          ],
        ),
      ),
    );
  }

  Widget _buildRoleDistribution(List<Employee> employees) {
    final roleMap = <String, int>{};
    for (final e in employees) {
      roleMap[e.role] = (roleMap[e.role] ?? 0) + 1;
    }

    final roleNames = {
      'staff': 'موظف',
      'cashier': 'كاشير',
      'waiter': 'نادل',
      'manager': 'مدير',
      'cleaner': 'عامل نظافة',
      'chef': 'شيف',
      'delivery': 'توصيل',
    };

    final roleColors = {
      'staff': const Color(0xFF6B7280),
      'cashier': const Color(0xFF2563EB),
      'waiter': const Color(0xFF059669),
      'manager': const Color(0xFF7C3AED),
      'cleaner': const Color(0xFFF59E0B),
      'chef': const Color(0xFFDC2626),
      'delivery': const Color(0xFF0891B2),
    };

    return _sectionCard(
      'توزيع الموظفين حسب الدور',
      PhosphorIconsBold.chartPie,
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: roleMap.entries.map((e) {
          final color = roleColors[e.key] ?? AppColors.textMuted;
          final name = roleNames[e.key] ?? e.key;
          final pct = employees.isEmpty
              ? 0
              : (e.value / employees.length * 100).round();
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: color.withValues(alpha: 0.15)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('${e.value}',
                    style: GoogleFonts.cairo(
                        fontSize: 18, fontWeight: FontWeight.w800, color: color)),
                Text(name,
                    style: GoogleFonts.cairo(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: color)),
                Text('$pct%',
                    style: GoogleFonts.cairo(
                        fontSize: 10, color: AppColors.textMuted)),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildSalaryOverview(IHRRepository hrRepo, List<Employee> employees) {
    final now = DateTime.now();

    return _sectionCard(
      'ملخص الرواتب — ${_monthName(now.month)} ${now.year}',
      PhosphorIconsBold.currencyCircleDollar,
      child: FutureBuilder<List<EmployeeSalaryCalculation>>(
        future: Future.wait(
          employees.map((e) => hrRepo.calculateNetSalary(
                employeeId: e.id,
                year: now.year,
                month: now.month,
              )),
        ),
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Padding(
              padding: EdgeInsets.all(16),
              child: LinearProgressIndicator(),
            );
          }
          final calcs = snap.data!;
          final totalBase = calcs.fold(0.0, (s, c) => s + c.baseSalary);
          final totalOvertime = calcs.fold(0.0, (s, c) => s + c.overtimeAmount);
          final totalAdv = calcs.fold(0.0, (s, c) => s + c.totalAdvances);
          final totalDed = calcs.fold(0.0, (s, c) => s + c.totalDeductions);
          final totalNet = calcs.fold(0.0, (s, c) => s + c.netSalary);
          const paid = 0; // Salary payment tracking not yet wired

          return Column(
            children: [
              _salaryRow('الرواتب الأساسية', totalBase, AppColors.textPrimary),
              _salaryRow('إضافي', totalOvertime, const Color(0xFF059669)),
              _salaryRow('سُلف', -totalAdv, const Color(0xFFDC2626)),
              _salaryRow('خصومات', -totalDed, const Color(0xFFDC2626)),
              const Divider(height: 16),
              _salaryRow('صافي المستحق', totalNet, AppColors.primary, isBold: true),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: paid == calcs.length
                      ? const Color(0xFF059669).withValues(alpha: 0.06)
                      : const Color(0xFFF59E0B).withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'تم الصرف: $paid من ${calcs.length} موظف',
                  style: GoogleFonts.cairo(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: paid == calcs.length
                        ? const Color(0xFF059669)
                        : const Color(0xFFF59E0B),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _salaryRow(String label, double amount, Color color,
      {bool isBold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: GoogleFonts.cairo(
                  fontSize: 12,
                  fontWeight: isBold ? FontWeight.w700 : FontWeight.w500)),
          Text(
            '${amount.toStringAsFixed(AppConstants.decimalPlaces)} ${AppConstants.currencySymbolEn}',
            style: GoogleFonts.cairo(
              fontSize: 13,
              fontWeight: isBold ? FontWeight.w800 : FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTodayAttendance(
      IHRRepository hrRepo, List<Employee> employees) {
    final today = DateTime.now();

    return _sectionCard(
      'حضور اليوم — ${today.day}/${today.month}/${today.year}',
      PhosphorIconsBold.calendarCheck,
      child: StreamBuilder<List<EmployeeAttendanceWithDetails>>(
        stream: hrRepo.watchTodayAttendance(),
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Padding(
              padding: EdgeInsets.all(16),
              child: LinearProgressIndicator(),
            );
          }
          final records = snap.data!;
          final checkedIn = records.where((r) => r.attendance.checkIn != null).length;
          final total = employees.length;
          final pct =
              total > 0 ? (checkedIn / total * 100).round() : 0;

          return Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _attendanceStat('حضروا', '$checkedIn', const Color(0xFF059669)),
                  _attendanceStat('غائبون', '${total - checkedIn}', const Color(0xFFDC2626)),
                  _attendanceStat('نسبة الحضور', '$pct%', const Color(0xFF2563EB)),
                ],
              ),
              const SizedBox(height: 12),
              // Progress bar
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: total > 0 ? checkedIn / total : 0,
                  minHeight: 10,
                  backgroundColor: const Color(0xFFDC2626).withValues(alpha: 0.12),
                  valueColor: const AlwaysStoppedAnimation(Color(0xFF059669)),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _attendanceStat(String label, String value, Color color) {
    return Column(
      children: [
        Text(value,
            style: GoogleFonts.cairo(
                fontSize: 22, fontWeight: FontWeight.w800, color: color)),
        Text(label,
            style: GoogleFonts.cairo(
                fontSize: 11, color: AppColors.textMuted)),
      ],
    );
  }

  Widget _buildPendingLeaves(IHRRepository hrRepo) {
    return _sectionCard(
      'إجازات معلقة',
      PhosphorIconsBold.clock,
      child: StreamBuilder<List<EmployeeLeave>>(
        stream: hrRepo.watchPendingLeaves(),
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Padding(
              padding: EdgeInsets.all(16),
              child: LinearProgressIndicator(),
            );
          }
          final leaves = snap.data!;
          if (leaves.isEmpty) {
            return Padding(
              padding: const EdgeInsets.all(16),
              child: Center(
                child: Text('لا توجد إجازات معلقة ✅',
                    style: GoogleFonts.cairo(
                        color: const Color(0xFF059669), fontWeight: FontWeight.w600)),
              ),
            );
          }

          return Column(
            children: leaves.take(5).map((leave) {
              final typeLabels = {
                'annual': 'سنوية',
                'sick': 'مرضية',
                'unpaid': 'بدون راتب',
                'emergency': 'طارئة',
              };
              final typeColors = {
                'annual': const Color(0xFF2563EB),
                'sick': const Color(0xFFDC2626),
                'unpaid': const Color(0xFF6B7280),
                'emergency': const Color(0xFFF59E0B),
              };
              final label = typeLabels[leave.leaveType] ?? leave.leaveType;
              final color = typeColors[leave.leaveType] ?? AppColors.textMuted;

              return Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.04),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: color.withValues(alpha: 0.12)),
                ),
                child: Row(
                  children: [
                    Icon(PhosphorIconsBold.calendar, size: 16, color: color),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FutureBuilder<Employee?>(
                        future: hrRepo.getEmployeeById(leave.employeeId),
                        builder: (context, empSnap) {
                          return Text(
                            empSnap.data?.name ?? '#${leave.employeeId}',
                            style: GoogleFonts.cairo(
                                fontSize: 12, fontWeight: FontWeight.w600),
                          );
                        },
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(label,
                          style: GoogleFonts.cairo(
                              fontSize: 10,
                              color: color,
                              fontWeight: FontWeight.w700)),
                    ),
                    const SizedBox(width: 8),
                    Text('${leave.days} يوم',
                        style: GoogleFonts.cairo(
                            fontSize: 11, color: AppColors.textMuted)),
                  ],
                ),
              );
            }).toList(),
          );
        },
      ),
    );
  }

  Widget _buildSalaryTypeBreakdown(List<Employee> employees) {
    final monthly =
        employees.where((e) => e.salaryType == 'monthly').length;
    final daily =
        employees.where((e) => e.salaryType == 'daily').length;
    final hourly =
        employees.where((e) => e.salaryType == 'hourly').length;

    return _sectionCard(
      'تصنيف الرواتب',
      PhosphorIconsBold.chartBar,
      child: Row(
        children: [
          _salaryTypeChip('شهري', monthly, const Color(0xFF2563EB)),
          const SizedBox(width: 10),
          _salaryTypeChip('يومي', daily, const Color(0xFF059669)),
          const SizedBox(width: 10),
          _salaryTypeChip('بالساعة', hourly, const Color(0xFF7C3AED)),
        ],
      ),
    );
  }

  Widget _salaryTypeChip(String label, int count, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.12)),
        ),
        child: Column(
          children: [
            Text('$count',
                style: GoogleFonts.cairo(
                    fontSize: 22, fontWeight: FontWeight.w800, color: color)),
            Text(label,
                style: GoogleFonts.cairo(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: color)),
          ],
        ),
      ),
    );
  }

  Widget _sectionCard(String title, IconData icon, {required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: AppColors.primary),
              const SizedBox(width: 8),
              Text(title,
                  style: GoogleFonts.cairo(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primary)),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  String _monthName(int month) {
    const months = [
      '', 'يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو',
      'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر',
    ];
    return months[month];
  }
}
