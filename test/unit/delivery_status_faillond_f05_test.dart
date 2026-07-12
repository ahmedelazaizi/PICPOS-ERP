// ═══════════════════════════════════════════════════════════════════════════
// Spec 151 · Wave C · F-05 (MINOR) — updateSalesDeliveryStatus must run the
// deferred→revenue conversion (autoPostDeliveryConfirmed) FIRST and FAIL LOUD;
// the invoice can never flip to 'delivered' while that conversion is unposted.
// ═══════════════════════════════════════════════════════════════════════════
//
// Pre-fix: the status was written FIRST, then autoPostDeliveryConfirmed ran in
// a bare try{}catch{debugPrint} — a JE-posting failure was SWALLOWED and the
// invoice committed as 'delivered' with its deferred revenue left un-converted.
// Fix reorders: autoPostDeliveryConfirmed runs BEFORE the status flip and its
// throw is no longer caught, so a JE failure propagates and the status write
// below is never reached (the same invariant as a rollback, without a nested
// transaction — see the method's F-05 comment).
//
// WHAT autoPostDeliveryConfirmed ACTUALLY POSTS ON THIS PATH — verified against
// the running code, not assumed:
//   updateSalesDeliveryStatus calls autoPostDeliveryConfirmed while the row
//   still reads deliveryStatus='pending'. autoPostDeliveryConfirmed reverses
//   the deferred_sale JE (a 'deferred_sale_reversal' entry dated now) and then
//   calls autoPostCashSale(sale); because that sale object still carries
//   'pending', autoPostCashSale re-enters the deferred branch and its dedup
//   short-circuits, so NO bare 'sale'/'sales_invoice' revenue entry is written
//   on this transition. The one entry that DOES commit before the flip — and
//   whose failure must abort the flip — is therefore the 'deferred_sale_reversal'.
//   (An earlier draft of this test guessed 'sale'/'sales_invoice'; that entry
//   never exists here, which is why the happy-path assertion was failing.)
//
// FAILURE TRIGGER — the reversal entry is dated DateTime.now(), so closing the
// CURRENT month (not the invoice's month) forces THAT entry to hit a closed
// accounting period and throw. The invoice's own month stays open, so its
// deferred_sale entry was posted cleanly at creation. This mirrors
// failloud_b7_test's PUR-4 technique (close now's month for a now-dated JE).
// ═══════════════════════════════════════════════════════════════════════════

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/database/database.dart';

