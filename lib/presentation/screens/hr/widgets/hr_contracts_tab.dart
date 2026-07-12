import 'package:ural_erp/core/constants/app_constants.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../data/providers/providers.dart';
import '../../../../domain/repositories/hr_repository_interface.dart';

/// HR Contracts Management Tab
class ContractsTab extends ConsumerWidget {
  const ContractsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hrRepo = ref.watch(hrRepositoryProvider);

    return Directionality(
      textDirection: TextDirection.rtl,
      child: FutureBuilder<List<Employee>>(
        future: hrRepo.getAllEmployees(),
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final employees = snap.data!;

          return Column(
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    const Icon(PhosphorIconsBold.fileText,
                        color: AppColors.primary),
                    const SizedBox(width: 8),
                    Text('عقود العمل',
                        style: GoogleFonts.cairo(
                            fontSize: 18, fontWeight: FontWeight.w700)),
                    const Spacer(),
                    // Expiring soon alert
                    FutureBuilder<List<EmployeeContract>>(
                      future: hrRepo.getExpiringContracts(30),
                      builder: (ctx, exSnap) {
                        final count = exSnap.data?.length ?? 0;
                        if (count == 0) return const SizedBox.shrink();
                        return Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF59E0B).withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                                color: const Color(0xFFF59E0B).withValues(alpha: 0.3)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(PhosphorIconsBold.warning,
                                  size: 14, color: Color(0xFFF59E0B)),
                              const SizedBox(width: 6),
                              Text('$count عقود تنتهي خلال 30 يوم',
                                  style: GoogleFonts.cairo(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: const Color(0xFFF59E0B))),
                            ],
                          ),
                        );
                      },
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      onPressed: () =>
                          _showAddContractDialog(context, ref, employees),
                      icon: const Icon(PhosphorIconsBold.plus, size: 16),
                      label: const Text('عقد جديد'),
                      style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white),
                    ),
                  ],
                ),
              ),
              // Contracts List
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: employees.length,
                  itemBuilder: (context, index) {
                    final emp = employees[index];
                    return _EmployeeContractCard(
                        employee: emp, hrRepo: hrRepo);
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showAddContractDialog(
      BuildContext context, WidgetRef ref, List<Employee> employees) {
    Employee? selectedEmployee;
    String contractType = 'permanent';
    final salaryCtrl = TextEditingController();
    final benefitsCtrl = TextEditingController();
    final notesCtrl = TextEditingController();
    DateTime startDate = DateTime.now();
    DateTime? endDate;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            title: Text('عقد عمل جديد',
                style: GoogleFonts.cairo(fontWeight: FontWeight.w700)),
            content: SizedBox(
              width: 450,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<Employee>(
                      decoration: const InputDecoration(
                          labelText: 'الموظف', border: OutlineInputBorder()),
                      items: employees
                          .map((e) => DropdownMenuItem(
                              value: e, child: Text(e.name)))
                          .toList(),
                      onChanged: (v) {
                        setState(() {
                          selectedEmployee = v;
                          salaryCtrl.text = v?.salary.toStringAsFixed(AppConstants.decimalPlaces) ?? '';
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      decoration: const InputDecoration(
                          labelText: 'نوع العقد', border: OutlineInputBorder()),
                      initialValue: contractType,
                      items: const [
                        DropdownMenuItem(
                            value: 'permanent', child: Text('دائم')),
                        DropdownMenuItem(
                            value: 'temporary', child: Text('مؤقت')),
                        DropdownMenuItem(
                            value: 'part_time', child: Text('دوام جزئي')),
                        DropdownMenuItem(
                            value: 'freelance', child: Text('حر')),
                      ],
                      onChanged: (v) => setState(() => contractType = v!),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: salaryCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                          labelText: 'الراتب', border: OutlineInputBorder()),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: InkWell(
                            onTap: () async {
                              final picked = await showDatePicker(
                                context: ctx,
                                initialDate: startDate,
                                firstDate: DateTime(2020),
                                lastDate: DateTime(2030),
                              );
                              if (picked != null) {
                                setState(() => startDate = picked);
                              }
                            },
                            child: InputDecorator(
                              decoration: const InputDecoration(
                                  labelText: 'تاريخ البداية',
                                  border: OutlineInputBorder()),
                              child: Text(
                                  '${startDate.day}/${startDate.month}/${startDate.year}'),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: InkWell(
                            onTap: () async {
                              final picked = await showDatePicker(
                                context: ctx,
                                initialDate:
                                    endDate ?? startDate.add(const Duration(days: 365)),
                                firstDate: startDate,
                                lastDate: DateTime(2030),
                              );
                              if (picked != null) {
                                setState(() => endDate = picked);
                              }
                            },
                            child: InputDecorator(
                              decoration: const InputDecoration(
                                  labelText: 'تاريخ الانتهاء',
                                  border: OutlineInputBorder()),
                              child: Text(endDate != null
                                  ? '${endDate!.day}/${endDate!.month}/${endDate!.year}'
                                  : 'غير محدد (دائم)'),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: benefitsCtrl,
                      maxLines: 2,
                      decoration: const InputDecoration(
                          labelText: 'المزايا', border: OutlineInputBorder()),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: notesCtrl,
                      maxLines: 2,
                      decoration: const InputDecoration(
                          labelText: 'ملاحظات', border: OutlineInputBorder()),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('إلغاء')),
              ElevatedButton(
                onPressed: selectedEmployee == null
                    ? null
                    : () async {
                        final hrRepo = ref.read(hrRepositoryProvider);
                        await hrRepo.addEmployeeContract(
                          employeeId: selectedEmployee!.id,
                          contractType: contractType,
                          startDate: startDate,
                          endDate: endDate,
                          salary: double.tryParse(salaryCtrl.text) ?? 0,
                          benefits: benefitsCtrl.text.isEmpty
                              ? null
                              : benefitsCtrl.text,
                          notes: notesCtrl.text.isEmpty
                              ? null
                              : notesCtrl.text,
                        );
                        if (ctx.mounted) Navigator.pop(ctx);
                      },
                style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white),
                child: const Text('حفظ العقد'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmployeeContractCard extends StatelessWidget {
  final Employee employee;
  final IHRRepository hrRepo;

  const _EmployeeContractCard({required this.employee, required this.hrRepo});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<EmployeeContract>>(
      stream: hrRepo.watchEmployeeContracts(employee.id),
      builder: (context, snap) {
        final contracts = snap.data ?? [];
        final activeContract =
            contracts.where((c) => c.status == 'active').firstOrNull;

        if (contracts.isEmpty) {
          return const SizedBox.shrink(); // Skip employees without contracts
        }

        final contractTypes = {
          'permanent': 'دائم',
          'temporary': 'مؤقت',
          'part_time': 'دوام جزئي',
          'freelance': 'حر',
        };

        final statusColors = {
          'active': const Color(0xFF059669),
          'expired': const Color(0xFFDC2626),
          'terminated': const Color(0xFF6B7280),
          'renewed': const Color(0xFF2563EB),
        };

        final statusLabels = {
          'active': 'نشط',
          'expired': 'منتهي',
          'terminated': 'منهي',
          'renewed': 'مجدد',
        };

        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ExpansionTile(
            leading: CircleAvatar(
              backgroundColor: activeContract != null
                  ? const Color(0xFF059669).withValues(alpha: 0.1)
                  : const Color(0xFF6B7280).withValues(alpha: 0.1),
              child: Icon(
                activeContract != null
                    ? PhosphorIconsBold.fileText
                    : PhosphorIconsBold.fileDashed,
                color: activeContract != null
                    ? const Color(0xFF059669)
                    : const Color(0xFF6B7280),
                size: 18,
              ),
            ),
            title: Text(employee.name,
                style: GoogleFonts.cairo(fontWeight: FontWeight.w700)),
            subtitle: activeContract != null
                ? Text(
                    '${contractTypes[activeContract.contractType] ?? activeContract.contractType}'
                    '${activeContract.endDate != null ? ' — ينتهي ${activeContract.endDate!.day}/${activeContract.endDate!.month}/${activeContract.endDate!.year}' : ' — دائم'}',
                    style: GoogleFonts.cairo(
                        fontSize: 11, color: AppColors.textMuted),
                  )
                : Text('بدون عقد نشط',
                    style: GoogleFonts.cairo(
                        fontSize: 11, color: AppColors.textMuted)),
            children: contracts.map((c) {
              final color = statusColors[c.status] ?? AppColors.textMuted;
              return ListTile(
                dense: true,
                title: Text(
                  '${contractTypes[c.contractType] ?? c.contractType} — ${c.salary.toStringAsFixed(0)}',
                  style: GoogleFonts.cairo(fontSize: 12),
                ),
                subtitle: Text(
                  '${c.startDate.day}/${c.startDate.month}/${c.startDate.year}'
                  '${c.endDate != null ? ' → ${c.endDate!.day}/${c.endDate!.month}/${c.endDate!.year}' : ' → مفتوح'}',
                  style: GoogleFonts.cairo(fontSize: 10, color: AppColors.textMuted),
                ),
                trailing: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(statusLabels[c.status] ?? c.status,
                      style: GoogleFonts.cairo(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: color)),
                ),
              );
            }).toList(),
          ),
        );
      },
    );
  }
}
