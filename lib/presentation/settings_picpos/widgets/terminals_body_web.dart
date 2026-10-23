// بديل الويب لـ`screens/pos_terminals_screen.dart` → `PosTerminalsBody` (م3-9).
//
// تبويب «نقاط البيع» في شاشة الفروع يعرض إدارة أجهزة الكاشير المقترنة
// (تسجيل/تعطيل/سياسة نقص المخزون لكل جهاز). هذه إدارةُ أجهزةِ POS، ومسارُها
// (`/api/pos-terminals`) خارج مسارات الكتابة المفتوحة لرمز الويب عمداً، والملفّ
// الأصلي محظورٌ في مسار الويب (بادئة `pos`). فيُعرَض شرحٌ بدل الجسم.
//
// يُختار بالاستيراد الشرطي (`dart.library.js_interop`)؛ الديسكتوب (io) يبقى
// على الجسم الأصلي دون تغيير.
import 'package:flutter/material.dart';
import 'package:picpos_erp/core/i18n/tr.dart';

class PosTerminalsBody extends StatelessWidget {
  const PosTerminalsBody({super.key, this.searchQuery = ''});

  final String searchQuery;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.point_of_sale_outlined,
                size: 48, color: theme.colorScheme.outline),
            const SizedBox(height: 12),
            Text(tr('إدارة نقاط البيع متاحة من تطبيق سطح المكتب'),
                style: theme.textTheme.titleMedium),
          ],
        ),
      ),
    );
  }
}
