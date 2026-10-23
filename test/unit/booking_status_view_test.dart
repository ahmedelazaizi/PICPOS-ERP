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
import 'package:picpos_erp/domain/models/picpos_booking_view.dart';

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

  group('حِملُ المورد', () {
    final day = DateTime(2026, 9, 1);

    BookingBoardRow r({
      int id = 1,
      int? resourceId = 1,
      String status = 'confirmed',
      double price = 100,
      int hour = 10,
      int minutes = 60,
    }) =>
        BookingBoardRow(
          id: id,
          startsAt: day.add(Duration(hours: hour)),
          endsAt: day.add(Duration(hours: hour, minutes: minutes)),
          customerName: 'ع',
          status: status,
          depositAmount: 0,
          depositStatus: 'held',
          servicePrice: price,
          resourceId: resourceId,
          resourceName: resourceId == null ? null : 'مورد',
        );

    test('يجمع حجوزاتِ المورد وحدَه', () {
      final load = resourceDayLoad(
        resourceId: 1,
        rows: [r(), r(id: 2, resourceId: 2, hour: 11), r(id: 3, hour: 12)],
      );
      expect(load.bookings, 2);
      expect(load.revenue, 200);
    });

    test('الملغى والمتخلّفُ لا يُحسبان', () {
      final load = resourceDayLoad(
        resourceId: 1,
        rows: [
          r(status: 'cancelled'),
          r(id: 2, status: 'no_show', hour: 11),
          r(id: 3, hour: 12),
        ],
      );
      expect(load.bookings, 1,
          reason: 'نسبةُ إشغالٍ تعدّ حجزاً ملغىً تقول «مشغول» عن ساعةٍ فارغة');
      expect(load.revenue, 100);
    });

    test('النسبةُ تُقاس على الورديّة', () {
      // ورديّةٌ ٦٠٠→١٢٠٠ = ٦٠٠ دقيقة، وحجزٌ ٦٠ دقيقة ⇒ ١٠٪.
      final load = resourceDayLoad(
        resourceId: 1,
        rows: [r(minutes: 60)],
        shiftStartMinutes: 600,
        shiftEndMinutes: 1200,
      );
      expect(load.bookedMinutes, 60);
      expect(load.loadPct, closeTo(10, 0.001));
    });

    test('بلا ورديّةٍ معرّفةٍ ⇒ صفرٌ لا Infinity', () {
      final load = resourceDayLoad(resourceId: 1, rows: [r()]);
      expect(load.loadPct, 0,
          reason: 'القسمةُ على صفرٍ في دارت تعطي Infinity — فتُرسم شريطاً '
              'بلا نهاية');
      expect(load.loadPct.isFinite, isTrue);
    });

    test('الحملُ لا يتجاوز مئةً ولو زاد الحجز', () {
      final load = resourceDayLoad(
        resourceId: 1,
        rows: [r(minutes: 600), r(id: 2, hour: 20, minutes: 600)],
        shiftStartMinutes: 600,
        shiftEndMinutes: 1200,
      );
      expect(load.loadPct, 100);
    });
  });
}
