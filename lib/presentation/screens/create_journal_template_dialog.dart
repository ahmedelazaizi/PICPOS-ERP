import 'package:ural_erp/core/i18n/tr.dart';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../../domain/models/journal_balance.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme/app_colors.dart';
import '../picpos_shell/picpos_surface.dart';
import '../../data/database/database.dart';
import '../../data/providers/repository_providers.dart';
import '../../domain/repositories/accounting_repository.dart';
import '../../core/widgets/app_toast.dart';

class CreateJournalTemplateDialog extends ConsumerStatefulWidget {
  final JournalEntryTemplateData? templateToEdit;
  final List<Map<String, dynamic>>? initialLines;

  const CreateJournalTemplateDialog({
    super.key,
    this.templateToEdit,
    this.initialLines,
  });

  @override
  ConsumerState<CreateJournalTemplateDialog> createState() => _CreateJournalTemplateDialogState();
}

class _CreateJournalTemplateDialogState extends ConsumerState<CreateJournalTemplateDialog> {
  late TextEditingController _nameCtrl;
  late TextEditingController _descCtrl;
  bool _isActive = true;
  List<_TemplateLineInput> _lines = [];
  int? _globalCostCenterId;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.templateToEdit?.name ?? '');
    _descCtrl = TextEditingController(text: widget.templateToEdit?.description ?? '');
    _isActive = widget.templateToEdit?.isActive ?? true;

    if (widget.initialLines != null && widget.initialLines!.isNotEmpty) {
      for (final line in widget.initialLines!) {
        _lines.add(_TemplateLineInput()
          ..account = Account(
            id: line['account_id'] as int,
            code: line['account_code'] as String,
            name: line['account_name'] as String,
            accountType: '',
            accountNature: 'detail',
            level: 1,
            normalBalance: 'debit',
            balance: 0,
            isSystem: false,
            isActive: true,
            isHiddenFromEntries: false,
            rowVersion: 0,
          )
          ..descCtrl.text = line['description'] as String? ?? ''
          ..debitCtrl.text = (line['debit'] as double? ?? 0.0) > 0 ? (line['debit'] as double).toString() : ''
          ..creditCtrl.text = (line['credit'] as double? ?? 0.0) > 0 ? (line['credit'] as double).toString() : ''
          // (Adding cost center in templates isn't retrieved yet in this query, so mapping as null for now unless handled)
        );
      }
    } else {
      _lines = [
        _TemplateLineInput(),
        _TemplateLineInput(),
      ];
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    for (var l in _lines) {
      l.descCtrl.dispose();
      l.debitCtrl.dispose();
      l.creditCtrl.dispose();
    }
    super.dispose();
  }

  Future<void> _saveTemplate() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      AppToast.show(context, tr('يرجى إدخال اسم القالب'), type: ToastType.info);
      return;
    }

    for (final line in _lines) {
      if (line.account == null) {
        AppToast.show(context, tr('يرجى اختيار حساب لكل بند'), type: ToastType.info);
        return;
      }
      if (line.debit <= 0 && line.credit <= 0) {
        AppToast.show(context, tr('كل بند يجب أن يحتوي على قيمة مدين أو دائن'), type: ToastType.info);
        return;
      }
    }

    final totalDebit = _lines.fold(0.0, (s, l) => s + l.debit);
    final totalCredit = _lines.fold(0.0, (s, l) => s + l.credit);
    if (!JournalBalance(debit: totalDebit, credit: totalCredit)
        .isBalanced) {
      AppToast.show(context, tr('القيد غير متوازن، يجب أن يتساوى إجمالي المدين والدائن'), type: ToastType.info);
      return;
    }

    final accountingRepo = ref.read(accountingRepositoryProvider);
    final insertLines = _lines.map((l) => {
      'accountId': l.account!.id,
      'debit': l.debit,
      'credit': l.credit,
      'description': l.descCtrl.text.isEmpty ? null : l.descCtrl.text,
      'costCenterId': l.costCenterId,
    }).toList();

    try {
      if (widget.templateToEdit != null) {
        await accountingRepo.updateJournalTemplate(
          widget.templateToEdit!.id,
          name: name,
          description: _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
          lines: insertLines,
        );
      } else {
        await accountingRepo.createJournalTemplate(
          name: name,
          description: _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
          lines: insertLines,
        );
      }
      if (mounted) {
        Navigator.pop(context);
        AppToast.show(context, tr('تم الحفظ بنجاح'));
      }
    } catch (e) {
      if (mounted) {
        AppToast.show(context, tr('خطأ: {e}', {'e': e}), type: ToastType.error);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final totalDebit = _lines.fold(0.0, (s, l) => s + l.debit);
    final totalCredit = _lines.fold(0.0, (s, l) => s + l.credit);
    final isBalanced =
        JournalBalance(debit: totalDebit, credit: totalCredit).isPostable;

    return Directionality(
      textDirection: ui.TextDirection.rtl,
      child: AlertDialog(
        title: Row(
          children: [
            const Icon(PhosphorIconsBold.notebook, color: AppColors.primary, size: 20),
            const SizedBox(width: 8),
            Text(widget.templateToEdit == null ? tr('إنشاء قالب جديد') : tr('تعديل القالب'), style: GoogleFonts.cairo(fontWeight: FontWeight.w700)),
          ],
        ),
        content: SizedBox(
          width: 650,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: TextField(
                        controller: _nameCtrl,
                        decoration:  InputDecoration(
                          labelText: tr('اسم القالب'),
                          hintText: tr('قالب رواتب الموظفين...'),
                          border: const OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 3,
                      child: TextField(
                        controller: _descCtrl,
                        decoration:  InputDecoration(
                          labelText: tr('الوصف (اختياري)'),
                          border: const OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Row(
                      children: [
                        Checkbox(
                          value: _isActive,
                          onChanged: (v) => setState(() => _isActive = v ?? true),
                          activeColor: AppColors.primary,
                        ),
                        Text(tr('نشط'), style: GoogleFonts.cairo()),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Text(tr('بنود القيد'), style: GoogleFonts.cairo(fontWeight: FontWeight.w700, fontSize: 14)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _TemplateCostCenterPicker(
                        repo: ref.read(accountingRepositoryProvider),
                        selectedId: _globalCostCenterId,
                        labelOverride: tr('الفرع / مركز التكلفة لجميع البنود'),
                        onChanged: (id) {
                          setState(() {
                            _globalCostCenterId = id;
                            for (final line in _lines) {
                              line.costCenterId = id;
                            }
                          });
                        },
                      ),
                    ),
                    const Spacer(),
                    TextButton.icon(
                      onPressed: () => setState(() {
                        final newLine = _TemplateLineInput()..costCenterId = _globalCostCenterId;
                        _lines.add(newLine);
                      }),
                      icon: const Icon(PhosphorIconsBold.plus, size: 14),
                      label:  Text(tr('إضافة بند')),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ..._lines.asMap().entries.map((entry) {
                  final i = entry.key;
                  final line = entry.value;
                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      // ⚠️ كان `AppColors.surface` — ثابتٌ فاتحٌ لا يتبع
                      //    الثيم، فتظهر بطاقةُ كلِّ بندٍ **بيضاءَ فاقعةً** على
                      //    خلفيّةٍ داكنة (بلاغُ المالك بالصورة 2026-08-25).
                      color: context.picposField,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: context.picposHairline),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppColors.primary.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(tr('بند {p0}', {'p0': i + 1}), style: GoogleFonts.cairo(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.primary)),
                            ),
                            const Spacer(),
                            if (_lines.length > 2)
                              IconButton(
                                icon: const Icon(PhosphorIconsBold.trash, size: 14, color: AppColors.error),
                                onPressed: () => setState(() => _lines.removeAt(i)),
                                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                                padding: EdgeInsets.zero,
                              ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        _TemplateAccountAutocomplete(
                          repo: ref.read(accountingRepositoryProvider),
                          selectedAccount: line.account,
                          onSelected: (acc) => setState(() => line.account = acc),
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Expanded(
                              flex: 3,
                              child: TextField(
                                controller: line.descCtrl,
                                decoration: InputDecoration(
                                  hintText: tr('البيان'),
                                  isDense: true,
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                                ),
                                style: GoogleFonts.cairo(fontSize: 11),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              flex: 2,
                              child: _TemplateCostCenterPicker(
                                repo: ref.read(accountingRepositoryProvider),
                                selectedId: line.costCenterId,
                                onChanged: (id) => setState(() => line.costCenterId = id),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: line.debitCtrl,
                                keyboardType: TextInputType.number,
                                onChanged: (_) => setState(() {}),
                                decoration: InputDecoration(
                                  labelText: tr('مدين'),
                                  labelStyle: GoogleFonts.cairo(fontSize: 11),
                                  hintText: '0.00',
                                  isDense: true,
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                                ),
                                style: GoogleFonts.jetBrainsMono(fontSize: 11),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: TextField(
                                controller: line.creditCtrl,
                                keyboardType: TextInputType.number,
                                onChanged: (_) => setState(() {}),
                                decoration: InputDecoration(
                                  labelText: tr('دائن'),
                                  labelStyle: GoogleFonts.cairo(fontSize: 11),
                                  hintText: '0.00',
                                  isDense: true,
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                                ),
                                style: GoogleFonts.jetBrainsMono(fontSize: 11),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                }),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: isBalanced ? AppColors.success.withValues(alpha: 0.08) : AppColors.error.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: isBalanced ? AppColors.success.withValues(alpha: 0.3) : AppColors.error.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: [
                      Icon(isBalanced ? PhosphorIconsBold.checkCircle : PhosphorIconsBold.warning, size: 18, color: isBalanced ? AppColors.success : AppColors.error),
                      const SizedBox(width: 8),
                      Text(tr('مجموع المدين: {p0}', {'p0': totalDebit.toStringAsFixed(2)}), style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.w600)),
                      const SizedBox(width: 16),
                      Text(tr('مجموع الدائن: {p0}', {'p0': totalCredit.toStringAsFixed(2)}), style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.w600)),
                      const Spacer(),
                      Text(isBalanced ? tr('متوازن ✓') : tr('غير متوازن!'), style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.w700, color: isBalanced ? AppColors.success : AppColors.error)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child:  Text(tr('إلغاء'))),
          ElevatedButton.icon(
            onPressed: isBalanced ? _saveTemplate : null,
            icon: const Icon(PhosphorIconsBold.floppyDisk, size: 16),
            label:  Text(tr('حفظ القالب')),
          ),
        ],
      ),
    );
  }
}

class _TemplateLineInput {
  Account? account;
  int? costCenterId;
  final descCtrl = TextEditingController();
  final debitCtrl = TextEditingController();
  final creditCtrl = TextEditingController();

  double get debit => double.tryParse(debitCtrl.text) ?? 0;
  double get credit => double.tryParse(creditCtrl.text) ?? 0;
}

// -------------------------------------------------------------
// Component replicas below to keep it decoupled
// -------------------------------------------------------------

class _TemplateAccountAutocomplete extends StatefulWidget {
  final IAccountingRepository repo;
  final Account? selectedAccount;
  final ValueChanged<Account> onSelected;

  const _TemplateAccountAutocomplete({required this.repo, required this.selectedAccount, required this.onSelected});

  @override
  State<_TemplateAccountAutocomplete> createState() => _TemplateAccountAutocompleteState();
}

class _TemplateAccountAutocompleteState extends State<_TemplateAccountAutocomplete> {
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
  void didUpdateWidget(_TemplateAccountAutocomplete old) {
    super.didUpdateWidget(old);
    if (old.selectedAccount?.id != widget.selectedAccount?.id) {
      _textCtrl.text = widget.selectedAccount != null ? '${widget.selectedAccount!.code} - ${widget.selectedAccount!.name}' : '';
    }
  }

  Future<void> _loadAccounts() async {
    final all = await widget.repo.getAllAccounts();
    final parentIds = all.where((a) => a.parentId != null).map((a) => a.parentId!).toSet();
    _allAccounts = all.where((a) => !parentIds.contains(a.id) && !a.isHiddenFromEntries).toList();
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
              style: GoogleFonts.cairo(fontSize: 11),
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
                // قائمةُ اقتراحاتِ الحساب — كانت `Colors.white` فتظهر لوحاً
                // أبيضَ فوقَ حوارٍ داكن.
                decoration: BoxDecoration(color: context.picposCard, borderRadius: BorderRadius.circular(8), border: Border.all(color: AppColors.primary.withValues(alpha: 0.3))),
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
                              child: Text(a.code, style: GoogleFonts.jetBrainsMono(fontSize: 9, fontWeight: FontWeight.w600, color: AppColors.primary)),
                            ),
                            const SizedBox(width: 8),
                            Expanded(child: Text(trData(a.name), style: GoogleFonts.cairo(fontSize: 11, fontWeight: (isSelected || isHighlighted) ? FontWeight.w700 : FontWeight.w500, color: (isSelected || isHighlighted) ? AppColors.primary : AppColors.textPrimary), overflow: TextOverflow.ellipsis)),
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

class _TemplateCostCenterPicker extends StatefulWidget {
  final IAccountingRepository repo;
  final int? selectedId;
  final ValueChanged<int?> onChanged;
  final String? labelOverride;

  const _TemplateCostCenterPicker({required this.repo, required this.selectedId, required this.onChanged, this.labelOverride});

  @override
  State<_TemplateCostCenterPicker> createState() => _TemplateCostCenterPickerState();
}

class _TemplateCostCenterPickerState extends State<_TemplateCostCenterPicker> {
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
      value: widget.selectedId,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: widget.labelOverride ?? tr('مركز التكلفة'),
        labelStyle: GoogleFonts.cairo(fontSize: 11),
        isDense: true,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      ),
      style: GoogleFonts.cairo(fontSize: 11, color: AppColors.textPrimary),
      items: [
        DropdownMenuItem<int?>(value: null, child: Text(tr('بدون'), style: GoogleFonts.cairo(fontSize: 11, color: AppColors.textMuted))),
        ..._centers!.map((c) => DropdownMenuItem<int?>(value: c.id, child: Text('${c.code} - ${c.name}', style: GoogleFonts.cairo(fontSize: 11)))),
      ],
      onChanged: widget.onChanged,
    );
  }
}
