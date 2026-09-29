import 'package:ural_erp/core/i18n/tr.dart';
import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

/// اسمُ الحالة ولونُها وأيقونتُها — مصدرٌ واحدٌ لِما كان منسوخاً ثلاثَ مرّات.
class TableStatusInfo {
  const TableStatusInfo(this.label, this.color, this.icon);
  final String label;
  final Color color;
  final IconData icon;
}

/// الخريطةُ منقولةٌ من `table_card.dart` بلا تغييرِ قيمةٍ واحدة.
///
/// وفيها خمسُ حالاتٍ **لا يكتبها أحد** (`seated`/`ordered`/`eating`/`billing`/
/// `cleaning`) — بقايا مخطّطٍ قديمٍ موثَّقةٌ في رأس `table_status.dart`.
/// تبقى كما هي: حذفُها يغيّر ما تعرضه البطاقةُ لصفٍّ قديمٍ في قاعدةِ مالكٍ
/// قائمة، وذلك تغييرُ سلوكٍ لا توحيدُ مصدر.
Map<String, TableStatusInfo> get tableStatusInfoMap => {
  'available': TableStatusInfo(tr('متاحة'), const Color(0xFF10B981), PhosphorIconsBold.checkCircle),
  'reserved': TableStatusInfo(tr('محجوزة'), const Color(0xFFF59E0B), PhosphorIconsBold.calendarCheck),
  'occupied': TableStatusInfo(tr('مشغولة'), const Color(0xFF3B82F6), PhosphorIconsBold.users),
  'paid': TableStatusInfo(tr('مدفوعة'), const Color(0xFFF97316), PhosphorIconsBold.currencyCircleDollar),
  'out_of_service': TableStatusInfo(tr('خارج الخدمة'), const Color(0xFFCBD5E1), PhosphorIconsBold.prohibit),
  'seated': TableStatusInfo(tr('مشغولة'), const Color(0xFF3B82F6), PhosphorIconsBold.users),
  'ordered': TableStatusInfo(tr('مشغولة'), const Color(0xFF3B82F6), PhosphorIconsBold.users),
  'eating': TableStatusInfo(tr('مشغولة'), const Color(0xFF3B82F6), PhosphorIconsBold.users),
  'billing': TableStatusInfo(tr('مشغولة'), const Color(0xFF3B82F6), PhosphorIconsBold.users),
  'cleaning': TableStatusInfo(tr('تنظيف'), const Color(0xFF6366F1), PhosphorIconsBold.broom),
};

/// **الرجوعُ إلى `available` لا إلى الحالة نفسِها** — هكذا كانت البطاقةُ تفعل
/// (`table_card.dart:40`: `?? _statusMap['available']!`). تغييرُه يجعل حالةً
/// مجهولةً تُعرَض بنصِّها الإنجليزيِّ على شاشة الكاشير.
TableStatusInfo tableStatusInfo(String status) =>
    tableStatusInfoMap[status] ?? tableStatusInfoMap['available']!;

String tableStatusLabel(String status) => tableStatusInfo(status).label;
Color tableStatusColor(String status) => tableStatusInfo(status).color;
