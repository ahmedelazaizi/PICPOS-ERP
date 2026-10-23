import 'package:picpos_erp/core/i18n/tr.dart';
import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../../core/theme/table_status_palette.dart';

/// اسمُ الحالة ولونُها وأيقونتُها — مصدرٌ واحد لِما كان منسوخاً ثلاثَ مرّات.
/// الحالةُ تُعرَض دائماً **لوناً + أيقونةً + نصّاً** لا لوناً وحدَه.
class TableStatusInfo {
  const TableStatusInfo(this.label, this.color, this.icon);
  final String label;
  final Color color;
  final IconData icon;
}

/// اسمُ الحالة وأيقونتُها (بلا لون) — الألوانُ في [TableStatusPalette].
///
/// وفيها خمسُ حالاتٍ **لا يكتبها أحد** (`seated`/`ordered`/`eating`/`billing`/
/// `cleaning`) — بقايا مخطّطٍ قديمٍ موثَّقةٌ في رأس `table_status.dart`.
/// تبقى كما هي: حذفُها يغيّر ما تعرضه البطاقةُ لصفٍّ قديمٍ في قاعدةِ مالكٍ
/// قائمة، وذلك تغييرُ سلوكٍ لا توحيدُ مصدر.
Map<String, (String, IconData)> get _labelsAndIcons => {
  'available': (tr('متاحة'), PhosphorIconsBold.checkCircle),
  'reserved': (tr('محجوزة'), PhosphorIconsBold.calendarCheck),
  'occupied': (tr('مشغولة'), PhosphorIconsBold.users),
  'paid': (tr('مدفوعة'), PhosphorIconsBold.currencyCircleDollar),
  'out_of_service': (tr('خارج الخدمة'), PhosphorIconsBold.prohibit),
  'seated': (tr('مشغولة'), PhosphorIconsBold.users),
  'ordered': (tr('مشغولة'), PhosphorIconsBold.users),
  'eating': (tr('مشغولة'), PhosphorIconsBold.users),
  'billing': (tr('مشغولة'), PhosphorIconsBold.users),
  'cleaning': (tr('تنظيف'), PhosphorIconsBold.broom),
};

/// **الرجوعُ إلى `available` لا إلى الحالة نفسِها** — هكذا كانت البطاقةُ تفعل.
/// تغييرُه يجعل حالةً مجهولةً تُعرَض بنصِّها الإنجليزيِّ على شاشة الكاشير.
TableStatusInfo tableStatusInfoFor(Brightness brightness, String status) {
  final map = _labelsAndIcons;
  final (label, icon) = map[status] ?? map['available']!;
  return TableStatusInfo(
    label,
    TableStatusPalette.colorFor(brightness, status),
    icon,
  );
}

/// نسخةُ الثيم الحاليّ — **المطلوبةُ في أيّ ودجت**.
TableStatusInfo tableStatusInfoOf(BuildContext context, String status) =>
    tableStatusInfoFor(Theme.of(context).brightness, status);

/// خريطةٌ بلا سياق (لونُها للوضع الفاتح) — يستعملها مرشِّحُ الشاشة القديمة.
Map<String, TableStatusInfo> get tableStatusInfoMap => {
  for (final status in _labelsAndIcons.keys)
    status: tableStatusInfoFor(Brightness.light, status),
};

/// نسخةٌ بلا سياق للوضع الفاتح — للقديم؛ الودجتاتُ تستعمل [tableStatusInfoOf].
TableStatusInfo tableStatusInfo(String status) =>
    tableStatusInfoFor(Brightness.light, status);

String tableStatusLabel(String status) => tableStatusInfo(status).label;
Color tableStatusColor(String status) => tableStatusInfo(status).color;
