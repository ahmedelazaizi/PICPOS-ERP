// ═══════════════════════════════════════════════════════════════════════════
// 3-3 — العرض التلقائي كان بيدمّر سطر الخصم اليدوي، والعميل بيتحمّل زيادة
// ═══════════════════════════════════════════════════════════════════════════
//
// السلة بتفرّق بين نوعين من سطور العروض:
//   • `عرض:`         — اتطبّق تلقائياً، والجولة الجاية بتصفّره وتعيد حسابه.
//   • `عرض (يدوي):`  — الكاشير/المدير طبّقه بإيده، **ومفروض ما يتلمسش**.
//
// `isAutoApplied` (cart_controller.dart:522-530) بيعلن القرار ده صراحةً
// (يدوي ⇒ اتركه)، و`cartQtyMap` (:640) بيعلنه تاني (السطور اليدوية مش مؤهّلة
// ككمية أساس). لكن حلقات **التطبيق** الخمسة كانت بتسأل السؤال بفلتر أضيق —
// `startsWith('عرض:')` بس — و`'عرض (يدوي):'` **ما بيبدأش** بـ`'عرض:'`
// (بعد «عرض» بييجي « (» مش «:»). فالسطر اليدوي كان بيعدّي من الفلتر كأنه
// سطر أساس عادي.
//
// النتيجة عطلين في نفس اللحظة:
//   ١. العرض التلقائي بيكتب فوق السطر اليدوي: سعره بيتغيّر وملاحظته بتتحوّل
//      لـ`عرض:` ⇒ الجولة الجاية بتعتبره تلقائي وبترجّعه لسعر الأساس،
//      **فالخصم اليدوي يتدمّر نهائياً** والعميل يدفع زيادة.
//   ٢. الكمية اللي أهّلت العرض أصلاً (سطر الأساس) بتفضل من غير عرض، لأن
//      الحلقة استهلكت حصّتها على السطر اليدوي الغلط.
//
// الوصول ضيّق لكنه حقيقي: محتاج سطر يدوي قبل كمية أساس، و`AddToCartUseCase`
// بيدمج عادةً فيمنع الترتيب ده — **لكن الدمج بيترفض للأصناف الموزونة**
// (مطاعم/أغذية) وللسطر المعدَّل سعره، وهو بالظبط حال السطر اليدوي.

import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/providers/providers.dart';
import 'package:ural_erp/domain/entities/product_entity.dart';
import 'package:ural_erp/domain/repositories/offers_repository.dart';
import 'package:ural_erp/presentation/pos/providers/cart_controller.dart';

