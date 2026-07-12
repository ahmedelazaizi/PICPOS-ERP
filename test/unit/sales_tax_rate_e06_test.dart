// ═══════════════════════════════════════════════════════════════════════════
// Spec 151 · Wave C · E-06 (MINOR) — the sales-invoice save path must thread the
// CONFIGURED system VAT rate, not silently apply a hardcoded 14.
// ═══════════════════════════════════════════════════════════════════════════
//
// Pre-fix: SaleRequest.taxPercent defaulted to a bare `14` literal and the
// sales-invoice form never set it, so a taxable line whose per-product taxRate
// was 0 fell back to 14% regardless of jurisdiction. Fix (a) names the fallback
// `SaleRequest.kDefaultTaxPercent` and (b) makes the save path read the seeded
// `tax_rate` setting and thread it into the request.
//
// The production reader lives in the sales-invoice save WIDGET extension
// (sales_invoice_save_edit.dart) which needs a full screen state + Riverpod
// container and is not unit-invocable. This test therefore pins the two
// contracts that fix depends on: the SaleRequest passthrough/default, and the
// settings-resolution semantics the widget performs against a real settings row.
// ═══════════════════════════════════════════════════════════════════════════

import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/database/database.dart';
import 'package:ural_erp/domain/repositories/sales_repository.dart';

void main() {
  test('kDefaultTaxPercent is the named fallback (14), documenting the fix', () {
    expect(SaleRequest.kDefaultTaxPercent, 14);
  });

  test('SaleRequest default taxPercent wires to the named constant', () {
    const req = SaleRequest(items: [], paymentMethod: 'cash', paidAmount: 0);
    expect(req.taxPercent, SaleRequest.kDefaultTaxPercent,
        reason: 'the default must be the named constant, not a stray 14 literal');
  });

  test('an explicit (configured) rate threads through, overriding the default',
      () {
    const req = SaleRequest(
        items: [], paymentMethod: 'cash', paidAmount: 0, taxPercent: 15);
    expect(req.taxPercent, 15);
    expect(req.taxPercent, isNot(SaleRequest.kDefaultTaxPercent),
        reason: 'a non-14 configured rate must NOT collapse to the 14 default');
  });

  // The exact resolution the save path performs:
  //   double.tryParse(getSettingValue('tax_rate') ?? '') ?? kDefaultTaxPercent
  group('configured tax_rate threads into SaleRequest.taxPercent', () {
    late AppDatabase db;
    setUp(() => db = AppDatabase.forTesting());
    tearDown(() => db.close());

    Future<double> resolveSystemRate() async =>
        double.tryParse(await db.getSettingValue('tax_rate') ?? '') ??
        SaleRequest.kDefaultTaxPercent;

    test('tax_rate=15 → SaleRequest carries 15, not the 14 default', () async {
      await db.setSetting('tax_rate', '15');
      final resolved = await resolveSystemRate();
      expect(resolved, 15, reason: 'the configured rate is read from settings');

      final req = SaleRequest(
          items: const [],
          paymentMethod: 'cash',
          paidAmount: 0,
          taxPercent: resolved);
      expect(req.taxPercent, 15);
      expect(req.taxPercent, isNot(SaleRequest.kDefaultTaxPercent),
          reason: 'the Egyptian 14 default must not silently apply when the '
              'installation configured 15');
    });

    test('blank/unparseable tax_rate falls back to the named default (14)',
        () async {
      await db.setSetting('tax_rate', ''); // forces the ?? kDefaultTaxPercent arm
      final resolved = await resolveSystemRate();
      expect(resolved, SaleRequest.kDefaultTaxPercent);
    });
  });
}
