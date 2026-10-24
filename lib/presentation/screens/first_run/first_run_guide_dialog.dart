// «دليل الإعداد» — نسخةٌ مختصرةٌ للمستخدم (لا نصوص المبرمج).
import 'package:flutter/material.dart';

import '../../../core/i18n/tr.dart';

Future<void> showFirstRunGuide(BuildContext context) {
  final items = <(String, String)>[
    (
      tr('طريقة التشغيل'),
      tr('مستقلة: كل البيانات على هذا الجهاز. رئيسي: يستقبل الفروع. فرع: يتبع رئيسيًا ويعمل أونلاين وأوفلاين.')
    ),
    (
      tr('العملة'),
      tr('تُختار مرة واحدة ولا تتغير بعد أول فاتورة. الدينار الأردني والجنيه المصري فقط.')
    ),
    (
      tr('المسؤول'),
      tr('اسم الدخول admin. اختر كلمة مرور من 8 أحرف على الأقل واحتفظ بها.')
    ),
    (
      tr('إن أُغلق التطبيق'),
      tr('يُحفظ تقدّمك (بدون كلمات المرور) وتُكمل من حيث توقفت.')
    ),
    (
      tr('التفعيل'),
      tr('يتم من الإعدادات › حول بعد الإعداد، وليس هنا.')
    ),
  ];
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(tr('دليل الإعداد')),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final (h, b) in items) ...[
                Text(h, style: const TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(height: 2),
                Text(b),
                const SizedBox(height: 12),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: Text(tr('إغلاق')),
        ),
      ],
    ),
  );
}
