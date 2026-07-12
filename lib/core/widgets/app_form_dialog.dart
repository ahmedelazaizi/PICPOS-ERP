import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// A reusable RTL-aware form dialog for the entire application.
///
/// Encapsulates the common dialog pattern: RTL Directionality → Dialog →
/// rounded shape → ConstrainedBox → Column(title, content, actions).
/// Eliminates code duplication across 10+ dialog files (PIR-008).
///
/// Usage:
/// ```dart
/// showDialog(
///   context: context,
///   builder: (_) => AppFormDialog(
///     title: 'عنوان',
///     content: MyFormContent(),
///     actions: [
///       TextButton(onPressed: () => Navigator.pop(context), child: Text('إلغاء')),
///       ElevatedButton(onPressed: _save, child: Text('حفظ')),
///     ],
///   ),
/// );
/// ```
class AppFormDialog extends StatelessWidget {
  /// Dialog title displayed in Cairo bold font.
  final String title;

  /// The main content area of the dialog.
  final Widget content;

  /// Action buttons at the bottom (typically Cancel + Save).
  final List<Widget>? actions;

  /// Maximum width constraint. Default: 500.
  final double maxWidth;

  /// Maximum height constraint. Default: 600.
  final double maxHeight;

  /// Optional icon displayed before the title.
  final IconData? titleIcon;

  /// Optional icon color.
  final Color? titleIconColor;

  /// Whether the dialog content should be scrollable.
  final bool scrollable;

  const AppFormDialog({
    super.key,
    required this.title,
    required this.content,
    this.actions,
    this.maxWidth = 500,
    this.maxHeight = 600,
    this.titleIcon,
    this.titleIconColor,
    this.scrollable = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth, maxHeight: maxHeight),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Title Bar ──
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withValues(alpha: 0.08),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                ),
                child: Row(
                  children: [
                    if (titleIcon != null) ...[
                      Icon(titleIcon, size: 22, color: titleIconColor ?? theme.colorScheme.primary),
                      const SizedBox(width: 10),
                    ],
                    Expanded(
                      child: Text(
                        title,
                        style: GoogleFonts.cairo(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: theme.colorScheme.onSurface,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 20),
                      onPressed: () => Navigator.pop(context),
                      splashRadius: 18,
                    ),
                  ],
                ),
              ),

              // ── Content ──
              if (scrollable)
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                    child: content,
                  ),
                )
              else
                Flexible(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                    child: content,
                  ),
                ),

              // ── Actions ──
              if (actions != null && actions!.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  decoration: BoxDecoration(
                    border: Border(
                      top: BorderSide(color: theme.dividerColor.withValues(alpha: 0.3)),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: actions!
                        .expand((w) => [w, const SizedBox(width: 8)])
                        .toList()
                      ..removeLast(),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A convenience method to show an [AppFormDialog].
Future<T?> showAppFormDialog<T>({
  required BuildContext context,
  required String title,
  required Widget content,
  List<Widget>? actions,
  double maxWidth = 500,
  double maxHeight = 600,
  IconData? titleIcon,
  bool barrierDismissible = true,
  bool scrollable = false,
}) {
  return showDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    builder: (_) => AppFormDialog(
      title: title,
      content: content,
      actions: actions,
      maxWidth: maxWidth,
      maxHeight: maxHeight,
      titleIcon: titleIcon,
      scrollable: scrollable,
    ),
  );
}
