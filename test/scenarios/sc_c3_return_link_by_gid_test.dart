import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/providers/providers.dart';
import 'package:ural_erp/domain/models/return_original_link.dart';

import 'scenario_world.dart';

void main() {
  late ScenarioWorld w;
  late int product;
  late int customer;

  setUp(() async {
    w = await ScenarioWorld.create();
    product = await w.addProduct('C3', price: 100, cost: 60, stock: 50);
    customer = await w.addCustomer('عميل C3');
  });

  tearDown(() => w.dispose());

  test(
    'مطابقة المرتجع بالـ gid تتجاوز رقم الأصل المختلف وتمنع الإلغاء الخاطئ',
    () async {
      final sale1 = await w.sell(
        [w.line(product, 5, 100)],
        customerId: customer,
        method: 'credit',
      );
      final sale2 = await w.sell(
        [w.line(product, 3, 100)],
        customerId: customer,
        method: 'credit',
      );
      var original1 = (await (w.db.select(
        w.db.salesInvoices,
      )..where((i) => i.id.equals(sale1.invoiceId!))).getSingle());
      var original2 = (await (w.db.select(
        w.db.salesInvoices,
      )..where((i) => i.id.equals(sale2.invoiceId!))).getSingle());

      if (original1.globalId == null || original1.globalId!.isEmpty) {
        await (w.db.update(
          w.db.salesInvoices,
        )..where((i) => i.id.equals(original1.id))).write(
          const SalesInvoicesCompanion(globalId: Value('gid-c3-original-1')),
        );
        original1 = (await (w.db.select(
          w.db.salesInvoices,
        )..where((i) => i.id.equals(original1.id))).getSingle());
      }
      if (original2.globalId == null || original2.globalId!.isEmpty) {
        await (w.db.update(
          w.db.salesInvoices,
        )..where((i) => i.id.equals(original2.id))).write(
          const SalesInvoicesCompanion(globalId: Value('gid-c3-original-2')),
        );
        original2 = (await (w.db.select(
          w.db.salesInvoices,
        )..where((i) => i.id.equals(original2.id))).getSingle());
      }
      expect(original1.globalId, isNotNull);
      expect(original1.globalId, isNotEmpty);
      expect(original2.globalId, isNotNull);
      expect(original2.globalId, isNotEmpty);

      Future<int> addReturn({
        required String gid,
        required int wrongOriginalId,
      }) {
        return w.db.createSalesInvoice(
          warehouseId: w.warehouseId,
          userId: w.userId,
          customerId: customer,
          subtotal: 100,
          discount: 0,
          tax: 0,
          total: 100,
          paid: 0,
          paymentMethod: 'credit',
          saleType: 'return',
          notes: buildReturnOriginalLinkNote(
            wrongOriginalId,
            originalGlobalId: gid,
          ),
          items: [
            SalesInvoiceItemsCompanion.insert(
              invoiceId: 0,
              productId: product,
              quantity: 1,
              unitPrice: 100,
              total: 100,
              costPrice: const Value(60),
            ),
          ],
        );
      }

      final return1Id = await addReturn(
        gid: original1.globalId!,
        wrongOriginalId: original1.id + 100000,
      );
      final return2Id = await addReturn(
        gid: original2.globalId!,
        wrongOriginalId: original1.id,
      );

      final linked = await w.container
          .read(accountingRepositoryProvider)
          .getLinkedSalesReturnDocuments(original1);
      expect(linked.map((row) => row.id), contains(return1Id));
      expect(linked.map((row) => row.id), isNot(contains(return2Id)));
      expect(linked, hasLength(1));

      await expectLater(
        w.db.assertSalesInvoiceVoidable(original1),
        throwsA(isA<SalesVoidBlockedException>()),
      );
      await expectLater(
        w.db.voidSalesInvoice(original1.id, deletedBy: w.userId),
        throwsA(isA<SalesVoidBlockedException>()),
      );

      await w.container
          .read(returnsRepositoryProvider)
          .cancelSalesReturn(
            invoice: original1,
            userId: w.userId,
            userName: 'مستخدم C3',
          );

      final cancelled = (await (w.db.select(
        w.db.salesInvoices,
      )..where((i) => i.id.equals(return1Id))).getSingle());
      expect(cancelled.status, 'voided');
      expect(cancelled.isDeleted, isTrue);

      await w.db.voidSalesInvoice(original1.id, deletedBy: w.userId);
      final voidedOriginal = (await (w.db.select(
        w.db.salesInvoices,
      )..where((i) => i.id.equals(original1.id))).getSingle());
      expect(voidedOriginal.status, 'voided');
      expect(voidedOriginal.isDeleted, isTrue);
    },
  );
}
