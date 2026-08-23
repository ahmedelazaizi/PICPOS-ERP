// عرضُ حالةِ الحجز — ولا حالةَ تُرسم فارغة.
//
// ═══ العطبُ الذي يحرسه هذا الملفّ ═══
//
// التصميمُ يسمّي **ستّ** حالاتٍ بينما قيدُ `Bookings.status` يقبل **سبعاً**:
// `completed` موجودةٌ في القاعدة ويحتاجها تحويلُ الحجز إلى فاتورة، ولا اسمَ
// لها في التصميم. وحالةٌ بلا تسميةٍ تُرسم فراغاً — صفٌّ لا يقول عن نفسه شيئاً
// ولا يُلاحَظ في مراجعةٍ بصريّة.
//
// فالحارسُ يقرأ القيدَ **من ملفّ الجدول نفسِه** ويقارنه بالخريطة: أيُّ حالةٍ
// تُضاف للقاعدة ولا تُسمَّى تُسقط الاختبار. ولو قُورنت الخريطةُ بقائمةٍ
// مكتوبةٍ هنا لَمرّت الإضافةُ صامتة — القائمتان تُكتبان معاً وتُنسيان معاً.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/domain/models/picpos_booking_view.dart';

void main() {
  test('كلُّ حالةٍ يقبلها القيدُ لها تسميةٌ معروضة', () {
    final source =
        File('lib/data/database/tables/booking_tables.dart').readAsStringSync();

    // القيدُ مكتوبٌ على سطرين في المصدر، فيُلتقَط النصُّ بين القوسين.
    final match = RegExp(r"CHECK \(status IN \(([^)]*)\)\)", dotAll: true)
        .firstMatch(source);
    expect(match, isNotNull,
        reason: 'تعذّر العثورُ على قيد الحالة — تغيّر شكلُه فيجب تحديثُ الحارس');

    final codesInDb = RegExp("'([a-z_]+)'")
        .allMatches(match!.group(1)!)
        .map((m) => m.group(1)!)
        .toSet();

    expect(codesInDb, isNotEmpty);
    expect(codesInDb, bookingStatusCodes.toSet(),
        reason: 'قائمةُ المفردات في `domain` انحرفت عن القيد في القاعدة');

    for (final code in codesInDb) {
      final view = bookingStatusView(code);
      expect(view.label, isNotEmpty,
          reason: '«$code» يقبلها القيدُ ولا تسميةَ لها — تُرسم فارغة');
      expect(view.label, isNot(code),
          reason: '«$code» تُعرَض بكودها لا باسمٍ عربيّ');
      expect(view.tone, isNot(BookingStatusTone.neutral),
          reason: '«$code» سقطت على النغمة الافتراضيّة — أي أنها غيرُ معرّفة');
    }
  });

  test('حالةٌ غيرُ معروفةٍ تُسمّى بنصّها ولا تُبتلَع', () {
    final v = bookingStatusView('teleported');
    expect(v.label, 'teleported');
    expect(v.tone, BookingStatusTone.neutral);
  });

  group('الفعلُ التالي', () {
    test('السلسلةُ تمشي حتى الاكتمال', () {
      expect(bookingNextAction(status: 'pending', isInvoiced: false)!.next,
          'confirmed');
      expect(bookingNextAction(status: 'confirmed', isInvoiced: false)!.next,
          'seated');
      expect(bookingNextAction(status: 'seated', isInvoiced: false)!.next,
          'in_service');
      expect(bookingNextAction(status: 'in_service', isInvoiced: false)!.next,
          'completed');
    });

    test('كلُّ حالةٍ تالِيةٍ يقبلها القيد', () {
      for (final code in bookingStatusCodes) {
        final action = bookingNextAction(status: code, isInvoiced: false);
        if (action == null || action.next.isEmpty) continue;
        expect(bookingStatusCodes, contains(action.next),
            reason: 'الفعلُ من «$code» يكتب «${action.next}» — والقيدُ يرفضها '
                'فيرمي الحفظُ في وجه المستخدم');
      }
    });

    test('المكتملُ يُفوتَر مرّةً — ولا فعلَ بعد التفويتر', () {
      final before = bookingNextAction(status: 'completed', isInvoiced: false);
      expect(before!.label, 'تفويتر');
      expect(before.next, isEmpty,
          reason: 'التفويترُ ليس تبديلَ حالة — و`next` فارغةٌ تميّزه');
      expect(bookingNextAction(status: 'completed', isInvoiced: true), isNull);
    });

    test('الملغى والمتخلّفُ بلا فعل', () {
      expect(bookingNextAction(status: 'cancelled', isInvoiced: false), isNull);
      expect(bookingNextAction(status: 'no_show', isInvoiced: false), isNull);
    });
  });
}
