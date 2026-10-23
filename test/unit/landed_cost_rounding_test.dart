// توزيعُ التكاليف المحمَّلة — المجموعُ يساوي إجماليَّ الورقة بالضبط.
//
// ═══ لماذا هذا الفحص ═══
//
// `calculateAllocations` كانت تقسم نسبيّاً وتكتب الكسرَ العائمَ كما هو. وثلاثةُ
// بنودٍ متساويةٍ على مبلغٍ لا يقبل القسمةَ على ثلاثةٍ تعطي `33.333…` ثلاثَ
// مرّات، فمجموعُ المكتوب يخالف إجماليَّ الورقة.
//
// وذلك ليس تجميليّاً: `applyLandedCost` يقيّد **إجماليَّ الورقة** مديناً على
// المخزون بينما يبلبل الأسطرَ على متوسّطات التكلفة — فيبقى في حساب المخزون
// فرقٌ لا يقابله تحريكُ تكلفةٍ في أيّ صنف. والتعليقُ داخلَ `applyLandedCost`
// يبني عليها صراحةً: «total == Σ allocatedAmount».
//
// فالمقياسُ هنا هو تلك المساواةُ نفسُها، وأنّ الباقيَ وقع على **أكبر بند**
// كما يصف التصميمُ في رأس جدول التوزيع.

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/data/database/database.dart';

