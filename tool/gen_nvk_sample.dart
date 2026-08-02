// يولّد ملف عيّنة لموازين NVK TMA / TEM لاختبار الاستيراد في `mscale`.
//
//   dart run tool/gen_nvk_sample.dart [مسار الإخراج]
//
// الغرض: إثبات مفهوم لبلاغ العميل 2026-07-30. تفكيك ملفَّي تصدير حقيقيين
// أعطى بنية ورقة `Merchandise` كاملة؛ هذا السكربت يعيد إنتاجها من كودنا.
// الخطوة التالية يدوية بالضرورة: افتح mscale ← Import ← اختر هذا الملف.

import 'dart:io';

import 'package:ural_erp/services/scale_xls_writer.dart';

void main(List<String> args) {
  final path = args.isNotEmpty ? args.first : 'nvk_sample.xls';
  final bytes = buildMerchandiseSampleXls();
  File(path).writeAsBytesSync(bytes);

  stdout.writeln('تم إنشاء: $path (${bytes.length} بايت)');
  stdout.writeln('الورقة: $kMerchandiseSheetName');
  stdout.writeln('الأعمدة: ${kMerchandiseHeaders.join(" · ")}');
  stdout.writeln('');
  stdout.writeln('الخطوة التالية: mscale ← Import ← اختر الملف ← Download');
}
