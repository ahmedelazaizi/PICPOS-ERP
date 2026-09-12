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

  // ═══════════════════════════════════════════════════════════════════════
  // رمزُ الجلسة القصير — الحاجزُ البديلُ حين يخرج الخادمُ إلى دومين
  // ═══════════════════════════════════════════════════════════════════════
  //
  // ⚠️ **الحاجزُ الأوّلُ كان الشبكةَ نفسَها**: خادمٌ محلّيٌّ لا يبلغه إلّا من
  // هو في المحلّ. وخادمٌ على دومينٍ يُسقط ذلك الحاجزَ كلَّه — فمن صوّر الرمزَ
  // المطبوعَ مرّةً يقرأ حسابَ تلك الطاولة **من أيّ مكانٍ في العالم** كلّما
  // شُغلت، ويبلغ رمزَ الجلسة (‏يُعاد مع القراءة) فيكتب.
  //
  // فالبديلُ رقمٌ قصيرٌ **لا يُنال إلّا من داخل المحلّ**: يقرؤه النادلُ من
  // شاشته ويقوله للضيف الجالس أمامه. ويُشتقّ ولا يُخزَّن — لا عمودَ ولا هجرة.
  group('الرقمُ القصير', () {
    test('أربعةُ محارفَ رقميّةٌ دائماً', () {
      for (var id = 1; id <= 40; id++) {
        final pin = TableBillToken.sessionPin(orderId: id, openedAt: opened);
        expect(pin, hasLength(4), reason: 'الطلبُ $id أعطى «$pin»');
        expect(RegExp(r'^\d{4}$').hasMatch(pin), isTrue, reason: pin);
      }
    });

    test('وثابتٌ لنفس الجلسة — يُقال مرّةً ويبقى', () {
      expect(
        TableBillToken.sessionPin(orderId: 41, openedAt: opened),
        TableBillToken.sessionPin(orderId: 41, openedAt: opened),
      );
    });

    test('ويتبدّل بتبدّل الجلسة', () {
      final a = TableBillToken.sessionPin(orderId: 41, openedAt: opened);
      final b = TableBillToken.sessionPin(orderId: 42, openedAt: opened);
      final c = TableBillToken.sessionPin(
        orderId: 41,
        openedAt: opened.add(const Duration(minutes: 1)),
      );
      expect(a, isNot(b));
      expect(a, isNot(c), reason: 'جلسةٌ تاليةٌ على نفس الطاولة بنفس الرقم');
    });

    test('والتحقّقُ لا يقبل سواه ولا يقبل فراغاً', () {
      final pin = TableBillToken.sessionPin(orderId: 41, openedAt: opened);
      expect(
        TableBillToken.verifySessionPin(pin, orderId: 41, openedAt: opened),
        isTrue,
      );
      expect(
        TableBillToken.verifySessionPin('0000', orderId: 41, openedAt: opened),
        pin == '0000',
      );
      expect(
        TableBillToken.verifySessionPin(null, orderId: 41, openedAt: opened),
        isFalse,
      );
      expect(
        TableBillToken.verifySessionPin('', orderId: 41, openedAt: opened),
        isFalse,
      );
    });

    test('ويتجاوز الفراغَ حولَه — الضيفُ يكتبه بيده', () {
      final pin = TableBillToken.sessionPin(orderId: 41, openedAt: opened);
      expect(
        TableBillToken.verifySessionPin(
          ' $pin ',
          orderId: 41,
          openedAt: opened,
        ),
        isTrue,
      );
    });

    test('ولا يُشتقّ بلا مفتاح', () {
      TableBillToken.clearKey();
      expect(
        () => TableBillToken.sessionPin(orderId: 1, openedAt: opened),
        throwsStateError,
      );
      expect(
        TableBillToken.verifySessionPin('1234', orderId: 1, openedAt: opened),
        isFalse,
      );
    });

    test('وتوزيعُه غيرُ منحازٍ إلى قيمةٍ واحدة', () {
      // ⚠️ اشتقاقٌ من بايتٍ واحدٍ يعطي ٢٥٦ قيمةً فقط، ومن `hashCode` يعطي
      // تكراراً واضحاً. والمقياسُ هنا **عددُ القيم المتمايزة** لا شكلُها.
      final seen = <String>{};
      for (var id = 1; id <= 200; id++) {
        seen.add(TableBillToken.sessionPin(orderId: id, openedAt: opened));
      }
      expect(seen.length, greaterThan(180),
          reason: 'تصادمٌ كثيفٌ — الرقمُ يُخمَّن بمحاولاتٍ قليلة');
    });
  });
}
