// ═══════════════════════════════════════════════════════════════════════════
// PicPos — عيوب مقاسة في مسار الفلوس بالبيع السريع (إعادة إنتاج)
// ═══════════════════════════════════════════════════════════════════════════
//
// الملف ده اتكتب **أحمر عن قصد** كعقد إصلاح، واتشاف أحمر فعلاً (٥ سقطات:
// UB-1 إجمالي 150.0 بدل 60 · HO-1 خصم 0.0 بدل 10 و quantityInBase 1.0 بدل 12 ·
// CE-1 رسالة قديمة لزقة · SC-1 ملصق سعر صفر بيتقبل)، وبقى أخضر بعد الإصلاح
// **من غير أي تعديل في الشروط**. دلوقتي هو حارس انحدار.
//
// كل مجموعة فيها اختبار **ضابط (control)** أخضر دلوقتي — عشان لو المجموعة
// كلها وقعت يبقى الكسر في التجهيزة مش في المنتج.
//
// النطاق: شاشة PicPos (`lib/presentation/pos_picpos/`) والمحرّك المشترك اللي
// بتناديه. مفيش أي حاجة من HR/رواتب (بره نطاق بروفايل lite).
//
// ── العيوب ────────────────────────────────────────────────────────────────
// UB-1 — مسح باركود **وحدة** بيلزق التحويل على أول سطر لنفس الصنف مش السطر
//        اللي اتضاف. (`pos_search_controller.dart:385`, ونفس الغلط في `:349`)
// HO-1 — استرجاع فاتورة معلّقة بيفقد خصم السطر وتحويل الوحدة واسم الوحدة
//        ونسبة الضريبة. (`hold_order_usecase.dart:59`, `:119`)
// CE-1 — `CheckoutState.copyWith(error: null)` ما بيمسحش، فـ`clearError()`
//        عملية فاضية. (`checkout_controller.dart:29`, `:41`)
// SC-1 — ملصق ميزان بنمط **السعر** لصنف سعره صفر بيتحوّل لكمية = المبلغ.
//        (`scale_barcode_handler.dart:290`)
// ═══════════════════════════════════════════════════════════════════════════

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/data/providers/providers.dart';
import 'package:picpos_erp/domain/entities/cart_item_entity.dart';
import 'package:picpos_erp/domain/entities/product_entity.dart';
import 'package:picpos_erp/presentation/pos/providers/cart_controller.dart';
import 'package:picpos_erp/presentation/pos/providers/checkout_controller.dart';
import 'package:picpos_erp/presentation/pos/providers/pos_search_controller.dart';
import 'package:picpos_erp/presentation/pos/services/scale_barcode_handler.dart';

