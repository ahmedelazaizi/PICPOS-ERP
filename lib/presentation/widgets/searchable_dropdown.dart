import 'package:ural_erp/core/i18n/tr.dart';
// ignore_for_file: avoid_dynamic_calls
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/theme/app_colors.dart';
import '../picpos_shell/picpos_surface.dart';

/// A dropdown widget with search functionality for large lists
class SearchableDropdown<T> extends StatefulWidget {
  final List<T> items;
  final T? value;
  final String Function(T) labelBuilder;
  final void Function(T?) onChanged;
  final String hint;
  final String? label;
  final String searchHint;
  final bool isRequired;
  final bool enabled;
  final Widget Function(T)? itemBuilder;
  final bool showClearButton;
  /// Optional secondary search field (e.g. phone for parties, code for accounts)
  final String Function(T)? secondarySearchBuilder;

  const SearchableDropdown({
    super.key,
    required this.items,
    required this.labelBuilder,
    required this.onChanged,
    this.value,
    this.hint = 'اختر...',
    this.label,
    this.searchHint = 'بحث...',
    this.isRequired = false,
    this.enabled = true,
    this.itemBuilder,
    this.showClearButton = false,
    this.secondarySearchBuilder,
  });

  @override
  State<SearchableDropdown<T>> createState() => _SearchableDropdownState<T>();
}

class _SearchableDropdownState<T> extends State<SearchableDropdown<T>> {
  final TextEditingController _searchController = TextEditingController();
  final LayerLink _layerLink = LayerLink();
  OverlayEntry? _overlayEntry;
  bool _isOpen = false;
  List<T> _filteredItems = [];

  @override
  void initState() {
    super.initState();
    _filteredItems = widget.items;
  }

  @override
  void didUpdateWidget(SearchableDropdown<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.items != widget.items) {
      _filteredItems = widget.items;
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _removeOverlay();
    super.dispose();
  }

  void _toggleDropdown() {
    if (!widget.enabled) return;
    if (_isOpen) {
      _removeOverlay();
    } else {
      _showOverlay();
    }
  }

  void _showOverlay() {
    _overlayEntry = _createOverlayEntry();
    Overlay.of(context).insert(_overlayEntry!);
    setState(() => _isOpen = true);
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
    _searchController.clear();
    _filteredItems = widget.items;
    if (mounted) setState(() => _isOpen = false);
  }

  void _filterItems(String query) {
    if (query.isEmpty) {
      _filteredItems = widget.items;
    } else {
      final q = query.toLowerCase();
      _filteredItems = widget.items.where((item) {
        final label = widget.labelBuilder(item).toLowerCase();
        if (label.contains(q)) return true;
        if (widget.secondarySearchBuilder != null) {
          final secondary = widget.secondarySearchBuilder!(item).toLowerCase();
          if (secondary.contains(q)) return true;
        }
        return false;
      }).toList();
    }
    // Rebuild overlay
    _overlayEntry?.markNeedsBuild();
  }

  void _selectItem(T item) {
    widget.onChanged(item);
    _removeOverlay();
  }

