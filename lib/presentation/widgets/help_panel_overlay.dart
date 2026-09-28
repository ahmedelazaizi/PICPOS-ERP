// ═══════════════════════════════════════════════════════════════════════════
// U-01: Help Panel Overlay — F1 Keyboard Shortcut Help
// Shows context-sensitive keyboard shortcuts and help for current screen
// ═══════════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../core/theme/app_colors.dart';

/// A keyboard shortcut definition for the help panel
class HelpShortcut {
  final String keys;
  final String description;
  final String? category;

  const HelpShortcut({
    required this.keys,
    required this.description,
    this.category,
  });
}

/// Global shortcuts available on all screens
const _globalShortcuts = [
  HelpShortcut(keys: 'F1', description: 'عرض لوحة المساعدة', category: 'عام'),
  HelpShortcut(keys: 'Ctrl+S', description: 'حفظ', category: 'عام'),
  HelpShortcut(keys: 'Ctrl+N', description: 'إنشاء جديد', category: 'عام'),
  HelpShortcut(keys: 'Ctrl+F', description: 'بحث', category: 'عام'),
  HelpShortcut(keys: 'Ctrl+P', description: 'طباعة', category: 'عام'),
  HelpShortcut(keys: 'Ctrl+E', description: 'تصدير', category: 'عام'),
  HelpShortcut(keys: 'Escape', description: 'إغلاق / إلغاء', category: 'عام'),
  HelpShortcut(keys: 'Delete', description: 'حذف العنصر المحدد', category: 'عام'),
];

/// POS-specific shortcuts
const posShortcuts = [
  HelpShortcut(keys: 'F2', description: 'بحث الأصناف', category: 'البيع السريع'),
  HelpShortcut(keys: 'F3', description: 'العملاء', category: 'البيع السريع'),
  HelpShortcut(keys: 'F4', description: 'تعليق الطلب', category: 'البيع السريع'),
  HelpShortcut(keys: 'F5', description: 'استرجاع طلب معلق', category: 'البيع السريع'),
  HelpShortcut(keys: 'F8', description: 'خصم', category: 'البيع السريع'),
  HelpShortcut(keys: 'F9', description: 'طريقة الدفع', category: 'البيع السريع'),
  HelpShortcut(keys: 'F12', description: 'إتمام البيع', category: 'البيع السريع'),
  HelpShortcut(keys: '+/-', description: 'زيادة/تقليل الكمية', category: 'البيع السريع'),
];

/// Accounting-specific shortcuts
const accountingShortcuts = [
  HelpShortcut(keys: 'Ctrl+J', description: 'قيد يدوي جديد', category: 'المحاسبة'),
  HelpShortcut(keys: 'Ctrl+R', description: 'عكس القيد المحدد', category: 'المحاسبة'),
  HelpShortcut(keys: 'Ctrl+T', description: 'من قالب', category: 'المحاسبة'),
];

/// Help panel overlay showing keyboard shortcuts
class HelpPanelOverlay extends StatelessWidget {
  final List<HelpShortcut> screenShortcuts;
  final String screenName;
  final VoidCallback onClose;

  const HelpPanelOverlay({
    super.key,
    required this.screenShortcuts,
    required this.screenName,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    // Merge global + screen-specific shortcuts
    final allShortcuts = [..._globalShortcuts, ...screenShortcuts];

    // Group by category
    final grouped = <String, List<HelpShortcut>>{};
    for (final s in allShortcuts) {
      (grouped[s.category ?? 'أخرى'] ??= []).add(s);
    }

    return Material(
      color: Colors.black54,
      child: Center(
        child: Container(
          width: 500,
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.75,
          ),
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.3),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.05),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                ),
                child: Row(
                  children: [
                    const Icon(PhosphorIconsBold.keyboard, color: AppColors.primary, size: 24),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'اختصارات لوحة المفاتيح',
                            style: GoogleFonts.cairo(fontSize: 16, fontWeight: FontWeight.w700),
                          ),
                          Text(
                            screenName,
                            style: GoogleFonts.cairo(fontSize: 11, color: AppColors.textMuted),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(PhosphorIconsBold.x, size: 20),
                      onPressed: onClose,
                    ),
                  ],
                ),
              ),
              // Body
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Directionality(
                    textDirection: TextDirection.rtl,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: grouped.entries.map((entry) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(top: 8, bottom: 8),
                              child: Text(
                                entry.key,
                                style: GoogleFonts.cairo(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.primary,
                                ),
                              ),
                            ),
                            ...entry.value.map((s) => _shortcutRow(s)),
                          ],
                        );
                      }).toList(),
                    ),
                  ),
                ),
              ),
              // Footer hint
              Container(
                padding: const EdgeInsets.all(12),
                decoration: const BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.vertical(bottom: Radius.circular(16)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _keyBadge('F1'),
                    const SizedBox(width: 6),
                    Text(
                      'أو',
                      style: GoogleFonts.cairo(fontSize: 11, color: AppColors.textMuted),
                    ),
                    const SizedBox(width: 6),
                    _keyBadge('Esc'),
                    const SizedBox(width: 6),
                    Text(
                      'للإغلاق',
                      style: GoogleFonts.cairo(fontSize: 11, color: AppColors.textMuted),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _shortcutRow(HelpShortcut shortcut) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(
            width: 100,
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: _keyBadge(shortcut.keys),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              shortcut.description,
              style: GoogleFonts.cairo(fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _keyBadge(String key) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            offset: const Offset(0, 1),
            blurRadius: 1,
          ),
        ],
      ),
      child: Text(
        key,
        style: GoogleFonts.jetBrainsMono(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: AppColors.textPrimary,
        ),
      ),
    );
  }
}

/// Mixin to add F1 help panel support to any screen
/// Usage: Mix into State class and call `initHelpPanel(shortcuts, screenName)`
mixin HelpPanelMixin<T extends StatefulWidget> on State<T> {
  OverlayEntry? _helpOverlay;

  /// Register F1 key listener
  void initHelpPanel({
    required List<HelpShortcut> shortcuts,
    required String screenName,
  }) {
    // The F1 key is handled via the Focus widget wrapping the screen
    _helpShortcuts = shortcuts;
    _helpScreenName = screenName;
  }

  List<HelpShortcut> _helpShortcuts = [];
  String _helpScreenName = '';

  /// Call this from your KeyboardListener or Focus.onKeyEvent
  KeyEventResult handleHelpKey(KeyEvent event) {
    if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.f1) {
      toggleHelpPanel();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void toggleHelpPanel() {
    if (_helpOverlay != null) {
      _helpOverlay?.remove();
      _helpOverlay = null;
    } else {
      _helpOverlay = OverlayEntry(
        builder: (ctx) => HelpPanelOverlay(
          screenShortcuts: _helpShortcuts,
          screenName: _helpScreenName,
          onClose: () {
            _helpOverlay?.remove();
            _helpOverlay = null;
          },
        ),
      );
      Overlay.of(context).insert(_helpOverlay!);
    }
  }

  @override
  void dispose() {
    _helpOverlay?.remove();
    super.dispose();
  }
}
