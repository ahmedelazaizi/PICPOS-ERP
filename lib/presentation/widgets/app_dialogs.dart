import 'package:flutter/material.dart';
import '../../core/widgets/app_toast.dart';

/// Unified dialog builder for the UralCash ERP system.
///
/// Provides standardized, themed dialogs with consistent styling,
/// localized Arabic button labels, and reusable patterns.
class AppDialogs {
  AppDialogs._();

  // ═══════════════════════════════════════════════════════════════════════
  // CONFIRMATION DIALOGS
  // ═══════════════════════════════════════════════════════════════════════

  /// Shows a confirmation dialog with a title, message, and confirm/cancel buttons.
  /// Returns `true` if confirmed, `false` if cancelled.
  static Future<bool> confirm(
    BuildContext context, {
    required String title,
    required String message,
    String confirmLabel = 'تأكيد',
    String cancelLabel = 'إلغاء',
    Color? confirmColor,
    IconData? icon,
    bool isDangerous = false,
  }) async {
    final theme = Theme.of(context);
    final effectiveColor = confirmColor ??
        (isDangerous ? theme.colorScheme.error : theme.colorScheme.primary);

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: icon != null ? Icon(icon, color: effectiveColor, size: 32) : null,
        title: Text(title, textAlign: TextAlign.center),
        content: Text(message, textAlign: TextAlign.center),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(cancelLabel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(backgroundColor: effectiveColor),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  /// Shortcut for dangerous confirmations (delete, discard, etc.).
  static Future<bool> confirmDanger(
    BuildContext context, {
    required String title,
    required String message,
    String confirmLabel = 'حذف',
    IconData icon = Icons.warning_amber_rounded,
  }) =>
      confirm(
        context,
        title: title,
        message: message,
        confirmLabel: confirmLabel,
        icon: icon,
        isDangerous: true,
      );

  // ═══════════════════════════════════════════════════════════════════════
  // INFORMATION DIALOGS
  // ═══════════════════════════════════════════════════════════════════════

  /// Shows a success dialog with an optional auto-dismiss duration.
  static Future<void> success(
    BuildContext context, {
    required String title,
    String? message,
    Duration? autoDismiss,
  }) async {
    final future = showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Icon(Icons.check_circle_outline,
            color: Colors.green.shade600, size: 48),
        title: Text(title, textAlign: TextAlign.center),
        content:
            message != null ? Text(message, textAlign: TextAlign.center) : null,
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('حسناً'),
          ),
        ],
      ),
    );

    if (autoDismiss != null) {
      Future.delayed(autoDismiss, () {
        if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
      });
    }

    return future;
  }

  /// Shows an error dialog.
  static Future<void> error(
    BuildContext context, {
    required String title,
    String? message,
    String? details,
  }) {
    return showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Icon(Icons.error_outline,
            color: Theme.of(ctx).colorScheme.error, size: 48),
        title: Text(title, textAlign: TextAlign.center),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (message != null)
              Text(message, textAlign: TextAlign.center),
            if (details != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(ctx)
                      .colorScheme
                      .errorContainer
                      .withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  details,
                  style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                        fontFamily: 'monospace',
                      ),
                  textDirection: TextDirection.ltr,
                ),
              ),
            ],
          ],
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('حسناً'),
          ),
        ],
      ),
    );
  }

  /// Shows an informational dialog.
  static Future<void> info(
    BuildContext context, {
    required String title,
    String? message,
  }) {
    return showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Icon(Icons.info_outline,
            color: Theme.of(ctx).colorScheme.primary, size: 48),
        title: Text(title, textAlign: TextAlign.center),
        content:
            message != null ? Text(message, textAlign: TextAlign.center) : null,
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('حسناً'),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // INPUT DIALOGS
  // ═══════════════════════════════════════════════════════════════════════

  /// Shows a text input dialog. Returns `null` if cancelled.
  static Future<String?> textInput(
    BuildContext context, {
    required String title,
    String? hint,
    String? initialValue,
    String confirmLabel = 'حفظ',
    String cancelLabel = 'إلغاء',
    int maxLines = 1,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
  }) async {
    final controller = TextEditingController(text: initialValue);
    final formKey = GlobalKey<FormState>();

    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title, textAlign: TextAlign.center),
        content: Form(
          key: formKey,
          child: TextFormField(
            controller: controller,
            maxLines: maxLines,
            keyboardType: keyboardType,
            decoration: InputDecoration(
              hintText: hint,
              border: const OutlineInputBorder(),
            ),
            validator: validator,
            autofocus: true,
          ),
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(cancelLabel),
          ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState?.validate() ?? true) {
                Navigator.of(ctx).pop(controller.text);
              }
            },
            child: Text(confirmLabel),
          ),
        ],
      ),
    );

    controller.dispose();
    return result;
  }

  /// Shows a numeric input dialog. Returns `null` if cancelled.
  static Future<double?> numericInput(
    BuildContext context, {
    required String title,
    String? hint,
    double? initialValue,
    String confirmLabel = 'حفظ',
  }) async {
    final text = await textInput(
      context,
      title: title,
      hint: hint ?? '0.00',
      initialValue: initialValue?.toString(),
      confirmLabel: confirmLabel,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      validator: (v) {
        if (v == null || v.isEmpty) return 'مطلوب';
        if (double.tryParse(v) == null) return 'رقم غير صالح';
        return null;
      },
    );
    return text != null ? double.tryParse(text) : null;
  }

  // ═══════════════════════════════════════════════════════════════════════
  // SELECTION DIALOGS
  // ═══════════════════════════════════════════════════════════════════════

  /// Shows a single-selection dialog from a list of options.
  static Future<T?> select<T>(
    BuildContext context, {
    required String title,
    required List<T> items,
    required String Function(T) labelBuilder,
    T? selectedItem,
    IconData? Function(T)? iconBuilder,
  }) {
    return showDialog<T>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(title, textAlign: TextAlign.center),
        children: items.map((item) {
          final isSelected = item == selectedItem;
          return SimpleDialogOption(
            onPressed: () => Navigator.of(ctx).pop(item),
            child: Row(
              children: [
                if (iconBuilder != null) ...[
                  Icon(iconBuilder(item), size: 20),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  child: Text(
                    labelBuilder(item),
                    style: isSelected
                        ? TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Theme.of(ctx).colorScheme.primary,
                          )
                        : null,
                  ),
                ),
                if (isSelected)
                  Icon(Icons.check,
                      color: Theme.of(ctx).colorScheme.primary, size: 20),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // LOADING / PROGRESS
  // ═══════════════════════════════════════════════════════════════════════

  /// Shows a loading overlay dialog. Returns a dismiss function.
  static void Function() loading(
    BuildContext context, {
    String message = 'جاري المعالجة...',
  }) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => PopScope(
        canPop: false,
        child: AlertDialog(
          content: Row(
            children: [
              const CircularProgressIndicator(),
              const SizedBox(width: 20),
              Expanded(child: Text(message)),
            ],
          ),
        ),
      ),
    );

    return () {
      if (context.mounted) {
        Navigator.of(context, rootNavigator: true).pop();
      }
    };
  }

  // ═══════════════════════════════════════════════════════════════════════
  // SNACKBAR HELPERS
  // ═══════════════════════════════════════════════════════════════════════

  /// Shows a success snackbar.
  static void showSuccessSnackBar(
    BuildContext context,
    String message, {
    Duration duration = const Duration(seconds: 3),
  }) {
    AppToast.show(context, message);
  }

  /// Shows an error snackbar.
  static void showErrorSnackBar(
    BuildContext context,
    String message, {
    Duration duration = const Duration(seconds: 4),
  }) {
    AppToast.show(context, message, type: ToastType.info);
  }

  /// Shows an info snackbar.
  static void showInfoSnackBar(
    BuildContext context,
    String message, {
    Duration duration = const Duration(seconds: 3),
  }) {
    AppToast.show(context, message, type: ToastType.info);
  }

  // ═══════════════════════════════════════════════════════════════════════
  // LEGAL COMPLIANCE WARNINGS — تنبيهات الامتثال القانوني
  // ═══════════════════════════════════════════════════════════════════════

  /// Shows a red legal warning that blocks the operation.
  /// The user must acknowledge the warning before proceeding.
  /// Returns `true` if user acknowledges, `false` if cancelled.
  static Future<bool> legalWarning(
    BuildContext context, {
    required String title,
    required String message,
    required String impact,
    String confirmLabel = 'أفهم المخاطر',
    String cancelLabel = 'تراجع',
  }) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.gavel, color: Colors.red, size: 48),
        title: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.warning_amber, color: Colors.red, size: 20),
            const SizedBox(width: 8),
            Text(title, style: const TextStyle(color: Colors.red)),
            const SizedBox(width: 8),
            const Icon(Icons.warning_amber, color: Colors.red, size: 20),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.balance, color: Colors.red.shade700, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '⚖️ التأثير القانوني: $impact',
                      style: TextStyle(
                        color: Colors.red.shade800,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            style: FilledButton.styleFrom(
              backgroundColor: Colors.grey.shade600,
            ),
            child: Text(cancelLabel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  /// Shows a regulatory confirmation dialog that requires typing 'أوافق'
  /// to proceed. Used for high-risk operations like period reopening or
  /// tax rate changes.
  /// Returns `true` if confirmed with correct keyword, `false` otherwise.
  static Future<bool> regulatoryConfirm(
    BuildContext context, {
    required String title,
    required String message,
    required String impact,
    String keyword = 'أوافق',
  }) async {
    final controller = TextEditingController();
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              icon: const Icon(Icons.policy, color: Colors.deepOrange, size: 48),
              title: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.gavel, color: Colors.deepOrange, size: 20),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(title,
                        style: const TextStyle(color: Colors.deepOrange)),
                  ),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(message, textAlign: TextAlign.center),
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.orange.shade200),
                    ),
                    child: Text(
                      '⚖️ $impact',
                      style: TextStyle(
                        color: Colors.orange.shade900,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: controller,
                    textAlign: TextAlign.center,
                    decoration: InputDecoration(
                      border: const OutlineInputBorder(),
                      hintText: 'اكتب "$keyword" للمتابعة',
                      prefixIcon: const Icon(Icons.edit_note),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ],
              ),
              actionsAlignment: MainAxisAlignment.center,
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  child: const Text('تراجع'),
                ),
                FilledButton(
                  onPressed: controller.text.trim() == keyword
                      ? () => Navigator.of(ctx).pop(true)
                      : null,
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.deepOrange,
                  ),
                  child: const Text('تأكيد'),
                ),
              ],
            );
          },
        );
      },
    );
    controller.dispose();
    return result ?? false;
  }

  /// Shows an amber compliance alert with details about the operation's
  /// compliance implications. Non-blocking but informative.
  static Future<void> complianceAlert(
    BuildContext context, {
    required String title,
    required String message,
    required List<String> implications,
  }) {
    return showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Icon(Icons.admin_panel_settings,
            color: Colors.amber.shade700, size: 48),
        title: Text(title,
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.amber.shade800)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(message, textAlign: TextAlign.center),
            if (implications.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.amber.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.amber.shade200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: implications
                      .map((i) => Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(Icons.arrow_left,
                                    color: Colors.amber.shade800, size: 16),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(i,
                                      style: TextStyle(
                                        color: Colors.amber.shade900,
                                        fontSize: 13,
                                      )),
                                ),
                              ],
                            ),
                          ))
                      .toList(),
                ),
              ),
            ],
          ],
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('فهمت'),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // LEGAL WARNING CONSTANTS — ثوابت رسائل التنبيهات القانونية
  // ═══════════════════════════════════════════════════════════════════════

  /// Pre-defined legal warning messages for common operations
  static const legalMessages = {
    'vat_rate_change': {
      'title': 'تنبيه قانوني — تغيير نسبة الضريبة',
      'message': 'تغيير نسبة ضريبة القيمة المضافة يؤثر على جميع الفواتير المستقبلية',
      'impact': 'مخالفة ضريبية محتملة — قانون 67/2016',
    },
    'period_reopen': {
      'title': 'تنبيه رقابي — إعادة فتح فترة محاسبية',
      'message': 'إعادة فتح فترة مغلقة يعني تعديل قوائم مالية معتمدة',
      'impact': 'يتطلب توثيق السبب — مسؤولية قانونية ومهنية',
    },
    'safe_manual_adjust': {
      'title': 'تنبيه مالي — تعديل رصيد خزنة',
      'message': 'تعديل رصيد الخزنة يدوياً بدون مستند داعم',
      'impact': 'مسؤولية مالية — يُسجل في سجل التدقيق',
    },
    'large_manual_je': {
      'title': 'تنبيه رقابي — قيد يدوي كبير',
      'message': 'القيد اليدوي بمبلغ كبير يخضع لنظام الاعتماد',
      'impact': 'يتطلب موافقة المحاسب المسؤول (Maker-Checker)',
    },
    'locked_invoice_modify': {
      'title': 'تنبيه — تعديل فاتورة مقفلة',
      'message': 'الفاتورة مُقفلة بعد إقفال الوردية — تعديلها يؤثر على التقارير المالية',
      'impact': 'تعديل سجلات مالية معتمدة — مخالفة لمعايير المراجعة',
    },
    'credit_note': {
      'title': 'تنبيه ضريبي — إشعار ائتمان',
      'message': 'إشعار الائتمان يُرسل تلقائياً لهيئة الضرائب',
      'impact': 'ربط بالفاتورة الأصلية إلزامي — لا يتجاوز مبلغها',
    },
    'fiscal_year_close': {
      'title': 'تنبيه — إقفال سنة مالية',
      'message': 'إقفال السنة المالية عملية نهائية يجب التأكد من اكتمال جميع الفترات الشهرية',
      'impact': 'لا يمكن التراجع إلا بإعادة فتح رسمية مع سبب موثق',
    },
  };
}
