import 'package:ural_erp/core/i18n/tr.dart';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_colors.dart';
import '../../data/providers/providers.dart';
import '../../domain/repositories/accounting_repository.dart';
import '../../core/widgets/app_toast.dart';

class CreateBudgetDialog extends ConsumerStatefulWidget {
  const CreateBudgetDialog({super.key});

  @override
  ConsumerState<CreateBudgetDialog> createState() => _CreateBudgetDialogState();
}

class _CreateBudgetDialogState extends ConsumerState<CreateBudgetDialog> {
  final _nameCtrl = TextEditingController();
  final _amountCtrl = TextEditingController();
  String _distributionMethod = 'equal';
  
  Account? _selectedAccount;
  int? _selectedCostCenterId;
  FiscalYearData? _selectedFiscalYear;
  
  List<FiscalYearData> _fiscalYears = [];

  @override
  void initState() {
    super.initState();
    _loadFiscalYears();
  }
  
  Future<void> _loadFiscalYears() async {
    try {
      final repo = ref.read(accountingRepositoryProvider);
      final years = await repo.getFiscalYears();
      if (mounted) {
        setState(() {
          _fiscalYears = years;
          if (_fiscalYears.isNotEmpty) {
            _selectedFiscalYear = _fiscalYears.firstWhere((y) => y.isCurrent, orElse: () => _fiscalYears.first);
          }
        });
      }
    } catch (e) {
      debugPrint('Error loading fiscal years: $e');
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _amountCtrl.dispose();
    super.dispose();
  }

  Future<void> _saveBudget() async {
    final name = _nameCtrl.text.trim();
    final amountText = _amountCtrl.text.trim();
    final annualAmount = double.tryParse(amountText) ?? 0.0;
    
    if (annualAmount <= 0) {
      AppToast.show(context, tr('يرجى إدخال مبلغ صحيح للموازنة'), type: ToastType.info);
      return;
    }
    if (_selectedFiscalYear == null) {
      AppToast.show(context, tr('يرجى اختيار السنة المالية'), type: ToastType.info);
      return;
    }
    if (_selectedAccount == null) {
      AppToast.show(context, tr('يرجى اختيار الحساب'), type: ToastType.info);
      return;
    }

    try {
      final repo = ref.read(budgetRepositoryProvider);
      await repo.createBudget(
        fiscalYearId: _selectedFiscalYear!.id,
        accountId: _selectedAccount!.id,
        costCenterId: _selectedCostCenterId,
        annualAmount: annualAmount,
        name: name.isEmpty ? null : name,
        distributionMethod: _distributionMethod,
      );
      
      if (mounted) {
        Navigator.pop(context, true);
        AppToast.show(context, tr('تم إنشاء الموازنة بنجاح'));
      }
    } catch (e) {
      if (mounted) {
        AppToast.show(context, tr('خطأ أثناء الإنشاء: {e}', {'e': e}), type: ToastType.error);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: ui.TextDirection.rtl,
      child: AlertDialog(
        title: Row(
          children: [
            const Icon(PhosphorIconsBold.chartBar, color: AppColors.primary, size: 20),
            const SizedBox(width: 8),
            Text(tr('موازنة سنوية جديدة'), style: GoogleFonts.cairo(fontWeight: FontWeight.w700)),
          ],
        ),
        content: SizedBox(
          width: 500,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<FiscalYearData>(
                        decoration:  InputDecoration(
                          labelText: tr('السنة المالية'),
                          border: const OutlineInputBorder(),
                          isDense: true,
                        ),
                        initialValue: _selectedFiscalYear,
                        items: _fiscalYears.map((y) => DropdownMenuItem(
                          value: y,
                          child: Text(y.name, style: GoogleFonts.cairo(fontSize: 13)),
                        )).toList(),
                        onChanged: (v) => setState(() => _selectedFiscalYear = v),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: TextField(
                        controller: _nameCtrl,
                        decoration:  InputDecoration(
                          labelText: tr('اسم الموازنة (اختياري)'),
                          hintText: tr('مثال: موازنة تسويق 2026...'),
                          border: const OutlineInputBorder(),
                          isDense: true,
                        ),
                        style: GoogleFonts.cairo(fontSize: 13),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(tr('الحساب المالي المرتبط'), style: GoogleFonts.cairo(fontWeight: FontWeight.w700, fontSize: 13)),
                const SizedBox(height: 8),
                _AccountAutocomplete(
                  repo: ref.read(accountingRepositoryProvider),
                  selectedAccount: _selectedAccount,
                  onSelected: (acc) => setState(() => _selectedAccount = acc),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: _CostCenterPicker(
                        repo: ref.read(accountingRepositoryProvider),
                        selectedId: _selectedCostCenterId,
                        onChanged: (id) => setState(() => _selectedCostCenterId = id),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Divider(),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: TextField(
                        controller: _amountCtrl,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: tr('المبلغ السنوي الإجمالي'),
                          border: const OutlineInputBorder(),
                          isDense: true,
                          prefixText: '${AppConstants.currencySymbol} ',
                        ),
                        style: GoogleFonts.jetBrainsMono(fontSize: 14, fontWeight: FontWeight.bold),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: DropdownButtonFormField<String>(
                        decoration:  InputDecoration(
                          labelText: tr('طريقة التوزيع على الأشهر'),
                          border: const OutlineInputBorder(),
                          isDense: true,
                        ),
                        initialValue: _distributionMethod,
                        items: [
                          DropdownMenuItem(value: 'equal', child: Text(tr('متساوي (يوزع تلقائياً)'), style: GoogleFonts.cairo(fontSize: 12))),
                          DropdownMenuItem(value: 'seasonal', child: Text(tr('موسمي'), style: GoogleFonts.cairo(fontSize: 12))),
                          DropdownMenuItem(value: 'manual', child: Text(tr('يدوي'), style: GoogleFonts.cairo(fontSize: 12))),
                        ],
                        onChanged: (v) => setState(() => _distributionMethod = v ?? 'equal'),
                      ),
                    ),
                  ],
                ),
                if (_distributionMethod == 'equal') ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
                    ),
                    child: Row(
                      children: [
                        const Icon(PhosphorIconsBold.info, size: 16, color: AppColors.primary),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            tr('سيتم تقسيم المبلغ السنوي المكتوب بالتساوي على 12 شهراً فور الحفظ. يمكنك لاحقاً النقر على الموازنة وتعديل كل شهر على حدة إذا رغبت.'),
                            style: GoogleFonts.cairo(fontSize: 11, color: AppColors.primaryDark),
                          ),
                        ),
                      ],
                    ),
                  )
                ] else ...[
                  const SizedBox(height: 12),
                  Text(tr('سيتم إضافة 12 بنداً بقيمة صفرية لتعديلها يدوياً من واجهة التفاصيل.'), style: GoogleFonts.cairo(fontSize: 11, color: AppColors.textMuted)),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child:  Text(tr('إلغاء'))),
          ElevatedButton.icon(
            onPressed: _saveBudget,
            icon: const Icon(PhosphorIconsBold.check, size: 16),
            label:  Text(tr('إنشاء الموازنة')),
          ),
        ],
      ),
    );
  }
}