/// يفرّغ طابور الأحداث — نفس أسلوب pos_offers_known_defects_repro_test.dart.
/// الجولة بتقرا الأصناف من القاعدة فعلاً، فمحتاجة دورات أكتر من مجرد تكملة
/// Future جاهزة.
Future<void> _settle() async {
  for (var i = 0; i < 60; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

class _OffersRepo implements IOffersRepository {
  _OffersRepo(this.offers, this.items);

  final List<Offer> offers;
  final List<OfferItem> items;

  @override
  Future<List<Offer>> getActiveOffers() async => offers;

  @override
  Future<List<OfferItem>> getOfferItems(int offerId) async => items;

  @override
  bool isOfferWithinTimeWindow(Offer offer) => true;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

Offer _offer({
  int id = 1,
  String name = 'حزمة الشاي',
  double offerPrice = 6,
  String offerType = 'bundle',
}) =>
    Offer(
      id: id,
      name: name,
      offerPrice: offerPrice,
      isActive: true,
      createdAt: DateTime(2026),
      offerType: offerType,
      currentUses: 0,
      isGlobal: true,
    );

ProductEntity _product({required int id, double salePrice = 10}) =>
    ProductEntity(
      id: id,
      code: 'A1',
      name: 'شاي',
      salePrice: salePrice,
      costPrice: 5,
      currentStock: 100, // موجب عشان حارس «غير متوفر» ما يرفضش الإضافة
      minStock: 0,
      taxRate: 0,
    );

void main() {
  group('3-3 — السطر اليدوي محمي من العرض التلقائي', () {
    late AppDatabase db;
    late ProviderContainer container;
    late CartController cart;
    late ProductEntity a;
    late Offer manualOffer;

    const salePrice = 10.0;
    // العرض اليدوي أرخص من التلقائي عن قصد: لو الاتنين بنفس السعر، تأكيد
    // السعر ما بيفرّقش بين «السطر اتحمى» و«السطر اتكتب فوقه بنفس القيمة».
    const manualOfferPrice = 4.0;
    const autoOfferPrice = 6.0;

    setUp(() async {
      db = AppDatabase.forTesting();

      // الصنف لازم يبقى في القاعدة: `_applyBundleOffer` بتقرا سعر البيع منها
      // عن طريق `getProductById`؛ لو مش موجود العرض ما بيتطبّقش خالص
      // والاختبار يبقى بيعدّي على كود فاضي.
      final productId = await db.into(db.products).insert(
            ProductsCompanion.insert(
              code: 'A1',
              name: 'شاي',
              salePrice: const Value(salePrice),
            ),
          );
      a = _product(id: productId);

      // العرض اليدوي لازم يكون في القاعدة فعلاً: `applyOffer` بيمرّ على
      // `CartPricingService.calculateOfferItems` اللي بيقرا `getOfferItems`
      // و`getProductsByIds` من `databaseProvider` مباشرةً — مش من مستودع
      // العروض. مستودع وهمي هنا كان هيخلّي `applyOffer` يرجع noItems
      // والسطر اليدوي ما يتخلقش أصلاً.
      final manualOfferId = await db.into(db.offers).insert(
            OffersCompanion.insert(
              name: 'خصم المدير',
              offerPrice: manualOfferPrice,
            ),
          );
      await db.into(db.offerItems).insert(
            OfferItemsCompanion.insert(
              offerId: manualOfferId,
              productId: productId,
              quantity: 1,
            ),
          );
      manualOffer = _offer(
        id: manualOfferId,
        name: 'خصم المدير',
        offerPrice: manualOfferPrice,
      );

      container = ProviderContainer(overrides: [
        databaseProvider.overrideWithValue(db),
        // مستودع العروض بيغذّي المسار **التلقائي** بس.
        offersRepositoryProvider.overrideWithValue(
          _OffersRepo(
            [_offer(id: 999, name: 'حزمة الشاي', offerPrice: autoOfferPrice)],
            [OfferItem(id: 1, offerId: 999, productId: productId, quantity: 1)],
          ),
        ),
        posDefaultTaxRateProvider.overrideWith((ref) async => 0.0),
        enableNegativeSalesProvider.overrideWith((ref) async => false),
      ]);
      cart = container.read(cartControllerProvider.notifier);

      addTearDown(() async {
        container.dispose();
        await db.close();
      });
    });

    List<({double qty, double price, String? note})> lines() => container
        .read(cartControllerProvider)
        .items
        .map((i) => (qty: i.quantity, price: i.effectivePrice, note: i.note))
        .toList();

    /// يبني الحالة الواقعية: سطر خصم يدوي **قبل** سطر أساس لنفس الصنف.
    Future<void> buildCart() async {
      // سطر ٠ — يدوي، عن طريق المسار الحقيقي `applyOffer` (هو اللي بيكتب
      // `note: 'عرض (يدوي): ...'` على الكيان مباشرةً). `updateItemNote`
      // **ما ينفعش** هنا: هو بيمرّ على `composeCartItemNote` اللي بيسبق
      // الملاحظة بـ'📝 ' فالبادئة تتكسر والسطر يبقى مش يدوي أصلاً.
      final outcome = await cart.applyOffer(manualOffer);
      expect(outcome, ApplyOfferOutcome.added,
          reason: 'تجهيزة: العرض اليدوي لازم يتضاف فعلاً');

      // سطر ١ — أساس: هو ده اللي بيأهّل الحزمة (`cartQtyMap` بيعدّه لوحده).
      // `forceNewEntry` عشان الترتيب يبقى مضبوط بالبرهان مش بالاعتماد على
      // قواعد الدمج — والدمج مرفوض أصلاً للسطر المعدَّل سعره وللموزون.
      cart.addItem(a, forceNewEntry: true);

      // ── تأكيدات التجهيزة لازم تتقاس **قبل** الـsettle ──────────────────
      // `addItem` بيشغّل جولة تطبيق تلقائي، والجولة دي هي نفسها اللي بنصطادها.
      // لو قِسنا التجهيزة بعد الـsettle، العطل بيكون ضرب خلاص والتأكيد يقع
      // هنا — فيبان كأنه تجهيزة بايظة ويخبّي العطل الحقيقي. هنا لسه الجولة
      // ما كمّلتش (كلها async)، فالحالة دي هي المدخل الصافي.
      final pre = lines();
      expect(pre.length, 2, reason: 'تجهيزة: لازم سطرين منفصلين مش سطر مدموج');
      expect(pre[0].note, startsWith('عرض (يدوي):'),
          reason: 'تجهيزة: السطر الأول لازم يكون سطر عرض يدوي');
      expect(pre[0].price, closeTo(manualOfferPrice, 0.0005),
          reason: 'تجهيزة: السطر اليدوي اتسعّر بسعر العرض اليدوي');
      expect(pre[1].note, isNot(startsWith('عرض')),
          reason: 'تجهيزة: السطر التاني أساس مش سطر عرض');

      await _settle();
    }

    test('العرض التلقائي ما بيكتبش فوق سعر السطر اليدوي', () async {
      await buildCart();

      cart.autoApplyMatchingOffers();
      await _settle();

      final manual = lines()[0];
      expect(manual.price, closeTo(manualOfferPrice, 0.0005),
          reason: 'الخصم اليدوي اتدمّر — العميل هيتحمّل زيادة');
    });

    test('العرض التلقائي ما بيغيّرش ملاحظة السطر اليدوي لـ«عرض:»', () async {
      await buildCart();

      cart.autoApplyMatchingOffers();
      await _settle();

      // ده أخطر من السعر: لو الملاحظة اتحوّلت لـ`عرض:` فالجولة الجاية
      // هتعتبر السطر تلقائي وترجّعه لسعر الأساس ⇒ الخصم يضيع نهائياً.
      expect(lines()[0].note, startsWith('عرض (يدوي):'),
          reason: 'السطر اليدوي اتصنّف تلقائي ⇒ الجولة الجاية هتصفّره');
    });

    test('السطر اليدوي بيفضل يدوي بعد جولتين متتاليتين', () async {
      await buildCart();

      cart.autoApplyMatchingOffers();
      await _settle();
      cart.autoApplyMatchingOffers();
      await _settle();

      final manual = lines()[0];
      expect(manual.note, startsWith('عرض (يدوي):'));
      expect(manual.price, closeTo(manualOfferPrice, 0.0005),
          reason: 'الجولة التانية رجّعت السطر لسعر الأساس — الخصم اتمسح');
    });

    test('العرض بيتطبّق على سطر الأساس اللي أهّله فعلاً', () async {
      await buildCart();

      cart.autoApplyMatchingOffers();
      await _settle();

      // العطل التاني: الحلقة كانت بتستهلك حصّة العرض على السطر اليدوي الغلط،
      // فالسطر اللي أهّل العرض أصلاً يفضل بسعر الأساس.
      final base = lines()[1];
      expect(base.price, closeTo(autoOfferPrice, 0.0005),
          reason: 'الكمية أهّلت العرض لكن العرض راح لسطر تاني');
      // بلا لاحقة مضاعِف: سطر أساس واحد أهّل **طقم واحد**. `x2` معناها إن
      // السطر اليدوي اتعدّ ككمية أساس كمان ⇒ خصم مضاعَف على حساب المحل.
      expect(base.note, 'عرض: حزمة الشاي',
          reason: 'المضاعِف اتحسب من كمية مش مؤهّلة');
    });

    test('recalculateAllPrices ما بيمسحش الخصم اليدوي عند تغيير مستوى السعر',
        () async {
      await buildCart();

      // نفس عدم التطابق كان في `recalculateAllPrices` كمان: توثيقها بيقول
      // إنها بتتخطّى السطور «اللي جزء من عرض»، وسطر العرض اليدوي جزء من عرض
      // بالتعريف — لكن الفلتر كان بيشوف التلقائي بس.
      await cart.recalculateAllPrices();
      await _settle();

      final manual = lines()[0];
      expect(manual.note, startsWith('عرض (يدوي):'));
      expect(manual.price, closeTo(manualOfferPrice, 0.0005),
          reason: 'إعادة حساب الأسعار رجّعت السطر اليدوي لسعر الأساس');
    });
  });
}
