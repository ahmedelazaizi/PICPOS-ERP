// ═══════════════════════════════════════════════════════════════════════════
// تقريبُ الإجماليّ — الحسابُ الخالص (`pos_total_rounding`)
// ═══════════════════════════════════════════════════════════════════════════
//
// الحسابُ وحدَه، بلا قاعدةِ بيانات: خطوةُ التقريب من فهرس الخيار، والإجماليُّ
// المقرَّب، والفرقُ بإشارته. أثرُه المحاسبيُّ في
// `quick_sale_rounding_autopost_test.dart`.

import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/domain/models/quick_sale_policy.dart';

QuickSalePolicyValues _values(String? stored) => QuickSalePolicyValues(
      stored == null
          ? const <String, String>{}
          : <String, String>{'pos_total_rounding': stored},
    );

void main() {
  group('quickSaleRoundingStep — الخيارُ يترجَم إلى خطوةٍ بالعملة', () {
    test('الخياراتُ الأربعةُ بترتيب الشاشة', () {
      expect(quickSaleRoundingStep(_values('0')), 0.0);
      expect(quickSaleRoundingStep(_values('1')), 0.05);
      expect(quickSaleRoundingStep(_values('2')), 0.25);
      expect(quickSaleRoundingStep(_values('3')), 1.00);
    });

    // ⚠️ الحارسُ الأهمُّ في الملفّ: المفتاحُ غائبٌ عن **كلِّ** قاعدةٍ قائمة،
    // فالافتراضُ هو ما ستقرؤه كلُّ تنصيبةٍ لحظةَ الترقية. وافتراضٌ غيرُ الصفر
    // كان سيبدأ تقريبَ فواتيرِ كلِّ فرعٍ بلا أن يطلبه أحد.
    test('الغيابُ ⇒ بلا تقريب — لا تنقلب دفاترُ تنصيبةٍ عند الترقية', () {
      expect(quickSaleRoundingStep(_values(null)), 0.0);
    });

    test('القيمةُ الفاسدةُ أو خارجَ المدى ⇒ بلا تقريب', () {
      expect(quickSaleRoundingStep(_values('نصّ')), 0.0);
      expect(quickSaleRoundingStep(_values('9')), 0.0);
      expect(quickSaleRoundingStep(_values('-1')), 0.0);
    });
  });

  group('quickSaleRoundedTotal — المقبوضُ بعد التقريب', () {
    test('خطوةُ صفرٍ تُعيد الإجماليَّ كما هو', () {
      expect(quickSaleRoundedTotal(total: 114.08, step: 0), 114.08);
    });

    test('لأقرب ٥ قروش — هبوطاً وصعوداً', () {
      // ⚠️ **لأقرب** لا «للأدنى»: ١١٤٫٠٨ تبعد ٠٫٠٢ عن ١١٤٫١٠ و٠٫٠٣ عن
      // ١١٤٫٠٥، فتصعد. والوسمُ على الشاشة «لأقرب ٥ قروش» فهذا هو عقدُه.
      expect(quickSaleRoundedTotal(total: 114.08, step: 0.05),
          closeTo(114.10, 1e-9));
      expect(quickSaleRoundedTotal(total: 114.07, step: 0.05),
          closeTo(114.05, 1e-9));
      expect(quickSaleRoundedTotal(total: 114.03, step: 0.05),
          closeTo(114.05, 1e-9));
    });

    test('لأقرب ٢٥ قرشاً ولأقرب جنيه', () {
      expect(quickSaleRoundedTotal(total: 114.08, step: 0.25),
          closeTo(114.00, 1e-9));
      expect(quickSaleRoundedTotal(total: 114.60, step: 1.00),
          closeTo(115.00, 1e-9));
    });
  });

  group('quickSaleRoundingDelta — الفرقُ بإشارته', () {
    test('موجبٌ = قُرِّب هبوطاً (‏قُبض أقلّ) ⇒ مدين', () {
      expect(quickSaleRoundingDelta(total: 114.07, step: 0.05, decimals: 2),
          closeTo(0.02, 1e-9));
    });

    test('سالبٌ = قُرِّب صعوداً (‏قُبض أكثر) ⇒ دائن', () {
      expect(quickSaleRoundingDelta(total: 114.03, step: 0.05, decimals: 2),
          closeTo(-0.02, 1e-9));
      expect(quickSaleRoundingDelta(total: 114.08, step: 0.05, decimals: 2),
          closeTo(-0.02, 1e-9));
    });

    test('بلا تقريبٍ ⇒ صفرٌ حتماً', () {
      expect(quickSaleRoundingDelta(total: 114.08, step: 0, decimals: 2), 0);
    });

    test('إجماليٌّ يقع على الخطوة تماماً ⇒ صفرٌ فلا سطرَ قيدٍ زائد', () {
      expect(quickSaleRoundingDelta(total: 114.05, step: 0.05, decimals: 2), 0);
      expect(quickSaleRoundingDelta(total: 115.00, step: 1.00, decimals: 2), 0);
    });

    // ⚠️ `(114.08/0.05).round()*0.05` تعطي `114.05000000000001` —
    // فالفرقُ بلا قصٍّ للخانات يصير `-1.4e-14` ويولّد سطرَ قيدٍ بقيمةٍ لا
    // تُرى: يُرفض في الترحيل أو يلوّث الأستاذ بفتاتٍ لا معنى له.
    test('فتاتُ العائم يُقَصّ — الفرقُ نظيفٌ عند الخانات المطلوبة', () {
      // بلا القصّ: `(114.07/0.05).round()*0.05` تعطي `114.05000000000001`
      // فيصير الفرقُ `0.019999999999996` — سطرُ قيدٍ بقيمةٍ لا تُرى.
      final d = quickSaleRoundingDelta(total: 114.07, step: 0.05, decimals: 2);
      expect(d, 0.02, reason: 'مساواةٌ تامّةٌ لا تقريبيّة');
      expect(d.toString(), '0.02');
    });

    test('الفرقُ لا يتجاوز نصفَ الخطوة أبداً', () {
      for (final step in <double>[0.05, 0.25, 1.00]) {
        for (var cents = 0; cents < 400; cents++) {
          final total = 100 + cents / 100.0;
          final d =
              quickSaleRoundingDelta(total: total, step: step, decimals: 2);
          expect(d.abs(), lessThanOrEqualTo(step / 2 + 1e-9),
              reason: 'total=$total step=$step delta=$d');
        }
      }
    });

    // القيدُ يقوم على هذه المعادلة: المقبوضُ + الفرقُ = الإجماليُّ الحقيقيّ.
    // انكسارُها يعني قيداً غيرَ متوازنٍ يُرمى ويصير dead-letter.
    test('المقبوضُ + الفرقُ = الإجماليُّ الحقيقيُّ — دائماً', () {
      for (final step in <double>[0.05, 0.25, 1.00]) {
        for (var cents = 0; cents < 400; cents++) {
          final total = 100 + cents / 100.0;
          final rounded = quickSaleRoundedTotal(total: total, step: step);
          final delta =
              quickSaleRoundingDelta(total: total, step: step, decimals: 2);
          expect(rounded + delta, closeTo(total, 1e-9),
              reason: 'total=$total step=$step');
        }
      }
    });
  });
}
