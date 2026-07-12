import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/widgets/app_toast.dart';
import 'package:ural_erp/l10n/app_localizations.dart';
import 'package:ural_erp/core/theme/app_colors.dart';

/// Standard form-based dialog for the UralCash ERP system.
/// Extends the logic of base forms with a more premium design.
abstract class AppFormDialog<T> extends ConsumerStatefulWidget {
  const AppFormDialog({super.key});
}

abstract class AppFormDialogState<T, W extends AppFormDialog<T>>
    extends ConsumerState<W> {
  // ── Template Methods ──

  String get dialogTitle;
  IconData get dialogIcon;
  Color get dialogIconColor => AppColors.primary;
  double get dialogWidth => 500;

  Widget buildFormContent(BuildContext context, AppLocalizations localizations);

  Future<T> onSave();

  // ── Infrastructure ──

  bool isLoading = false;
  final formKey = GlobalKey<FormState>();
  final List<TextEditingController> _controllers = [];

  TextEditingController registerController([String? initialText]) {
    final ctrl = TextEditingController(text: initialText);
    _controllers.add(ctrl);
    return ctrl;
  }

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _handleSave() async {
    if (formKey.currentState?.validate() == false) return;

    setState(() => isLoading = true);
    try {
      final result = await onSave();
      if (mounted) Navigator.pop(context, result);
    } catch (e) {
      if (mounted) AppToast.show(context, '$e');
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        titlePadding: const EdgeInsets.all(0),
        title: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.05),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: dialogIconColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(dialogIcon, color: dialogIconColor, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  dialogTitle,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                ),
              ),
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close, size: 20),
                style: IconButton.styleFrom(
                  backgroundColor: Colors.grey.withValues(alpha: 0.1),
                ),
              ),
            ],
          ),
        ),
        content: SizedBox(
          width: dialogWidth,
          child: Form(
            key: formKey,
            child: SingleChildScrollView(
              padding: const EdgeInsets.only(top: 8),
              child: buildFormContent(context, localizations),
            ),
          ),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        actions: [
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: isLoading ? null : () => Navigator.pop(context),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: Text(localizations.cancel),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: isLoading ? null : _handleSave,
                  icon: isLoading
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : Icon(dialogIcon, size: 18),
                  label: Text(localizations.save),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
