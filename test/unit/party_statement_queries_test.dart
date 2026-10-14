// استعلاماتُ تبويبات كشف الحساب.
//
// ═══ ما يحمي هذا الملفّ ═══
//
// أربعةُ استعلاماتٍ تقوم عليها ثمانِ تبويباتٍ في كشفَي العميل والمورد. ولكلٍّ
// عطبٌ يمرّ صامتاً — يُنتج شاشةً تعرض أرقاماً معقولةً وكاذبة:
//
//  ‏١) **الفواتيرُ القائمة**: لو رُشِّحت بـ`status` بدل `total > paid` لسقطت
//     فاتورةٌ وسمُها «مسدَّدة» ورصيدُها موجب. والمالُ لا يتبع وسماً.
//  ‏٢) **مطابقةُ الدفعات**: ضمٌّ داخليٌّ يُخفي الدفعةَ **غيرَ المطابَقة** —
//     وهي بالضبط ما يبحث عنه التقرير.
//  ‏٣) **المطابقةُ الثلاثيّة**: جمعُ كلّ فواتير المورد بدل فاتورةِ الأمر
//     يَنسب إلى الأمر بضاعةً لم تأتِ منه.
//  ‏٤) **معدّلاتُ الملفّ**: أمرٌ **مفتوحٌ** لو دخل حسابَ الالتزام لعُدَّ
//     تأخّراً، فينهار تقييمُ مورّدٍ ملتزمٍ كلّما فُتح له أمرٌ جديد.
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/database/database.dart';

