// `field op value` — قاعدةٌ واحدةٌ لا مفسِّرَ تعابيرَ كامل.
//
// ── لماذا لا مفسِّرَ كامل ─────────────────────────────────────────────────
// المطلوبُ من الشروط في القوالب حالةٌ واحدةٌ متكرّرة: «أظهرْ سطرَ الخصم إن
// كان الخصمُ أكبرَ من صفر». ومفسِّرُ التعابير الكاملُ يجرّ أولويّاتِ عمليّاتٍ
// وأقواساً وسلاسلَ هروبٍ ودوالَّ — سطحُ عطبٍ واسعٌ لعائدٍ معدوم.
//
// ── والحرفُ المهمّ: الغموضُ يُظهِر لا يُخفي ────────────────────────────────
// شرطٌ مكسورٌ (خطأُ إملاءٍ في اسم الحقل، عاملٌ غيرُ معروف) **يُظهِر** العنصر.
// لأنّ العطبَ الظاهرَ يُبلَّغ عنه في دقيقة، والعطبَ المخفيَّ يحذف سطرَ الخصم
// من فواتيرِ شهرٍ كاملٍ ولا يشكو أحد.

import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/domain/printing/condition_evaluator.dart';

void main() {
  const values = {
    'discount': '15.5',
    'tax': '0',
    'total': '200',
    'customer_name': 'أحمد',
    'notes': '',
  };

  group('العواملُ الستّة', () {
    test('أكبر من', () {
      expect(evaluateCondition('discount > 0', values), isTrue);
      expect(evaluateCondition('tax > 0', values), isFalse);
    });

    test('أصغر من', () {
      expect(evaluateCondition('discount < 20', values), isTrue);
      expect(evaluateCondition('discount < 10', values), isFalse);
    });

    test('أكبر أو يساوي / أصغر أو يساوي', () {
      expect(evaluateCondition('tax >= 0', values), isTrue);
      expect(evaluateCondition('tax <= 0', values), isTrue);
      expect(evaluateCondition('discount >= 15.5', values), isTrue);
    });

    test('يساوي ولا يساوي — رقميّاً', () {
      expect(evaluateCondition('total == 200', values), isTrue);
      expect(evaluateCondition('total != 200', values), isFalse);
    });

    test('يساوي ولا يساوي — نصّيّاً', () {
      expect(evaluateCondition('customer_name == أحمد', values), isTrue);
      expect(evaluateCondition('customer_name != أحمد', values), isFalse);
      expect(evaluateCondition('customer_name == سعيد', values), isFalse);
    });
  });

  group('الشرطُ الفارغُ يعني «يظهر دائماً»', () {
    test('null', () => expect(evaluateCondition(null, values), isTrue));
    test('فارغ', () => expect(evaluateCondition('', values), isTrue));
    test('مسافات', () => expect(evaluateCondition('   ', values), isTrue));
  });

  group('الغموضُ يُظهِر لا يُخفي', () {
    test('حقلٌ غيرُ معروفٍ يُظهِر العنصر', () {
      expect(
        evaluateCondition('nonexistent_field > 0', values),
        isTrue,
        reason: 'إخفاءُ عنصرٍ بسببِ خطأِ إملاءٍ عطبٌ صامت — يحذف سطرَ الخصم '
            'من فواتيرِ شهرٍ ولا يشكو أحد',
      );
    });

    test('عاملٌ غيرُ معروفٍ يُظهِر العنصر', () {
      expect(evaluateCondition('discount ~ 0', values), isTrue);
    });

    test('شرطٌ بلا عاملٍ أصلاً يُظهِر العنصر', () {
      expect(evaluateCondition('discount', values), isTrue);
    });

    test('مقارنةٌ رقميّةٌ على نصٍّ غيرِ رقميٍّ تُظهِر العنصر', () {
      expect(evaluateCondition('customer_name > 5', values), isTrue);
    });
  });

  group('تفاصيلُ التحليل', () {
    test('المسافاتُ الزائدةُ لا تكسر الشرط', () {
      expect(evaluateCondition('  discount   >   0  ', values), isTrue);
    });

    test('`>=` تُقرأ قبل `>` — لا تُقصّ لعاملين', () {
      // لو قُرئ `>` أوّلاً لصارت القيمةُ «= 0» فتفشل المقارنة.
      expect(evaluateCondition('tax >= 0', values), isTrue);
      expect(evaluateCondition('tax > 0', values), isFalse);
    });

    test('الحقلُ الفارغُ يساوي صفراً في المقارنة الرقميّة', () {
      expect(evaluateCondition('notes > 0', values), isFalse);
      expect(evaluateCondition('notes == 0', values), isTrue);
    });

    test('القيمةُ النصّيّةُ قد تحوي مسافات', () {
      expect(
        evaluateCondition('customer_name == أحمد', {'customer_name': 'أحمد'}),
        isTrue,
      );
      expect(
        evaluateCondition(
          'city == مدينة نصر',
          {'city': 'مدينة نصر'},
        ),
        isTrue,
        reason: 'القصُّ عند أوّل مسافةٍ بعد العامل يكسر كلَّ اسمٍ مركَّب',
      );
    });
  });
}
