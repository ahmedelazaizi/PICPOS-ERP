// حوار «تكلفة الصنف غير معروفة» + منطق إعادة المحاولة بالتكلفة المؤقتة.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/data/database/sale_cost_resolver.dart'
    show CostRequiredException;
import 'package:picpos_erp/domain/entities/cart_item_entity.dart';
import 'package:picpos_erp/presentation/pos_picpos/widgets/picpos_cost_required_dialog.dart';

void main() {
  group('الحوار', () {
    Future<void> open(WidgetTester tester, List<double?> out) async {
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (ctx) => Scaffold(
            body: TextButton(
              onPressed: () async => out
                  .add(await showCostRequiredDialog(ctx, productName: 'سكر')),
              child: const Text('open'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    testWidgets('يعرض الرسالة بالاسم والحقل فارغ (لا سعر بيع افتراضي)',
        (tester) async {
      await open(tester, []);
      expect(
          find.text('تكلفة الصنف غير معروفة: سكر — أدخل تكلفة الوحدة لإكمال البيع'),
          findsOneWidget);
      final field =
          tester.widget<TextField>(find.byKey(const Key('cost_required_field')));
      expect(field.controller!.text, isEmpty);
    });

    testWidgets('قيمة > 0 تُقبل (وتقبل الأرقام العربية)', (tester) async {
      final out = <double?>[];
      await open(tester, out);
      await tester.enterText(
          find.byKey(const Key('cost_required_field')), '٧٫٥');
      await tester.tap(find.byKey(const Key('cost_required_confirm')));
      await tester.pumpAndSettle();
      expect(out, [7.5]);
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets('0 والفارغ يُرفضان ويبقى الحوار مفتوحاً', (tester) async {
      final out = <double?>[];
      await open(tester, out);
      for (final v in ['0', '0.00', '']) {
        await tester.enterText(find.byKey(const Key('cost_required_field')), v);
        await tester.tap(find.byKey(const Key('cost_required_confirm')));
        await tester.pump();
        expect(find.text('أدخل تكلفة أكبر من صفر'), findsOneWidget, reason: v);
        expect(find.byType(AlertDialog), findsOneWidget);
      }
      expect(out, isEmpty);
    });

    testWidgets('الإلغاء يرجع null', (tester) async {
      final out = <double?>[];
      await open(tester, out);
      await tester.tap(find.byKey(const Key('cost_required_cancel')));
      await tester.pumpAndSettle();
      expect(out, [null]);
    });
  });

  group('parseProvisionalCost', () {
    test('> 0 فقط', () {
      expect(parseProvisionalCost('5'), 5);
      expect(parseProvisionalCost('0'), isNull);
      expect(parseProvisionalCost('-3'), isNull);
      expect(parseProvisionalCost('abc'), isNull);
      expect(parseProvisionalCost(null), isNull);
    });
  });

  group('provisionalCostPerBase', () {
    const carton = CartItemEntity(
        productId: 1,
        productName: 'x',
        productCode: 'x',
        quantity: 1,
        unitPrice: 100,
        quantityInBase: 12);
    test('تُقسَم على معامل الوحدة', () {
      expect(provisionalCostPerBase([carton], 1, 60), 5);
      expect(provisionalCostPerBase([carton], 2, 60), 60);
    });
  });

  group('saveWithCostRetry', () {
    test('ينجح من أول مرة بلا سؤال', () async {
      var asked = 0;
      final r = await saveWithCostRetry(
        attempt: (_) async => true,
        pendingCost: () => null,
        askCost: (_) async {
          asked++;
          return 1;
        },
      );
      expect(r, CostRetryResult.saved);
      expect(asked, 0);
    });

    test('يسأل ثم يعيد بالتكلفة المؤقتة لذلك الصنف', () async {
      final seen = <Map<int, double>>[];
      CostRequiredException? pending;
      final r = await saveWithCostRetry(
        attempt: (costs) async {
          seen.add(Map.of(costs));
          if (costs.containsKey(7)) return true;
          pending = CostRequiredException(7, 'سكر');
          return false;
        },
        pendingCost: () => pending,
        askCost: (e) async => e.productId == 7 ? 4.25 : null,
      );
      expect(r, CostRetryResult.saved);
      expect(seen, [<int, double>{}, {7: 4.25}]);
    });

    test('صنفان: يسأل عن كلٍّ ويراكم التكاليف', () async {
      final seen = <Map<int, double>>[];
      CostRequiredException? pending;
      final r = await saveWithCostRetry(
        attempt: (costs) async {
          seen.add(Map.of(costs));
          for (final id in [1, 2]) {
            if (!costs.containsKey(id)) {
              pending = CostRequiredException(id, 'p$id');
              return false;
            }
          }
          return true;
        },
        pendingCost: () => pending,
        askCost: (e) async => e.productId * 10.0,
      );
      expect(r, CostRetryResult.saved);
      expect(seen.last, {1: 10.0, 2: 20.0});
    });

    test('الإلغاء ⇒ cancelled ولا محاولة ثانية', () async {
      var attempts = 0;
      final r = await saveWithCostRetry(
        attempt: (_) async {
          attempts++;
          return false;
        },
        pendingCost: () => CostRequiredException(7, 'سكر'),
        askCost: (_) async => null,
      );
      expect(r, CostRetryResult.cancelled);
      expect(attempts, 1);
    });

    test('فشلٌ لسبب آخر ⇒ failed بلا سؤال', () async {
      var asked = false;
      final r = await saveWithCostRetry(
        attempt: (_) async => false,
        pendingCost: () => null,
        askCost: (_) async {
          asked = true;
          return 1;
        },
      );
      expect(r, CostRetryResult.failed);
      expect(asked, isFalse);
    });

    test('نفس الصنف يُرفض رغم التكلفة ⇒ failed (لا حلقة)', () async {
      var attempts = 0;
      final r = await saveWithCostRetry(
        attempt: (_) async {
          attempts++;
          return false;
        },
        pendingCost: () => CostRequiredException(7, 'سكر'),
        askCost: (_) async => 3,
      );
      expect(r, CostRetryResult.failed);
      expect(attempts, 2);
    });
  });
}
