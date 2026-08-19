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
const Map<String, TableStatusInfo> tableStatusInfoMap = {
  'available': TableStatusInfo('متاحة', Color(0xFF10B981), PhosphorIconsBold.checkCircle),
  'reserved': TableStatusInfo('محجوزة', Color(0xFFF59E0B), PhosphorIconsBold.calendarCheck),
  'occupied': TableStatusInfo('مشغولة', Color(0xFF3B82F6), PhosphorIconsBold.users),
  'paid': TableStatusInfo('مدفوعة', Color(0xFFF97316), PhosphorIconsBold.currencyCircleDollar),
  'out_of_service': TableStatusInfo('خارج الخدمة', Color(0xFFCBD5E1), PhosphorIconsBold.prohibit),
  'seated': TableStatusInfo('مشغولة', Color(0xFF3B82F6), PhosphorIconsBold.users),
  'ordered': TableStatusInfo('مشغولة', Color(0xFF3B82F6), PhosphorIconsBold.users),
  'eating': TableStatusInfo('مشغولة', Color(0xFF3B82F6), PhosphorIconsBold.users),
  'billing': TableStatusInfo('مشغولة', Color(0xFF3B82F6), PhosphorIconsBold.users),
  'cleaning': TableStatusInfo('تنظيف', Color(0xFF6366F1), PhosphorIconsBold.broom),
};

/// **الرجوعُ إلى `available` لا إلى الحالة نفسِها** — هكذا كانت البطاقةُ تفعل
/// (`table_card.dart:40`: `?? _statusMap['available']!`). تغييرُه يجعل حالةً
/// مجهولةً تُعرَض بنصِّها الإنجليزيِّ على شاشة الكاشير.
TableStatusInfo tableStatusInfo(String status) =>
    tableStatusInfoMap[status] ?? tableStatusInfoMap['available']!;

String tableStatusLabel(String status) => tableStatusInfo(status).label;
Color tableStatusColor(String status) => tableStatusInfo(status).color;
