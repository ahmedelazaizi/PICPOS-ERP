// ═══════════════════════════════════════════════════════════════════════════
// «وضع الاستبدال» اتشال — الكمية السالبة كانت بتقلب اتجاه المخزون
// ═══════════════════════════════════════════════════════════════════════════
//
// ── العطل ───────────────────────────────────────────────────────────────────
// `sales_mutations_dao.dart:311-331` بياخد اتجاه المخزون من `saleType`،
// وبيمرّر **الكمية المخزَّنة بإشارتها**:
//
//     if (saleType == 'return') adjustStock(quantity: +stockQty)
//     else                      adjustStock(quantity: -stockQty)
//
// و«وضع الاستبدال» كان بيخزّن الكميات **سالبة** (`cart_controller:374`
// `finalQuantity = -quantity.abs()`) وبيعلّم السطور `returned`، وأي سطر
// `returned` كان بيحوّل الفاتورة كلها لـ`saleType = 'return'`.
//
// النتيجة: سالب × سالب = موجب. الصنف اللي **رجع** بينقص من المخزون، والصنف
// اللي **خرج** بيزيد، والدرج بينخصم فلوس الكاشير لسه قابضها.
//
// 🔴 والأهم: العطل ده **مش محتاج خلط أصلاً**. عربة كلها مرتجعات في وضع
//    الاستبدال = كميات كلها سالبة + `saleType='return'` ⇒ المخزون **ينقص**
//    بدل ما يزيد. يعني الوضع ده مكسور في كل حالاته، مش في الحالة المختلطة بس.
//
// ── ليه الحذف بدل الإصلاح ───────────────────────────────────────────────────
// UralCash عنده نفس العطل واتصلح (تدقيق B15) بتقسيم العربة لمستندين. الإصلاح
// ده بيلمس ١٣ ملف عندهم + نقطة نهاية سيرفر + طابور offline.
//
// وPicPos عنده **البديل الصح موجود وشغّال ومربوط بزرار جنبه**:
// `convertToQuickReturn` بيسيب الكميات **موجبة** وبيعتمد على `saleType`
// للاتجاه — وده بالظبط العقد اللي إصلاح Ural بيفرضه.
//
// فالكاشير بيوصل لنفس المستندين (مرتجع + بيعة) بزرارين موجودين. مفيش عميل
// على PicPos مستني الزرار المحذوف، فمفيش سلوك بينكسر.
//
// الملف ده بيثبّت الاتنين: إن المسار الباقي بيسيب الكميات موجبة، وإن مفيش
// أي مسار تاني قادر يولّد كمية سالبة.

import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/providers/providers.dart';
import 'package:ural_erp/domain/entities/cart_item_entity.dart';
import 'package:ural_erp/domain/entities/product_entity.dart';
import 'package:ural_erp/presentation/pos/providers/cart_controller.dart';

ProductEntity _product({required int id, double salePrice = 10}) =>
    ProductEntity(
      id: id,
      code: 'A1',
      name: 'شاي',
      salePrice: salePrice,
      costPrice: 5,
      currentStock: 100,
      minStock: 0,
      taxRate: 0,
    );

void main() {
  late AppDatabase db;
  late ProviderContainer container;
  late CartController cart;
  late ProductEntity a;

  setUp(() async {
    db = AppDatabase.forTesting();
    final id = await db.into(db.products).insert(
          ProductsCompanion.insert(
            code: 'A1',
            name: 'شاي',
            salePrice: const Value(10),
          ),
        );
    a = _product(id: id);

    container = ProviderContainer(overrides: [
      databaseProvider.overrideWithValue(db),
      posDefaultTaxRateProvider.overrideWith((ref) async => 0.0),
      enableNegativeSalesProvider.overrideWith((ref) async => false),
    ]);
    cart = container.read(cartControllerProvider.notifier);

    addTearDown(() async {
      container.dispose();
      await db.close();
    });
  });

  List<CartItemEntity> items() => container.read(cartControllerProvider).items;

  group('المسار الباقي — المرتجع السريع', () {
    test('بيسيب الكميات موجبة (الاتجاه من saleType مش من الإشارة)', () async {
      cart.addItem(a, quantity: 3);
      expect(items().single.quantity, 3.0, reason: 'تجهيزة');

      cart.convertToQuickReturn();

      final line = items().single;
      expect(line.quantity, 3.0,
          reason: 'كمية سالبة هنا معناها المخزون هينقص بدل ما يزيد — '
              'adjustStock بياخد الإشارة زي ما هي');
      expect(line.itemType, CartItemType.returned);
    });

    test('كمية أكبر من واحد بتفضل موجبة كمان', () async {
      cart.addItem(a, quantity: 7);
      cart.convertToQuickReturn();
      expect(items().single.quantity, 7.0);
    });
  });

  group('مفيش أي مسار بيولّد كمية سالبة', () {
    test('الإضافة العادية موجبة', () async {
      cart.addItem(a, quantity: 2);
      expect(items().single.quantity, greaterThan(0));
    });

    test('بعد المرتجع السريع، كل سطور السلة موجبة', () async {
      cart.addItem(a, quantity: 2);
      cart.addItem(a, quantity: 1);
      cart.convertToQuickReturn();

      for (final line in items()) {
        expect(line.quantity, greaterThan(0),
            reason: 'سطر بكمية سالبة = اتجاه مخزون مقلوب');
      }
    });

    test('تعديل الكمية ما بيقلبش الإشارة', () async {
      cart.addItem(a, quantity: 2);
      cart.convertToQuickReturn();
      cart.updateQuantity(0, 5);

      expect(items().single.quantity, 5.0);
    });
  });
}
