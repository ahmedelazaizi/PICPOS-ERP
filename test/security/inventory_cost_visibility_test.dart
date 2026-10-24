// AUTHZ-009 - unit cost / inventory valuation need products_cost_view, not just inventory_view.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/core/permissions/financial_figures_access.dart';
import 'package:picpos_erp/data/providers/auth_providers.dart';
import 'package:picpos_erp/data/providers/financial_figures_providers.dart';

void main() {
  group('canSeeInventoryCost', () {
    test('inventory_view alone does NOT reveal cost', () {
      expect(canSeeInventoryCost(['inventory_view']), isFalse);
      expect(canSeeInventoryCost(['inventory_view', 'products_stock_view']), isFalse);
    });
    test('products_cost_view reveals it; admin bypass too', () {
      expect(canSeeInventoryCost(['products_cost_view']), isTrue);
      expect(canSeeInventoryCost(const [], bypass: true), isTrue);
    });
  });

  group('inventoryCostVisibilityProvider', () {
    Future<bool> visible(List<String> perms) async {
      final c = ProviderContainer(overrides: [
        currentUserPermissionsProvider.overrideWith((ref) async => perms),
      ]);
      addTearDown(c.dispose);
      return c.read(inventoryCostVisibilityProvider.future);
    }

    test('a stock keeper (inventory_view) sees masked cost', () async {
      expect(await visible(['inventory_view']), isFalse);
    });
    test('a user with products_cost_view sees cost', () async {
      expect(await visible(['inventory_view', 'products_cost_view']), isTrue);
    });
  });
}
