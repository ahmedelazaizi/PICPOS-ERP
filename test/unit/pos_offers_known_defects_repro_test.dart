// ═══════════════════════════════════════════════════════════════════════════
// اختبارات انحدار لتلات عيوب في العروض — **العيوب دي اتصلحت**.
//
// ✅ الملف ده المفروض يعدّي أخضر بالكامل. كان أصله إعادة إنتاج حمرا (`+2 -3`)
// اتودعت قبل الإصلاح؛ دلوقتي كل اختبار هنا بيحرس إصلاح قايم. أي أحمر هنا
// **انحدار حقيقي** — رجوع للسلوك القديم، مش عطل في التجهيزة.
//
// كل مجموعة فيها اختبار **ضابط (control)** بيمسك المسار السليم اللي كان بيعدّي
// حتى قبل الإصلاح — وظيفته يفرّق بين انكسار التجهيزة وانكسار المنتج: لو الضابط
// وقع مع غيره فالمشكلة في التجهيزة نفسها.
//
// اللي بيتحرس هنا:
// * H1 — كمية بتتضاف جوّه نافذة `await` بتاعة العروض ما تضيعش، **والإعادة
//   المجدولة بتحسب وتكتب فعلاً** (`cart_controller.dart:_cartChangedSince`).
// * H2 — مجموع سطور الحزمة = سعر العرض المعلن
//   (`cart_pricing_service.dart:settleBundleRemainder`).
// * H3 — عرض سعره ≥ مجموع أسعار بيع أصنافه بيترفض برسالة، مش بيرفع الأسعار
//   (بما فيهم الحد الفاصل: سعر العرض = المجموع).
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/application/services/cart_pricing_service.dart';
import 'package:picpos_erp/core/constants/app_constants.dart';
import 'package:picpos_erp/data/providers/providers.dart';
import 'package:picpos_erp/domain/entities/product_entity.dart';
import 'package:picpos_erp/domain/repositories/offers_repository.dart';
import 'package:picpos_erp/presentation/pos/providers/cart_controller.dart';

