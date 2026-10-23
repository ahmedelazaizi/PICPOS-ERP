import 'package:picpos_erp/core/i18n/tr.dart';
// زرار «تصدير Excel» في شاشات التقارير — محروس بـ`reports_export` (دفعة ١٢).
//
// ── ليه ملف مشترك ─────────────────────────────────────────────────────────
// نفس الزرار مكرّر حرفياً في ١٣ شاشة تقرير (`IconButton` بأيقونة `fileXls`
// و`onPressed: _exportToExcel`)، والفرز وصفه بإنه «فجوة مفهوم واحد متكررة
// في كل شاشة تقرير». تجميعه في دالة واحدة معناه إن الحارس مصدره واحد —
// شاشة تقرير جديدة بتاخده بسطر واحد بدل ما تنساه.
//
// الشاشات دي **مشتركة بين البراندين**: `reports_picpos_screen.dart` بينادي
// نفس كلاسات الشاشات (`SalesReportScreen` وإخواتها)، فالحارس هنا بيغطّي
// الاتنين. المفروك هو كتالوج التقارير بس، مش الشاشات نفسها.
//
// ── ليه تجاوز مدير ────────────────────────────────────────────────────────
// التصدير فعل روتيني بيتطلب وسط الشغل (مراجعة، مشاركة مع محاسب خارجي)،
// والمنع النهائي بيوقف شغل شرعي. `onGranted` صريح (درس f8d3fa9).
import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/permissions/permission_codes.dart';
import '../../widgets/permission_guard.dart';

/// زرار تصدير التقرير لـExcel.
///
/// [onExport] بيبقى `null` في الشاشات اللي بتعطّل الزرار لما مفيش بيانات —
/// الحارس بيفضل مركّب زي ما هو عشان الشكل ما يختلفش بين الحالتين.
///
/// [icon] و[tooltip] ليهم قيم افتراضية عشان أغلب المواقع متطابقة؛ بيتغيّروا
/// بس في أزرار «طباعة» اللي بتنادي التصدير نفسه (شوف التوثيق تحت).
Widget buildReportExportAction({
  required VoidCallback? onExport,
  IconData icon = PhosphorIconsBold.fileXls,
  String tooltip = 'تصدير Excel',
}) {
  return PermissionGuard(
    permission: PermissionCodes.reportsExport,
    allowManagerOverride: true,
    actionName: tr('تصدير التقرير إلى Excel'),
    onGranted: onExport,
    child: IconButton(
      icon: Icon(icon),
      tooltip: tooltip,
      onPressed: onExport,
    ),
  );
}

/// زرار «طباعة» اللي بينادي التصدير نفسه.
///
/// في ٦ شاشات الزرار المكتوب عليه «طباعة» بينادي `_exportToExcel` مباشرة أو
/// عبر `_printReport` اللي جسمها `await _exportToExcel()` — يعني نفس العملية
/// بعنوان تاني. تبويبه بـ`reports_export` بيوصف اللي بيحصل فعلاً.
///
/// أزرار الطباعة الحقيقية (اللي بتولّد PDF) **ما اتبوّبتش**: مفيش كود
/// `reports_print` في الكتالوج، واستعارة `reports_export` ليها كانت هتخلّي
/// المفتاح يقفل حاجة اسمها حاجة تانية (درس هـ).
Widget buildReportPrintAsExportAction({required VoidCallback? onExport}) {
  return buildReportExportAction(
    onExport: onExport,
    icon: PhosphorIconsBold.printer,
    tooltip: tr('طباعة'),
  );
}
