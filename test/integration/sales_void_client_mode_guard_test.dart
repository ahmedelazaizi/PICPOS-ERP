// عيب (2) — وضع العميل/المرآة: `SalesRepositoryImpl.voidInvoice` كان يرسل الإلغاء
// ثم يكتب «ملغاة» محليًا قبل أن يردّ الخادم، فإن رفض الخادم (فاتورة لها مرتجع)
// بقي المحلي ملغيًا والخادم حيًّا. الفحص نفسه يجب أن يسبق أي إرسال/كتابة محلية.
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/data/database/sync_interceptor.dart';
import 'package:picpos_erp/data/providers/providers.dart';
import 'package:picpos_erp/data/repositories/sales_repository_impl.dart';
import 'package:picpos_erp/domain/models/return_original_link.dart';

import '../scenarios/scenario_world.dart';

/// مُعترِض يزعم وضع العميل؛ أي استدعاء آخر عليه يعني أن الكود تجاوز الفحص.
class _ClientModeInterceptor implements SyncInterceptor {
  @override
  bool get isClientModeImpl => true;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late ScenarioWorld w;
  late int product;

  setUp(() async {
    SyncInterceptor.instance = null;
    w = await ScenarioWorld.create();
    product = await w.addProduct('CM1', price: 100, cost: 60, stock: 50);
  });
  tearDown(() async {
    SyncInterceptor.instance = null;
    await w.dispose();
  });

  Future<String> statusOf(int id) async => (await (w.db.select(w.db.salesInvoices)
            ..where((i) => i.id.equals(id)))
          .getSingle())
      .status;

  test('وضع العميل: فاتورة لها مرتجع تُرفض قبل أي إرسال، والمحلي لا يصير ملغاة', () async {
    final r = await w.sell([w.line(product, 5, 100)]);
    await w.returnItems(r.invoiceId!, product, 2);
    expect(await statusOf(r.invoiceId!), 'partial_return');

    SyncInterceptor.instance = _ClientModeInterceptor();
    final repo = SalesRepositoryImpl(
        w.db, w.container.read(accountingServiceProvider));

    await expectLater(
      repo.voidInvoice(r.invoiceId!, reason: 'اختبار', userId: w.userId),
      throwsA(isA<SalesVoidBlockedException>()
          .having((e) => e.message, 'message', kSalesVoidHasReturnMessage)),
    );

    expect(await statusOf(r.invoiceId!), 'partial_return',
        reason: 'لا علامة "voided" محلية');
    expect(await w.stock(product), closeTo(47, kEps));
    expect(await w.safeBalance(), closeTo(300, kEps));
  });

  test('وضع العميل: cancelInvoice (المسار الذي تنادِيه الواجهة) يُرفض بالمثل', () async {
    final r = await w.sell([w.line(product, 5, 100)]);
    await w.returnItems(r.invoiceId!, product, 2);

    SyncInterceptor.instance = _ClientModeInterceptor();
    final repo = SalesRepositoryImpl(
        w.db, w.container.read(accountingServiceProvider));

    await expectLater(repo.cancelInvoice(r.invoiceId!, userId: w.userId),
        throwsA(isA<SalesVoidBlockedException>()));
    expect(await statusOf(r.invoiceId!), 'partial_return');
  });
}