/// يفرّغ طابور الأحداث عشان الـ Future اللي اتكمّلت تكمّل مشوارها.
/// حلقة صريحة بدل `pumpEventQueue` — مفيش widget binding في الملف ده.
/// ٦٠ دورة مش ٢٠: الإعادة المجدولة بتقرا الأصناف من قاعدة البيانات فعلاً
/// (`getProductById`)، فمحتاجة دورات أكتر من مجرد تكملة Future جاهزة.
Future<void> _settle() async {
  for (var i = 0; i < 60; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

/// مستودع عروض بيوقف `getActiveOffers()` عند بوابة يتحكّم فيها الاختبار.
///
/// ── ليه Completer مش تأخير زمني ────────────────────────────────────────────
/// التشابك اللي بنصطاده بيحصل **جوّه نافذة الـ await**. لو استنينا مدة بالوقت،
/// الاختبار يبقى بيقامر على جدولة المُشغِّل ويرفرف بين أحمر وأخضر. البوابة
/// بتخلّي الترتيب مضبوط بالمللي: إحنا اللي بنقرّر امتى العروض ترجع.
class _GatedOffersRepo implements IOffersRepository {
  _GatedOffersRepo(this.bundleItems);

  /// البوابة — `complete()` بترجّع العروض وتفكّ التطبيق التلقائي من وقفته.
  final Completer<List<Offer>> gate = Completer<List<Offer>>();

  /// أصناف العرض — **بتطابق الصنف اللي في السلة فعلاً**.
  ///
  /// كانت بترجع صنف وهمي (٩٩٩) مش في السلة، فالعرض ما كانش بيتطبّق أصلاً
  /// والاختبار يبقى بيتأكد من الكمية بس. ودي كانت ثغرة: الكمية ٢ بتيجي من
  /// `addItem` نفسها، فلو `_autoApplyOffers` مكتوبة `async {}` الاختبار
  /// **يعدّي**. دلوقتي العرض بيتطبّق فعلاً، فالتأكيد بيشوف السعر والملاحظة
  /// كمان — يعني بيفشل لو الكتابة اتشالت فوقها، **و** بيفشل لو الإعادة
  /// المجدولة ما اشتغلتش خالص.
  final List<OfferItem> bundleItems;

  @override
  Future<List<Offer>> getActiveOffers() => gate.future;

  @override
  Future<List<OfferItem>> getOfferItems(int offerId) async => bundleItems;

  @override
  bool isOfferWithinTimeWindow(Offer offer) => true;

  // باقي أعضاء الواجهة مش مستعملة في المسار ده.
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

Offer _offer({
  int id = 1,
  String name = 'عرض على صنف تاني',
  double offerPrice = 10,
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
  int id = 1,
  String code = 'A1',
  String name = 'شاي',
  double salePrice = 10,
}) =>
    ProductEntity(
      id: id,
      code: code,
      name: name,
      salePrice: salePrice,
      costPrice: 5,
      // مخزون موجب عشان حارس «غير متوفر» ما يرفضش الإضافة.
      currentStock: 100,
      minStock: 0,
      taxRate: 0,
    );

void main() {
  // ═════════════════════════════════════════════════════════════════════════
  // H1 — كمية بتتسحب أثناء انتظار العروض ما تضيعش
  //
  // السيناريو الواقعي: الكاشير بيسحب الباركود مرتين ورا بعض. أول سحبة بتشغّل
  // `_autoApplyOffers` اللي بياخد **لقطة** من السلة وبعدين بيستنى
  // `getActiveOffers()` (قراءة من القرص/الشبكة — مش لحظية). السحبة التانية
  // بتزوّد الكمية لـ٢ وهو لسه مستني.
  //
  // كان العطل: خطوة الدمج بتحافظ على الأصناف اللي **اتضافت** بعد اللقطة
  // بالمقارنة بـ`productId` بس — والصنف ده كان أصلاً في اللقطة فبيتخطّى، وحارس
  // القِدَم ما كانش بيضرب لأن `_tryAutoApplyOffers` بيرفع `_pendingAutoApply`
  // من غير ما يزوّد `_autoApplyGeneration`. النتيجة كانت `state` بترجع للكمية
  // القديمة (١) — والوحدة عمرها ما بترجع لأن الإعادة المجدولة بتلتقط لقطتها
  // بعد التشويه.
  //
  // الإصلاح: `_tryAutoApplyOffers` بيزوّد الجيل لما ينده والجولة شغّالة، فحارس
  // القِدَم يضرب والجولة القديمة ترجع من غير ما تكتب.
  // ═════════════════════════════════════════════════════════════════════════
  group('انحدار H1 — كمية أثناء انتظار العروض ما تضيعش', () {
    late AppDatabase db;
    late ProviderContainer container;
    late _GatedOffersRepo offersRepo;
    late CartController cart;
    late ProductEntity a;

    // سعر البيع ١٠ وسعر العرض ٦ → المعامل ٠٫٦ وسعر الوحدة تحت العرض ٦٫٠.
    const salePrice = 10.0;
    const offerPrice = 6.0;
    const offerUnitPrice = 6.0;

    setUp(() async {
      db = AppDatabase.forTesting();

      // الصنف لازم يبقى في القاعدة فعلاً: `_applyBundleOffer` بتقرا سعر البيع
      // عن طريق `productRepo.getProductById`، فلو مش موجود العرض ما بيتطبّقش
      // والاختبار يرجع ضعيف زي ما كان.
      final productId = await db.into(db.products).insert(
            ProductsCompanion.insert(
              code: 'A1',
              name: 'شاي',
              salePrice: const Value(salePrice),
            ),
          );
      a = _product(id: productId, salePrice: salePrice);

      offersRepo = _GatedOffersRepo([
        OfferItem(id: 1, offerId: 1, productId: productId, quantity: 1),
      ]);
      container = ProviderContainer(overrides: [
        databaseProvider.overrideWithValue(db),
        offersRepositoryProvider.overrideWithValue(offersRepo),
        posDefaultTaxRateProvider.overrideWith((ref) async => 0.0),
        enableNegativeSalesProvider.overrideWith((ref) async => false),
      ]);
      cart = container.read(cartControllerProvider.notifier);
      addTearDown(() async {
        container.dispose();
        await db.close();
      });
    });

    // بنستخرج القيم الأولية بدل ما نمرّر `CartItemEntity` — الحقول اللي تهم
    // الاختبار تلاتة بس، وكده مفيش نداء على `dynamic`.
    List<({double qty, double price, String? note})> linesOf(int productId) =>
        container
            .read(cartControllerProvider)
            .items
            .where((i) => i.productId == productId)
            .map((i) =>
                (qty: i.quantity, price: i.effectivePrice, note: i.note))
            .toList();

    double qtyOf(int productId) =>
        linesOf(productId).fold<double>(0, (acc, l) => acc + l.qty);

    /// بيتأكد إن العرض **اتطبّق فعلاً** على كل سطور الصنف.
    ///
    /// ده هو اللي بيمنع الاختبار من إنه يعدّي وهو فاضي: الكمية لوحدها بتيجي من
    /// `addItem`، فلو التطبيق التلقائي اتشال بالكامل الكمية تفضل صح. السعر
    /// والملاحظة ما بيجوش إلا لو الجولة اشتغلت **وكتبت**.
    void expectOfferApplied(int productId) {
      final lines = linesOf(productId);
      expect(lines, isNotEmpty, reason: 'الصنف اختفى من السلة');
      for (final line in lines) {
        expect(line.price, closeTo(offerUnitPrice, 0.0005),
            reason: 'سعر العرض ما اتكتبش — التطبيق التلقائي ما وصلش للكتابة');
        expect(line.note, startsWith('عرض:'),
            reason: 'ملاحظة العرض ناقصة — العرض ما اتطبّقش فعلاً');
      }
    }

    test('الضابط: من غير تشابك، سحبتين = كمية ٢ والعرض متطبّق', () async {
      cart.addItem(a);
      offersRepo.gate.complete([_offer(offerPrice: offerPrice)]);
      await _settle();
      cart.addItem(a);
      await _settle();

      expect(qtyOf(a.id), 2,
          reason: 'من غير تشابك المسار سليم — لو ده وقع فالتجهيزة هي البايظة');
      expectOfferApplied(a.id);
    });

    test('سحبة جوّه نافذة الـ await: الكمية بتفضل والعرض بيتطبّق بعدها',
        () async {
      // سحبة ١ — التطبيق التلقائي دلوقتي واقف على البوابة، ماسك لقطة «A × ١».
      cart.addItem(a);
      expect(qtyOf(a.id), 1, reason: 'تجهيزة: السحبة الأولى دخلت');
      expect(offersRepo.gate.isCompleted, isFalse,
          reason: 'تجهيزة: لازم نكون واقفين جوّه الـ await فعلاً');

      // سحبة ٢ — نفس الصنف، والتطبيق التلقائي لسه معلّق.
      cart.addItem(a);
      expect(qtyOf(a.id), 2,
          reason: 'تجهيزة: الكمية بقت ٢ فعلاً قبل ما العروض ترجع');

      // العروض رجعت → الجولة القديمة لازم ترجع من غير كتابة، والإعادة المجدولة
      // تحسب من جديد على «A × ٢».
      offersRepo.gate.complete([_offer(offerPrice: offerPrice)]);
      await _settle();

      // النص الأول: الكمية ما ضاعتش (قبل الإصلاح كانت بترجع ١).
      expect(qtyOf(a.id), 2,
          reason: 'الوحدة اللي اتسحبت أثناء انتظار العروض ضاعت من السلة');

      // النص التاني: الإعادة المجدولة اشتغلت **وكتبت**. من غير ده، استبدال
      // `_autoApplyOffers` بـ`async {}` كان بيخلّي الاختبار يعدّي.
      expectOfferApplied(a.id);
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  // H2 و H3 — تسعير العرض نفسه (CartPricingService)
  // ═════════════════════════════════════════════════════════════════════════
  group('انحدار H2 و H3 — CartPricingService.calculateOfferItems', () {
    late AppDatabase db;
    late ProviderContainer container;
    late CartPricingService service;

    setUp(() {
      db = AppDatabase.forTesting();
      container = ProviderContainer(overrides: [
        databaseProvider.overrideWithValue(db),
      ]);
      service = container.read(cartPricingServiceProvider);
      addTearDown(() async {
        container.dispose();
        await db.close();
      });
    });

    /// بيزرع أصناف بأسعار [salePrices] وعرض بسعر [offerPrice] عليهم كلهم
    /// (كمية ١ لكل صنف)، وبيرجّع صف العرض جاهز.
    Future<Offer> seedOffer({
      required List<double> salePrices,
      required double offerPrice,
      String name = 'عرض',
    }) async {
      final offerId = await db.into(db.offers).insert(
            OffersCompanion.insert(name: name, offerPrice: offerPrice),
          );
      for (var i = 0; i < salePrices.length; i++) {
        final productId = await db.into(db.products).insert(
              ProductsCompanion.insert(
                code: '$name-P$i',
                name: 'صنف $i',
                salePrice: Value(salePrices[i]),
              ),
            );
        await db.into(db.offerItems).insert(
              OfferItemsCompanion.insert(
                offerId: offerId,
                productId: productId,
                quantity: 1,
              ),
            );
      }
      return (db.select(db.offers)..where((o) => o.id.equals(offerId)))
          .getSingle();
    }

    double bundleTotal(List<PricedCartItem> items) =>
        items.fold<double>(0, (a, p) => a + p.quantity * p.customPrice);

    // ─────────────────────────────────────────────────────────────────────
    // H2 — مجموع سطور العرض لازم يساوي سعر العرض المعلن
    //
    // كان العطل: `factor = offerPrice / totalNormalPrice` وبعدين كل سطر بيتقرّب
    // **لوحده** على ٣ خانات، فالمجموع ما بيرجعش لسعر العرض (٩٫٩٩٩ بدل ١٠).
    // الزبون شايف لافتة بسعر والفاتورة بتطلع بسعر تاني.
    //
    // الإصلاح: `_settleBundleRemainder` بيوزّع باقي التقريب على السطور. الحزم
    // اللي كل كمياتها ١ (الشكل الغالب) بتوصل لمجموع مضبوط تماماً؛ والباقي
    // المتبقّي في الحالات التانية محدود ومقيس — اقرا التوثيق على الدالة.
    // ─────────────────────────────────────────────────────────────────────
    test('الضابط: عرض بيقسم بالظبط بيوصل لسعر العرض بالمليم', () async {
      // ١٠٠ + ٥٠ = ١٥٠، سعر العرض ١٢٠ → المعامل ٠٫٨ (قسمة نضيفة).
      final offer =
          await seedOffer(salePrices: [100, 50], offerPrice: 120, name: 'نضيف');
      final priced = await service.calculateOfferItems(
        ApplyOfferRequest(offer: offer),
      );

      expect(priced, hasLength(2), reason: 'تجهيزة: الخدمة رجّعت سطور العرض');
      // `closeTo` مش مساواة تامة: المجموع بيتجمّع بـdouble، فالمساواة الحرفية
      // بتعدّي بحظ الفاصلة العايمة مش بصحة الحساب. نصف مليم هو حد الخطأ اللي
      // يهم فعلاً — أقل من أصغر وحدة قابلة للطباعة.
      expect(bundleTotal(priced), closeTo(offer.offerPrice, 0.0005),
          reason: 'قسمة نضيفة لازم تجمع لسعر العرض بالظبط');
    });

    test('عرض ما بيقسمش بالظبط: المجموع بيفضل مساوي لسعر العرض المعلن', () async {
      // تلات أصناف بـ٥ للواحد = ١٥، سعر العرض ١٠ → المعامل ٠٫٦٦٦٦…
      // كل وحدة بتتقرّب لـ٣٫٣٣٣ والمجموع كان بيطلع ٩٫٩٩٩ قبل توزيع الباقي.
      final offer =
          await seedOffer(salePrices: [5, 5, 5], offerPrice: 10, name: 'تلاتة');
      final priced = await service.calculateOfferItems(
        ApplyOfferRequest(offer: offer),
      );

      expect(priced, hasLength(3), reason: 'تجهيزة: الخدمة رجّعت تلات سطور');

      final total = bundleTotal(priced);
      final drift = (total - offer.offerPrice).abs();
      printOnFailure(
        'أسعار الوحدات: ${priced.map((p) => p.customPrice).toList()}\n'
        'المجموع = $total · سعر العرض = ${offer.offerPrice} · '
        'الفرق = $drift (بخانات العملة = ${AppConstants.decimalPlaces})',
      );

      // قبل الإصلاح: ٩٫٩٩٩ مش ١٠. الفرق كان مليم كامل — أكبر بـ٢× من هامش
      // الـ`closeTo` هنا، فالتأكيد لسه بيمسك الانحدار من غير ما يعتمد على حظ
      // الفاصلة العايمة.
      expect(total, closeTo(offer.offerPrice, 0.0005),
          reason: 'مجموع سطور العرض لازم يساوي سعر العرض المعلن — الفرق $drift');

      // وكمان: توزيع الباقي ممنوع يطلّع أي سطر فوق سعر بيعه. هنا التأكيد ده
      // بيعضّ فعلاً (٣٫٣٣٤ مقابل ٥) — مش زي المجموعة المرفوضة تحت اللي
      // بترجع فاضية.
      for (final p in priced) {
        expect(p.customPrice, lessThanOrEqualTo(p.product.salePrice),
            reason: 'تصحيح الباقي رفع ${p.product.name} فوق سعر بيعه');
      }
    });

    // ─────────────────────────────────────────────────────────────────────
    // H3 — عرض متظبّط غلط لازم يترفض، مش يرفع الأسعار
    //
    // كان العطل: مفيش حارس إن `offerPrice < totalNormalPrice`، فعرض بسعر أعلى
    // من مجموع أسعار أصنافه بيدّي معامل > ١ وكل سطر بيتسعّر **أغلى** من سعر
    // بيعه العادي. الزبون بياخد «عرض» بيغرّمه.
    //
    // الحارس كان موجود بالحرف في `apply_offers_usecase.dart:70` — بس الـ use
    // case دي ميتة، والمسار الحيّ ورث الشرط الناقص بس.
    //
    // الإصلاح عند **التطبيق** مش عند الإنشاء بس: `salePrice` ممكن ينزل على جهاز
    // تاني بعد ما العرض اتحفظ، فعرض سليم يوصل مقلوب بعد المزامنة. والرفض بيتبلّغ
    // (`onRejected`) عشان الكاشير يعرف السبب بدل no-op صامت.
    // ─────────────────────────────────────────────────────────────────────
    test('عرض سعره أعلى من مجموع أصنافه بيترفض ومش بيرفع الأسعار', () async {
      // تلات أصناف بـ٥ = ١٥، وسعر العرض ٣٠ → المعامل كان هيبقى ٢٫٠.
      final offer =
          await seedOffer(salePrices: [5, 5, 5], offerPrice: 30, name: 'مقلوب');

      OfferRejection? rejection;
      final priced = await service.calculateOfferItems(
        ApplyOfferRequest(offer: offer),
        onRejected: (r) => rejection = r,
      );

      printOnFailure(
        'سعر البيع العادي = ٥ لكل صنف · '
        'أسعار العرض الراجعة = ${priced.map((p) => p.customPrice).toList()}',
      );

      // قبل الإصلاح كانت بترجع تلات سطور بـ١٠ للوحدة — ضِعف سعر البيع.
      // الإصلاح بيرفض العرض من أصله، وده أقوى من مجرد تسقيف السعر: عرض بيغلّي
      // مش عرض ناقص، فما ينفعش يدخل السلة بأي سعر.
      expect(priced, isEmpty, reason: 'عرض مقلوب لازم يترفض بالكامل');

      // الرفض ممنوع يكون صامت — الكاشير لازم يعرف السبب.
      expect(rejection?.reason, OfferRejectionReason.notADiscount,
          reason: 'سبب الرفض لازم يوصل للي مناديها مش يتبلع في اللوج');
      expect(rejection?.normalPrice, 15.0);

      // (اتشالت حلقة كانت بتلفّ على `priced` وهي متأكَّد إنها فاضية — ثابت
      // بيعدّي فراغياً مش بيحرس حاجة. الثابت الحقيقي بيتفحص في اختبار H2 فوق
      // على سطور موجودة فعلاً.)
    });

    // الحد الفاصل: `>=` مش `>`. عرض سعره **يساوي** مجموع أسعار البيع مش عرض —
    // خصمه صفر، فبيضيف سطور وبيوهم الكاشير إنه وفّر. من غير الاختبار ده، قلب
    // الشرط لـ`>` كان هيعدّي من غير ما حد ياخد باله.
    test('الحد الفاصل: سعر العرض = مجموع أسعار البيع بيترفض برضه', () async {
      final offer = await seedOffer(
          salePrices: [5, 5, 5], offerPrice: 15, name: 'متعادل');

      OfferRejection? rejection;
      final priced = await service.calculateOfferItems(
        ApplyOfferRequest(offer: offer),
        onRejected: (r) => rejection = r,
      );

      expect(priced, isEmpty,
          reason: 'عرض بخصم صفر مش عرض — لازم يترفض زي المقلوب');
      expect(rejection?.reason, OfferRejectionReason.notADiscount);
      expect(rejection?.normalPrice, 15.0);
    });
  });
}
