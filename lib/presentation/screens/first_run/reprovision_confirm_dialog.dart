// A1: the confirmation shared by every entry of "re-provision this device"
// (settings tile, self-check screen, Fatal screen, developer tools).
import 'package:flutter/material.dart';

import '../../../core/i18n/tr.dart';

/// `true` when the owner confirmed. Business data is NOT deleted.
Future<bool> confirmReprovision(BuildContext context) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      key: const Key('reprovision_confirm_dialog'),
      title: Text(tr('إعادة توفير هذا الجهاز')),
      content: Text(tr(
          'سيُنسى نمط التشغيل وإقران هذا الجهاز، وتعود شاشة الإعداد الأول بعد إعادة تشغيل البرنامج. بيانات العمل لا تُحذف.')),
      actions: [
        TextButton(
          key: const Key('reprovision_cancel'),
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(tr('إلغاء')),
        ),
        FilledButton(
          key: const Key('reprovision_confirm'),
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(tr('إعادة التوفير')),
        ),
      ],
    ),
  );
  return ok == true;
}
