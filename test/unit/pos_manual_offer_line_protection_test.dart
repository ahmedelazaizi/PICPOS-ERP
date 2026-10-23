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
// ⚠️ **تصحيح**: نسخة أولى من الملف ده قالت إن «الوصول ضيّق لكنه حقيقي»
// وإن الدمج بيترفض للسطر المعدَّل سعره. **الاتنين غلط**، ومراجعة مستقلة
// أثبتت العكس:
//
//   ١. `add_to_cart_usecase.dart:66-73` بيلغي شرط تطابق السعر عن قصد لما
//      السطر الموجود سطر عرض (`existingIsAnyOffer`). فالسطر اليدوي **بيبلع**
//      السحبات اللاحقة بدل ما يرفض الدمج.
//   ٢. الأهم: `_applyPercentageOffer` و`_applyFixedDiscountOffer` **مالهمش
//      ميزانية كمية** — بيلفّوا على كل السطور وبيطبّقوا على كل مطابقة. يعني
//      ما يهمّهمش الترتيب ولا الدمج ولا وجود سطر أساس أصلاً.
//
// فالوصول **واسع ويومي**: الكاشير يمسح باركود عرض (سطر يدوي)، يسحب أي صنف
// تاني (بيشغّل الجولة)، وأي عرض نسبي نشِط على نفس الفئة بيمسح الخصم اليدوي.
// مجموعة «المسار النسبي» تحت بتغطّي الحالة دي بالظبط.


import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/data/providers/providers.dart';
import 'package:picpos_erp/domain/entities/product_entity.dart';
import 'package:picpos_erp/domain/repositories/offers_repository.dart';
import 'package:picpos_erp/presentation/pos/providers/cart_controller.dart';

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

