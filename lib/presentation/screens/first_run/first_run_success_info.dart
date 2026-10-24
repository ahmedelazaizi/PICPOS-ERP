// محتوى صفحة النجاح الخاص بكلّ مسار: «الخطوة التالية» وبطاقةُ معلومات الاتصال
// (‏المقرّ: عناوين هذا الخادم لإدخالها في أجهزة الفروع · الفرع: السيرفر والجهاز
// والفرع والحساب). كلُّها حقائقُ من المسودّة لا قيمٌ وهميّة.
import 'package:flutter/material.dart';

import '../../../core/i18n/tr.dart';
import '../../../domain/models/first_run/first_run_draft.dart';
import '../../../domain/models/first_run/first_run_path.dart';
import '../../picpos_shell/picpos_surface.dart';

List<(IconData, String)> successNextSteps(FirstRunPath path) => switch (path) {
      FirstRunPath.standalone => [
          (Icons.login, tr('ادخل بحساب المسؤول (admin) وكلمة المرور التي اخترتها.')),
          (Icons.inventory_2_outlined, tr('أضف أصنافك وأسعارها من شاشة الأصناف.')),
          (Icons.group_add_outlined, tr('أنشئ مستخدميك وصلاحياتهم من الإعدادات.')),
          (Icons.print_outlined, tr('جهّز الطابعة من الإعدادات › الطابعات.')),
          (Icons.verified_outlined, tr('فعّل النسخة من الإعدادات › حول.')),
        ],
      FirstRunPath.hq => [
          (Icons.restart_alt, tr('أعد تشغيل التطبيق ليتصل بقاعدة PostgreSQL.')),
          (Icons.login, tr('ادخل بحساب المسؤول (admin) وكلمة المرور التي اخترتها.')),
          (Icons.qr_code_2_outlined, tr('أصدر رموز إقران أجهزة كل فرع من الإعدادات › الشبكة.')),
          (Icons.store_outlined, tr('على جهاز كل فرع اختر «فرع تابع للسيرفر الرئيسي» وأدخل عنوان الخادم والرمز.')),
          (Icons.group_outlined, tr('سلّم كل موظف اسم دخوله وكلمته الأولية؛ يغيّرها عند أول دخول.')),
          (Icons.verified_outlined, tr('فعّل النسخة من الإعدادات › حول.')),
        ],
      FirstRunPath.branch => [
          (Icons.login, tr('ادخل بحسابك المعتمد من الإدارة الرئيسية.')),
          (Icons.sync, tr('تتم المزامنة تلقائيًا؛ ما يُحفظ دون اتصال يُرسل عند عودته.')),
          (Icons.print_outlined, tr('جهّز الطابعة من الإعدادات › الطابعات.')),
          (Icons.verified_outlined, tr('فعّل النسخة من الإعدادات › حول.')),
        ],
      FirstRunPath.mirror => [
          (Icons.login, tr('ادخل بحساب مدير السيرفر الرئيسي.')),
          (Icons.verified_outlined, tr('فعّل النسخة من الإعدادات › حول.')),
        ],
    };

/// بطاقةُ معلومات الاتصال (‏أو `SizedBox.shrink()` للمستقل والمرآة).
class SuccessConnectionCard extends StatelessWidget {
  const SuccessConnectionCard({super.key, required this.draft, required this.addresses});

  final FirstRunDraft draft;

  /// عناوينُ IPv4 لهذا الجهاز (‏المقرّ فقط).
  final List<String> addresses;

  @override
  Widget build(BuildContext context) {
    final d = draft;
    final rows = <(String, String)>[
      if (d.path == FirstRunPath.hq) ...[
        (
          tr('عنوان هذا السيرفر للأجهزة'),
          addresses.isEmpty
              ? tr('تعذّر اكتشاف عنوان الشبكة؛ استعمل عنوان الجهاز.')
              : addresses.map((a) => '$a:8080').join('  ·  '),
        ),
        (tr('قاعدة البيانات'), '${d.pgHost.trim()}:${d.pgPort.trim()} / ${d.pgDatabase.trim()}'),
        (tr('الفروع'), '${d.branchName.trim()}${d.branches.isEmpty ? '' : ' + ${d.branches.length}'}'),
      ],
      if (d.path == FirstRunPath.branch) ...[
        (tr('متصل بالرئيسي'), '${d.endpoint.trim()}:${d.port.trim()}'),
        (tr('اسم الجهاز'), d.deviceName.trim()),
        (tr('الفرع'), '${d.selectedBranchName} (${d.selectedBranchCode})'),
        (tr('الحساب المعتمد'), d.accountUsername.trim()),
      ],
    ];
    if (rows.isEmpty) return const SizedBox.shrink();
    return Container(
      key: const Key('first_run_success_connection'),
      width: double.infinity,
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.picposCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.picposHairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            d.path == FirstRunPath.hq
                ? tr('معلومات اتصال الفروع')
                : tr('معلومات الاتصال'),
            style: TextStyle(fontWeight: FontWeight.w800, color: context.picposText),
          ),
          const SizedBox(height: 8),
          for (final (k, v) in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 190,
                    child: Text(k, style: TextStyle(color: context.picposMuted)),
                  ),
                  Expanded(
                    child: SelectableText(v, style: TextStyle(color: context.picposText)),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
