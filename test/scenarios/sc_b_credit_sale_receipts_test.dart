// سيناريو (ب): بيع آجل لعميل ← سند قبض جزئي ← سند قبض كامل. رصيد العميل في
// كشف الحساب يطابق القيود (دفتر الأستاذ) وبطاقة العميل والخزينة.
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/core/permissions/permission_codes.dart';
import 'package:ural_erp/data/providers/providers.dart';
import 'package:ural_erp/domain/usecases/treasury/create_voucher_usecase.dart';

import 'scenario_world.dart';

void main() {
  late ScenarioWorld w;
  late int product;
  late int customer;

  setUp(() async {
    w = await ScenarioWorld.create();
    await w.grant(PermissionCodes.treasuryReceiptsCreate);
    product = await w.addProduct('B1', price: 100, cost: 60, stock: 50);
    customer = await w.addCustomer('عميل آجل');
  });
  tearDown(() => w.dispose());

  CreateVoucherUseCase vouchers() =>
      CreateVoucherUseCase(w.container.read(treasuryRepositoryProvider));

  test('(ب) آجل 500 ← قبض 200 ← قبض 300: الرصيد 500 → 300 → 0 ويطابق القيود',
      () async {
    await w.sell([w.line(product, 5, 100)],
        customerId: customer, method: 'credit');

    // بعد البيع الآجل: لا نقدية، العميل مدين 500، المخزون 45
    expect(await w.partyBalance(customer), closeTo(500, kEps));
    expect(await w.safeBalance(), closeTo(0, kEps));
    expect(await w.stock(product), closeTo(45, kEps));
    expect(await w.accountNet('1121'), closeTo(500, kEps));

    // سند قبض جزئي 200
    await vouchers().createReceipt(
        amount: 200,
        category: 'customers',
        safeId: w.cashSafeId,
        partyId: customer,
        userId: w.userId);
    expect(await w.partyBalance(customer), closeTo(300, kEps));
    expect(await w.safeBalance(), closeTo(200, kEps));
    expect(await w.accountNet('1121'), closeTo(300, kEps));

    // كشف الحساب: آخر رصيد جارٍ = 300، ومجموع المدين − الدائن = 300
    var statement = await w.db.getPartyStatement(customer);
    expect(statement.last.balance, closeTo(300, kEps));
    expect(statement.fold<double>(0, (s, e) => s + e.debit - e.credit),
        closeTo(300, kEps));

    // سند قبض يسدّد الباقي 300
    await vouchers().createReceipt(
        amount: 300,
        category: 'customers',
        safeId: w.cashSafeId,
        partyId: customer,
        userId: w.userId);
    expect(await w.partyBalance(customer), closeTo(0, kEps));
    expect(await w.safeBalance(), closeTo(500, kEps));
    expect(await w.accountNet('1121'), closeTo(0, kEps));

    statement = await w.db.getPartyStatement(customer);
    expect(statement, hasLength(3), reason: 'فاتورة + قبضان');
    expect(statement.last.balance, closeTo(0, kEps));
    expect(statement.fold<double>(0, (s, e) => s + e.debit), closeTo(500, kEps));
    expect(statement.fold<double>(0, (s, e) => s + e.credit), closeTo(500, kEps));

    expect(await w.unbalancedEntries(), isEmpty);
    expect(await w.db.getPartyBalanceMismatches(), isEmpty,
        reason: 'بطاقة العميل = رصيد حسابه في الأستاذ');
  });

  test('(ب) سند قبض يتخطّى رصيد الفاتورة لا يترك الدفتر غير متوازن', () async {
    await w.sell([w.line(product, 2, 100)], customerId: customer, method: 'credit');
    await vouchers().createReceipt(
        amount: 250,
        category: 'customers',
        safeId: w.cashSafeId,
        partyId: customer,
        userId: w.userId);
    // العميل صار دائناً بـ 50 (دفعة مقدمة) ويطابق الأستاذ
    expect(await w.partyBalance(customer), closeTo(-50, kEps));
    expect(await w.accountNet('1121'), closeTo(-50, kEps));
    expect(await w.unbalancedEntries(), isEmpty);
  });
}
