// المرحلة 2 (ويب): إثبات أن مسار شاشات الحسابات/التقارير يُترجم للويب مع
// طبقة البيانات (providers + database.dart) دون POS ولا حزم الأجهزة.
// الاتصال الفعلي بالبيانات (drift/remote) يُوصَّل في مرحلة لاحقة.
import 'package:flutter/material.dart';

import '../presentation/dashboard_picpos/screens/dashboard_picpos_screen.dart';

/// يفتح لوحة التحكم (قراءة فقط) من مسار الويب.
void openWebDashboardPreview(BuildContext context) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (_) => const DashboardPicposScreen()),
  );
}