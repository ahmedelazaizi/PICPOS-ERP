// test/unit/expense_allocation_test.dart
//
// توزيعُ مصروفٍ على أوامر التصنيع — بالقيم المحسوبة يدوياً.
//
// ═══ ما يحرسه هذا الملفّ ═══
//
// 🔴 **فرقُ التقريب**: تقريبُ كلِّ سطرٍ على حدة يجعل مجموعَ الأسطر يخالف
//    المبلغَ بقروش — وهي تظهر في الأستاذ فرقاً لا يُفسَّر. فتُحمَّل على أكبر
//    سطر، ويُثبَّت أنّ المجموعَ يساوي المبلغَ **بالضبط**.
//
// 🔴 **والباقي قد يكون سالباً**: التصميمُ يسمّيه «غير محمَّل» ويفترضه موجباً.
//    والمعدّلُ الأعلى من الواقع يُنتج تحميلاً يفوق المصروف — وابتلاعُ السالب
//    يُخفي تجاوزاً حقيقيّاً في تكلفة الأوامر.
//
// ⚠️ **والأرقامُ مثبَّتةٌ محسوبةً بيد** لا «> صفر»: مصالحةٌ تتّفق عند رقمٍ
// خاطئٍ تمرّ خضراء.
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/domain/models/expense_allocation.dart';

void main() {
  group('بالمعدل × الكمية', () {
    test('أرقامُ التصميم: 1.20 × (١٨٠ + ٣٢٠) = 600 من 8,640', () {
      final plan = allocateExpense(
        expenseAmount: 8640,
        quantities: const {138: 180, 137: 320},
        basis: AllocationBasis.byRate,
        rate: 1.20,
      );

      expect(plan.lines.length, 2);
      // ‏1.20 × 180 = 216 · و1.20 × 320 = 384.
      expect(plan.lines[0].amount, closeTo(216, 1e-9));
      expect(plan.lines[1].amount, closeTo(384, 1e-9));
      expect(plan.allocated, closeTo(600, 1e-9));

      // ‏8,640 − 600 = 8,040 غيرَ محمَّل — وهو رقمُ لوحة التصميم نفسِه.
      expect(plan.unallocated, closeTo(8040, 1e-9));
      expect(plan.isExact, isFalse);
    });

    test('🔴 معدّلٌ أعلى من الواقع يعطي باقياً سالباً لا صفراً', () {
      // ‏50 × (180 + 320) = 25,000 على مصروفٍ 8,640 ⇒ تجاوزٌ 16,360.
      final plan = allocateExpense(
        expenseAmount: 8640,
        quantities: const {138: 180, 137: 320},
        basis: AllocationBasis.byRate,
        rate: 50,
      );

      expect(plan.allocated, closeTo(25000, 1e-9));
      expect(plan.unallocated, closeTo(-16360, 1e-9));
      expect(plan.unallocated, lessThan(0));
    });

    test('أمرٌ بكمّيّةٍ صفريّةٍ يأخذ صفراً', () {
      final plan = allocateExpense(
        expenseAmount: 1000,
        quantities: const {1: 0, 2: 100},
        basis: AllocationBasis.byRate,
        rate: 2,
      );
      expect(plan.lines.firstWhere((l) => l.orderId == 1).amount, 0);
      expect(plan.lines.firstWhere((l) => l.orderId == 2).amount, 200);
    });
  });

  group('توزيع كامل المبلغ', () {
    test('نسبةً للكمّيّات — والمجموعُ يساوي المبلغَ بالضبط', () {
      // ‏8,640 على (180 + 320 = 500):
      //   180/500 × 8,640 = 3,110.40
      //   320/500 × 8,640 = 5,529.60
      final plan = allocateExpense(
        expenseAmount: 8640,
        quantities: const {138: 180, 137: 320},
        basis: AllocationBasis.fullAmount,
      );

      expect(plan.lines[0].amount, closeTo(3110.40, 1e-9));
      expect(plan.lines[1].amount, closeTo(5529.60, 1e-9));
      expect(plan.allocated, closeTo(8640, 1e-9));
      expect(plan.unallocated, closeTo(0, 1e-9));
      expect(plan.isExact, isTrue);
    });

    test('🔴 قسمةٌ لا تنتهي: الفرقُ يُحمَّل على أكبر سطرٍ والمجموعُ يطابق', () {
      // ‏100 على ثلاثة أوامرَ متساوية = 33.333… لكلٍّ.
      // وتقريبُ كلٍّ إلى 33.33 يعطي مجموعاً 99.99 — قرشٌ ضائع.
      final plan = allocateExpense(
        expenseAmount: 100,
        quantities: const {1: 1, 2: 1, 3: 1},
        basis: AllocationBasis.fullAmount,
      );

      expect(plan.allocated, closeTo(100, 1e-9),
          reason: 'المجموعُ خالف المبلغَ — القرشُ الضائعُ يظهر في الأستاذ');
      expect(plan.isExact, isTrue);

      // وسطرٌ واحدٌ يحمل القرشَ: 33.34 والآخران 33.33.
      final amounts = plan.lines.map((l) => l.amount).toList()..sort();
      expect(amounts, [closeTo(33.33, 1e-9), closeTo(33.33, 1e-9), closeTo(33.34, 1e-9)]);
    });

    test('الفرقُ يقع على **أكبر** سطرٍ لا على أوّله', () {
      // ‏10 على كمّيّاتٍ 1 و2 و6 (‏مجموعُها ٩):
      //   1/9 × 10 = 1.111… ⇒ 1.11
      //   2/9 × 10 = 2.222… ⇒ 2.22
      //   6/9 × 10 = 6.666… ⇒ 6.67
      // المجموع 10.00 — بلا فرقٍ هنا، فنأخذ حالةً بفرق:
      final plan = allocateExpense(
        expenseAmount: 100,
        quantities: const {1: 1, 2: 1, 3: 4},
        basis: AllocationBasis.fullAmount,
      );

      // ‏1/6 × 100 = 16.666… ⇒ 16.67 ×٢ · و4/6 × 100 = 66.666… ⇒ 66.67
      // المجموع 100.01 ⇒ الفرقُ −0.01 يقع على السطر الأكبر (66.67 → 66.66).
      expect(plan.allocated, closeTo(100, 1e-9));
      final biggest =
          plan.lines.reduce((a, b) => a.amount > b.amount ? a : b);
      expect(biggest.orderId, 3);
      expect(biggest.amount, closeTo(66.66, 1e-9));
    });

    test('كلُّ الكمّيّات صفرٌ ⇒ لا تحميلَ ولا NaN', () {
      // 🔴 القسمةُ على مجموعٍ صفريٍّ تُنتج `NaN` تُكتَب في القاعدة.
      final plan = allocateExpense(
        expenseAmount: 5000,
        quantities: const {1: 0, 2: 0},
        basis: AllocationBasis.fullAmount,
      );

      for (final l in plan.lines) {
        expect(l.amount, 0);
        expect(l.amount.isNaN, isFalse);
      }
      expect(plan.unallocated, closeTo(5000, 1e-9));
    });
  });

  test('بلا أوامرَ مختارةٍ ⇒ خطّةٌ فارغةٌ والمبلغُ كلُّه غيرُ محمَّل', () {
    final plan = allocateExpense(
      expenseAmount: 8640,
      quantities: const {},
      basis: AllocationBasis.fullAmount,
    );
    expect(plan.lines, isEmpty);
    expect(plan.allocated, 0);
    expect(plan.unallocated, closeTo(8640, 1e-9));
  });
}