// Reusable components (Same as in journal entries)
class _AccountAutocomplete extends StatefulWidget {
  final IAccountingRepository repo;
  final Account? selectedAccount;
  final ValueChanged<Account> onSelected;

  const _AccountAutocomplete({required this.repo, required this.selectedAccount, required this.onSelected});

  @override
  State<_AccountAutocomplete> createState() => _AccountAutocompleteState();
}

class _AccountAutocompleteState extends State<_AccountAutocomplete> {
  List<Account>? _allAccounts;
  List<Account> _currentOptions = [];
  late TextEditingController _textCtrl;
  late FocusNode _focusNode;
  int _highlightedIndex = -1;

  @override
  void initState() {
    super.initState();
    _textCtrl = TextEditingController(text: widget.selectedAccount != null ? '${widget.selectedAccount!.code} - ${widget.selectedAccount!.name}' : '');
    _focusNode = FocusNode();
    _loadAccounts();
  }

  @override
  void didUpdateWidget(_AccountAutocomplete old) {
    super.didUpdateWidget(old);
    if (old.selectedAccount?.id != widget.selectedAccount?.id) {
      _textCtrl.text = widget.selectedAccount != null ? '${widget.selectedAccount!.code} - ${widget.selectedAccount!.name}' : '';
    }
  }

