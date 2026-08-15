import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/domain/models/split_plan.dart';

void main() {
  group('SplitPlan.equal', () {
    test('مجموعُ الحصص يساوي الإجمالي بالضبط عند ١٠٠ ÷ ٣', () {
      final plan = SplitPlan.equal(total: 100, ways: 3);
      expect(plan.parts.map((p) => p.amount).toList(),
          [33.333, 33.333, 33.334]);
      final sum = plan.parts.fold<double>(0, (s, p) => s + p.amount);
      expect((sum * 1000).round(), (100 * 1000).round());
    });

    test('الفرقُ الكسريُّ يقع على الحصّة الأخيرة عند ١٠٠ ÷ ٧', () {
      final plan = SplitPlan.equal(total: 100, ways: 7);
      final sum = plan.parts.fold<double>(0, (s, p) => s + p.amount);
      expect((sum * 1000).round(), 100000);
      expect(plan.parts.last.amount, greaterThan(plan.parts.first.amount));
    });

    test('القسمةُ المضبوطة لا تترك بواقي', () {
      final plan = SplitPlan.equal(total: 100, ways: 4);
      expect(plan.parts.every((p) => p.amount == 25.0), isTrue);
    });

    test('دافعٌ واحدٌ يُرفض', () {
      expect(() => SplitPlan.equal(total: 100, ways: 1),
          throwsA(isA<SplitPlanException>()));
    });

    test('إجماليٌّ غيرُ موجبٍ يُرفض', () {
      expect(() => SplitPlan.equal(total: 0, ways: 2),
          throwsA(isA<SplitPlanException>()));
    });

    test('لا تُصدر فواتيرَ منفصلة', () {
      expect(SplitPlan.equal(total: 100, ways: 2).producesSeparateInvoices,
          isFalse);
    });
  });

  group('SplitPlan.byAmounts', () {
    test('المجموعُ المطابق يُقبل', () {
      final plan = SplitPlan.byAmounts(total: 100, amounts: [40, 35, 25]);
      expect(plan.parts.length, 3);
      expect(plan.parts[0].amount, 40);
    });

    test('المجموعُ المخالف يُرفض', () {
      expect(() => SplitPlan.byAmounts(total: 100, amounts: [40, 35, 20]),
          throwsA(isA<SplitPlanException>()));
    });

    test('حصّةٌ غيرُ موجبةٍ تُرفض', () {
      expect(() => SplitPlan.byAmounts(total: 100, amounts: [100, 0]),
          throwsA(isA<SplitPlanException>()));
    });
  });

  group('SplitPlan.byItems', () {
    const items = [
      SplitItem(itemId: 1, quantity: 2, lineTotal: 60),
      SplitItem(itemId: 2, quantity: 1, lineTotal: 40),
    ];

    test('كلُّ بندٍ يذهب لصاحبه ويُجمع مبلغُه', () {
      final plan = SplitPlan.byItems(
        items: items,
        assignment: {1: 0, 2: 1},
        ways: 2,
      );
      expect(plan.parts[0].amount, 60);
      expect(plan.parts[1].amount, 40);
      expect(plan.parts[0].itemQuantities, {1: 2.0});
    });

    test('بندٌ بلا صاحبٍ يُرفض', () {
      expect(
          () => SplitPlan.byItems(
              items: items, assignment: {1: 0}, ways: 2),
          throwsA(isA<SplitPlanException>()));
    });

    test('صاحبٌ خارج النطاق يُرفض', () {
      expect(
          () => SplitPlan.byItems(
              items: items, assignment: {1: 0, 2: 5}, ways: 2),
          throwsA(isA<SplitPlanException>()));
    });

    test('تُصدر فواتيرَ منفصلة', () {
      final plan = SplitPlan.byItems(
          items: items, assignment: {1: 0, 2: 1}, ways: 2);
      expect(plan.producesSeparateInvoices, isTrue);
    });
  });
}
