// سيناريو (ح): وردية — فتح، بيع نقدي، إقفال بعجز أو فائض يُرحَّل بقيد.
import 'package:flutter_test/flutter_test.dart';

import 'scenario_world.dart';

void main() {
  late ScenarioWorld w;
  late int product;

  setUp(() async {
    w = await ScenarioWorld.create(openShift: false);
    product = await w.addProduct('H1', price: 100, cost: 60, stock: 50);
  });
  tearDown(() => w.dispose());

  Future<Shift> shiftRow(int id) =>
      (w.db.select(w.db.shifts)..where((s) => s.id.equals(id))).getSingle();

  test('بيع نقدي بلا وردية مفتوحة يُرفض ولا يترك أثراً', () async {
    final before = await w.journalTotals();
    await expectLater(
        w.sales.completeSalesTransaction(_cash(w, product)),
        throwsA(anything));
    expect(await w.stock(product), closeTo(50, kEps));
    expect(await w.safeBalance(), closeTo(0, kEps));
    final after = await w.journalTotals();
    expect(after.debit, closeTo(before.debit, kEps));
  });

  test('إقفال مطابق: 300 متوقعة و300 فعلية ← فرق صفر بلا قيد فروقات', () async {
    final shiftId = await w.db.openShift(w.userId, 0);
    await w.sell([w.line(product, 3, 100)]);
    await w.db.closeShiftWithAudit(shiftId, 300);
    final s = await shiftRow(shiftId);
    expect(s.status, 'closed');
    expect(s.expectedCash, closeTo(300, kEps));
    expect(s.actualCash, closeTo(300, kEps));
    expect(s.variance, closeTo(0, kEps));
    expect(await w.linesOf('shift_close', shiftId), isEmpty,
        reason: 'لا فرق ⇒ لا قيد عجز/فائض');
    // النقدية تنتقل من درج الكاشير إلى الصندوق الرئيسي كاملة
    expect(await w.safeBalance(), closeTo(0, kEps));
    expect((await w.db.getCentralSafe())!.balance, closeTo(300, kEps));
    expect(await w.unbalancedEntries(), isEmpty);
  });

  test('إقفال بعجز 20: متوقع 300 وفعلي 280 ← variance=−20 وقيد عجز 20', () async {
    final shiftId = await w.db.openShift(w.userId, 0);
    await w.sell([w.line(product, 3, 100)]);
    await w.db.closeShiftWithAudit(shiftId, 280, notes: 'عجز');

    final s = await shiftRow(shiftId);
    expect(s.status, 'closed');
    expect(s.expectedCash, closeTo(300, kEps));
    expect(s.actualCash, closeTo(280, kEps));
    expect(s.variance, closeTo(-20, kEps), reason: 'variance = فعلي − متوقع');
    final je = await w.linesOf('shift_close', shiftId);
    expect(je.fold<double>(0, (a, l) => a + (l['debit'] as num)), closeTo(20, kEps));
    expect(je.fold<double>(0, (a, l) => a + (l['credit'] as num)), closeTo(20, kEps));
    expect(je.where((l) => (l['debit'] as num) > 0).single['code'], '6217');
    expect(await w.unbalancedEntries(), isEmpty);
    expect(await w.accountNet('111'), closeTo(280, kEps));
    expect((await w.db.getCentralSafe())!.balance, closeTo(280, kEps));
    expect(await w.safeBalance(), closeTo(0, kEps));
  });

  test('إقفال بفائض 30: متوقع 300 وفعلي 330 ← variance=+30 وقيد فائض 30',
      () async {
    final shiftId = await w.db.openShift(w.userId, 0);
    await w.sell([w.line(product, 3, 100)]);
    await w.db.closeShiftWithAudit(shiftId, 330);

    final s = await shiftRow(shiftId);
    expect(s.variance, closeTo(30, kEps));
    final je = await w.linesOf('shift_close', shiftId);
    expect(je.fold<double>(0, (a, l) => a + (l['debit'] as num)), closeTo(30, kEps));
    expect(je.where((l) => (l['credit'] as num) > 0).single['code'], isNot('6217'));
    // إجمالي أرصدة الخزائن النقدية = النقدية في الأستاذ = المعدود فعلاً (330)
    final total = await w.db.customSelect(
        "select sum(balance) s from safes where safe_type = 'cash'").getSingle();
    expect((total.data['s'] as num).toDouble(), closeTo(330, kEps));
    expect(await w.accountNet('111'), closeTo(330, kEps));
    expect(await w.accountNet('111'), closeTo(330, kEps));
    expect(await w.unbalancedEntries(), isEmpty);
  });

  test('إقفال وردية مغلقة مرة ثانية لا يضاعف قيد الفروقات', () async {
    final shiftId = await w.db.openShift(w.userId, 0);
    await w.sell([w.line(product, 3, 100)]);
    await w.db.closeShiftWithAudit(shiftId, 280);
    final mid = await w.journalTotals();
    await w.db.closeShiftWithAudit(shiftId, 280);
    final end = await w.journalTotals();
    expect(end.debit, closeTo(mid.debit, kEps));
  });
}

SaleRequest _cash(ScenarioWorld w, int product) => SaleRequest(
    items: [w.line(product, 1, 100)],
    warehouseId: w.warehouseId,
    userId: w.userId,
    paymentMethod: 'cash',
    paidAmount: 100,
    taxEnabled: false,
    cashSafeId: w.cashSafeId);
