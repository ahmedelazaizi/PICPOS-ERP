import 'package:ural_erp/core/i18n/tr.dart';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_colors.dart';
import '../../data/providers/providers.dart';
import '../../core/widgets/app_toast.dart';

class BudgetDetailsDialog extends ConsumerStatefulWidget {
  final BudgetData budget;

  const BudgetDetailsDialog({super.key, required this.budget});

  @override
  ConsumerState<BudgetDetailsDialog> createState() => _BudgetDetailsDialogState();
}

class _BudgetDetailsDialogState extends ConsumerState<BudgetDetailsDialog> {
  List<BudgetLineData> _lines = [];
  bool _isLoading = true;
  
  // To track edits
  final Map<int, TextEditingController> _controllers = {};
  double _totalPlanned = 0;

  @override
  void initState() {
    super.initState();
    _loadLines();
  }

  Future<void> _loadLines() async {
    try {
      final repo = ref.read(budgetRepositoryProvider);
      final lines = await repo.getBudgetLines(widget.budget.id);
      
      if (mounted) {
        setState(() {
          _lines = lines;
          _totalPlanned = 0;
          for (var line in lines) {
            _controllers[line.id] = TextEditingController(text: line.plannedAmount.toStringAsFixed(2));
            _totalPlanned += line.plannedAmount;
          }
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading lines: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _recalculateTotal() {
    double total = 0;
    for (var ctrl in _controllers.values) {
      total += double.tryParse(ctrl.text) ?? 0;
    }
    setState(() {
      _totalPlanned = total;
    });
  }

  Future<void> _saveChanges() async {
    try {
      final repo = ref.read(budgetRepositoryProvider);
      
      final List<BudgetLineData> updatedLines = [];
      for (var line in _lines) {
        final newAmount = double.tryParse(_controllers[line.id]?.text ?? '0') ?? 0;
        if ((newAmount - line.plannedAmount).abs() > 0.01) {
          updatedLines.add(
            BudgetLineData(
              id: line.id,
              budgetId: line.budgetId,
              month: line.month,
              plannedAmount: newAmount,
              actualAmount: line.actualAmount,
              variance: line.actualAmount - newAmount,
            ),
          );
        } else {
          updatedLines.add(line);
        }
      }

      await repo.updateBudgetLines(
        budgetId: widget.budget.id,
        lines: updatedLines,
        annualAmount: _totalPlanned,
      );
      
      if (mounted) {
        Navigator.pop(context, true);
        AppToast.show(context, tr('تم حفظ تعديلات الموازنة'));
      }
    } catch (e) {
      if (mounted) {
        AppToast.show(context, tr('حدث خطأ أثناء الحفظ: {e}', {'e': e}), type: ToastType.error);
      }
    }
  }

  @override
  void dispose() {
    for (var ctrl in _controllers.values) {
      ctrl.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: ui.TextDirection.rtl,
      child: AlertDialog(
        title: Row(
          children: [
            const Icon(PhosphorIconsBold.calendar, color: AppColors.primary, size: 20),
            const SizedBox(width: 8),
            Text(tr('تفاصيل فترات الموازنة'), style: GoogleFonts.cairo(fontWeight: FontWeight.w700)),
            const Spacer(),
            Text(widget.budget.name ?? tr('بدون اسم'), style: GoogleFonts.cairo(fontSize: 14, color: AppColors.textMuted)),
          ],
        ),
        content: SizedBox(
          width: 600,
          child: _isLoading
            ? const SizedBox(height: 200, child: Center(child: CircularProgressIndicator()))
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(tr('المجموع المخطط (السنوي):'), style: GoogleFonts.cairo(fontWeight: FontWeight.w600)),
                        Text('${_totalPlanned.toStringAsFixed(2)} ${AppConstants.currencySymbol}',
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 16, 
                            fontWeight: FontWeight.bold,
                            color: (_totalPlanned - widget.budget.annualAmount).abs() > 0.01 ? AppColors.warning : AppColors.primary
                          )
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  
                  // Table Header
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                    decoration: const BoxDecoration(
                      color: AppColors.surface,
                      border: Border(bottom: BorderSide(color: AppColors.border, width: 2)),
                    ),
                    child: Row(
                      children: [
                        Expanded(flex: 1, child: Text(tr('الشهر'), style: GoogleFonts.cairo(fontWeight: FontWeight.w700, fontSize: 12))),
                        Expanded(flex: 2, child: Text(tr('المبلغ المخطط'), style: GoogleFonts.cairo(fontWeight: FontWeight.w700, fontSize: 12))),
                        Expanded(flex: 2, child: Text(tr('الفعلي (للمقارنة)'), style: GoogleFonts.cairo(fontWeight: FontWeight.w700, fontSize: 12))),
                      ],
                    ),
                  ),
                  
                  // Table Body
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 400),
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: _lines.length,
                      itemBuilder: (ctx, i) {
                        final line = _lines[i];
                        return Container(
                          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                          decoration: BoxDecoration(
                            border: Border(bottom: BorderSide(color: AppColors.border.withValues(alpha: 0.5))),
                            color: i % 2 == 0 ? Colors.transparent : AppColors.surface.withValues(alpha: 0.3),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                flex: 1, 
                                child: Text(tr('شهر {p0}', {'p0': line.month}), style: GoogleFonts.cairo(fontWeight: FontWeight.w600, fontSize: 13))
                              ),
                              Expanded(
                                flex: 2, 
                                child: Padding(
                                  padding: const EdgeInsetsDirectional.only(end: 16),
                                  child: TextField(
                                    controller: _controllers[line.id],
                                    keyboardType: TextInputType.number,
                                    decoration: InputDecoration(
                                      isDense: true,
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                                    ),
                                    style: GoogleFonts.jetBrainsMono(fontSize: 13),
                                    onChanged: (_) => _recalculateTotal(),
                                  ),
                                ),
                              ),
                              Expanded(
                                flex: 2, 
                                child: Text(
                                  line.actualAmount.toStringAsFixed(2), 
                                  style: GoogleFonts.jetBrainsMono(
                                    fontSize: 13, 
                                    color: AppColors.textMuted
                                  )
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child:  Text(tr('إلغاء'))),
          ElevatedButton.icon(
            onPressed: _isLoading ? null : _saveChanges,
            icon: const Icon(PhosphorIconsBold.check, size: 16),
            label:  Text(tr('حفظ التعديلات')),
          ),
        ],
      ),
    );
  }
}
