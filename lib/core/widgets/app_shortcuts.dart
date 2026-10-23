import 'package:picpos_erp/core/i18n/tr.dart';
import 'package:picpos_erp/core/design_system/typography.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// ───────────────────────────────────────────────────────────────────
/// AppShortcuts — Reusable keyboard shortcuts wrapper for ERP screens
/// ───────────────────────────────────────────────────────────────────
///
/// Bindings:
///   F2  → Focus search field
///   F5  → Trigger "New" action (create invoice/product/etc.)
///   Esc → Close topmost dialog / clear search
///   Ctrl+S → Save / submit
///   Ctrl+P → Print
///
/// Usage:
/// ```dart
/// AppShortcuts(
///   searchFocusNode: _searchFocusNode,
///   onNew: () => _showCreateDialog(),
///   onSave: () => _save(),
///   child: Scaffold(...),
/// )
/// ```
class AppShortcuts extends StatelessWidget {
  final Widget child;

  /// Focus node for the search TextField. F2 will request focus on this node.
  final FocusNode? searchFocusNode;

  /// Called when F5 is pressed (create new entity).
  final VoidCallback? onNew;

  /// Called when Ctrl+S is pressed.
  final VoidCallback? onSave;

  /// Called when Ctrl+P is pressed.
  final VoidCallback? onPrint;

  /// Called when Esc is pressed with no dialog open.
  /// If null, Esc defaults to clearing the search field + unfocusing.
  final VoidCallback? onEscape;

  /// Search controller — used by Esc to clear text.
  final TextEditingController? searchController;

  /// Feature 031 — optional hook fired BEFORE the existing Esc handler.
  /// If non-null and returns `true`, the Esc keystroke is treated as
  /// consumed (the touch keyboard dismissed itself) and the existing
  /// search-clear / dialog-pop logic is skipped. Default `null` keeps
  /// every prior call site behaviour-identical (Constitution
  /// Principle I).
  final bool Function()? onTouchKeyboardDismiss;

  const AppShortcuts({
    super.key,
    required this.child,
    this.searchFocusNode,
    this.onNew,
    this.onSave,
    this.onPrint,
    this.onEscape,
    this.searchController,
    this.onTouchKeyboardDismiss,
  });

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        // F2 → Focus search
        if (searchFocusNode != null)
          const SingleActivator(LogicalKeyboardKey.f2): () {
            searchFocusNode!.requestFocus();
          },

        // F5 → New / Refresh
        const SingleActivator(LogicalKeyboardKey.f5): ?onNew,

        // Ctrl+S → Save
        const SingleActivator(LogicalKeyboardKey.keyS, control: true):
              ?onSave,

        // Ctrl+P → Print
        const SingleActivator(LogicalKeyboardKey.keyP, control: true):
              ?onPrint,

        // Esc → Close dialog or clear search
        const SingleActivator(LogicalKeyboardKey.escape): () {
          // Feature 031 — touch keyboard claims Esc when visible.
          if (onTouchKeyboardDismiss != null && onTouchKeyboardDismiss!()) {
            return;
          }
          if (onEscape != null) {
            onEscape!();
            return;
          }
          // Default: clear search field and unfocus
          if (searchController != null && searchController!.text.isNotEmpty) {
            searchController!.clear();
            if (searchFocusNode != null) {
              searchFocusNode!.unfocus();
            }
          } else {
            // Try to pop navigator if there's a dialog
            final navigator = Navigator.maybeOf(context);
            if (navigator != null && navigator.canPop()) {
              navigator.pop();
            }
          }
        },
      },
      child: Focus(
        autofocus: true,
        child: child,
      ),
    );
  }
}

/// A simple banner widget that shows available keyboard shortcuts.
/// Display at the bottom of screens for discoverability.
class ShortcutHintBar extends StatelessWidget {
  final bool showSearch;
  final bool showNew;
  final bool showSave;

  const ShortcutHintBar({
    super.key,
    this.showSearch = true,
    this.showNew = true,
    this.showSave = false,
  });

  @override
  Widget build(BuildContext context) {
    final hints = <String>[];
    if (showSearch) hints.add(tr('F2 بحث'));
    if (showNew) hints.add(tr('F5 جديد'));
    if (showSave) hints.add(tr('Ctrl+S حفظ'));
    hints.add(tr('Esc إغلاق'));

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        border: Border(top: BorderSide(color: Colors.grey.shade200)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: hints
            .map((h) => Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade200,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: Colors.grey.shade300),
                        ),
                        child: Text(
                          h.split(' ').first,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: Colors.grey.shade700,
                            fontFamily: AppTypography.mono,
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        h.split(' ').sublist(1).join(' '),
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ))
            .toList(),
      ),
    );
  }
}
