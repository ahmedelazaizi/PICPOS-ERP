// test/unit/table_bill_token_test.dart
//
// رمزا رابطِ حسابِ الطاولة — البندُ الأوّل من فيتشرات المالك 2026-09-12.
//
// ═══ لماذا رمزان لا رمزٌ واحد ═══
//
// الـQR **يُطبَع مرّةً ويُلصَق على الطاولة**، فرمزُه لا يمكن أن يتغيّر مع كلّ
// جلسة. ورمزٌ ثابتٌ يُجيز الكتابةَ يعني أن من مسحه مرّةً يظلّ قادراً على
// «طلب الحساب» لطاولةٍ يجلس عليها غيرُه بعد شهر.
//
// فالقراءةُ برمزِ الطاولة الثابت، والكتابةُ برمزِ **الجلسة** المشتقِّ من
// الطلب ولحظةِ فتحه — يموت بإغلاق الطلب ولا يُحيا.
//
// ═══ والحدُّ الأمنيُّ الحقيقيُّ مذكورٌ لا مُدَّعى ═══
//
// الخادمُ على شبكة المحلّ، فمن لا يبلغ الشبكةَ لا يبلغ هذه المسارات أصلاً.
// والتوقيعُ يمنع التخمينَ والتلاعبَ بالرقم، لا يمنع من جلس أمسَ وعاد اليوم
// إلى نفس الشبكة. والرمزُ الثاني هو ما يمنعه من الكتابة.
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/services/api/table_bill_token.dart';

void main() {
  final opened = DateTime.utc(2026, 9, 12, 13, 5, 7);

  setUp(() => TableBillToken.setKeyForTesting('seed-one'));
  tearDown(TableBillToken.clearKey);

  group('فشلٌ مغلقٌ قبل اشتقاق المفتاح', () {
    test('لا سكَّ بلا مفتاح', () {
      TableBillToken.clearKey();
      expect(() => TableBillToken.mintTable(5), throwsStateError);
      expect(
        () => TableBillToken.mintSession(orderId: 1, openedAt: opened),
        throwsStateError,
      );
    });

    test('والتحقّقُ يرفض بلا مفتاح — لا يقبل', () {
      // ⚠️ السكُّ **قبل** المحو: سكٌّ بعده يرمي `StateError` فيسقط الاختبارُ
      // على الرمي لا على ما يقيسه — وهو ما وقع في أوّل صياغة.
      final table = TableBillToken.mintTable(5);
      final session = TableBillToken.mintSession(orderId: 1, openedAt: opened);

      TableBillToken.clearKey();
      expect(TableBillToken.verifyTable(table), isNull);
      expect(
        TableBillToken.verifySession(session, orderId: 1, openedAt: opened),
        isFalse,
      );
    });
  });

  group('رمزُ الطاولة — الثابتُ المطبوع', () {
    test('يعود بنفس الرقم', () {
      expect(TableBillToken.verifyTable(TableBillToken.mintTable(7)), 7);
    });

    test('ولا يقبل تلاعباً بالرقم داخلَ الحمولة', () {
      // الهجومُ الطبيعيّ: خذ رمزَ طاولتك، بدّل الرقمَ، اقرأ حسابَ غيرك.
      final mine = TableBillToken.mintTable(5);
      final other = TableBillToken.mintTable(6);
      final forged = '${other.split('.').first}.${mine.split('.').last}';
      expect(TableBillToken.verifyTable(forged), isNull,
          reason: 'حمولةٌ مبدَّلةٌ بتوقيعٍ صالحٍ لغيرها قُبلت');
    });

    test('ولا توقيعاً مبتوراً أو مشوَّهاً', () {
      final token = TableBillToken.mintTable(7);
      expect(TableBillToken.verifyTable('${token}x'), isNull);
      expect(
          TableBillToken.verifyTable(token.substring(0, token.length - 1)),
          isNull);
      expect(TableBillToken.verifyTable('7'), isNull, reason: 'بلا توقيعٍ أصلاً');
      expect(TableBillToken.verifyTable(''), isNull);
      expect(TableBillToken.verifyTable(null), isNull);
    });

    test('ولا رقمَ طاولةٍ غيرَ موجب', () {
      // معرِّفاتُ drift تبدأ من ١؛ وصفرٌ أو سالبٌ حمولةٌ ملفَّقة.
      expect(TableBillToken.verifyTable(TableBillToken.mintTable(0)), isNull);
    });

    test('وتدويرُ المفتاح يُبطل كلَّ ما طُبع', () {
      final token = TableBillToken.mintTable(7);
      TableBillToken.setKeyForTesting('seed-two');
      expect(TableBillToken.verifyTable(token), isNull);
    });
  });

  group('رمزُ الجلسة — الذي يموت بإغلاق الطلب', () {
    test('يتحقّق لطلبه ولحظتِه', () {
      final t = TableBillToken.mintSession(orderId: 41, openedAt: opened);
      expect(
        TableBillToken.verifySession(t, orderId: 41, openedAt: opened),
        isTrue,
      );
    });

    test('ولا يتحقّق لطلبٍ آخر', () {
      final t = TableBillToken.mintSession(orderId: 41, openedAt: opened);
      expect(
        TableBillToken.verifySession(t, orderId: 42, openedAt: opened),
        isFalse,
      );
    });

    test('ولا لجلسةٍ تاليةٍ على نفس الطاولة — وهذا هو الغرضُ كلُّه', () {
      // نفسُ الطلب رقماً يستحيل (‏autoIncrement)، لكنّ الاحتياطَ على
      // `openedAt` هو ما يمنع إحياءَ رمزٍ لو أُعيد استعمالُ معرّف.
      final t = TableBillToken.mintSession(orderId: 41, openedAt: opened);
      expect(
        TableBillToken.verifySession(
          t,
          orderId: 41,
          openedAt: opened.add(const Duration(seconds: 1)),
        ),
        isFalse,
      );
    });

    test('ورمزُ الطاولة لا يصلح رمزَ جلسةٍ ولا العكس', () {
      // خلطُ الرمزَين يفتح الكتابةَ بالرمز المطبوع — وهو عينُ ما نمنعه.
      final table = TableBillToken.mintTable(41);
      expect(
        TableBillToken.verifySession(table, orderId: 41, openedAt: opened),
        isFalse,
        reason: 'الرمزُ المطبوعُ قُبل للكتابة',
      );
      final session = TableBillToken.mintSession(orderId: 41, openedAt: opened);
      expect(TableBillToken.verifyTable(session), isNull);
    });

    test('ولا يقبل فارغاً ولا مشوَّهاً', () {
      expect(
        TableBillToken.verifySession(null, orderId: 41, openedAt: opened),
        isFalse,
      );
      expect(
        TableBillToken.verifySession('', orderId: 41, openedAt: opened),
        isFalse,
      );
    });
  });
}
