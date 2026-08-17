import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/domain/models/tax_rate_bounds.dart';

/// حدودُ نسبةِ الضريبة — مصدرُ الحقيقة الذي تنطق به الحُرّاسُ الثلاثةُ معاً.
///
/// `tax_rate > 0` وحدَها تقبل `0.0000001`: الزرُّ «مفعَّل»، والقيدُ راضٍ،
/// والمحصَّلُ صفرٌ بعد التقريب — الكذبةُ نفسُها التي أُغلقت في v156، بصورةٍ
/// تمرّ من تحت القيد. وهذا الملفُّ يثبّت الحدَّ الذي يسدّها.
void main() {
  group('المجموعةُ المسموحة — {0} ∪ [1٪, 100٪]', () {
    test('الصفرُ مقبولٌ — تعبيرُ «محلٌّ بلا ضريبة»', () {
      // معالجُ التهيئة يكتبه عمداً عند إطفاء الضريبة، والـ`assert` القائمُ
      // يُجيز `rate == 0` صراحةً. فمنعُه يكسر مساراً مشروعاً.
      expect(TaxRateBounds.isValidPercent(0), isTrue);
    });

    test('الحدُّ الأدنى نفسُه مقبول — ١٪ ليست مرفوضةً بفارقٍ كسريّ', () {
      expect(TaxRateBounds.isValidPercent(TaxRateBounds.minPercent), isTrue);
    });

    test('ما دون الحدِّ فوق الصفر مرفوض — وهذه هي الثغرةُ بعينها', () {
      // `0.001٪` = `0.00001` كسريّاً: تمرّ من `tax_rate > 0`، وتُحصّل صفراً.
      expect(TaxRateBounds.isValidPercent(0.001), isFalse);
      expect(TaxRateBounds.isValidPercent(0.5), isFalse);
      expect(TaxRateBounds.isValidPercent(0.999), isFalse);
    });

    test('السالبُ مرفوض — لا ثغرةَ تحت الصفر', () {
      expect(TaxRateBounds.isValidPercent(-1), isFalse);
      expect(TaxRateBounds.isValidPercent(-0.001), isFalse);
    });

    test('النسبُ الواقعيّةُ مقبولة — الميزةُ لم تُمنع', () {
      for (final percent in [1.0, 5.0, 14.0, 15.0, 16.0, 20.0, 100.0]) {
        expect(TaxRateBounds.isValidPercent(percent), isTrue,
            reason: '$percent٪ نسبةٌ واقعيّةٌ يجب أن تُقبل');
      }
    });

    test('ما فوق المئةِ مرفوض — كسريّةٌ قُرئت مئويّةً فضُربت في ١٠٠', () {
      expect(TaxRateBounds.isValidPercent(100.001), isFalse);
      expect(TaxRateBounds.isValidPercent(1600), isFalse);
    });
  });

  group('الكسريّةُ والمئويّةُ تصفان حدّاً واحداً', () {
    test('minRate هي minPercent مقسومةً على مئة', () {
      // القيدُ في SQL و`setOrderTax` يعملان بالكسريّة، والشاشةُ والـ`assert`
      // بالمئويّة. انزلاقُ أحدهما دون الآخر يفتح باباً ثالثاً صامتاً.
      expect(TaxRateBounds.minRate, closeTo(TaxRateBounds.minPercent / 100, 1e-12));
    });

    test('minRate تساوي حرفيّاً ما تكتبه الشاشةُ عند ١٪', () {
      // الشاشةُ تحفظ `val / 100`. لو لم يتطابق الرقمان بتّاً لَرفض القيدُ
      // قيمةً كتبتها الشاشةُ بنفسها بعد أن أجازها المُتحقِّق.
      expect(1.0 / 100, TaxRateBounds.minRate);
    });

    test('نصُّ minRate هو ما يُكتَب في قيد SQL', () {
      // القيدُ رقمٌ حرفيٌّ في `restaurant_tables.dart` (ملفُّ `part` بلا
      // استيرادات)، فالربطُ يقع على هذا التأكيد لا على الاستيفاء.
      expect(TaxRateBounds.minRate.toString(), '0.01');
    });
  });
}
