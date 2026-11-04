// تحويلُ قيمِ الأعمدة الرقميّة في معدّلات ملفّ الطرف (`asNumOrNull`).
//
// ═══ ما يحمي هذا الملفّ ═══
//
// PostgreSQL يُعيد `numeric` (ومنه `AVG`) نصّاً أحياناً، فكان `as num?` يرمي
// `type 'String' is not a subtype of type 'num?'` ويُسقط تبويبَي الملفّ
// الشخصيّ والأعمار. هذا الاختبار يثبت أنّ النصَّ الرقميَّ يُقرأ رقماً، وأنّ
// `null` وما ليس رقماً يعود `null` بلا رمي.
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/data/database/database.dart';

void main() {
  group('asNumOrNull', () {
    test('الرقمُ يبقى كما هو', () {
      expect(asNumOrNull(12.5), 12.5);
      expect(asNumOrNull(7), 7);
    });

    test('النصُّ الرقميُّ (ما يُعيده numeric/AVG) يُقرأ رقماً', () {
      expect(asNumOrNull('12.5'), 12.5);
      expect(asNumOrNull(' 12.5 '), 12.5);
      expect(asNumOrNull('7'), 7);
    });

    test('النصُّ المكسورُ والفارغُ وغيرُ الرقميّ ⇒ null بلا رمي', () {
      expect(asNumOrNull(''), isNull);
      expect(asNumOrNull('abc'), isNull);
      expect(asNumOrNull(true), isNull);
    });

    test('null ⇒ null', () {
      expect(asNumOrNull(null), isNull);
    });

    test(
      'النصُّ الرقميُّ يُحوَّل بعدها إلى double كما تفعل الدالّةُ في الـDAO',
      () {
        expect(asNumOrNull('12.5')?.toDouble(), 12.5);
        expect(asNumOrNull(null)?.toDouble() ?? 0, 0);
      },
    );
  });
}
