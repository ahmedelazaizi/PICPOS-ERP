// سيناريو (ل): الصلاحيات في الطبقة الخدمية — مستخدم بلا صلاحية يُرفض، وبعد منحها
// ينجح، والرفض لا يترك أثراً. (مرجع: test/unit/critical_financial_ops_gate_test.dart
// و test/unit/security_phase1_gates_test.dart — هنا على مستندات حقيقية كاملة.)
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/core/permissions/permission_codes.dart';
import 'package:ural_erp/data/providers/providers.dart';
import 'package:ural_erp/domain/usecases/treasury/create_voucher_usecase.dart';

import 'scenario_world.dart';

void main() {
  late ScenarioWorld w;
  late int product;
  late int customer;
  late int cashierId; // مستخدم بدور بلا أي صلاحية حرجة

  setUp(() async {
    w = await ScenarioWorld.create();
    product = await w.addProduct('L1', price: 100, cost: 60, stock: 50);
    customer = await w.addCustomer('عميل الصلاحيات');
    final role = await w.db.into(w.db.roles).insert(
        RolesCompanion.insert(name: 'كاشير بلا صلاحيات', isSystemRole: const Value(false)));
    cashierId = await w.db.createUser(
        username: 'plain_cashier',
        password: 'plain-cashier-pw',
        displayName: 'كاشير',
        roleId: role);
  });
  tearDown(() => w.dispose());

  test('إلغاء فاتورة مدفوعة كاملاً: مرفوض بـPermissionDeniedException(voidPaidInvoice) '
      'ولا يتغير شيء؛ وبعد منح الصلاحية ينجح', () async {
    final r = await w.sell([w.line(product, 2, 100)]);

    await expectLater(
        w.db.voidSalesInvoice(r.invoiceId!, deletedBy: cashierId),
        throwsA(isA<PermissionDeniedException>().having(
            (e) => e.code, 'code', PermissionCodes.voidPaidInvoice)));
    final inv = (await w.db.getSalesInvoiceById(r.invoiceId!))!;
    expect(inv.status, isNot('voided'));
    expect(await w.stock(product), closeTo(48, kEps));
    expect(await w.safeBalance(), closeTo(200, kEps));

    await w.grant(PermissionCodes.voidPaidInvoice, forUser: cashierId);
    await w.db.voidSalesInvoice(r.invoiceId!, deletedBy: cashierId);
    expect(await w.stock(product), closeTo(50, kEps));
    expect(await w.safeBalance(), closeTo(0, kEps));
  });

  test('إلغاء بلا هوية مستخدم (deletedBy=null) مرفوض للفاتورة المدفوعة', () async {
    final r = await w.sell([w.line(product, 1, 100)]);
    await expectLater(w.db.voidSalesInvoice(r.invoiceId!),
        throwsA(isA<PermissionDeniedException>()));
    expect(await w.stock(product), closeTo(49, kEps));
  });

  test('سند قبض يدوي: مرفوض بلا treasuryReceiptsCreate ولا يمس الخزينة أو العميل',
      () async {
    await w.sell([w.line(product, 3, 100)], customerId: customer, method: 'credit');
    await w.db.openShift(cashierId, 0);
    final uc = CreateVoucherUseCase(w.container.read(treasuryRepositoryProvider));

    await expectLater(
        uc.createReceipt(
            amount: 100,
            category: 'customers',
            safeId: w.cashSafeId,
            partyId: customer,
            userId: cashierId),
        throwsA(isA<PermissionDeniedException>()));
    expect(await w.partyBalance(customer), closeTo(300, kEps));
    expect(await w.safeBalance(), closeTo(0, kEps));

    await w.grant(PermissionCodes.treasuryReceiptsCreate, forUser: cashierId);
    await uc.createReceipt(
        amount: 100,
        category: 'customers',
        safeId: w.cashSafeId,
        partyId: customer,
        userId: cashierId);
    expect(await w.partyBalance(customer), closeTo(200, kEps));
    expect(await w.safeBalance(), closeTo(100, kEps));
  });

  test('سند صرف يدوي: مرفوض بلا treasuryPaymentsCreate', () async {
    await w.sell([w.line(product, 3, 100)]);
    final uc = CreateVoucherUseCase(w.container.read(treasuryRepositoryProvider));
    await expectLater(
        uc.createPayment(
            amount: 50,
            category: 'مصروف',
            safeId: w.cashSafeId,
            userId: cashierId),
        throwsA(isA<PermissionDeniedException>()));
    expect(await w.safeBalance(), closeTo(300, kEps));
  });

  test('المدير الافتراضي لا يتجاوز العمليات الحرجة (فصل المهام)', () async {
    // مستخدم السيناريو يملك voidPaidInvoice فقط؛ سحب الصلاحية يعيد الرفض.
    final r = await w.sell([w.line(product, 1, 100)]);
    final u = await (w.db.select(w.db.users)..where((x) => x.id.equals(w.userId)))
        .getSingle();
    final perm = await (w.db.select(w.db.permissions)
          ..where((p) => p.code.equals(PermissionCodes.voidPaidInvoice)))
        .getSingle();
    await (w.db.delete(w.db.rolePermissions)
          ..where((rp) => rp.roleId.equals(u.roleId!) & rp.permissionId.equals(perm.id)))
        .go();
    await expectLater(w.db.voidSalesInvoice(r.invoiceId!, deletedBy: w.userId),
        throwsA(isA<PermissionDeniedException>()));
  });
}
