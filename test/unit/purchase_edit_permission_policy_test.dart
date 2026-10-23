// ═══════════════════════════════════════════════════════════════════════════
// Purchase-edit policy (owner decision 2026-07-22)
// ═══════════════════════════════════════════════════════════════════════════
//
// Editing a purchase invoice is governed by ONE thing — does the caller hold
// `purchases_edit`?
//   • holds it  → UNLIMITED edits, before AND after the invoice is posted to
//     the GL (`isLocked == true`).
//   • lacks it  → denied outright, posted or not.
//
// What this replaces: `updatePurchaseInvoice` used to demand the
// `modify_locked_invoice` critical-op permission whenever `isLocked` was true,
// but NO call site ever threaded `userId` down to it — so
// `PermissionEnforcer.hasCriticalOp(null, ...)` always returned false and
// EVERY posted purchase invoice became permanently uneditable, for every user
// including مدير النظام. Because the first edit itself re-posts the GL entry
// (and `autoPostPurchase` sets `isLocked`), the practical limit was exactly
// ONE edit per invoice. The UI compounded it by hard-disabling the edit button
// on `isLocked`, so the permission was unreachable even in principle.
//
// The three tests below pin the policy end-to-end: unlimited edits for a
// permission holder (test 1), denial without the permission (test 2), and
// denial for an anonymous/system caller (test 3).
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/data/database/database.dart';
import 'package:picpos_erp/core/permissions/permission_codes.dart';

void main() {
  late AppDatabase db;
  late int supplierId;
  late int warehouseId;
  late int productId;

  /// Seeded `admin` (role_id 1 = مدير النظام). `purchases_edit` is a normal
  /// permission — not in `PermissionCodes.criticalFinancialOps` — so the
  /// system-admin bypass grants it.
  Future<int> adminUserId() async {
    final row = await db
        .customSelect("SELECT id FROM users WHERE username = 'admin' LIMIT 1")
        .getSingle();
    return row.read<int>('id');
  }

  /// A user on a fresh role with NO permissions at all.
  Future<int> unprivilegedUserId() async {
    final roleId = await db.into(db.roles).insert(
          RolesCompanion.insert(
            name: 'مشاهد فقط',
            isSystemRole: const Value(false),
          ),
        );
    return db.into(db.users).insert(
          UsersCompanion.insert(
            username: 'viewer',
            passwordHash: 'x',
            passwordSalt: const Value('y'),
            displayName: 'مشاهد',
            roleId: Value(roleId),
          ),
        );
  }

  Future<int> createInvoice() => db.createPurchaseInvoice(
        supplierId: supplierId,
        warehouseId: warehouseId,
        items: [
          PurchaseInvoiceItemsCompanion.insert(
            invoiceId: 0,
            productId: productId,
            quantity: 10,
            unitCost: 100,
            total: 1000,
          ),
        ],
        paid: 0,
        paymentMethod: 'credit',
      );

  Future<void> edit(int invoiceId, double qty, {int? userId}) =>
      db.updatePurchaseInvoice(
        invoiceId: invoiceId,
        supplierId: supplierId,
        warehouseId: warehouseId,
        paid: 0,
        paymentMethod: 'credit',
        items: [
          PurchaseInvoiceItemsCompanion.insert(
            invoiceId: invoiceId,
            productId: productId,
            quantity: qty,
            unitCost: 100,
            total: qty * 100,
          ),
        ],
        userId: userId,
      );

  setUp(() async {
    db = AppDatabase.forTesting();
    await db.syncDefaultAccounts();
    warehouseId = await db.into(db.warehouses).insert(
          WarehousesCompanion.insert(
            name: 'مخزن رئيسي',
            isDefault: const Value(true),
          ),
        );
    await db.into(db.safes).insert(
          SafesCompanion.insert(
            name: 'خزنة رئيسية',
            safeType: const Value('cash'),
            isDefault: const Value(true),
          ),
        );
    supplierId = await db.into(db.parties).insert(
          PartiesCompanion.insert(
            name: 'مورد',
            isSupplier: const Value(true),
          ),
        );
    productId = await db.into(db.products).insert(
          ProductsCompanion.insert(
            code: 'P-1',
            name: 'صنف',
            trackInventory: const Value(true),
          ),
        );
  });

  tearDown(() async => db.close());

  test('permission holder edits a POSTED invoice repeatedly — no limit',
      () async {
    final userId = await adminUserId();
    final invoiceId = await createInvoice();

    // First edit re-posts the GL entry, and autoPostPurchase sets isLocked.
    await edit(invoiceId, 15, userId: userId);
    final afterFirst = await db.getPurchaseInvoiceById(invoiceId);
    expect(afterFirst!.isLocked, isTrue,
        reason: 'the re-post locks the invoice — this is what used to make '
            'every later edit impossible');
    expect(afterFirst.total, closeTo(1500, 0.001));

    // The invoice is now posted+locked. Under the old gate this threw. Three
    // more edits must all succeed and each must land on the header.
    await edit(invoiceId, 20, userId: userId);
    expect((await db.getPurchaseInvoiceById(invoiceId))!.total,
        closeTo(2000, 0.001));

    await edit(invoiceId, 25, userId: userId);
    expect((await db.getPurchaseInvoiceById(invoiceId))!.total,
        closeTo(2500, 0.001));

    await edit(invoiceId, 7, userId: userId);
    final finalInvoice = await db.getPurchaseInvoiceById(invoiceId);
    expect(finalInvoice!.total, closeTo(700, 0.001));

    // Stock followed every edit (reverse-old + apply-new), so the last edit's
    // quantity is what the product carries — no accumulation across edits.
    expect((await db.getProductById(productId))!.currentStock,
        closeTo(7, 0.001));

    // Exactly ONE live purchase JE survives — each edit reversed the previous.
    final jes = await (db.select(db.journalEntries)
          ..where((e) =>
              (e.referenceType.equals('purchase') |
                  e.referenceType.equals('purchase_invoice')) &
              e.referenceId.equals(invoiceId)))
        .get();
    expect(jes.length, 1,
        reason: 'repeated edits must not pile up journal entries');
  });

  test('user without purchases_edit is denied — even on an UNPOSTED invoice',
      () async {
    final viewerId = await unprivilegedUserId();
    final invoiceId = await createInvoice();

    final before = await db.getPurchaseInvoiceById(invoiceId);
    expect(before!.isLocked, isFalse, reason: 'not posted yet');

    await expectLater(
      edit(invoiceId, 15, userId: viewerId),
      throwsA(isA<PermissionDeniedException>().having(
        (e) => e.code,
        'code',
        PermissionCodes.purchasesEdit,
      )),
    );

    // The whole edit is one transaction — nothing partially applied.
    expect((await db.getPurchaseInvoiceById(invoiceId))!.total,
        closeTo(1000, 0.001));
    expect((await db.getProductById(productId))!.currentStock,
        closeTo(10, 0.001));
  });

  test('anonymous caller (null userId) is denied', () async {
    final invoiceId = await createInvoice();

    await expectLater(
      edit(invoiceId, 15),
      throwsA(isA<PermissionDeniedException>()),
    );

    expect((await db.getPurchaseInvoiceById(invoiceId))!.total,
        closeTo(1000, 0.001));
  });
}
