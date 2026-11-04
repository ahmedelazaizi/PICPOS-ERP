// بند ٤ — سلوكُ `CartController` مع سطور المرتجع بلا فاتورة.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/data/providers/providers.dart';
import 'package:picpos_erp/domain/entities/cart_item_entity.dart';
import 'package:picpos_erp/domain/entities/product_entity.dart';
import 'package:picpos_erp/presentation/pos/providers/cart_controller.dart';

ProductEntity product({
  int id = 1,
  double salePrice = 100,
  double taxRate = 0,
  bool taxExempt = false,
  double currentStock = 0,
}) =>
    ProductEntity(
      id: id,
      code: 'P$id',
      name: 'صنف $id',
      salePrice: salePrice,
      costPrice: 40,
      currentStock: currentStock,
      minStock: 0,
      trackInventory: true,
      taxRate: taxRate,
      taxExempt: taxExempt,
    );

void main() {
  late AppDatabase db;
  late ProviderContainer container;
  late CartController cart;

  setUp(() {
    // قاعدةُ اختبارٍ في الذاكرة: `_logAction` يكتب سجلَّ النشاط.
    db = AppDatabase.forTesting();
    container = ProviderContainer(overrides: [
      databaseProvider.overrideWith((ref) => db),
      posDefaultTaxRateProvider.overrideWith((ref) async => 0.16),
    ]);
    addTearDown(() async {
      container.dispose();
      await db.close();
    });
    cart = container.read(cartControllerProvider.notifier);
  });

  CartState state() => container.read(cartControllerProvider);

  test('addReturnItem: سطر returned بكمية ١ وسعر بيع الصنف الحاليّ', () {
    cart.addReturnItem(product(salePrice: 75));
    final line = state().items.single;
    expect(line.itemType, CartItemType.returned);
    expect(line.quantity, 1);
    expect(line.effectivePrice, 75);
    expect(state().hasReturnLines, isTrue);
    expect(state().isReturnOnly, isTrue);
  });

  test('لا حارسَ مخزون على المرتجع (رصيد صفر مقبول)', () {
    cart.addReturnItem(product(currentStock: 0));
    expect(state().items, hasLength(1));
  });

  test('السعر اليدويّ يُحترَم ويبقى سعرُ البيع في unitPrice', () {
    cart.addReturnItem(product(salePrice: 75), price: 60);
    final line = state().items.single;
    expect(line.effectivePrice, 60);
    expect(line.unitPrice, 75);
  });

  test('الكمية قابلةٌ للتعديل والسطر قابلٌ للحذف', () {
    cart.addReturnItem(product());
    cart.updateQuantity(0, 3);
    expect(state().items.single.quantity, 3);
    cart.removeFromCart(0);
    expect(state().items, isEmpty);
  });

  test('سلّة مختلطة: الإجماليُّ صافٍ وsignedTotal بإشارته', () {
    cart.addItem(product(id: 1, salePrice: 100, currentStock: 5), quantity: 1);
    cart.addReturnItem(product(id: 2, salePrice: 30), quantity: 2);
    expect(state().isMixedCart, isTrue);
    expect(state().total, 40);
    expect(state().signedTotal, 40);
  });

  test('الصافي السالب يظهر سالباً ويُعلَّم isNegative', () {
    cart.addItem(product(id: 1, salePrice: 10, currentStock: 5), quantity: 1);
    cart.addReturnItem(product(id: 2, salePrice: 30), quantity: 1);
    expect(state().total, -20);
    expect(state().isNegative, isTrue);
    expect(state().signedTotal, -20);
  });

  test('مرتجعٌ خالصٌ: total موجبٌ كما كان (توافقُ الشاشة القديمة) والعرضُ سالب', () {
    cart.addReturnItem(product(salePrice: 30), quantity: 2);
    expect(state().total, 60);
    expect(state().isNegative, isFalse);
    expect(state().signedTotal, -60);
  });

  test('بيعُ صنفٍ له سطرُ مرتجع لا يدمج في سطر المرتجع', () {
    cart.addReturnItem(product(id: 1, salePrice: 50));
    cart.addItem(product(id: 1, salePrice: 50, currentStock: 5), quantity: 2);
    expect(state().items, hasLength(2));
    final byType = {for (final i in state().items) i.itemType: i.quantity};
    expect(byType[CartItemType.returned], 1);
    expect(byType[CartItemType.normal], 2);
  });

  test('التعليق يرفض سلّةً فيها مرتجع (لا يحفظ نوع السطر)', () async {
    cart.addReturnItem(product());
    expect(await cart.holdOrder(), isNull);
    expect(state().items, hasLength(1), reason: 'السلّة لم تُمسّ');
  });

  test('removeSettledLines: حفظُ البيع يُبقي المرتجعَ ويصفّر خصمَ الفاتورة', () {
    cart.addItem(product(id: 1, salePrice: 100, currentStock: 5), quantity: 1);
    cart.addReturnItem(product(id: 2, salePrice: 30));
    cart.setDiscount(10);
    cart.removeSettledLines(returned: false);
    expect(state().items.single.itemType, CartItemType.returned);
    expect(state().discountPercent, 0);
  });

  test('removeSettledLines: حفظُ المرتجع يُبقي البيع', () {
    cart.addItem(product(id: 1, salePrice: 100, currentStock: 5), quantity: 1);
    cart.addReturnItem(product(id: 2, salePrice: 30));
    cart.removeSettledLines(returned: true);
    expect(state().items.single.itemType, CartItemType.normal);
  });

  test('الأصناف المعفاة: سطرُ المرتجع بنسبة صفر حتى مع ضريبة مفعَّلة', () {
    cart.addReturnItem(product(salePrice: 100, taxRate: 14, taxExempt: true));
    expect(state().items.single.taxRate, 0);
    expect(state().items.single.taxExempt, isTrue);
  });
}
