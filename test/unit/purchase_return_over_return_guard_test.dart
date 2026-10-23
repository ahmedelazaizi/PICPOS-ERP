// 🔴 الردُّ مرّتَين من نفس السطر — سقفٌ كان يقرأ الكمّيّةَ الأصليّةَ وحدَها.
//
// ═══ العطبُ المقيس ═══
//
// `updateReturnQuantity` كان يقصُّ عند `item.item.quantity` — الكمّيّةِ
// **المشتراة** — بلا طرحِ ما رُدَّ من قبل. وكذلك حارسُ الإرسال في
// `processReturn`. فردُّ خمسةٍ من خمسةٍ **مرّتَين** كان يمرّ من الطرفَين:
//
//   • المخزونُ يُخصَم مرّتَين ⇒ رصيدٌ سالب.
//   • ذمّةُ المورّد تُخفَّض مرّتَين ⇒ استردادٌ مضاعف.
//   • وقيدان في الأستاذ لحدثٍ واحد.
//
// ⚠️ **وجانبُ المبيعات يطرحُ السابقَ منذ زمن** (`returns_repository_impl`
// يقرأ `getAlreadyReturnedQty` ويرمي)، **والشراءُ لا**. فالعطبُ ليس فرضاً
// نظريّاً بل فجوةٌ بين توأمَين أحدُهما محروس.
//
// ⚠️ **والوحدةُ أساسيّةٌ في الطرفَين:** `stock_movements.quantity` للمرتجع
// يُكتَب من `item.returnQuantity` الآتية من `purchase_invoice_items.quantity`
// المخزَّنة بالوحدة الأساسيّة بعد التحويل في `createPurchaseInvoice`. فطرحُ
// أحدِهما من الآخر مشروعٌ بلا ضربٍ في معامل الوحدة — والضربُ هنا كان سيعطي
// عشرةَ أضعافٍ كما وقع فعلاً 2026-04-28.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/data/database/database.dart';
import 'package:picpos_erp/presentation/providers/purchase_return_provider.dart';

PurchaseInvoiceItem _item({
  required int id,
  required int productId,
  required double quantity,
}) =>
    PurchaseInvoiceItem(
      id: id,
      invoiceId: 1,
      productId: productId,
      quantity: quantity,
      unitCost: 100,
      discount: 0,
      taxRate: 0,
      taxAmount: 0,
      total: quantity * 100,
      quantityInBase: quantity,
      rowVersion: 0,
    );

/// صنفٌ بأقلّ ما يقبله النوع — الاختبارُ يقرأ `item` وحدَه، والمنتَجُ
/// حاضرٌ لأنّ `PurchaseInvoiceItemWithProduct` يشترطه لا لأنّه يُقاس.
Product _product(int id) => Product(
      id: id,
      code: 'P$id',
      name: 'حبر طابعة',
      salePrice: 120,
      priceTalabat: 0,
      priceCareem: 0,
      priceAshyae: 0,
      wholesalePrice: 0,
      costPrice: 100,
      minStock: 0,
      currentStock: 0,
      isActive: true,
      isLocked: false,
      trackInventory: true,
      trackExpiry: false,
      defaultShelfDays: 0,
      alertDaysBefore: 0,
      isSoldByWeight: false,
      weightUnit: 'kg',
      allowNegativeSale: false,
      productType: 'simple',
      isKitchenSet: false,
      taxRate: 0,
      scaleType: 'none',
      itemTaxType: '',
      itemTaxSubtype: '',
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
      sortOrder: 0,
      rowVersion: 0,
      createdOnServer: false,
    );

/// مزوّدٌ بحالةٍ مثبَّتة — `build` تُستبدَل كاملةً فلا تُلمَس قاعدة.
class _FrozenReturns extends PurchaseReturnNotifier {
  _FrozenReturns(this._state);
  final PurchaseReturnState _state;

  @override
  PurchaseReturnState build() => _state;
}

PurchaseReturnState _state({
  required double purchased,
  required double alreadyReturned,
}) =>
    PurchaseReturnState(
      fromDate: DateTime(2026, 9, 1),
      toDate: DateTime(2026, 9, 30),
      invoiceItems: [
        PurchaseInvoiceItemWithProduct(
          item: _item(id: 10, productId: 99, quantity: purchased),
          product: _product(99),
        ),
      ],
      alreadyReturnedByProduct: {99: alreadyReturned},
    );

PurchaseReturnNotifier _notifier(PurchaseReturnState s) {
  final container = ProviderContainer(
    overrides: [
      purchaseReturnProvider.overrideWith(() => _FrozenReturns(s)),
    ],
  );
  addTearDown(container.dispose);
  // قراءةُ الحالة أوّلاً تُنشئ المزوّدَ فعلاً — بلا ذلك يبقى بارداً.
  container.read(purchaseReturnProvider);
  return container.read(purchaseReturnProvider.notifier);
}

void main() {
  test('مرساةٌ — بلا مرتجعٍ سابقٍ المتاحُ هو المشترى كلُّه', () {
    final n = _notifier(_state(purchased: 5, alreadyReturned: 0));
    expect(n.maxReturnableFor(10), 5.0);
  });

  test('والمرتجعُ السابقُ يُطرَح من المتاح', () {
    final n = _notifier(_state(purchased: 5, alreadyReturned: 2));
    expect(n.maxReturnableFor(10), 3.0,
        reason: 'السقفُ ما زال يقرأ الكمّيّةَ المشتراةَ وحدَها');
  });

  test('ورُدَّ الكلُّ ⇒ لا متاحَ إطلاقاً', () {
    final n = _notifier(_state(purchased: 5, alreadyReturned: 5));
    expect(n.maxReturnableFor(10), 0.0,
        reason: 'ردُّ خمسةٍ من خمسةٍ مرّتَين — مخزونٌ سالبٌ واستردادٌ مضاعف');
  });

  test('ولا يُرجِع سالباً لو تجاوز المرتجعُ المشترى', () {
    // يقع بصفٍّ قديمٍ أو بمرتجعٍ سُجِّل على جهازٍ آخرَ قبل المزامنة.
    final n = _notifier(_state(purchased: 5, alreadyReturned: 7));
    expect(n.maxReturnableFor(10), 0.0);
  });

  test('وصنفٌ لا وجودَ له ⇒ صفرٌ لا استثناء', () {
    final n = _notifier(_state(purchased: 5, alreadyReturned: 0));
    expect(n.maxReturnableFor(999), 0.0);
  });

  test('والحقلُ يقصُّ عند المتاح لا عند المشترى', () {
    final n = _notifier(_state(purchased: 5, alreadyReturned: 3));
    n.updateReturnQuantity(10, 5);
    expect(n.state.returnQuantities[10], 2.0,
        reason: 'الحقلُ قبِل أكثرَ من المتاح — والقصُّ هو الحارسُ الأوّل');
  });
}
