// خطّةُ دفتر الشيكات — الحسابُ الخالصُ الذي يمنع رقماً مكرَّراً من الوصول
// إلى البنك.
//
// ⚠️ ما يُقاس هنا **قواعدُ** لا صيغ: التداخلُ على الحساب البنكيّ ·
//    الشمولُ في العدّ · اشتقاقُ الحالة · ورفضُ السحبِ الجزئيّ.

import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/domain/models/cheque_book_plan.dart';

ChequeBookRow _book({
  int id = 1,
  int account = 10,
  int from = 101,
  int to = 200,
  int? next,
  String status = 'active',
}) =>
    (
      id: id,
      bankAccountId: account,
      fromNumber: from,
      toNumber: to,
      nextNumber: next ?? from,
      status: status,
    );

void main() {
  group('المتبقّي شاملُ الطرفين', () {
    test('دفترٌ لم يُمَسّ فيه مئةُ شيكٍ لا تسعٌ وتسعون', () {
      // 🔴 النقصُ بواحدٍ هنا يُظهر دفتراً منتهياً وفيه ورقةٌ بيضاء.
      expect(chequesRemaining(nextNumber: 101, toNumber: 200), 100);
    });

    test('وآخرُ ورقةٍ تُعَدّ واحدةً لا صفراً', () {
      expect(chequesRemaining(nextNumber: 200, toNumber: 200), 1);
    });

    test('والتالي خارجَ المدى صفرٌ لا سالب', () {
      expect(chequesRemaining(nextNumber: 201, toNumber: 200), 0);
      expect(chequesRemaining(nextNumber: 260, toNumber: 200), 0);
    });
  });

  group('الرقمُ المطبوع', () {
    test('🔴 العرضُ من نهاية الدفتر لا من الرقم — وإلّا بدا رقمان من دفترَين',
        () {
      // دفترٌ ٩٨–١٠٢: الصفُّ بعرض الرقم وحدَه يعطي «98» ثمّ «100».
      expect(formatChequeNumber(number: 98, toNumber: 102), '098');
      expect(formatChequeNumber(number: 100, toNumber: 102), '100');
    });

    test('والبادئةُ تُلصَق كما هي', () {
      expect(formatChequeNumber(prefix: 'CHK-', number: 7, toNumber: 500),
          'CHK-007');
    });

    test('وبادئةٌ فارغةٌ أو بمسافاتٍ لا تُطبَع', () {
      expect(formatChequeNumber(prefix: '', number: 7, toNumber: 50), '07');
      expect(formatChequeNumber(prefix: '   ', number: 7, toNumber: 50), '07');
      expect(formatChequeNumber(number: 7, toNumber: 50), '07');
    });
  });

  group('الحالةُ مشتقّةٌ من المدى', () {
    test('لا متبقّيَ ⇒ منتهٍ', () {
      expect(
          resolveChequeBookStatus(
              current: 'active', nextNumber: 201, toNumber: 200),
          'exhausted');
    });

    test('وتوسيعُ النهاية يُعيد المنتهيَ نشطاً بلا خطوةٍ ثانية', () {
      expect(
          resolveChequeBookStatus(
              current: 'exhausted', nextNumber: 201, toNumber: 300),
          'active');
    });

    test('🔴 والإلغاءُ يغلب — دفترٌ ضاع لا يعود نشطاً لأنّ فيه أرقاماً', () {
      expect(
          resolveChequeBookStatus(
              current: 'cancelled', nextNumber: 101, toNumber: 200),
          'cancelled');
    });
  });

  group('فحصُ المدى', () {
    test('المدى السليمُ بلا خطأ', () {
      expect(
          validateChequeBookRange(
              fromNumber: 101, toNumber: 200, nextNumber: 150),
          isNull);
    });

    test('ونهايةٌ قبل البداية تُرفَض', () {
      expect(
          validateChequeBookRange(
              fromNumber: 200, toNumber: 101, nextNumber: 200),
          contains('قبل رقم البداية'));
    });

    test('وبدايةٌ غيرُ موجبةٍ تُرفَض', () {
      expect(
          validateChequeBookRange(fromNumber: 0, toNumber: 200, nextNumber: 0),
          isNotNull);
    });

    test('⚠️ والتالي = النهاية + ١ مقبولٌ عمداً — هو الدفترُ المنتهي', () {
      // ورفضُه كان يمنع إنهاءَ أيّ دفترٍ إطلاقاً.
      expect(
          validateChequeBookRange(
              fromNumber: 101, toNumber: 200, nextNumber: 201),
          isNull);
      expect(
          validateChequeBookRange(
              fromNumber: 101, toNumber: 200, nextNumber: 202),
          contains('خارج الدفتر'));
    });

    test('وتالٍ قبل البداية يُرفَض', () {
      expect(
          validateChequeBookRange(
              fromNumber: 101, toNumber: 200, nextNumber: 100),
          contains('قبل بداية الدفتر'));
    });

    test('والغلطةُ المطبعيّةُ في النهاية تُمسَك بالسقف', () {
      expect(
          validateChequeBookRange(
              fromNumber: 1, toNumber: kMaxChequeBookSize, nextNumber: 1),
          isNull);
      expect(
          validateChequeBookRange(
              fromNumber: 1, toNumber: kMaxChequeBookSize + 1, nextNumber: 1),
          isNotNull);
    });
  });

  group('🔴 تداخلُ المدى — سببُ وجود الجدول', () {
    test('مدًى يبتلع أوّلَ دفترٍ قائمٍ يُرفَض', () {
      final hit = findChequeRangeOverlap(
        existing: [_book(id: 1, from: 101, to: 200)],
        bankAccountId: 10,
        fromNumber: 150,
        toNumber: 260,
      );
      expect(hit?.id, 1);
    });

    test('والتماسُّ عند الحدّ تداخلٌ — ٢٠٠ في الدفترَين', () {
      expect(
          findChequeRangeOverlap(
            existing: [_book(id: 1, from: 101, to: 200)],
            bankAccountId: 10,
            fromNumber: 200,
            toNumber: 300,
          )?.id,
          1);
      // و٢٠١ لا يتداخل.
      expect(
          findChequeRangeOverlap(
            existing: [_book(id: 1, from: 101, to: 200)],
            bankAccountId: 10,
            fromNumber: 201,
            toNumber: 300,
          ),
          isNull);
    });

    test('🔴 وحسابان مختلفان لا يتداخلان — بنكُ مصر وبنكُ القاهرة كلاهما ١٠١',
        () {
      // منعُ هذا كان يُبطل الدفترَ الثانيَ المشروعَ تماماً.
      expect(
          findChequeRangeOverlap(
            existing: [_book(id: 1, account: 10, from: 101, to: 200)],
            bankAccountId: 11,
            fromNumber: 101,
            toNumber: 200,
          ),
          isNull);
    });

    test('والدفترُ لا يتداخل مع نفسِه عند التعديل', () {
      expect(
          findChequeRangeOverlap(
            existing: [_book(id: 7, from: 101, to: 200)],
            bankAccountId: 10,
            fromNumber: 101,
            toNumber: 300,
            editingId: 7,
          ),
          isNull);
    });

    test('والملغى لا يحجز أرقامه', () {
      expect(
          findChequeRangeOverlap(
            existing: [_book(id: 1, from: 101, to: 200, status: 'cancelled')],
            bankAccountId: 10,
            fromNumber: 101,
            toNumber: 200,
          ),
          isNull);
    });

    test('⚠️ والمنتهي **يحجزها** — أرقامُه صُرفت فعلاً', () {
      expect(
          findChequeRangeOverlap(
            existing: [
              _book(id: 1, from: 101, to: 200, next: 201, status: 'exhausted')
            ],
            bankAccountId: 10,
            fromNumber: 150,
            toNumber: 250,
          )?.id,
          1);
    });
  });

  group('سحبُ الأرقام', () {
    test('ثلاثةُ شيكاتٍ متتاليةٌ من التالي', () {
      final p = planChequeNumbers(book: _book(next: 105), count: 3);
      expect(p.error, isNull);
      expect(p.numbers, [105, 106, 107]);
    });

    test('🔴 ولا سحبَ جزئيّ — ثلاثةٌ من دفترٍ فيه اثنان تُرفَض كلُّها', () {
      // السحبُ الجزئيُّ كان يكتب شيكَين ويترك الثالثَ بلا رقمٍ في سندٍ
      // مُرحَّل.
      final p = planChequeNumbers(book: _book(next: 199), count: 3);
      expect(p.numbers, isEmpty);
      expect(p.error, contains('2'));
    });

    test('ومن دفترٍ انتهى لا يُسحَب', () {
      final p = planChequeNumbers(book: _book(next: 201), count: 1);
      expect(p.numbers, isEmpty);
      expect(p.error, contains('انتهى'));
    });

    test('ومن ملغًى لا يُسحَب ولو بقيت أرقامُه', () {
      final p = planChequeNumbers(
          book: _book(next: 101, status: 'cancelled'), count: 1);
      expect(p.numbers, isEmpty);
      expect(p.error, contains('ملغى'));
    });

    test('وصفرُ شيكاتٍ لا يُنتج سحباً', () {
      expect(planChequeNumbers(book: _book(), count: 0).numbers, isEmpty);
      expect(planChequeNumbers(book: _book(), count: 0).error, isNotNull);
    });

    test('وآخرُ ورقةٍ تُسحَب', () {
      final p = planChequeNumbers(book: _book(next: 200), count: 1);
      expect(p.error, isNull);
      expect(p.numbers, [200]);
    });
  });
}