  Future<void> _loadAccounts() async {
    final all = await widget.repo.getAllAccounts();
    final parentIds = all.where((a) => a.parentId != null).map((a) => a.parentId!).toSet();
    // Only fetch active leaf accounts
    _allAccounts = all.where((a) => !parentIds.contains(a.id) && !a.isHiddenFromEntries && a.isActive).toList();
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _textCtrl.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_allAccounts == null) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        decoration: BoxDecoration(border: Border.all(color: AppColors.border), borderRadius: BorderRadius.circular(6)),
        child: Text(tr('تحميل الحسابات...'), style: GoogleFonts.cairo(fontSize: 11, color: AppColors.textMuted)),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) => RawAutocomplete<Account>(
        textEditingController: _textCtrl,
        focusNode: _focusNode,
        optionsBuilder: (textEditingValue) {
          final q = textEditingValue.text.toLowerCase().trim();
          List<Account> filtered = q.isEmpty ? _allAccounts! : _allAccounts!.where((a) => a.name.toLowerCase().contains(q) || a.code.toLowerCase().contains(q)).toList();
          _currentOptions = filtered;
          _highlightedIndex = filtered.isNotEmpty ? 0 : -1;
          return filtered;
        },
        displayStringForOption: (a) => '${a.code} - ${a.name}',
        onSelected: widget.onSelected,
        fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
          return KeyboardListener(
            focusNode: FocusNode(),
            onKeyEvent: (event) {
              if (event is KeyDownEvent || event is KeyRepeatEvent) {
                if (event.logicalKey == LogicalKeyboardKey.arrowDown && _highlightedIndex < _currentOptions.length - 1) {
                  setState(() => _highlightedIndex++);
                } else if (event.logicalKey == LogicalKeyboardKey.arrowUp && _highlightedIndex > 0) {
                  setState(() => _highlightedIndex--);
                }
              }
            },
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              decoration: InputDecoration(
                hintText: tr('اكتب اسم أو رمز الحساب...'),
                hintStyle: GoogleFonts.cairo(fontSize: 11, color: AppColors.textMuted),
                isDense: true,
                prefixIcon: const Icon(PhosphorIconsBold.magnifyingGlass, size: 14, color: AppColors.primary),
                prefixIconConstraints: const BoxConstraints(minWidth: 32),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: AppColors.primary, width: 1.5)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              ),
              style: GoogleFonts.cairo(fontSize: 13, fontWeight: FontWeight.bold),
              onSubmitted: (_) {
                final idx = _highlightedIndex >= 0 && _highlightedIndex < _currentOptions.length ? _highlightedIndex : 0;
                if (_currentOptions.isNotEmpty) {
                  final selected = _currentOptions[idx];
                  controller.text = '${selected.code} - ${selected.name}';
                  widget.onSelected(selected);
                  focusNode.unfocus();
                }
              },
            ),
          );
        },
        optionsViewBuilder: (context, onSelected, options) {
          final optionsList = options.toList();
          return Align(
            alignment: AlignmentDirectional.topStart,
            child: Material(
              elevation: 8,
              borderRadius: BorderRadius.circular(8),
              shadowColor: AppColors.primaryDark.withValues(alpha: 0.2),
              child: Container(
                width: constraints.maxWidth,
                constraints: const BoxConstraints(maxHeight: 250),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), border: Border.all(color: AppColors.primary.withValues(alpha: 0.3))),
                child: ListView.builder(
                  padding: EdgeInsets.zero,
                  shrinkWrap: true,
                  itemCount: optionsList.length,
                  itemBuilder: (ctx, i) {
                    final a = optionsList[i];
                    final isSelected = widget.selectedAccount?.id == a.id;
                    final isHighlighted = i == _highlightedIndex;
                    return InkWell(
                      onTap: () => onSelected(a),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        decoration: BoxDecoration(
                          color: isHighlighted ? AppColors.primary.withValues(alpha: 0.12) : isSelected ? AppColors.primary.withValues(alpha: 0.06) : null,
                          border: Border(bottom: BorderSide(color: AppColors.border.withValues(alpha: 0.3))),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                              decoration: BoxDecoration(color: isHighlighted ? AppColors.primary.withValues(alpha: 0.18) : AppColors.primary.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(3)),
                              child: Text(a.code, style: GoogleFonts.jetBrainsMono(fontSize: 10, fontWeight: FontWeight.w600, color: AppColors.primary)),
                            ),
                            const SizedBox(width: 8),
                            Expanded(child: Text(trData(a.name), style: GoogleFonts.cairo(fontSize: 12, fontWeight: (isSelected || isHighlighted) ? FontWeight.w700 : FontWeight.w500, color: (isSelected || isHighlighted) ? AppColors.primary : AppColors.textPrimary), overflow: TextOverflow.ellipsis)),
                            if (isHighlighted) const Icon(PhosphorIconsBold.caretLeft, size: 12, color: AppColors.primary),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _CostCenterPicker extends StatefulWidget {
  final IAccountingRepository repo;
  final int? selectedId;
  final ValueChanged<int?> onChanged;

  const _CostCenterPicker({required this.repo, required this.selectedId, required this.onChanged});

  @override
  State<_CostCenterPicker> createState() => _CostCenterPickerState();
}

class _CostCenterPickerState extends State<_CostCenterPicker> {
  List<CostCenter>? _centers;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    _centers = await widget.repo.getCostCenters();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    if (_centers == null || _centers!.isEmpty) return const SizedBox.shrink();
    return DropdownButtonFormField<int?>(
      initialValue: widget.selectedId,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: tr('مركز التكلفة (اختياري)'),
        labelStyle: GoogleFonts.cairo(fontSize: 12),
        isDense: true,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      ),
      style: GoogleFonts.cairo(fontSize: 12, color: AppColors.textPrimary),
      items: [
        DropdownMenuItem<int?>(value: null, child: Text(tr('بدون (عام)'), style: GoogleFonts.cairo(fontSize: 12, color: AppColors.textMuted))),
        ..._centers!.map((c) => DropdownMenuItem<int?>(value: c.id, child: Text('${c.code} - ${c.name}', style: GoogleFonts.cairo(fontSize: 12)))),
      ],
      onChanged: widget.onChanged,
    );
  }
}
