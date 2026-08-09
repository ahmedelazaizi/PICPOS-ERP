// ═══════════════════════════════════════════════════════════════════════════
// توحيدُ خريطة طرق الدفع لا يغيّر حرفاً واحداً ممّا يراه المستخدم.
// ═══════════════════════════════════════════════════════════════════════════
//
// الخريطةُ كانت مكرّرةً في سبعةِ مواضع لا تتفق. وخطرُ أيّ توحيد أن يُغيّر
// تسميةً في تقريرٍ قائمٍ صمتاً، فيقرأ المحاسبُ رقماً تحت وسمٍ لم يعتده.
//
// فهذا الاختبار يثبّت **النصوصَ الحرفية** لكلّ مفتاح، في الصيغتين: القياسية
// وصيغةِ تقرير المبيعات المجمَّعة. أيُّ تغييرٍ لاحقٍ في تسميةٍ يفشل هنا
// فيصير قراراً واعياً لا أثراً جانبياً.
// ═══════════════════════════════════════════════════════════════════════════

import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/core/constants/payment_methods.dart';

void main() {
  group('التسميةُ القياسية', () {
    const expected = {
      'cash': 'نقدي',
      'card': 'بطاقة',
      'transfer': 'تحويل',
      'bank': 'بنك',
      'credit': 'آجل',
      'click': 'كليك',
      'multiple': 'متعدد',
    };
    expected.forEach((key, label) {
      test('$key ⇒ $label', () => expect(PaymentMethods.label(key), label));
    });

    test('`mixed` مرادفُ `multiple` — تسميةٌ واحدة', () {
      expect(PaymentMethods.label('mixed'), 'متعدد');
      expect(PaymentMethods.canonical('mixed'), 'multiple');
    });

    test('المفتاحُ غيرُ المعروف يُعاد كما هو لا يُخفى بشرطة', () {
      expect(PaymentMethods.label('paypal'), 'paypal',
          reason: 'قيمةٌ غريبةٌ في البيانات يجب أن تُرى لتُصلَح — '
              'وإخفاؤها بـ«-» يجعل العطلَ غيرَ مرئيّ');
    });

    test('الفارغُ والمعدوم ⇒ شرطة', () {
      expect(PaymentMethods.label(null), '-');
      expect(PaymentMethods.label(''), '-');
    });
  });

  group('تجميعُ تقرير المبيعات محفوظٌ حرفياً', () {
    // ⚠️ الاختلافُ عن القياسية **مقصود**: حسمُه قرارُ منتجٍ يغيّر تجميعَ
    // الأرقام في تقريرٍ قائم. الاختبارُ يثبّته لا يباركه.
    test('البطاقةُ والتحويلُ والبنك وسمٌ واحد', () {
      for (final k in ['card', 'transfer', 'bank']) {
        expect(PaymentMethods.groupedLabel(k), 'بطاقة/تحويل');
      }
    });

    test('والباقي كالقياسية', () {
      expect(PaymentMethods.groupedLabel('cash'), 'نقدي');
      expect(PaymentMethods.groupedLabel('credit'), 'آجل');
      expect(PaymentMethods.groupedLabel('click'), 'كليك');
      expect(PaymentMethods.groupedLabel('mixed'), 'متعدد');
      expect(PaymentMethods.groupedLabel('multiple'), 'متعدد');
    });

    test('الصيغتان تختلفان فعلاً — وإلا فالتوحيدُ تمّ بلا قرار', () {
      expect(PaymentMethods.label('card'),
          isNot(PaymentMethods.groupedLabel('card')),
          reason: 'لو تطابقتا يوماً فذلك يعني أن أحداً وحّدهما — '
              'وهو قرارٌ يخصّ صاحبَ المنتج لا أثرٌ جانبيّ');
    });
  });
}
