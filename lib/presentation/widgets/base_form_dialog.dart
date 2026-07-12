import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/utils/friendly_error.dart';
import '../../core/widgets/app_toast.dart';
import 'package:ural_erp/l10n/app_localizations.dart';

/// Base class for form-based dialogs.
///
/// Provides:
/// - Auto-disposed [TextEditingController]s via [registerController]
/// - Loading state management with spinner overlay
/// - Standardized dialog layout (title, scrollable content, actions)
/// - Built-in RTL wrapping
/// - Template-method [onSave] with try/catch + toast notifications
/// - [FormState] key with auto-validation
///
/// ### Usage
/// ```dart
/// class MyDialog extends BaseFormDialog<int> {
///   const MyDialog({super.key});
///
///   @override
///   BaseFormDialogState<int, MyDialog> createState() => _MyDialogState();
/// }
///
/// class _MyDialogState extends BaseFormDialogState<int, MyDialog> {
///   late final amountCtrl = registerController();
///
///   @override
///   String get dialogTitle => 'عنوان';
///   @override
///   IconData get dialogIcon => Icons.add;
///   @override
///   Widget buildFormContent(BuildContext context, AppLocalizations l) => ...;
///   @override
///   Future<int> onSave() async => ...;
/// }
/// ```
///
/// ISS-10: Created as part of PIR Phase 4 to reduce dialog code duplication.
abstract class BaseFormDialog<T> extends ConsumerStatefulWidget {
  const BaseFormDialog({super.key});
}

/// State for [BaseFormDialog].
///
/// Subclass this and override:
/// - [dialogTitle] — header text
/// - [dialogIcon] — header icon
/// - [dialogIconColor] — optional icon colour (defaults to primary)
/// - [dialogWidth] — optional dialog width (defaults to 450)
/// - [buildFormContent] — the form body
/// - [onSave] — save logic, return value is popped back to caller
/// - [buildActions] — optional custom actions (defaults to Cancel + Save)
abstract class BaseFormDialogState<T, W extends BaseFormDialog<T>>
    extends ConsumerState<W> {
  // ── Template Methods (override in subclass) ────────────────────────────

  /// Dialog title text.
  String get dialogTitle;

  /// Icon shown beside the title.
  IconData get dialogIcon;

  /// Icon colour (defaults to primary).
  Color get dialogIconColor => Theme.of(context).colorScheme.primary;

  /// Dialog content width.
  double get dialogWidth => 450;

  /// Build the scrollable form body.
  Widget buildFormContent(BuildContext context, AppLocalizations localizations);

  /// Perform save operation. Throw to trigger error toast.
  /// Return value is passed to [Navigator.pop].
  Future<T> onSave();

  // ── Provided Infrastructure ────────────────────────────────────────────

  /// Whether a save is in progress.
  bool isLoading = false;

  /// Global form key for validation.
  final formKey = GlobalKey<FormState>();

  /// Registered controllers — auto-disposed.
  final List<TextEditingController> _controllers = [];

  /// Register a [TextEditingController] that will be auto-disposed.
  TextEditingController registerController([String? initialText]) {
    final ctrl = TextEditingController(text: initialText);
    _controllers.add(ctrl);
    return ctrl;
  }

  /// Show a success toast.
  void showSuccess(String message) {
    if (mounted) AppToast.show(context, message);
  }

  /// Show an error toast.
  void showError(String message) {
    if (mounted) AppToast.show(context, message);
  }

  // ── Lifecycle ──────────────────────────────────────────────────────────

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    super.dispose();
  }

  // ── Build ──────────────────────────────────────────────────────────────

  /// Override to provide custom action buttons.
  List<Widget> buildActions(
      BuildContext context, AppLocalizations localizations) {
    return [
      TextButton(
        onPressed: isLoading ? null : () => Navigator.pop(context),
        child: Text(localizations.cancel),
      ),
      ElevatedButton.icon(
        onPressed: isLoading ? null : _handleSave,
        icon: isLoading
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Icon(dialogIcon, size: 18),
        label: Text(localizations.save),
      ),
    ];
  }

  Future<void> _handleSave() async {
    if (formKey.currentState?.validate() == false) return;

    setState(() => isLoading = true);
    try {
      final result = await onSave();
      if (mounted) Navigator.pop(context, result);
    } catch (e) {
      showError(friendlyError(e));
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context)!;

    return Directionality(
      textDirection: ui.TextDirection.rtl,
      child: AlertDialog(
        title: Row(
          children: [
            Icon(dialogIcon, color: dialogIconColor),
            const SizedBox(width: 8),
            Expanded(child: Text(dialogTitle)),
          ],
        ),
        content: SizedBox(
          width: dialogWidth,
          child: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: buildFormContent(context, localizations),
            ),
          ),
        ),
        actions: buildActions(context, localizations),
      ),
    );
  }
}