ProductEntity _product({
  required int id,
  String code = 'A1',
  String name = 'شاي',
  double salePrice = 10,
  bool isSoldByWeight = true,
  int? categoryId,
}) =>
    ProductEntity(
      id: id,
      code: code,
      name: name,
      salePrice: salePrice,
      costPrice: 5,
      currentStock: 100, // موجب عشان حارس «غير متوفر» ما يرفضش الإضافة
      minStock: 0,
      taxRate: 0,
      // ── ليه موزون افتراضياً ────────────────────────────────────────────
      // عشان السطر الجديد يتخلق **بالمسار الإنتاجي الحقيقي**. كل نقاط
      // النداء بتمرّر `forceNewEntry: isSoldByWeight && preventStacking`
      // (`add_to_cart_usecase.dart:25`)، فتركيبة «معدود + forceNewEntry»
      // مستحيلة إنتاجياً. للصنف الموزون بـ`mergeWeight: false` (الافتراضي)
      // شرط الدمج في `:69` بيرجع false ⇒ سطر جديد بيتضاف بعد السطر اليدوي.
      // ودي الحالة الطبيعية في المطاعم/الأغذية.
      isSoldByWeight: isSoldByWeight,
      categoryId: categoryId,
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
              // لازم يطابق الكيان: `applyOffer` بيبني السطر اليدوي من صف
              // القاعدة (`product.isSoldByWeight`).
              isSoldByWeight: const Value(true),
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
      // بلا أي علم اصطناعي: الصنف موزون و`mergeWeight` افتراضياً false،
      // فـ`AddToCartUseCase` بيرفض الدمج ويضيف سطراً جديداً — نفس ما بيحصل
      // على تلّ مطعم/سوبرماركت.
      cart.addItem(a);

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

    test('تغيير مستوى السعر ما بيمسحش الخصم اليدوي', () async {
      await buildCart();

      // صنف تالت مش في أي عرض — **ضابط حيّ**: بيثبت إن حلقة إعادة الحساب
      // اشتغلت فعلاً. من غيره الاختبار كان بيعدّي وهو فاضي: كل سطور السلة
      // سطور عرض ⇒ الحلقة بتعمل `continue` على الكل ⇒ `changed == false` ⇒
      // مفيش كتابة على `state` خالص، والتأكيدات بتعيد قراءة حالة قديمة.
      final plainId = await db.into(db.products).insert(
            ProductsCompanion.insert(
              code: 'B1',
              name: 'سكر',
              salePrice: const Value(20),
              wholesalePrice: const Value(12),
            ),
          );
      final plain = _product(
          id: plainId,
          code: 'B1',
          name: 'سكر',
          salePrice: 20,
          isSoldByWeight: false);
      cart.addItem(plain);
      await _settle();

      // المسار الحقيقي: `setPriceLevel` هو اللي بينده `recalculateAllPrices`.
      cart.setPriceLevel('wholesale');
      await _settle();

      final plainLine = lines().firstWhere((l) => l.note == null && l.price != manualOfferPrice);
      expect(plainLine.price, closeTo(12, 0.0005),
          reason: 'الضابط: الحلقة لازم تكون اشتغلت وكتبت فعلاً');

      final manual = lines()[0];
      expect(manual.note, startsWith('عرض (يدوي):'));
      expect(manual.price, closeTo(manualOfferPrice, 0.0005),
          reason: 'إعادة حساب الأسعار رجّعت السطر اليدوي لسعر الأساس');
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  // المسار النسبي — هنا الوصول **واسع ويومي**، مش ضيّق
  //
  // `_applyPercentageOffer` مالهوش ميزانية كمية: بيلفّ على كل السطور وبيطبّق
  // على كل مطابقة. فما بيحتاجش ترتيباً معيّناً ولا سطر أساس ولا صنفاً موزوناً.
  // سطر يدوي **لوحده** في السلة + أي سحبة تشغّل الجولة = الخصم اليدوي يتمسح.
  // ═════════════════════════════════════════════════════════════════════════
  group('3-3 — المسار النسبي: سطر يدوي لوحده يكفي', () {
    late AppDatabase db;
    late ProviderContainer container;
    late CartController cart;
    late Offer manualOffer;
    late ProductEntity other;

    const manualOfferPrice = 4.0;

    setUp(() async {
      db = AppDatabase.forTesting();

      final categoryId = await db.into(db.categories).insert(
            CategoriesCompanion.insert(name: 'مشروبات'),
          );
      final teaId = await db.into(db.products).insert(
            ProductsCompanion.insert(
              code: 'A1',
              name: 'شاي',
              salePrice: const Value(10),
              categoryId: Value(categoryId),
            ),
          );
      // صنف تاني — سحبته هي اللي بتشغّل الجولة، زي أي صنف على التلّ.
      final otherId = await db.into(db.products).insert(
            ProductsCompanion.insert(
              code: 'Z9',
              name: 'ماء',
              salePrice: const Value(5),
            ),
          );
      other = _product(id: otherId, code: 'Z9', name: 'ماء', salePrice: 5,
          isSoldByWeight: false);

      final manualOfferId = await db.into(db.offers).insert(
            OffersCompanion.insert(
                name: 'خصم المدير', offerPrice: manualOfferPrice),
          );
      await db.into(db.offerItems).insert(
            OfferItemsCompanion.insert(
                offerId: manualOfferId, productId: teaId, quantity: 1),
          );
      manualOffer = _offer(
          id: manualOfferId, name: 'خصم المدير', offerPrice: manualOfferPrice);

      container = ProviderContainer(overrides: [
        databaseProvider.overrideWithValue(db),
        offersRepositoryProvider.overrideWithValue(
          _OffersRepo(
            [
              Offer(
                id: 555,
                name: 'خصم الفئة',
                offerPrice: 0,
                isActive: true,
                createdAt: DateTime(2026),
                offerType: 'percentage',
                discountValue: 20,
                categoryId: categoryId,
                currentUses: 0,
                isGlobal: true,
              ),
            ],
            const [],
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

    test('عرض نسبي على نفس الفئة ما بيلمسش سطر الخصم اليدوي', () async {
      expect(await cart.applyOffer(manualOffer), ApplyOfferOutcome.added,
          reason: 'تجهيزة: السطر اليدوي اتضاف');

      // سحبة صنف تاني — ده كل اللي محتاجينه عشان الجولة تشتغل.
      cart.addItem(other);
      await _settle();

      final tea = container
          .read(cartControllerProvider)
          .items
          .firstWhere((i) => i.productName == 'شاي');

      expect(tea.note, startsWith('عرض (يدوي):'),
          reason: 'العرض النسبي حوّل السطر اليدوي لتلقائي');
      expect(tea.effectivePrice, closeTo(manualOfferPrice, 0.0005),
          reason: 'العرض النسبي ضرب ٢٠٪ فوق الخصم اليدوي — خصم على خصم');
    });

    // ═══════════════════════════════════════════════════════════════════════
    // تعليق الطلب واسترجاعه — كان بيهدم الحماية كلها
    //
    // `_serializeCartItemMeta` بتسلسل `modifiers` و`itemNote` بس؛ `item.note`
    // (اللي فيه بادئة العرض) مش موجود فيها خالص، والاسترجاع ما بيحطّهوش.
    // بينما `customPrice` **بيتحفظ**. فالسطر اليدوي بيرجع بسعر العرض وبملاحظة
    // `null` ⇒ سطر أساس عادي في عين الفلاتر الستة كلها ⇒ يتعدّ ككمية مؤهّلة
    // ويتخصم فوق خصمه ويترجّع لسعر المستوى.
    //
    // ودي مش حالة حافة: تعليق/استرجاع مسار كاشير يومي.
    // ═══════════════════════════════════════════════════════════════════════
    test('تعليق الطلب واسترجاعه بيحافظ على ملاحظة العرض اليدوي', () async {
      expect(await cart.applyOffer(manualOffer), ApplyOfferOutcome.added,
          reason: 'تجهيزة: السطر اليدوي اتضاف');
      final before = container
          .read(cartControllerProvider)
          .items
          .firstWhere((i) => i.productName == 'شاي');
      expect(before.note, startsWith('عرض (يدوي):'), reason: 'تجهيزة');

      final holdNum = await cart.holdOrder();
      expect(holdNum, isNotNull, reason: 'تجهيزة: الطلب اتعلّق');

      final held = await db.select(db.heldOrders).get();
      expect(held, hasLength(1), reason: 'تجهيزة: صف طلب معلّق واحد');

      await cart.retrieveHeldOrder(held.first.id);
      await _settle();

      final after = container
          .read(cartControllerProvider)
          .items
          .firstWhere((i) => i.productName == 'شاي');

      expect(after.effectivePrice, closeTo(manualOfferPrice, 0.0005),
          reason: 'تجهيزة: السعر بيتحفظ أصلاً — المشكلة في الملاحظة');
      expect(after.note, startsWith('عرض (يدوي):'),
          reason: 'السطر رجع بملاحظة فاضية ⇒ بقى سطر أساس عادي، '
              'وكل حماية الفلاتر الستة اتهدّت');
    });
  });
}
