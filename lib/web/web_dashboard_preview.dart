// المرحلة 2 (ويب): إثبات أن مسار شاشات الحسابات/التقارير يُترجم للويب مع
// طبقة البيانات (providers + database.dart) دون POS ولا حزم الأجهزة.
// م3-6: تُعرض الآن ببيانات حقيقية عبر drift remote (انظر web_providers.dart).
import 'package:flutter/material.dart';

import '../presentation/dashboard_picpos/screens/dashboard_picpos_screen.dart';

/// لوحة التحكم (قراءة فقط) كعنصر قابل للتضمين في صفحة الويب.
class WebDashboardPreview extends StatelessWidget {
  const WebDashboardPreview({super.key});

  @override
  Widget build(BuildContext context) => const DashboardPicposScreen();
}

/// يفتح لوحة التحكم (قراءة فقط) من مسار الويب.
void openWebDashboardPreview(BuildContext context) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (_) => const WebDashboardPreview()),
  );
}
