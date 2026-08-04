// ═══════════════════════════════════════════════════════════════════════════
// إعادة إنتاج لعيوب العروض في نقطة البيع — **العيوب دي لسه ما اتصلحتش**.
//
// ⚠️ الملف ده متوقَّع منه يفشل. الأحمر هنا **مش انحدار (regression)** — ده
// توثيق تنفيذي لعطل قايم في الإنتاج. ما تصلّحش الاختبار عشان يعدّي؛ لو الأحمر
// اختفى من غير ما حد يلمس كود الإنتاج يبقى الاختبار نفسه بايظ.
//
// كل مجموعة هنا فيها اختبار **ضابط (control)** بيعدّي أخضر — وظيفته يثبت إن
// التجهيزة سليمة، فلو الأحمر جه من عطل في التجهيزة مش من عطل في المنتج،
// الضابط هيقع معاه ويفضحها.
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/application/services/cart_pricing_service.dart';
import 'package:ural_erp/core/constants/app_constants.dart';
import 'package:ural_erp/data/providers/providers.dart';
import 'package:ural_erp/domain/entities/product_entity.dart';
import 'package:ural_erp/domain/repositories/offers_repository.dart';
import 'package:ural_erp/presentation/pos/providers/cart_controller.dart';

/// يفرّغ طابور الأحداث عشان الـ Future اللي اتكمّلت تكمّل مشوارها.
/// حلقة صريحة بدل `pumpEventQueue` — مفيش widget binding في الملف ده.
Future<void> _settle() async {
  for (var i = 0; i < 20; i++) {
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

  /// أصناف العرض. بترجع لصنف **مش موجود في السلة**، فـ `_applyBundleOffer`
  /// بتخرج بدري ومش بتعدّل أي سعر — وكده اللي يتبقّى تحت المجهر هو خطوة
  /// الدمج لوحدها، مش حساب العرض.
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
  // فرضية ١ — كمية بتتسحب أثناء انتظار العروض بتضيع
  //
  // السيناريو الواقعي: الكاشير بيسحب الباركود مرتين ورا بعض. أول سحبة بتشغّل
  // `_autoApplyOffers` اللي بياخد **لقطة** من السلة وبعدين بيستنى
  // `getActiveOffers()` (قراءة من القرص/الشبكة — مش لحظية). السحبة التانية
  // بتزوّد الكمية لـ٢ وهو لسه مستني.
  //
  // لما العروض ترجع، خطوة الدمج (cart_controller.dart:547-556) بتحافظ على
  // الأصناف اللي **اتضافت** بعد اللقطة بالمقارنة بـ`productId` — لكن الصنف ده
  // كان أصلاً في اللقطة، فبيتخطّى. وحارس القِدَم عند :545 ما بيضربش لأن
  // `_tryAutoApplyOffers` بيرفع `_pendingAutoApply` بس ومش بيزوّد
  // `_autoApplyGeneration`. النتيجة: `state` بتترجع للكمية القديمة (١).
  //
  // وأسوأ حاجة إن الإعادة المجدولة بتاخد لقطتها من الحالة **بعد** ما اتشوّهت،
  // فالوحدة الضايعة عمرها ما بترجع. ده مال بيتباع ومش بيتحاسب عليه.
  // ═════════════════════════════════════════════════════════════════════════
  group('فرضية ١ — كمية بتضيع أثناء انتظار العروض (عطل قايم)', () {
    late AppDatabase db;
    late ProviderContainer container;
    late _GatedOffersRepo offersRepo;
    late CartController cart;

    setUp(() {
      db = AppDatabase.forTesting();
      offersRepo = _GatedOffersRepo([
        // صنف العرض ٩٩٩ مش في السلة خالص → العرض ما بيتطبّقش.
        const OfferItem(id: 1, offerId: 1, productId: 999, quantity: 1),
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

    double qtyOf(int productId) => container
        .read(cartControllerProvider)
        .items
        .where((i) => i.productId == productId)
        .fold<double>(0, (a, i) => a + i.quantity);

    test('الضابط: من غير تشابك، سحبتين = كمية ٢', () async {
      final a = _product();
      cart.addItem(a);
      offersRepo.gate.complete([_offer()]);
      await _settle();
      cart.addItem(a);
      await _settle();

      expect(qtyOf(a.id), 2,
          reason: 'من غير تشابك المسار سليم — لو ده وقع فالتجهيزة هي البايظة');
    });

    test('السحبة التانية جوّه نافذة الـ await بتتمسح', () async {
      final a = _product();

      // سحبة ١ — التطبيق التلقائي دلوقتي واقف على البوابة، ماسك لقطة «A × ١».
      cart.addItem(a);
      expect(qtyOf(a.id), 1, reason: 'تجهيزة: السحبة الأولى دخلت');
      expect(offersRepo.gate.isCompleted, isFalse,
          reason: 'تجهيزة: لازم نكون واقفين جوّه الـ await فعلاً');

      // سحبة ٢ — نفس الصنف، والتطبيق التلقائي لسه معلّق.
      cart.addItem(a);
      expect(qtyOf(a.id), 2,
          reason: 'تجهيزة: الكمية بقت ٢ فعلاً قبل ما العروض ترجع');

      // العروض رجعت → الدمج بيكتب اللقطة القديمة فوق الحالة الحالية.
      offersRepo.gate.complete([_offer()]);
      await _settle();

      // 🔴 متوقَّع يفشل: بترجع ١. الوحدة اتمسحت ومش بترجع تاني.
      expect(qtyOf(a.id), 2,
          reason: 'الوحدة اللي اتسحبت أثناء انتظار العروض ضاعت من السلة');
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  // فرضيتان ٢ و٣ — تسعير العرض نفسه (CartPricingService)
  // ═════════════════════════════════════════════════════════════════════════
  group('فرضيات ٢ و٣ — CartPricingService.calculateOfferItems (عطل قايم)', () {
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
    // فرضية ٢ — مجموع سطور العرض ما بيساويش سعر العرض المعلن
    //
    // `factor = offerPrice / totalNormalPrice` وبعدين كل سطر بيتقرّب **لوحده**
    // على ٣ خانات (cart_pricing_service.dart:64-72). التقريب لكل وحدة معناه إن
    // المجموع مش مضمون يرجع لسعر العرض. الزبون شايف لافتة بسعر والفاتورة
    // بتطلع بسعر تاني.
    // ─────────────────────────────────────────────────────────────────────
    test('الضابط: عرض بيقسم بالظبط بيوصل لسعر العرض بالمليم', () async {
      // ١٠٠ + ٥٠ = ١٥٠، سعر العرض ١٢٠ → المعامل ٠٫٨ (قسمة نضيفة).
      final offer =
          await seedOffer(salePrices: [100, 50], offerPrice: 120, name: 'نضيف');
      final priced = await service.calculateOfferItems(
        ApplyOfferRequest(offer: offer),
      );

      expect(priced, hasLength(2), reason: 'تجهيزة: الخدمة رجّعت سطور العرض');
      expect(bundleTotal(priced), offer.offerPrice,
          reason: 'قسمة نضيفة لازم تجمع لسعر العرض بالظبط');
    });

    test('عرض ما بيقسمش بالظبط: المجموع بيبعد عن سعر العرض المعلن', () async {
      // تلات أصناف بـ٥ للواحد = ١٥، سعر العرض ١٠ → المعامل ٠٫٦٦٦٦…
      // كل وحدة بتتقرّب لـ٣٫٣٣٣ والمجموع ٩٫٩٩٩.
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

      // 🔴 متوقَّع يفشل: المجموع ٩٫٩٩٩ مش ١٠.
      expect(total, offer.offerPrice,
          reason: 'مجموع سطور العرض لازم يساوي سعر العرض المعلن — الفرق $drift');
    });

    // ─────────────────────────────────────────────────────────────────────
    // فرضية ٣ — عرض متظبّط غلط بيرفع الأسعار بدل ما يخفّضها
    //
    // مفيش أي حارس إن `offerPrice < totalNormalPrice`. لو اتحفظ عرض بسعر أعلى
    // من مجموع أسعار أصنافه، المعامل بيبقى > ١ وكل سطر بيتسعّر **أغلى** من
    // سعر بيعه العادي. الزبون بياخد «عرض» بيغرّمه.
    //
    // الحارس ده كان موجود بالحرف في `apply_offers_usecase.dart:70`
    // (`if (offer.offerPrice >= totalNormalPrice) continue;`) — بس الـ use case
    // دي بقت ميتة (مفيش حد بينادي عليها غير ملف التصدير)، والمسار الحيّ
    // اللي ورثها ما نقلش الحارس معاه.
    //
    // وشاشة إنشاء العروض (offer_dialogs.dart) بتتحقق من الاسم والسعر > ٠
    // ووجود أصناف بس — فمفيش حاجة بتمنع حفظ العرض ده من الأساس.
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

      // الثابت الأصلي محفوظ: مفيش سطر راجع بسعر أعلى من سعر بيعه.
      for (final p in priced) {
        expect(p.customPrice, lessThanOrEqualTo(p.product.salePrice),
            reason: 'عرض المفروض ما يرفعش سعر الصنف '
                '(${p.product.name}: عرض ${p.customPrice} مقابل بيع ${p.product.salePrice})');
      }
    });
  });
}