void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase.forTesting();
    await db.syncDefaultAccounts();
  });

  tearDown(() => db.close());

  // A date in a DIFFERENT calendar month than "now" (same year) so the
  // invoice's deferred JE lands in a period we can leave OPEN while closing
  // "now"'s period (where the delivery-confirmation reversal JE is dated).
  // Copied from failloud_b7_test's ACC-1/PUR-4 setup.
  DateTime pastDateDifferentMonth() {
    final now = DateTime.now();
    final month = now.month == 1 ? 2 : 1;
    return DateTime(now.year, month, 10);
  }

  Future<void> setMonthClosed(DateTime date, bool closed) async {
    final updated = await (db.update(db.accountingPeriods)
          ..where((p) => p.month.equals(date.month) & p.year.equals(date.year)))
        .write(AccountingPeriodsCompanion(isClosed: Value(closed)));
    expect(updated, greaterThan(0),
        reason: 'AppDatabase.forTesting() must pre-seed a monthly '
            'accounting_periods row for ${date.month}/${date.year}');
  }

  Future<int> seedUser() async {
    final roleId = await db.into(db.roles).insert(
          RolesCompanion.insert(
              name: 'كاشير F05', isSystemRole: const Value(false)),
        );
    return db.createUser(
      username: 'f05_user',
      password: 'test',
      displayName: 'F05 User',
      roleId: roleId,
    );
  }

  Future<int> seedPendingDeliverySale(DateTime invoiceDate, String number,
      {required int userId, required int warehouseId}) {
    // A cash-paid delivery order left 'pending' → createSalesInvoice posts a
    // 'deferred_sale' JE for the full total at creation (verified below via the
    // deferredJes precondition check — NOT assumed). Items are irrelevant to
    // the deferral: it is driven by the invoice total, so an empty item list is
    // deliberate and non-vacuous, exactly as failloud_b7_test's ACC-1 seeds it.
    return db.createSalesInvoice(
      invoiceNumber: number,
      warehouseId: warehouseId,
      userId: userId,
      subtotal: 300.0,
      discount: 0.0,
      tax: 0.0,
      total: 300.0,
      paid: 300.0,
      cashAmount: 300.0,
      paymentMethod: 'cash',
      deliveryStatus: 'pending', // → deferred-revenue JE at creation
      invoiceDate: invoiceDate,
      items: const [],
    );
  }

  // The deferral posted at creation — the precondition that makes this test
  // non-vacuous. If it is empty the sale never deferred and there is nothing to
  // convert (the test would be testing nothing).
  deferredJes(int invoiceId) => (db.select(db.journalEntries)
        ..where((e) =>
            e.referenceType.equals('deferred_sale') &
            e.referenceId.equals(invoiceId)))
      .get();

  // The entry autoPostDeliveryConfirmed commits BEFORE the status flip — the
  // deferred→revenue conversion whose failure must abort the flip. This is the
  // 'deferred_sale_reversal' entry (see file header for why it is this and not
  // a bare 'sale' entry on this path).
  conversionJes(int invoiceId) => (db.select(db.journalEntries)
        ..where((e) =>
            e.referenceType.equals('deferred_sale_reversal') &
            e.referenceId.equals(invoiceId)))
      .get();

  // Spec 151 F-05 (revenue-recognition fix): confirming delivery must not only
  // REVERSE the deferral but also RECOGNIZE revenue (a forward 'sale' JE, Dr
  // Cash/Cr Sales). Before the fix, autoPostDeliveryConfirmed passed the still-
  // 'pending' sale to autoPostCashSale, which re-deferred → dedup no-op →
  // revenue vanished (deferral + reversal netted to zero).
  revenueJes(int invoiceId) => (db.select(db.journalEntries)
        ..where((e) =>
            e.referenceType.equals('sale') & e.referenceId.equals(invoiceId)))
      .get();

  test(
      'conversion JE cannot post → status does NOT advance to delivered '
      '(fail-loud, no swallow)', () async {
    final warehouseId = (await db.getDefaultWarehouse())!.id;
    final userId = await seedUser();
    final invoiceDate = pastDateDifferentMonth(); // invoice month stays OPEN
    final invoiceId = await seedPendingDeliverySale(invoiceDate, 'F05-FAIL-1',
        userId: userId, warehouseId: warehouseId);

    // Precondition: the sale actually deferred at creation — otherwise there is
    // no conversion to fail and the test is vacuous.
    expect(await deferredJes(invoiceId), hasLength(1),
        reason: 'a pending delivery order must post a deferred_sale JE at '
            'creation for this test to be meaningful');

    // Close the CURRENT month → the deferred_sale_reversal JE (dated now, minted
    // inside autoPostDeliveryConfirmed) can no longer post. invoiceDate's month
    // stays open, so the deferred JE above was unaffected.
    await setMonthClosed(DateTime.now(), true);

    await expectLater(
      () => db.updateSalesDeliveryStatus(invoiceId, 'delivered'),
      throwsA(anything),
      reason: 'a failed conversion JE must fail loud, not be swallowed',
    );

    final after = await (db.select(db.salesInvoices)
          ..where((i) => i.id.equals(invoiceId)))
        .getSingle();
    expect(after.deliveryStatus, isNot('delivered'),
        reason:
            'the status must NOT advance while the deferral is un-converted');
    expect(after.deliveryStatus, 'pending');

    expect(await conversionJes(invoiceId), isEmpty,
        reason: 'no false success — the conversion JE never committed');
  });

  test(
      'happy path: status becomes delivered ONLY once the conversion JE exists '
      '(JE posted before the flip)', () async {
    final warehouseId = (await db.getDefaultWarehouse())!.id;
    final userId = await seedUser();
    final invoiceDate = pastDateDifferentMonth(); // all periods open
    final invoiceId = await seedPendingDeliverySale(invoiceDate, 'F05-OK-1',
        userId: userId, warehouseId: warehouseId);

    // Same non-vacuous precondition: the deferral exists to be converted.
    expect(await deferredJes(invoiceId), hasLength(1));

    await db.updateSalesDeliveryStatus(invoiceId, 'delivered');

    final after = await (db.select(db.salesInvoices)
          ..where((i) => i.id.equals(invoiceId)))
        .getSingle();
    expect(after.deliveryStatus, 'delivered');
    expect(await conversionJes(invoiceId), isNotEmpty,
        reason: 'a delivered invoice must have its deferral converted '
            '(deferred_sale_reversal JE posted before the flip)');
    // Revenue must be RECOGNIZED, not just de-deferred — the forward 'sale' JE
    // must exist. This is the assertion that catches the F-05 revenue-vanish
    // regression (it was empty before autoPostDeliveryConfirmed forced the
    // in-memory sale to 'delivered' for the revenue post).
    expect(await revenueJes(invoiceId), isNotEmpty,
        reason: 'confirming delivery must recognize revenue (forward sale JE), '
            'not merely reverse the deferral');
  });
}