void main() {
  late AppDatabase db;
  late int warehouseId;
  late int supplierId;

  setUp(() async {
    db = AppDatabase.forTesting();
    await db.syncDefaultAccounts();

    final branchId = await db.into(db.branches).insert(
          BranchesCompanion.insert(
            name: 'main-lcr',
            globalId: const Value('gid-br-lcr'),
          ),
        );
    warehouseId = await db.into(db.warehouses).insert(
          WarehousesCompanion.insert(
            name: 'wh-lcr',
            branchId: Value(branchId),
            globalId: const Value('gid-wh-lcr'),
          ),
        );
    supplierId = await db.into(db.parties).insert(
          PartiesCompanion.insert(
            name: 'مورد التقريب',
            isSupplier: const Value(true),
            isCustomer: const Value(false),
            globalId: const Value('gid-supplier-lcr'),
          ),
        );
  });

  tearDown(() async => db.close());

  /// فاتورةُ شراءٍ بثلاثةِ أصنافٍ متساويةِ القيمة — فالقسمةُ «بالتساوي»
  /// و«بالقيمة» كلتاهما تعطيان ثلثاً لا ينتهي.
  Future<int> threeEqualLines() async {
    final ids = <int>[];
    for (var i = 1; i <= 3; i++) {
      ids.add(await db.insertProduct(
        ProductsCompanion.insert(
          code: 'LCR-0$i',
          name: 'صنف تقريب $i',
          salePrice: const Value(200.0),
          costPrice: const Value(100.0),
          currentStock: const Value(0),
          trackInventory: const Value(true),
        ),
      ));
    }
    return db.createPurchaseInvoice(
      supplierId: supplierId,
      warehouseId: warehouseId,
      paid: 0.0,
      paymentMethod: 'credit',
      items: [
        for (final pid in ids)
          PurchaseInvoiceItemsCompanion.insert(
            invoiceId: 0,
            productId: pid,
            quantity: 10,
            unitCost: 100,
            total: 1000,
          ),
      ],
    );
  }

  /// ورقةُ تحميلٍ بمبلغٍ لا يقبل القسمةَ على ثلاثة.
  Future<int> sheetWith(int invoiceId, String method, double amount) async {
    final sheetId = await db.createLandedCostSheet(
      purchaseInvoiceId: invoiceId,
      sheetNumber: 'LC-ROUND-$method-${amount.toStringAsFixed(0)}',
      allocationMethod: method,
    );
    await db.addLandedCostItem(
      sheetId: sheetId,
      costType: 'shipping',
      description: 'شحن اختبار التقريب',
      amount: amount,
    );
    return sheetId;
  }

  for (final method in ['by_value', 'by_quantity', 'equal']) {
    test('$method — مجموعُ ما وُزِّع يساوي إجماليَّ الورقة بالضبط', () async {
      final inv = await threeEqualLines();
      // ١٠٠ ÷ ٣ = ٣٣٫٣٣٣… — أشهرُ ما يُنتج فرقَ تقريب.
      final sheetId = await sheetWith(inv, method, 100);

      final allocs = await db.calculateAllocations(sheetId);
      expect(allocs, hasLength(3), reason: 'الأصنافُ الثلاثةُ كلُّها وُزِّع عليها');

      final sum = allocs.fold<double>(0, (s, a) => s + a.allocatedAmount);

      // ⚠️ `closeTo` بهامشٍ ضيّقٍ جدّاً لا `equals`: القيمُ عائمةٌ، لكنّ
      //    الهامشَ أضيقُ من نصفِ قرشٍ فيسقط الفحصُ على أيّ فرقٍ حقيقيّ.
      expect(sum, closeTo(100.0, 0.0001),
          reason: 'مجموعُ الأسطر $sum يخالف إجماليَّ الورقة ١٠٠ — '
              'فالقيدُ على المخزون لن يقابله تحريكُ تكلفةٍ مساوٍ.');
    });
  }

  test('الباقي يقع على أكبر بندٍ لا على أوّلِ بند', () async {
    // ⚠️ **الأرقامُ مختارةٌ لتُنتج فرقاً فعلاً.** أساسٌ مجموعُه ٩٠٠٠ يجعل كلَّ
    //    نصيبٍ كسراً دوريّاً (‏٤/٩ و٣/٩ و٢/٩)، فالتقريبُ إلى قرشَين يعطي
    //    ٤٤٫٤٤ + ٣٣٫٣٣ + ٢٢٫٢٢ = ٩٩٫٩٩ — وباقٍ قدرُه قرشٌ واحد.
    //
    //    ولو قُسِم الأساسُ على ١٠٠٠٠ (‏٦٠٪ و٣٠٪ و١٠٪) لانتهى الكسرُ ولم يبقَ
    //    شيءٌ — فمرَّ الفحصُ وهو لا يقيس شيئاً. وهذا ما أسقط الصيغةَ الأولى.
    final ids = <int>[];
    for (var i = 1; i <= 3; i++) {
      ids.add(await db.insertProduct(
        ProductsCompanion.insert(
          code: 'LCB-0$i',
          name: 'صنف متفاوت $i',
          salePrice: const Value(200.0),
          costPrice: const Value(100.0),
          currentStock: const Value(0),
          trackInventory: const Value(true),
        ),
      ));
    }
    const qtys = [40.0, 30.0, 20.0];
    final inv = await db.createPurchaseInvoice(
      supplierId: supplierId,
      warehouseId: warehouseId,
      paid: 0.0,
      paymentMethod: 'credit',
      items: [
        for (var i = 0; i < 3; i++)
          PurchaseInvoiceItemsCompanion.insert(
            invoiceId: 0,
            productId: ids[i],
            quantity: qtys[i],
            unitCost: 100,
            total: qtys[i] * 100,
          ),
      ],
    );

    final sheetId = await sheetWith(inv, 'by_value', 100);
    final allocs = await db.calculateAllocations(sheetId);

    final sum = allocs.fold<double>(0, (s, a) => s + a.allocatedAmount);
    expect(sum, closeTo(100.0, 0.0001),
        reason: 'المجموعُ لا يستوي بالإجماليّ عند قيمٍ متفاوتة.');

    final byProduct = {for (final a in allocs) a.productId: a.allocatedAmount};

    // الأصغران يبقيان على نصيبهما المقرَّب بالضبط…
    expect(byProduct[ids[1]], closeTo(33.33, 0.0001),
        reason: 'البندُ المتوسّطُ انحرف عن نصيبه المقرَّب — الباقي أُلقي '
            'عليه وهو ليس الأكبر.');
    expect(byProduct[ids[2]], closeTo(22.22, 0.0001),
        reason: 'أصغرُ بندٍ انحرف عن نصيبه المقرَّب — الباقي أُلقي عليه.');

    // …وأكبرُهما وحدَه يستوعب القرشَ الباقي: ٤٤٫٤٤ + ٠٫٠١.
    expect(byProduct[ids[0]], closeTo(44.45, 0.0001),
        reason: 'أكبرُ بندٍ لم يستوعب الباقي — المتوقَّعُ ٤٤٫٤٥ '
            '(‏٤٤٫٤٤ نصيبُه المقرَّب + ٠٫٠١ باقي التقريب).');
  });
}
