// ═══════════════════════════════════════════════════════════════════════════
// «منع تراكم الأصناف» — يخص أصناف الميزان وحدها
// ═══════════════════════════════════════════════════════════════════════════
//
// الباج اللي الاختبار ده موجود عشانه: الإعداد كان **مقلوب** في التطبيق.
//
// كل مسارات الإضافة (اللمس والباركود) كانت بتمرّر قيمة الإعداد كما هي في
// `forceNewEntry` لكل الأصناف. وفي نفس الوقت `AddToCartUseCase` فيها شرط
// `(!isSoldByWeight || mergeWeight)` اللي بيمنع دمج أصناف الميزان أصلاً —
// ومسار اللمس مكانش بيمرّر `mergeWeight` خالص.
//
// النتيجة: الإعداد **مالوش أي أثر** على أصناف الميزان (اللي هو مخصوص
// ليها)، وكل أثره وقع على أصناف العدد والحبة (اللي المفروض تتراكم دايماً).
// يعني كاشير بيدوس على نفس زجاجة المية مرتين كان بيلاقي سطرين.
//
// الاختبار ده بيثبّت المصفوفة الصح: الميزان بيتأثر بالإعداد، والعدد بيتراكم
// دايماً مهما كان الإعداد.
// ═══════════════════════════════════════════════════════════════════════════

import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/domain/entities/cart_item_entity.dart';
import 'package:ural_erp/domain/usecases/sales/add_to_cart_usecase.dart';

void main() {
  group('resolveStackingFlags', () {
    test('ميزان + الإعداد مفعّل → سطر جديد', () {
      final flags = resolveStackingFlags(
        isSoldByWeight: true,
        preventStacking: true,
      );
      expect(flags.forceNewEntry, isTrue);
      expect(flags.mergeWeight, isFalse);
    });

    test('ميزان + الإعداد مغلق → يتراكم', () {
      final flags = resolveStackingFlags(
        isSoldByWeight: true,
        preventStacking: false,
      );
      expect(flags.forceNewEntry, isFalse);
      // لازم `mergeWeight` تبقى true، لأن شرط الـ use case بيمنع دمج
      // الميزان من غيرها — سيبها false معناها الإعداد مالوش أثر تاني.
      expect(flags.mergeWeight, isTrue);
    });

    test('عدد + الإعداد مفعّل → يتراكم برضه (جوهر الإصلاح)', () {
      final flags = resolveStackingFlags(
        isSoldByWeight: false,
        preventStacking: true,
      );
      expect(flags.forceNewEntry, isFalse);
      expect(flags.mergeWeight, isFalse);
    });

    test('عدد + الإعداد مغلق → يتراكم', () {
      final flags = resolveStackingFlags(
        isSoldByWeight: false,
        preventStacking: false,
      );
      expect(flags.forceNewEntry, isFalse);
      expect(flags.mergeWeight, isFalse);
    });
  });

  // ── السلوك الفعلي على السلة ────────────────────────────────────────────
  //
  // الاختبارات فوق بتتحقق من الأعلام. دي بتتحقق إن الأعلام دي فعلاً بتنتج
  // السلوك المطلوب لما تعدّي على الـ use case — عشان لو حد غيّر شرط الدمج
  // جوه الـ use case الاختبار يقع.

  group('AddToCartUseCase مع الأعلام المحسوبة', () {
    final useCase = AddToCartUseCase();

    List<CartItemEntity> addTwice({
      required bool isSoldByWeight,
      required bool preventStacking,
      double quantity = 1,
    }) {
      final flags = resolveStackingFlags(
        isSoldByWeight: isSoldByWeight,
        preventStacking: preventStacking,
      );
      var cart = <CartItemEntity>[];
      for (var i = 0; i < 2; i++) {
        cart = useCase.execute(
          currentCart: cart,
          productId: 7,
          productName: 'صنف تجريبي',
          productCode: 'P7',
          unitPrice: 10,
          quantity: quantity,
          isSoldByWeight: isSoldByWeight,
          forceNewEntry: flags.forceNewEntry,
          mergeWeight: flags.mergeWeight,
        );
      }
      return cart;
    }

    test('صنف عدد يتراكم في سطر واحد حتى والإعداد مفعّل', () {
      final cart = addTwice(isSoldByWeight: false, preventStacking: true);
      expect(cart, hasLength(1));
      expect(cart.single.quantity, 2);
    });

    test('صنف عدد يتراكم والإعداد مغلق', () {
      final cart = addTwice(isSoldByWeight: false, preventStacking: false);
      expect(cart, hasLength(1));
      expect(cart.single.quantity, 2);
    });

    test('صنف ميزان يعمل سطرين والإعداد مفعّل', () {
      final cart =
          addTwice(isSoldByWeight: true, preventStacking: true, quantity: 0.5);
      expect(cart, hasLength(2));
      expect(cart[0].quantity, 0.5);
      expect(cart[1].quantity, 0.5);
    });

    test('صنف ميزان يتراكم في سطر واحد والإعداد مغلق', () {
      final cart =
          addTwice(isSoldByWeight: true, preventStacking: false, quantity: 0.5);
      expect(cart, hasLength(1));
      expect(cart.single.quantity, 1.0);
    });
  });
}
