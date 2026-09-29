// =======================================================================
// JOURNAL ENTRY HELPER WIDGETS — Phase 7 God File Splitting
// Extracted from journal_entries_screen.dart (lines 1032-1340)
// =======================================================================
part of 'journal_entries_screen.dart';

/// Input model for journal entry line
class JournalLineInput {
  Account? account;
  int? costCenterId;
  final descCtrl = TextEditingController();
  final debitCtrl = TextEditingController();
  final creditCtrl = TextEditingController();

  double get debit => double.tryParse(debitCtrl.text) ?? 0;
  double get credit => double.tryParse(creditCtrl.text) ?? 0;
}

/// Inline account autocomplete — type to search by name or code
class AccountAutocompleteField extends StatefulWidget {
  final IAccountingRepository repo;
  final Account? selectedAccount;
  final ValueChanged<Account> onSelected;

  const AccountAutocompleteField({
    super.key,
    required this.repo,
    required this.selectedAccount,
    required this.onSelected,
  });

  @override
  State<AccountAutocompleteField> createState() => _AccountAutocompleteFieldState();
}

class _AccountAutocompleteFieldState extends State<AccountAutocompleteField> {
  List<Account>? _allAccounts;
  List<Account> _currentOptions = [];
  late TextEditingController _textCtrl;
  late FocusNode _focusNode;
  int _highlightedIndex = -1;

  @override
  void initState() {
    super.initState();
    _textCtrl = TextEditingController(
      text: widget.selectedAccount != null
          ? '${widget.selectedAccount!.code} - ${widget.selectedAccount!.name}'
          : '',
    );
    _focusNode = FocusNode();
    _loadAccounts();
  }

  @override
  void didUpdateWidget(AccountAutocompleteField old) {
    super.didUpdateWidget(old);
    if (old.selectedAccount?.id != widget.selectedAccount?.id) {
      _textCtrl.text = widget.selectedAccount != null
          ? '${widget.selectedAccount!.code} - ${widget.selectedAccount!.name}'
          : '';
    }
  }

  Future<void> _loadAccounts() async {
    final all = await widget.repo.getAllAccounts();
    final parentIds = all
        .where((a) => a.parentId != null)
        .map((a) => a.parentId!)
        .toSet();
    _allAccounts = all.where((a) =>
        !parentIds.contains(a.id) && !a.isHiddenFromEntries).toList();
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
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.border),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(tr('تحميل الحسابات...'), style: GoogleFonts.cairo(fontSize: 11, color: AppColors.textMuted)),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) => RawAutocomplete<Account>(
        textEditingController: _textCtrl,
        focusNode: _focusNode,
        optionsBuilder: (textEditingValue) {
          final q = textEditingValue.text.toLowerCase().trim();
          List<Account> filtered;
          if (q.isEmpty) {
            filtered = _allAccounts!;
          } else {
            filtered = _allAccounts!.where((a) =>
                a.name.toLowerCase().contains(q) ||
                a.code.toLowerCase().contains(q),
            ).toList();
          }
          _currentOptions = filtered;
          _highlightedIndex = filtered.isNotEmpty ? 0 : -1;
          return filtered;
        },
        displayStringForOption: (a) => '${a.code} - ${a.name}',
        onSelected: (account) {
          widget.onSelected(account);
        },
        fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
          return KeyboardListener(
            focusNode: FocusNode(),
            onKeyEvent: (event) {
              if (event is KeyDownEvent || event is KeyRepeatEvent) {
                if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
                  setState(() {
                    if (_highlightedIndex < _currentOptions.length - 1) {
                      _highlightedIndex++;
                    }
                  });
                } else if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
                  setState(() {
                    if (_highlightedIndex > 0) {
                      _highlightedIndex--;
                    }
                  });
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
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              ),
              style: GoogleFonts.cairo(fontSize: 11),
              onSubmitted: (_) {
                final idx = _highlightedIndex >= 0 && _highlightedIndex < _currentOptions.length
                    ? _highlightedIndex
                    : 0;
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
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
                ),
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
                          color: isHighlighted
                              ? AppColors.primary.withValues(alpha: 0.12)
                              : isSelected
                                  ? AppColors.primary.withValues(alpha: 0.06)
                                  : null,
                          border: Border(bottom: BorderSide(color: AppColors.border.withValues(alpha: 0.3))),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                              decoration: BoxDecoration(
                                color: isHighlighted
                                    ? AppColors.primary.withValues(alpha: 0.18)
                                    : AppColors.primary.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(3),
                              ),
                              child: Text(
                                a.code,
                                style: GoogleFonts.jetBrainsMono(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.primary,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                a.name,
                                style: GoogleFonts.cairo(
                                  fontSize: 11,
                                  fontWeight: (isSelected || isHighlighted) ? FontWeight.w700 : FontWeight.w500,
                                  color: (isSelected || isHighlighted) ? AppColors.primary : AppColors.textPrimary,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (isHighlighted)
                              const Icon(PhosphorIconsBold.caretLeft, size: 12, color: AppColors.primary),
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


/// Cost center picker for journal entry lines
class CostCenterPicker extends StatefulWidget {
  final IAccountingRepository repo;
  final int? selectedId;
  final ValueChanged<int?> onChanged;
  final String? labelOverride;

  const CostCenterPicker({
    super.key,
    required this.repo,
    required this.selectedId,
    required this.onChanged,
    this.labelOverride,
  });

  @override
  State<CostCenterPicker> createState() => _CostCenterPickerState();
}

class _CostCenterPickerState extends State<CostCenterPicker> {
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
    if (_centers == null || _centers!.isEmpty) {
      return const SizedBox.shrink();
    }

    return DropdownButtonFormField<int?>(
      initialValue: widget.selectedId,
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

