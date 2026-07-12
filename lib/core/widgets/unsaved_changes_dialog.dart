import 'package:flutter/material.dart';

/// A reusable dialog to prompt the user before navigating away from a screen
/// with unsaved changes. Returns `true` if the user wants to leave (discard changes),
/// and `false` if the user wants to stay.
class UnsavedChangesDialog extends StatelessWidget {
  final String title;
  final String content;
  final String discardButtonText;
  final String stayButtonText;

  const UnsavedChangesDialog({
    super.key,
    this.title = 'تنبيه',
    this.content = 'يوجد تغييرات غير محفوظة. هل أنت متأكد من مغادرة هذه الصفحة؟ سيتم فقدان التغييرات.',
    this.discardButtonText = 'نعم، مغادرة',
    this.stayButtonText = 'لا، البقاء',
  });

  static Future<bool> show(
    BuildContext context, {
    String? title,
    String? content,
    String? discardButtonText,
    String? stayButtonText,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: UnsavedChangesDialog(
          title: title ?? 'تنبيه',
          content: content ?? 'يوجد تغييرات غير محفوظة. هل أنت متأكد من مغادرة هذه الصفحة؟ سيتم فقدان التغييرات.',
          discardButtonText: discardButtonText ?? 'نعم، مغادرة',
          stayButtonText: stayButtonText ?? 'لا، البقاء',
        ),
      ),
    );
    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 28),
          const SizedBox(width: 8),
          Text(title),
        ],
      ),
      content: Text(
        content,
        style: const TextStyle(height: 1.5),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false), // Stay
          child: Text(stayButtonText),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(context, true), // Leave
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.red,
            foregroundColor: Colors.white,
          ),
          child: Text(discardButtonText),
        ),
      ],
    );
  }
}
