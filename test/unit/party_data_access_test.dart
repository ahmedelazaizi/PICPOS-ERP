// AUTHZ-003 / RPT-006 (audit 2026-10-23): who may open a party statement,
// export parties (with balances) or import them; and who may export the
// products template (cost + sale prices).
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/core/permissions/financial_figures_access.dart';
import 'package:ural_erp/core/permissions/party_data_access.dart';

void main() {
  group('statement', () {
    test('action-only customers_add cannot open a customer statement', () {
      expect(
          PartyDataAccess.canViewStatement(['customers_add'], supplier: false),
          isFalse);
    });
    test('customers_view can; suppliers_view for suppliers', () {
      expect(
          PartyDataAccess.canViewStatement(['customers_view'], supplier: false),
          isTrue);
      expect(
          PartyDataAccess.canViewStatement(['suppliers_view'], supplier: true),
          isTrue);
      expect(
          PartyDataAccess.canViewStatement(['suppliers_view'], supplier: false),
          isFalse);
    });
    test('system admin bypass', () {
      expect(
          PartyDataAccess.canViewStatement(const [],
              supplier: false, bypass: true),
          isTrue);
    });
  });

  group('export', () {
    test('view alone is not enough (needs reports_export)', () {
      expect(PartyDataAccess.canExport(['customers_view'], supplier: false),
          isFalse);
    });
    test('export alone is not enough (needs the view code)', () {
      expect(PartyDataAccess.canExport(['reports_export'], supplier: false),
          isFalse);
    });
    test('view + reports_export can', () {
      expect(
          PartyDataAccess.canExport(['customers_view', 'reports_export'],
              supplier: false),
          isTrue);
    });
    test('action-only user cannot', () {
      expect(
          PartyDataAccess.canExport(['customers_add', 'customers_edit'],
              supplier: false),
          isFalse);
    });
  });

  group('import', () {
    test('needs add AND edit for the type', () {
      expect(PartyDataAccess.canImport(['customers_add'], supplier: false),
          isFalse);
      expect(
          PartyDataAccess.canImport(['customers_add', 'customers_edit'],
              supplier: false),
          isTrue);
      expect(
          PartyDataAccess.canImport(['customers_add', 'customers_edit'],
              supplier: true),
          isFalse);
      expect(
          PartyDataAccess.canImport(['suppliers_add', 'suppliers_edit'],
              supplier: true),
          isTrue);
    });
  });

  group('products template (RPT-006)', () {
    test('needs both price and cost view', () {
      expect(canExportProductFigures(['products_price_view']), isFalse);
      expect(canExportProductFigures(['products_cost_view']), isFalse);
      expect(
          canExportProductFigures(['products_price_view', 'products_cost_view']),
          isTrue);
      expect(canExportProductFigures(const [], bypass: true), isTrue);
    });
  });
}