/// يفرّغ طابور الأحداث — جولة العروض التلقائية بتقرا من القاعدة فعلاً.
Future<void> _settle() async {
  for (var i = 0; i < 60; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

/// قنوات إضافات بترمي `MissingPluginException` في بيئة الاختبار.
/// `PosSearchController` بيبني `AudioPlayer` في الإنشاء، والـ exception
/// بيصعد كخطأ غير ممسوك ويفشّل الاختبار لأسباب مالهاش علاقة بالعيب.
void _silencePlugins(TestWidgetsFlutterBinding binding) {
  for (final ch in const [
    'xyz.luan/audioplayers.global',
    'xyz.luan/audioplayers',
    'plugins.flutter.io/path_provider',
  ]) {
    binding.defaultBinaryMessenger
        .setMockMethodCallHandler(MethodChannel(ch), (call) async => null);
  }
}

class _ScaleDs implements ScaleBarcodeDataSource {
  _ScaleDs(this.byPlu);
  final Map<int, ProductEntity> byPlu;
  @override
  Future<String?> getSettingValue(String key) async => null;
  @override
  Future<ProductEntity?> getProductByScalePlu(int plu) async => byPlu[plu];
  @override
  Future<ProductEntity?> getProductByCode(String code) async => null;
  @override
  Future<ProductEntity?> getProductByBarcode(String barcode) async => null;
}

/// رقم تحقّق EAN-13 على أول ١٢ خانة.
String _ean13(String d12) {
  var sum = 0;
  for (var i = 0; i < 12; i++) {
    sum += int.parse(d12[i]) * (i.isEven ? 1 : 3);
  }
  return '$d12${(10 - (sum % 10)) % 10}';
}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => _silencePlugins(binding));

  // ═════════════════════════════════════════════════════════════════════════
  group('UB-1 — باركود الوحدة بيعدّل السطر الغلط', () {
    // ───────────────────────────────────────────────────────────────────────
    // التجهيزة: صنف واحد ببـاركودين — باركود الصنف (قطعة، ٥) وباركود وحدة
    // «كرتونة» (×١٢، ٥٠). ده أشيع تركيب في سوبرماركت.
    //
    // `pos_search_controller.searchBarcode` بيضيف السطر الجديد ثم بيدوّر عليه
    // بـ `indexWhere((i) => i.productId == product.id)` — **أول** مطابقة، مش
    // السطر اللي لسه اتضاف. فلو الصنف موجود في السلة على سطر قطعة، التحويل
    // (`quantityInBase` + `unitSalePrice`) بينزل على سطر القطعة.
    late AppDatabase db;
    late ProviderContainer container;

    setUp(() async {
      db = AppDatabase.forTesting();
      final pid = await db.into(db.products).insert(
            ProductsCompanion.insert(
              code: 'P1',
              name: 'مياه',
              barcode: const Value('PIECE-1'),
              salePrice: const Value(5),
              costPrice: const Value(3),
              currentStock: const Value(100),
            ),
          );
      await db.into(db.productUnits).insert(
            ProductUnitsCompanion.insert(
              productId: pid,
              unitName: 'كرتونة',
              barcode: const Value('CARTON-1'),
              quantityInBase: const Value(12),
              salePrice: const Value(50),
            ),
          );
      container = ProviderContainer(overrides: [
        databaseProvider.overrideWithValue(db),
        posDefaultTaxRateProvider.overrideWith((ref) async => 0.0),
        enableNegativeSalesProvider.overrideWith((ref) async => false),
        preventItemStackingProvider.overrideWith((ref) async => false),
      ]);
      addTearDown(() async {
        container.dispose();
        await db.close();
      });
    });

    Future<void> scan(String code) async {
      await container.read(posSearchControllerProvider.notifier).searchBarcode(code);
      await _settle();
    }

    CartState cart() => container.read(cartControllerProvider);

    test('ضابط: باركود الوحدة لوحده بيتسعّر ويتحوّل صح', () async {
      await scan('CARTON-1');
      expect(cart().items, hasLength(1));
      expect(cart().items.single.effectivePrice, 50);
      expect(cart().items.single.quantityInBase, 12);
      expect(cart().total, 50);
    });

    test('قطعتين ثم كرتونة: الفاتورة ٦٠ والمخزون ١٤ حبة', () async {
      await scan('PIECE-1');
      await scan('PIECE-1');
      await scan('CARTON-1');

      final stockToDeduct =
          cart().items.fold<double>(0, (s, i) => s + i.stockQuantity);

      expect(
        cart().total,
        60,
        reason: 'قطعتين ب٥ + كرتونة ب٥٠ = ٦٠. المقاس دلوقتي ١٥٠ — سطر '
            'القطعتين اتسعّر بسعر الكرتونة (٥٠) لأن '
            'pos_search_controller.dart:385 بيمسك أول سطر لنفس الصنف بدل '
            'السطر اللي لسه اتضاف. زيادة ٩٠ على العميل.',
      );
      expect(
        stockToDeduct,
        14,
        reason: 'قطعتين + ١٢ حبة كرتونة = ١٤ حبة. المقاس دلوقتي ٢٥ — سطر '
            'القطعتين خد quantityInBase=12، فالمخزون بينزل ١١ حبة وهمية.',
      );
      expect(
        cart().items.first.selectedUnitName,
        isNull,
        reason: 'سطر القطع مالوش وحدة تغليف؛ اسم «كرتونة» عليه بيطبع على '
            'الإيصال وصف غلط كمان.',
      );
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  group('HO-1 — تعليق فاتورة واسترجاعها بيفقد بيانات مالية', () {
    // ───────────────────────────────────────────────────────────────────────
    // `HoldOrderUseCase.executeHold` بيسلسل أربع حاجات بس لكل سطر:
    // productId / quantity / unitPrice / customPrice (+ ملاحظة). و
    // `executeRetrieve` بيعيد بناء `CartItemEntity` من غير `discountPercent`
    // ولا `taxRate` ولا `selectedUnitId/Name` ولا `quantityInBase`.
    //
    // النتيجة على تلّ حقيقي: الكاشير يعلّق فاتورة فيها كرتونة (×١٢) بخصم ١٠٪،
    // يرجعها بعد شوية، تتحوّل لسطر «قطعة واحدة» بلا خصم — العميل بيدفع أكتر
    // والمخزون بينزل حبة واحدة بدل ١٢.
    late AppDatabase db;
    late ProviderContainer container;

    setUp(() async {
      db = AppDatabase.forTesting();
      final pid = await db.into(db.products).insert(
            ProductsCompanion.insert(
              code: 'P1',
              name: 'مياه',
              barcode: const Value('PIECE-1'),
              salePrice: const Value(5),
              costPrice: const Value(3),
              currentStock: const Value(100),
            ),
          );
      await db.into(db.productUnits).insert(
            ProductUnitsCompanion.insert(
              productId: pid,
              unitName: 'كرتونة',
              barcode: const Value('CARTON-1'),
              quantityInBase: const Value(12),
              salePrice: const Value(50),
            ),
          );
      container = ProviderContainer(overrides: [
        databaseProvider.overrideWithValue(db),
        posDefaultTaxRateProvider.overrideWith((ref) async => 0.0),
        enableNegativeSalesProvider.overrideWith((ref) async => false),
        preventItemStackingProvider.overrideWith((ref) async => false),
      ]);
      addTearDown(() async {
        container.dispose();
        await db.close();
      });
    });

    /// يبني السلة الأصلية ويعلّقها ويرجّعها. بيرجّع سطر واحد بعد الاسترجاع.
    Future<CartItemEntity> holdAndResume() async {
      final cart = container.read(cartControllerProvider.notifier);
      await container
          .read(posSearchControllerProvider.notifier)
          .searchBarcode('CARTON-1');
      await _settle();
      cart.setItemDiscount(0, 10);

      final before = container.read(cartControllerProvider).items.single;
      expect(before.quantityInBase, 12, reason: 'تجهيزة: الوحدة اتطبّقت');
      expect(before.discountPercent, 10, reason: 'تجهيزة: الخصم اتطبّق');

      final holdNum = await cart.holdOrder();
      expect(holdNum, isNotNull, reason: 'تجهيزة: التعليق نجح');

      final held = await db.watchHeldOrders().first;
      await cart.retrieveHeldOrder(held.first.id);
      await _settle();
      return container.read(cartControllerProvider).items.single;
    }

    test('ضابط: الكمية والسعر بينجوا من التعليق', () async {
      final line = await holdAndResume();
      expect(line.quantity, 1);
      expect(line.effectivePrice, 50);
    });

    test('خصم السطر بينجو من التعليق', () async {
      final line = await holdAndResume();
      expect(line.discountPercent, 10,
          reason: 'اتقاس صفر — الخصم اليدوي اتبخّر، فالعميل بيدفع ٥٠ بدل ٤٥.');
    });

    test('تحويل الوحدة بينجو من التعليق', () async {
      final line = await holdAndResume();
      expect(line.quantityInBase, 12,
          reason: 'اتقاس ١ — الفاتورة هتخصم حبة واحدة من المخزون بدل ١٢، '
              'يعني ١١ حبة بتخرج من المحل ومش مسجّلة.');
      expect(line.selectedUnitName, 'كرتونة',
          reason: 'اسم الوحدة بيتطبع على الإيصال وبيتخزّن في سطر الفاتورة.');
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  group('CE-1 — clearError مش بيمسح', () {
    // ───────────────────────────────────────────────────────────────────────
    // `CheckoutState.copyWith` بيستخدم `error ?? this.error`، فتمرير `null`
    // معناها «ما تغيّرش». `clearError()` (اللي `CartController` بينادي عليه من
    // كل تعديل على السلة) بيبقى عملية فاضية، والرسالة القديمة بتفضل ملزوقة.
    //
    // الأثر في PicPos: `_processPaymentAndSave` بيعرض
    // `checkoutController.error ?? 'فشل حفظ الفاتورة'` — فأي فشل تاني (زي رفض
    // حارس إعادة الدخول اللي بيرجّع false بلا رسالة) بيطلع برسالة بيعة قديمة
    // خالص، والكاشير بيتصرّف على سبب غلط.
    late AppDatabase db;
    late ProviderContainer container;

    setUp(() async {
      db = AppDatabase.forTesting();
      container = ProviderContainer(overrides: [
        databaseProvider.overrideWithValue(db),
        posDefaultTaxRateProvider.overrideWith((ref) async => 0.0),
      ]);
      addTearDown(() async {
        container.dispose();
        await db.close();
      });
    });

    test('ضابط: الفشل بيسجّل رسالة', () async {
      final ok = await container
          .read(checkoutControllerProvider.notifier)
          .processPayment(method: 'cash', total: 0);
      expect(ok, isFalse);
      expect(container.read(checkoutControllerProvider).error, isNotNull);
    });

    test('clearError بيرجّع الحالة بلا رسالة', () async {
      final ctl = container.read(checkoutControllerProvider.notifier);
      await ctl.processPayment(method: 'cash', total: 0);
      ctl.clearError();
      expect(container.read(checkoutControllerProvider).error, isNull,
          reason: 'الرسالة القديمة لسه موجودة — copyWith مش قادر يمرّر null.');
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  group('SC-1 — ملصق ميزان بنمط السعر لصنف سعره صفر', () {
    // ───────────────────────────────────────────────────────────────────────
    // `_extractScaleProduct` بيحسب `qty = totalPrice / (salePrice > 0 ?
    // salePrice : 1.0)`. الحارس بيمنع القسمة على صفر لكنه **بيحوّل المبلغ
    // لكمية**: ملصق بـ١٢٫٣٥ لصنف سعره غير مضبوط بيدخل السلة ١٢٫٣٥ كجم بسعر
    // صفر ⇒ بضاعة مجانية + خصم مخزون وهمي بحجم المبلغ.
    //
    // الصح: رفض التحليل (`null`) عشان الكاشير يشوف رسالة، مش سطر صامت.
    ProductEntity meat({required double salePrice}) => ProductEntity(
          id: 5,
          code: '00007',
          name: 'لحمة',
          salePrice: salePrice,
          costPrice: 30,
          currentStock: 40,
          minStock: 0,
          isSoldByWeight: true,
          scaleType: 'price',
          scalePluNumber: 7,
        );

    // بادئة 20 (سعر) · PLU 00007 · قيمة 01235 → ١٢٫٣٥
    final label = _ean13('200000701235');

    test('ضابط: بسعر ٧٫٥ الكمية بتطلع صح وإجمالي السطر = المبلغ', () async {
      final r = await ScaleBarcodeHandler.tryParse(
          _ScaleDs({7: meat(salePrice: 7.5)}), label);
      expect(r, isNotNull);
      expect(r!.quantity * 7.5, closeTo(12.35, 0.0005));
    });

    test('بسعر صفر الملصق يترفض بدل ما يتحوّل لـ١٢٫٣٥ كجم', () async {
      final r = await ScaleBarcodeHandler.tryParse(
          _ScaleDs({7: meat(salePrice: 0)}), label);
      expect(r, isNull,
          reason: 'اتقاس quantity=12.35 بسعر صفر — بضاعة بتخرج ببلاش '
              'والمخزون بينزل ١٢٫٣٥ وحدة على غير الحقيقة.');
    });
  });
}