  OverlayEntry _createOverlayEntry() {
    final renderBox = context.findRenderObject() as RenderBox;
    final size = renderBox.size;
    final offset = renderBox.localToGlobal(Offset.zero);
    final screenHeight = MediaQuery.of(context).size.height;
    final spaceBelow = screenHeight - offset.dy - size.height - 8;
    final spaceAbove = offset.dy - 8;
    final showAbove = spaceBelow < 200 && spaceAbove > spaceBelow;
    final maxHeight = showAbove ? spaceAbove.clamp(100, 300).toDouble() : spaceBelow.clamp(100, 300).toDouble();

    return OverlayEntry(
      builder: (context) => Stack(
        children: [
          // Tap barrier to close dropdown
          Positioned.fill(
            child: GestureDetector(
              onTap: _removeOverlay,
              behavior: HitTestBehavior.opaque,
              child: const SizedBox.expand(),
            ),
          ),
          // Dropdown overlay
          Positioned(
            width: size.width,
            child: CompositedTransformFollower(
              link: _layerLink,
              showWhenUnlinked: false,
              offset: showAbove
                  ? Offset(0, -maxHeight - 4)
                  : Offset(0, size.height + 4),
              child: Material(
                elevation: 8,
                borderRadius: BorderRadius.circular(8),
                shadowColor: AppColors.primaryDark.withValues(alpha: 0.2),
                child: Container(
                  constraints: BoxConstraints(maxHeight: maxHeight),
                  decoration: BoxDecoration(
                    // خلفيّةُ القائمة المنسدلة — سطحٌ لا مقدّمة، فتتبع الوضعَ.
                    color: context.picposCard,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Search field
                      Padding(
                        padding: const EdgeInsets.all(8),
                        child: TextField(
                          controller: _searchController,
                          autofocus: true,
                          decoration: InputDecoration(
                            hintText: '${widget.searchHint} (${widget.items.length})',
                            hintStyle: GoogleFonts.cairo(fontSize: 12, color: AppColors.textMuted),
                            prefixIcon: const Icon(Icons.search, size: 18, color: AppColors.primary),
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: BorderSide(color: AppColors.primary.withValues(alpha: 0.3)),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: const BorderSide(color: AppColors.primary),
                            ),
                          ),
                          style: GoogleFonts.cairo(fontSize: 13),
                          onChanged: _filterItems,
                        ),
                      ),
                      const Divider(height: 1),
                      // Items list
                      Flexible(
                        child: _filteredItems.isEmpty
                            ? Padding(
                                padding: const EdgeInsets.all(16),
                                child: Text(
                                  tr('لا توجد نتائج'),
                                  style: GoogleFonts.cairo(color: AppColors.textMuted, fontSize: 12),
                                ),
                              )
                            : ListView.builder(
                                shrinkWrap: true,
                                padding: EdgeInsets.zero,
                                itemCount: _filteredItems.length,
                                itemBuilder: (context, index) {
                                  final item = _filteredItems[index];
                                  final isSelected = widget.value == item;
                                  return InkWell(
                                    onTap: () => _selectItem(item),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 10,
                                      ),
                                      decoration: BoxDecoration(
                                        color: isSelected
                                            ? AppColors.primary.withValues(alpha: 0.08)
                                            : null,
                                        border: Border(
                                          bottom: BorderSide(
                                            color: context.picposHairline.withValues(alpha: 0.5),
                                            width: 0.5,
                                          ),
                                        ),
                                      ),
                                      child:
                                          widget.itemBuilder?.call(item) ??
                                          Text(
                                            widget.labelBuilder(item),
                                            style: GoogleFonts.cairo(
                                              fontSize: 13,
                                              fontWeight: isSelected
                                                  ? FontWeight.w700
                                                  : FontWeight.w500,
                                              color: isSelected
                                                  ? AppColors.primary
                                                  : AppColors.textPrimary,
                                            ),
                                          ),
                                    ),
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final selectedLabel = widget.value != null
        ? widget.labelBuilder(widget.value as T)
        : widget.hint;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.label != null) ...[
          Text(
            widget.isRequired ? '${widget.label} *' : widget.label!,
            style: GoogleFonts.cairo(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 6),
        ],
        CompositedTransformTarget(
          link: _layerLink,
          child: GestureDetector(
            onTap: _toggleDropdown,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              decoration: BoxDecoration(
                border: Border.all(
                  color: !widget.enabled
                      ? context.picposHairline.withValues(alpha: 0.5)
                      : _isOpen
                          ? AppColors.primary
                          : context.picposHairline,
                ),
                borderRadius: BorderRadius.circular(8),
                // أرضيّةُ الحقل — لا نصَّه: المفعَّلُ يأخذ سطحَ البطاقة
                // والمعطَّلُ يأخذ السطحَ الخافت، وكلاهما يتبع الوضعَ.
                color: widget.enabled ? context.picposCard : context.picposField,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      selectedLabel,
                      style: GoogleFonts.cairo(
                        fontSize: 13,
                        color: widget.value != null
                            ? AppColors.textPrimary
                            : AppColors.textMuted,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (widget.showClearButton && widget.value != null) ...[
                    GestureDetector(
                      onTap: () {
                        widget.onChanged(null);
                      },
                      child: const Icon(Icons.close, size: 16, color: AppColors.textMuted),
                    ),
                    const SizedBox(width: 4),
                  ],
                  Icon(
                    _isOpen ? Icons.arrow_drop_up : Icons.arrow_drop_down,
                    color: AppColors.textSecondary,
                    size: 20,
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Searchable dropdown specifically for Party (Customer/Supplier)
class PartySearchableDropdown extends StatelessWidget {
  final List<dynamic> parties;
  final int? selectedId;
  final void Function(int?) onChanged;
  final String label;
  final String hint;
  final bool isRequired;
  final bool showClearButton;

  const PartySearchableDropdown({
    super.key,
    required this.parties,
    required this.onChanged,
    this.selectedId,
    this.label = 'اختر',
    this.hint = 'اختر...',
    this.isRequired = false,
    this.showClearButton = false,
  });

  @override
  Widget build(BuildContext context) {
    final selectedParty = parties
        .cast<dynamic>()
        .where((p) => p.id == selectedId)
        .firstOrNull;

    return SearchableDropdown<dynamic>(
      items: parties,
      value: selectedParty,
      label: label,
      hint: hint,
      isRequired: isRequired,
      showClearButton: showClearButton,
      searchHint: tr('بحث بالاسم أو الهاتف...'),
      labelBuilder: (party) => party.name ?? tr('بدون اسم'),
      secondarySearchBuilder: (party) => party.phone ?? '',
      itemBuilder: (party) => Row(
        children: [
          const Icon(
            Icons.person_outline,
            size: 16,
            color: AppColors.textMuted,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  party.name ?? tr('بدون اسم'),
                  style: GoogleFonts.cairo(fontSize: 13, fontWeight: FontWeight.w600),
                ),
                if (party.phone != null && party.phone.isNotEmpty)
                  Text(
                    party.phone,
                    style: GoogleFonts.cairo(
                      fontSize: 11,
                      color: AppColors.textMuted,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
      onChanged: (party) => onChanged(party?.id),
    );
  }
}

/// Searchable dropdown specifically for Accounts (code + name)
class AccountSearchableDropdown extends StatelessWidget {
  final List<dynamic> accounts;
  final int? selectedId;
  final void Function(int?) onChanged;
  final String label;
  final String hint;
  final bool isRequired;
  final bool showClearButton;

  const AccountSearchableDropdown({
    super.key,
    required this.accounts,
    required this.onChanged,
    this.selectedId,
    this.label = 'الحساب',
    this.hint = 'اختر حساب...',
    this.isRequired = false,
    this.showClearButton = false,
  });

  @override
  Widget build(BuildContext context) {
    final selectedAccount = accounts
        .cast<dynamic>()
        .where((a) => a.id == selectedId)
        .firstOrNull;

    return SearchableDropdown<dynamic>(
      items: accounts,
      value: selectedAccount,
      label: label,
      hint: hint,
      isRequired: isRequired,
      showClearButton: showClearButton,
      searchHint: tr('بحث بالاسم أو الرمز...'),
      labelBuilder: (a) => '${a.code} - ${a.name}',
      secondarySearchBuilder: (a) => a.code ?? '',
      itemBuilder: (a) => Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              a.code,
              style: GoogleFonts.jetBrainsMono(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: AppColors.primary,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              a.name,
              style: GoogleFonts.cairo(fontSize: 13, fontWeight: FontWeight.w500),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      onChanged: (a) => onChanged(a?.id),
    );
  }
}