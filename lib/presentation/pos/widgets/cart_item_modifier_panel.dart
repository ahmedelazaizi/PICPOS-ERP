part of 'cart_item_tile.dart';

// ═══════════════════════════════════════════════════════════════════════════
// CART ITEM — Modifier / Options / Notes Inline Panel
// Extracted from cart_item_tile.dart for maintainability (PIR Phase 2)
// ═══════════════════════════════════════════════════════════════════════════

/// حقل ملاحظة الصنف — مستخرج كودجت top-level مستقل عن
/// `_CartItemModifierPanelMixin` عشان يتعمله اختبار widget بدون تركيب
/// `CartItemTile` الحقيقي أو أي قاعدة بيانات (نفس نمط Task 6a/6b).
///
/// `allowManagerOverride` بلا `onGranted`: الحقل نص حر بلا زرار واحد واضح —
/// إضافة ملاحظة عملية كتابة حقيقية على الصنف، مش مجرد عرض، فمن غير الصلاحية
/// المستخدم لازم تصريح مدير. الموافقة هنا **بتفتح القفل** (نفس السيناريو
/// الموثّق في `permission_guard.dart` لقسم/حقل بلا فعل واحد) بدل ما تشغّل
/// حفظ فوري — بعدها الكاشير يكتب ويضغط ✓ بنفسه زي أي مستخدم مصرّح له.
@visibleForTesting
Widget buildCartItemNoteField({
  required TextEditingController noteController,
  required VoidCallback onSave,
  double scaleFactor = 1.0,
}) {
  return PermissionGuard(
    permission: PermissionCodes.posNoteAdd,
    allowManagerOverride: true,
    actionName: tr('إضافة ملاحظة على الصنف'),
    child: Padding(
      padding: EdgeInsets.symmetric(
        horizontal: 10 * scaleFactor,
        vertical: 6 * scaleFactor,
      ),
      child: Row(
        children: [
          Icon(
            PhosphorIconsBold.notepad,
            size: 14 * scaleFactor,
            color: AppColors.warning,
          ),
          SizedBox(width: 4 * scaleFactor),
          Expanded(
            child: SizedBox(
              height: 30 * scaleFactor,
              child: TextField(
                controller: noteController,
                style: TextStyle(fontSize: 11 * scaleFactor),
                textInputAction: TextInputAction.done,
                decoration: InputDecoration(
                  isDense: true,
                  hintText: tr('ملاحظة على الصنف...'),
                  hintStyle: TextStyle(
                    fontSize: 10 * scaleFactor,
                    color: AppColors.textMuted,
                  ),
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 8 * scaleFactor,
                    vertical: 6 * scaleFactor,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: BorderSide(
                      color: AppColors.border.withValues(alpha: 0.3),
                    ),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: BorderSide(
                      color: AppColors.border.withValues(alpha: 0.3),
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: const BorderSide(
                      color: AppColors.warning,
                    ),
                  ),
                  suffixIcon: GestureDetector(
                    onTap: onSave,
                    child: Icon(
                      PhosphorIconsBold.checkCircle,
                      size: 16 * scaleFactor,
                      color: AppColors.success,
                    ),
                  ),
                ),
                onSubmitted: (_) => onSave(),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

/// Mixin providing the expandable modifier/note panel and all related
/// build helpers for [_CartItemTileState].
mixin _CartItemModifierPanelMixin on State<CartItemTile> {
  // ── Required state from _CartItemTileState ──
  int get activeModifierTab;
  set activeModifierTab(int v);
  OptionQuantityLevel get selectedQuantityLevel;
  set selectedQuantityLevel(OptionQuantityLevel v);
  TextEditingController get noteController;
  CartItemTile get tileWidget;
  int get tileIndex;
  WidgetRef get tileRef;

  // ─────────────────────────────────────────────────────────────────────
  // EXPANDED PANEL — Two tabs (additions / options) + note field
  // ─────────────────────────────────────────────────────────────────────

  Widget buildExpandedPanel(double scaleFactor) {
    return FutureBuilder<List<ModifierGroupWithItems>>(
      future: _loadModifierGroups(),
      builder: (context, snapshot) {
        final groups = snapshot.data ?? [];
        final currentModifiers = tileWidget.item.modifiers;

        // Separate groups
        final additionGroups = groups.where((mg) =>
            mg.items.any((item) => item.extraPrice > 0) && mg.group.type != 'option').toList();
        final optionGroups = groups.where((mg) =>
            mg.items.every((item) => item.extraPrice <= 0) || mg.group.type == 'option').toList();

        return Container(
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.02),
            border: Border(
              top: BorderSide(
                color: AppColors.border.withValues(alpha: 0.3),
              ),
            ),
            borderRadius: const BorderRadius.vertical(
              bottom: Radius.circular(12),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ─── Tab Bar ───
              _buildModifierTabBar(currentModifiers, scaleFactor),

              // ─── Tab Content ───
              Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: 10 * scaleFactor,
                  vertical: 4 * scaleFactor,
                ),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: activeModifierTab == 0
                      ? _buildAdditionsTabContent(
                          additionGroups, currentModifiers, scaleFactor)
                      : _buildOptionsTabContent(
                          optionGroups, currentModifiers, scaleFactor),
                ),
              ),

              // ─── Manual note field ───
              _buildNoteField(scaleFactor),
            ],
          ),
        );
      },
    );
  }

  // ─────────────────────────────────────────────────────────────────────
  // TAB BAR — additions / options toggle
  // ─────────────────────────────────────────────────────────────────────

  Widget _buildModifierTabBar(
      List<SelectedModifier> currentModifiers, double scaleFactor) {
    return Container(
      margin: EdgeInsets.symmetric(
        horizontal: 8 * scaleFactor,
        vertical: 6 * scaleFactor,
      ),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
      ),
      padding: const EdgeInsets.all(3),
      child: Row(
        children: [
          // الإضافات tab
          Expanded(
            child: GestureDetector(
              onTap: () => setState(() => activeModifierTab = 0),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: EdgeInsets.symmetric(vertical: 6 * scaleFactor),
                decoration: BoxDecoration(
                  color: activeModifierTab == 0
                      ? AppColors.success.withValues(alpha: 0.15)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                  border: activeModifierTab == 0
                      ? Border.all(color: AppColors.success.withValues(alpha: 0.3))
                      : null,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      PhosphorIconsBold.plusCircle,
                      size: 13 * scaleFactor,
                      color: activeModifierTab == 0
                          ? AppColors.success
                          : AppColors.textMuted,
                    ),
                    SizedBox(width: 4 * scaleFactor),
                    Text(
                      tr('الإضافات'),
                      style: TextStyle(
                        fontSize: 10 * scaleFactor,
                        fontWeight: activeModifierTab == 0
                            ? FontWeight.w900
                            : FontWeight.w600,
                        color: activeModifierTab == 0
                            ? AppColors.success
                            : AppColors.textMuted,
                      ),
                    ),
                    // Count badge
                    if (currentModifiers.any((m) => !m.isOption)) ...[
                      SizedBox(width: 4 * scaleFactor),
                      Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: 4 * scaleFactor,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.success,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '${currentModifiers.where((m) => !m.isOption).length}',
                          style: TextStyle(
                            fontSize: 8 * scaleFactor,
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          SizedBox(width: 4 * scaleFactor),
          // الخيارات tab
          Expanded(
            child: GestureDetector(
              onTap: () => setState(() => activeModifierTab = 1),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: EdgeInsets.symmetric(vertical: 6 * scaleFactor),
                decoration: BoxDecoration(
                  color: activeModifierTab == 1
                      ? AppColors.info.withValues(alpha: 0.15)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                  border: activeModifierTab == 1
                      ? Border.all(color: AppColors.info.withValues(alpha: 0.3))
                      : null,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      PhosphorIconsBold.listChecks,
                      size: 13 * scaleFactor,
                      color: activeModifierTab == 1
                          ? AppColors.info
                          : AppColors.textMuted,
                    ),
                    SizedBox(width: 4 * scaleFactor),
                    Text(
                      tr('الخيارات'),
                      style: TextStyle(
                        fontSize: 10 * scaleFactor,
                        fontWeight: activeModifierTab == 1
                            ? FontWeight.w900
                            : FontWeight.w600,
                        color: activeModifierTab == 1
                            ? AppColors.info
                            : AppColors.textMuted,
                      ),
                    ),
                    // Count badge
                    if (currentModifiers.any((m) => m.isOption)) ...[
                      SizedBox(width: 4 * scaleFactor),
                      Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: 4 * scaleFactor,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.info,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '${currentModifiers.where((m) => m.isOption).length}',
                          style: TextStyle(
                            fontSize: 8 * scaleFactor,
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────
  // NOTE FIELD
  // ─────────────────────────────────────────────────────────────────────

  Widget _buildNoteField(double scaleFactor) {
    return buildCartItemNoteField(
      scaleFactor: scaleFactor,
      noteController: noteController,
      onSave: () {
        final note = noteController.text.trim();
        tileRef
            .read(cartControllerProvider.notifier)
            .updateItemNote(tileIndex, note.isEmpty ? null : note);
        FocusScope.of(context).unfocus();
      },
    );
  }

  // ─────────────────────────────────────────────────────────────────────
  // ADDITIONS TAB CONTENT
  // ─────────────────────────────────────────────────────────────────────

  Widget _buildAdditionsTabContent(
    List<ModifierGroupWithItems> additionGroups,
    List<SelectedModifier> currentModifiers,
    double scaleFactor,
  ) {
    if (additionGroups.isEmpty) {
      return Padding(
        key: const ValueKey('additions-empty'),
        padding: EdgeInsets.symmetric(vertical: 8 * scaleFactor),
        child: Text(
          tr('لا توجد إضافات لهذا الصنف'),
          style: TextStyle(fontSize: 10 * scaleFactor, color: AppColors.textMuted),
          textAlign: TextAlign.center,
        ),
      );
    }

    return Column(
      key: const ValueKey('additions-content'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final group in additionGroups)
          _buildAdditionGroup(group, currentModifiers, scaleFactor),
      ],
    );
  }

  /// Build a single addition group with toggleable chips
  Widget _buildAdditionGroup(
    ModifierGroupWithItems group,
    List<SelectedModifier> currentModifiers,
    double scaleFactor,
  ) {
    final selectedIds = currentModifiers
        .where((m) => m.groupName == group.group.name && !m.isOption)
        .map((m) => m.itemId)
        .toSet();

    return Padding(
      padding: EdgeInsets.only(bottom: 6 * scaleFactor),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Group header
          Row(
            children: [
              Icon(PhosphorIconsBold.plusCircle,
                  size: 11 * scaleFactor, color: AppColors.success),
              SizedBox(width: 4 * scaleFactor),
              Text(
                group.group.name,
                style: TextStyle(
                  fontSize: 10 * scaleFactor,
                  fontWeight: FontWeight.w800,
                  color: AppColors.success,
                ),
              ),
              if (group.group.isRequired) ...[
                SizedBox(width: 3 * scaleFactor),
                Text('*', style: TextStyle(
                  fontSize: 10 * scaleFactor, color: AppColors.error,
                  fontWeight: FontWeight.bold,
                )),
              ],
            ],
          ),
          SizedBox(height: 4 * scaleFactor),
          // Addition chips
          Wrap(
            spacing: 5 * scaleFactor,
            runSpacing: 5 * scaleFactor,
            children: group.items.map((item) {
              final isSelected = selectedIds.contains(item.id);
              return GestureDetector(
                onTap: () => _toggleAddition(group, item, isSelected),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: EdgeInsets.symmetric(
                    horizontal: 8 * scaleFactor,
                    vertical: 5 * scaleFactor,
                  ),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? AppColors.success.withValues(alpha: 0.15)
                        : Theme.of(context).colorScheme.surface,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isSelected
                          ? AppColors.success.withValues(alpha: 0.5)
                          : AppColors.border.withValues(alpha: 0.4),
                      width: isSelected ? 1.5 : 1,
                    ),
                    boxShadow: isSelected ? [
                      BoxShadow(
                        color: AppColors.success.withValues(alpha: 0.1),
                        blurRadius: 4,
                        offset: const Offset(0, 1),
                      ),
                    ] : null,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isSelected
                            ? PhosphorIconsBold.checkCircle
                            : PhosphorIconsBold.circle,
                        size: 12 * scaleFactor,
                        color: isSelected ? AppColors.success : AppColors.textMuted,
                      ),
                      SizedBox(width: 4 * scaleFactor),
                      Text(
                        item.name,
                        style: TextStyle(
                          fontSize: 10 * scaleFactor,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                          color: isSelected ? AppColors.success : null,
                        ),
                      ),
                      if (item.extraPrice > 0) ...[
                        SizedBox(width: 4 * scaleFactor),
                        Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: 4 * scaleFactor,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.success.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            '+${item.extraPrice.toStringAsFixed(0)} ${AppConstants.currencySymbolEn}',
                            style: TextStyle(
                              fontSize: 8 * scaleFactor,
                              color: AppColors.success,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────
  // OPTIONS TAB CONTENT
  // ─────────────────────────────────────────────────────────────────────

  Widget _buildOptionsTabContent(
    List<ModifierGroupWithItems> optionGroups,
    List<SelectedModifier> currentModifiers,
    double scaleFactor,
  ) {
    if (optionGroups.isEmpty) {
      return Padding(
        key: const ValueKey('options-empty'),
        padding: EdgeInsets.symmetric(vertical: 8 * scaleFactor),
        child: Text(
          tr('لا توجد خيارات لهذا الصنف'),
          style: TextStyle(fontSize: 10 * scaleFactor, color: AppColors.textMuted),
          textAlign: TextAlign.center,
        ),
      );
    }

    return Column(
      key: const ValueKey('options-content'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ─── Quantity Level Segmented Control ───
        Container(
          margin: EdgeInsets.only(bottom: 8 * scaleFactor),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.border.withValues(alpha: 0.3)),
          ),
          padding: const EdgeInsets.all(3),
          child: Row(
            children: OptionQuantityLevel.values
                .where((l) => l != OptionQuantityLevel.none)
                .map((level) {
              final isActive = selectedQuantityLevel == level;
              return Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => selectedQuantityLevel = level),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    padding: EdgeInsets.symmetric(vertical: 6 * scaleFactor),
                    decoration: BoxDecoration(
                      color: isActive
                          ? level.color.withValues(alpha: 0.18)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                      border: isActive
                          ? Border.all(color: level.color.withValues(alpha: 0.4))
                          : null,
                      boxShadow: isActive ? [
                        BoxShadow(
                          color: level.color.withValues(alpha: 0.1),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ] : null,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          level.icon,
                          size: 13 * scaleFactor,
                          color: isActive ? level.color : AppColors.textMuted,
                        ),
                        SizedBox(width: 4 * scaleFactor),
                        Text(
                          level.label,
                          style: TextStyle(
                            fontSize: 10 * scaleFactor,
                            fontWeight: isActive ? FontWeight.w900 : FontWeight.w600,
                            color: isActive ? level.color : AppColors.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),

        // ─── Option groups ───
        for (final group in optionGroups)
          _buildOptionGroup(group, currentModifiers, scaleFactor),
      ],
    );
  }

  /// Build a single option group with quantity-level aware chips
  Widget _buildOptionGroup(
    ModifierGroupWithItems group,
    List<SelectedModifier> currentModifiers,
    double scaleFactor,
  ) {
    return Padding(
      padding: EdgeInsets.only(bottom: 6 * scaleFactor),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Group header
          Row(
            children: [
              Icon(PhosphorIconsBold.listChecks,
                  size: 11 * scaleFactor, color: AppColors.info),
              SizedBox(width: 4 * scaleFactor),
              Text(
                group.group.name,
                style: TextStyle(
                  fontSize: 10 * scaleFactor,
                  fontWeight: FontWeight.w800,
                  color: AppColors.info,
                ),
              ),
              if (group.group.isRequired) ...[
                SizedBox(width: 3 * scaleFactor),
                Text('*', style: TextStyle(
                  fontSize: 10 * scaleFactor, color: AppColors.error,
                  fontWeight: FontWeight.bold,
                )),
              ],
            ],
          ),
          SizedBox(height: 4 * scaleFactor),
          // Option chips
          Wrap(
            spacing: 5 * scaleFactor,
            runSpacing: 5 * scaleFactor,
            children: group.items.map((item) {
              // Find if this item is already selected
              final existingMod = currentModifiers.cast<SelectedModifier?>().firstWhere(
                (m) => m!.itemId == item.id && m.groupName == group.group.name && m.isOption,
                orElse: () => null,
              );
              final isSelected = existingMod != null;
              final assignedLevel = existingMod?.quantityLevel ?? OptionQuantityLevel.none;
              final chipColor = isSelected ? assignedLevel.color : AppColors.textMuted;

              return GestureDetector(
                onTap: () => _toggleOption(group, item, isSelected, existingMod),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: EdgeInsets.symmetric(
                    horizontal: 8 * scaleFactor,
                    vertical: 5 * scaleFactor,
                  ),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? chipColor.withValues(alpha: 0.12)
                        : Theme.of(context).colorScheme.surface,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isSelected
                          ? chipColor.withValues(alpha: 0.5)
                          : AppColors.border.withValues(alpha: 0.4),
                      width: isSelected ? 1.5 : 1,
                    ),
                    boxShadow: isSelected ? [
                      BoxShadow(
                        color: chipColor.withValues(alpha: 0.1),
                        blurRadius: 4,
                        offset: const Offset(0, 1),
                      ),
                    ] : null,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isSelected ? assignedLevel.icon : PhosphorIconsBold.circle,
                        size: 12 * scaleFactor,
                        color: chipColor,
                      ),
                      SizedBox(width: 4 * scaleFactor),
                      Text(
                        item.name,
                        style: TextStyle(
                          fontSize: 10 * scaleFactor,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                          color: isSelected ? chipColor : null,
                        ),
                      ),
                      // Show assigned level label
                      if (isSelected && assignedLevel != OptionQuantityLevel.none) ...[
                        SizedBox(width: 4 * scaleFactor),
                        Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: 4 * scaleFactor,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: chipColor.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            assignedLevel.label,
                            style: TextStyle(
                              fontSize: 8 * scaleFactor,
                              color: chipColor,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────
  // TOGGLE HELPERS
  // ─────────────────────────────────────────────────────────────────────

  /// Toggle an addition modifier (simple on/off)
  void _toggleAddition(
    ModifierGroupWithItems group,
    ModifierItemData item,
    bool isCurrentlySelected,
  ) {
    final currentModifiers = List<SelectedModifier>.from(tileWidget.item.modifiers);
    final isSingle = group.group.maxSelect == 1;

    if (isCurrentlySelected) {
      currentModifiers.removeWhere(
        (m) => m.itemId == item.id && m.groupName == group.group.name,
      );
    } else {
      if (isSingle) {
        currentModifiers.removeWhere(
          (m) => m.groupName == group.group.name && !m.isOption,
        );
      } else {
        final currentGroupCount = currentModifiers
            .where((m) => m.groupName == group.group.name && !m.isOption)
            .length;
        if (group.group.maxSelect > 0 && currentGroupCount >= group.group.maxSelect) {
          return;
        }
      }
      currentModifiers.add(SelectedModifier(
        itemId: item.id,
        itemName: item.name,
        groupName: group.group.name,
        extraPrice: item.extraPrice,
        isOption: false,
        quantityLevel: OptionQuantityLevel.none,
      ));
    }

    tileRef.read(cartControllerProvider.notifier)
        .updateItemModifiers(tileIndex, currentModifiers);
  }

  /// Toggle an option modifier with quantity level
  void _toggleOption(
    ModifierGroupWithItems group,
    ModifierItemData item,
    bool isCurrentlySelected,
    SelectedModifier? existingMod,
  ) {
    final currentModifiers = List<SelectedModifier>.from(tileWidget.item.modifiers);
    final isSingle = group.group.maxSelect == 1;

    if (isCurrentlySelected) {
      // If tapping the same item again with same level, remove it
      // If different level, update it
      if (existingMod?.quantityLevel == selectedQuantityLevel) {
        currentModifiers.removeWhere(
          (m) => m.itemId == item.id && m.groupName == group.group.name,
        );
      } else {
        // Update quantity level
        final idx = currentModifiers.indexWhere(
          (m) => m.itemId == item.id && m.groupName == group.group.name,
        );
        if (idx >= 0) {
          currentModifiers[idx] = SelectedModifier(
            itemId: item.id,
            itemName: item.name,
            groupName: group.group.name,
            extraPrice: item.extraPrice,
            isOption: true,
            quantityLevel: selectedQuantityLevel,
          );
        }
      }
    } else {
      if (isSingle) {
        currentModifiers.removeWhere(
          (m) => m.groupName == group.group.name && m.isOption,
        );
      } else {
        final currentGroupCount = currentModifiers
            .where((m) => m.groupName == group.group.name && m.isOption)
            .length;
        if (group.group.maxSelect > 0 && currentGroupCount >= group.group.maxSelect) {
          return;
        }
      }
      currentModifiers.add(SelectedModifier(
        itemId: item.id,
        itemName: item.name,
        groupName: group.group.name,
        extraPrice: item.extraPrice,
        isOption: true,
        quantityLevel: selectedQuantityLevel,
      ));
    }

    tileRef.read(cartControllerProvider.notifier)
        .updateItemModifiers(tileIndex, currentModifiers);
  }

  /// Load modifier groups for this product from DB
  Future<List<ModifierGroupWithItems>> _loadModifierGroups() async {
    try {
      final productRepo = tileRef.read(productRepositoryProvider);
      return await productRepo.getProductModifiers(tileWidget.item.productId);
    } catch (_) {
      return [];
    }
  }
}