void main() {
  late AppDatabase db;
  late int wh;
  late int user;
  late int customer;
  late int supplier;
  late int product;
  late int safe;

  final asOf = DateTime(2026, 8, 26);

  setUp(() async {
    db = AppDatabase.forTesting();
    wh = await db
        .into(db.warehouses)
        .insert(WarehousesCompanion.insert(name: 'المخزن'));
    user = await db
        .into(db.users)
        .insert(
          UsersCompanion.insert(
            username: 'cashier9',
            passwordHash: 'x',
            displayName: 'كاشير',
          ),
        );
    customer = await db
        .into(db.parties)
        .insert(PartiesCompanion.insert(name: 'سوبر ماركت النور'));
    supplier = await db
        .into(db.parties)
        .insert(
          PartiesCompanion.insert(
            name: 'جهينة للأغذية',
            isSupplier: const Value(true),
          ),
        );
    safe = await db
        .into(db.safes)
        .insert(SafesCompanion.insert(name: 'صندوق الكاشير'));
    product = await db
        .into(db.products)
        .insert(
          ProductsCompanion.insert(
            code: 'P-1',
            name: 'لبن كامل الدسم',
            costPrice: const Value(6),
            salePrice: const Value(10),
          ),
        );
  });

  Future<int> sale({
    required DateTime issued,
    DateTime? due,
    double total = 1000,
    double paid = 0,
    String? saleType,
    String number = 'S-1',
    int? warehouseId,
  }) => db
      .into(db.salesInvoices)
      .insert(
        SalesInvoicesCompanion.insert(
          invoiceNumber: number,
          warehouseId: warehouseId ?? wh,
          userId: user,
          customerId: Value(customer),
          invoiceDate: issued,
          dueDate: Value(due),
          total: Value(total),
          paid: Value(paid),
          saleType: Value.absentIfNull(saleType),
        ),
      );

  group('الفواتيرُ القائمة', () {
    test('المسدَّدُ كاملاً يخرج، والجزئيُّ يبقى بمتبقّيه', () async {
      await sale(issued: DateTime(2026, 8, 1), total: 1000, paid: 1000);
      await sale(
        issued: DateTime(2026, 8, 2),
        total: 800,
        paid: 300,
        number: 'S-2',
      );

      final rows = await db.getPartyOpenInvoices(
        partyId: customer,
        supplier: false,
        asOf: asOf,
      );

      expect(rows, hasLength(1));
      expect(rows.single.invoiceNumber, 'S-2');
      expect(rows.single.remaining, 500);
    });

    test(
      'branch scope keeps its branch and global-warehouse invoices only',
      () async {
        final selectedBranch = await db
            .into(db.branches)
            .insert(BranchesCompanion.insert(name: 'Selected branch'));
        final otherBranch = await db
            .into(db.branches)
            .insert(BranchesCompanion.insert(name: 'Other branch'));
        final selectedWarehouse = await db
            .into(db.warehouses)
            .insert(
              WarehousesCompanion.insert(
                name: 'Selected warehouse',
                branchId: Value(selectedBranch),
              ),
            );
        final otherWarehouse = await db
            .into(db.warehouses)
            .insert(
              WarehousesCompanion.insert(
                name: 'Other warehouse',
                branchId: Value(otherBranch),
              ),
            );

        await sale(
          issued: DateTime(2026, 8, 1),
          number: 'BRANCH-SELECTED',
          warehouseId: selectedWarehouse,
        );
        await sale(
          issued: DateTime(2026, 8, 2),
          number: 'BRANCH-OTHER',
          warehouseId: otherWarehouse,
        );
        await sale(issued: DateTime(2026, 8, 3), number: 'BRANCH-GLOBAL');

        final scoped = await db.getPartyOpenInvoices(
          partyId: customer,
          supplier: false,
          asOf: asOf,
          branchId: selectedBranch,
        );
        expect(scoped.map((row) => row.invoiceNumber).toSet(), {
          'BRANCH-SELECTED',
          'BRANCH-GLOBAL',
        });

        final unfiltered = await db.getPartyOpenInvoices(
          partyId: customer,
          supplier: false,
          asOf: asOf,
        );
        expect(unfiltered.map((row) => row.invoiceNumber).toSet(), {
          'BRANCH-SELECTED',
          'BRANCH-OTHER',
          'BRANCH-GLOBAL',
        });

        Future<void> purchase(String invoiceNumber, int warehouseId) async {
          await db
              .into(db.purchaseInvoices)
              .insert(
                PurchaseInvoicesCompanion.insert(
                  invoiceNumber: invoiceNumber,
                  supplierId: supplier,
                  warehouseId: warehouseId,
                  invoiceDate: DateTime(2026, 8, 10),
                  total: const Value(200),
                ),
              );
        }

        await purchase('PURCHASE-SELECTED', selectedWarehouse);
        await purchase('PURCHASE-OTHER', otherWarehouse);
        await purchase('PURCHASE-GLOBAL', wh);

        final supplierScoped = await db.getPartyOpenInvoices(
          partyId: supplier,
          supplier: true,
          asOf: asOf,
          branchId: selectedBranch,
        );
        expect(supplierScoped.map((row) => row.invoiceNumber).toSet(), {
          'PURCHASE-SELECTED',
          'PURCHASE-GLOBAL',
        });
      },
    );

    test('العمرُ من الاستحقاق، والسالبُ يبقى سالباً', () async {
      // تستحق بعد عشرةِ أيّامٍ من نقطة القياس.
      await sale(
        issued: DateTime(2026, 8, 1),
        due: asOf.add(const Duration(days: 10)),
        total: 500,
      );
      final r = (await db.getPartyOpenInvoices(
        partyId: customer,
        supplier: false,
        asOf: asOf,
      )).single;

      expect(
        r.daysLate,
        lessThan(0),
        reason: 'التأخّرُ قُصّ إلى صفرٍ — «يستحق بعد ١٠ أيّام» ضاعت',
      );
      expect(r.overdue, isFalse);
      expect(r.bucket, 'لم يحن');
    });

    test('المرتجعُ ليس ذمّةً قائمة', () async {
      await sale(
        issued: DateTime(2026, 8, 1),
        total: 300,
        saleType: 'return',
        number: 'R-1',
      );
      expect(
        await db.getPartyOpenInvoices(
          partyId: customer,
          supplier: false,
          asOf: asOf,
        ),
        isEmpty,
      );
    });
  });

  group('مطابقةُ الدفعات', () {
    Future<int> payment({required double amount, String number = 'PAY-1'}) => db
        .into(db.payments)
        .insert(
          PaymentsCompanion.insert(
            paymentNumber: number,
            paymentDate: DateTime(2026, 8, 10),
            amount: amount,
            partyId: Value(customer),
            safeId: safe,
            paymentType: 'receipt',
          ),
        );

    test('دفعةٌ بلا تخصيصٍ تظهر غيرَ مطابَقة', () async {
      await payment(amount: 400);
      final r = (await db.getPartyPaymentMatches(partyId: customer)).single;

      expect(r.allocated, 0);
      expect(
        r.unallocated,
        400,
        reason: 'الضمُّ داخليٌّ — الدفعةُ غيرُ المطابَقة اختفت',
      );
      expect(r.fullyMatched, isFalse);
      expect(r.invoiceCount, 0);
    });

    test('التخصيصاتُ تُجمَع ويُعَدُّ عددُ الفواتير', () async {
      final inv1 = await sale(issued: DateTime(2026, 8, 1), total: 300);
      final inv2 = await sale(
        issued: DateTime(2026, 8, 2),
        total: 200,
        number: 'S-2',
      );
      final pay = await payment(amount: 500);
      for (final inv in [inv1, inv2]) {
        await db
            .into(db.paymentAllocations)
            .insert(
              PaymentAllocationsCompanion.insert(
                paymentId: pay,
                invoiceType: 'sales',
                invoiceId: inv,
                allocatedAmount: inv == inv1 ? 300 : 200,
              ),
            );
      }

      final r = (await db.getPartyPaymentMatches(partyId: customer)).single;
      expect(r.allocated, 500);
      expect(r.unallocated, 0);
      expect(r.fullyMatched, isTrue);
      expect(r.invoiceCount, 2);
    });
  });

  group('المطابقةُ الثلاثيّة', () {
    test('المطلوبُ والمستلَمُ والمفوتَرُ ونوعُ الفرق', () async {
      final order = await db
          .into(db.purchaseOrders)
          .insert(
            PurchaseOrdersCompanion.insert(
              orderNumber: 'PO-1',
              supplierId: supplier,
              warehouseId: wh,
              orderDate: DateTime(2026, 8, 1),
              expectedDate: Value(DateTime(2026, 8, 5)),
            ),
          );
      await db
          .into(db.purchaseOrderItems)
          .insert(
            PurchaseOrderItemsCompanion.insert(
              orderId: order,
              productId: product,
              quantity: 100,
              unitCost: 6,
              total: 600,
              receivedQuantity: const Value(90),
            ),
          );

      final rows = await db.getPurchaseOrderMatches(supplierId: supplier);
      expect(rows, hasLength(1));
      final r = rows.single;
      expect(r.ordered, 100);
      expect(r.received, 90);
      // لم يُحوَّل الأمرُ إلى فاتورةٍ بعد ⇒ المفوتَرُ صفر.
      expect(r.invoiced, 0);
      expect(r.qtyGap, -10);
      expect(r.clean, isFalse);
      expect(r.gapKind, 'نقصُ استلام');
      expect(r.productName, 'لبن كامل الدسم');
    });
  });

  group('معدّلاتُ الملفّ', () {
    test('أمرٌ مفتوحٌ لا يُحتسَب تأخّراً', () async {
      // أمرٌ استُلم متأخّراً + أمرٌ لم يُستلَم بعد.
      await db
          .into(db.purchaseOrders)
          .insert(
            PurchaseOrdersCompanion.insert(
              orderNumber: 'PO-late',
              supplierId: supplier,
              warehouseId: wh,
              orderDate: DateTime(2026, 8, 1),
              expectedDate: Value(DateTime(2026, 8, 5)),
              receivedAt: Value(DateTime(2026, 8, 9)),
            ),
          );
      await db
          .into(db.purchaseOrders)
          .insert(
            PurchaseOrdersCompanion.insert(
              orderNumber: 'PO-open',
              supplierId: supplier,
              warehouseId: wh,
              orderDate: DateTime(2026, 8, 10),
              expectedDate: Value(DateTime(2026, 8, 12)),
            ),
          );

      final m = await db.getPartyProfileMetrics(
        partyId: supplier,
        supplier: true,
      );

      expect(
        m.receivedOrders,
        1,
        reason:
            'أمرٌ مفتوحٌ دخل حسابَ الالتزام — التقييمُ ينهار بكلّ أمرٍ جديد',
      );
      expect(m.onTimeOrders, 0);
      expect(m.onTimeDeliveryPct, 0);
    });

    test('بلا أوامرَ مستلَمةٍ ⇒ «لا بيانات» لا «صفر٪»', () async {
      final m = await db.getPartyProfileMetrics(
        partyId: supplier,
        supplier: true,
      );
      expect(m.receivedOrders, 0);
      expect(
        m.onTimeDeliveryPct,
        isNull,
        reason: '«لا بيانات» عُرضت صفراً — تقييمٌ ظالمٌ لمورّدٍ جديد',
      );
      expect(m.onTimeSettlementPct, isNull);
    });
  });

  group('الأوراقُ التجاريّة', () {
    test('أوراقُ الطرفِ وحدَه مرتَّبةً بالاستحقاق', () async {
      for (final d in [DateTime(2026, 9, 10), DateTime(2026, 9, 1)]) {
        await db
            .into(db.commercialPapers)
            .insert(
              CommercialPapersCompanion.insert(
                paperNumber: 'CHQ-${d.day}',
                type: 'cheque',
                direction: 'incoming',
                partyId: customer,
                amount: 1000,
                issueDate: DateTime(2026, 8, 1),
                dueDate: d,
              ),
            );
      }
      final papers = await db.getPartyPapers(customer);
      expect(papers, hasLength(2));
      expect(papers.first.dueDate.day, 1, reason: 'الترتيبُ ليس بالاستحقاق');
      expect(await db.getPartyPapers(supplier), isEmpty);
    });
  });
}
