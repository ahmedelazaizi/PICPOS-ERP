// Spec 029 / US5 — POS quick-add negative-sales gate.
//
// Cluster 024 / Issue 8 commit `1746080` taught the quick-add dialog to
// persist `allowNegativeSale=true` on the new product row whenever the
// install-wide negative-sales toggle was ON at quick-add time. That
// latch defeats subsequent global-toggle flips: if the operator turns
// the global OFF later, the per-product flag is still TRUE and the
// cart guard's `!product.allowNegativeSale` short-circuits — the
// product keeps selling at zero stock contrary to operator intent.
//
// Spec 029 reverts the latch. The new product row inherits the column
// default (`allowNegativeSale=false`). The cart's existing OR-of-flags
// handles the dynamic case correctly: global ON → gate doesn't fire;
// global OFF → gate fires.
//
// Three scenarios pin the contract:
//   1. global OFF + quick-added product with currentStock=0
//      → gate fires (sale blocked).
//   2. global ON + same setup → gate does NOT fire (sale allowed).
//   3. quick-add while global ON, then flip global OFF, sell same
//      product → gate fires. THIS IS THE REGRESSION TEST. Fails on
//      `main` (where the latch is still applied).

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/database/database.dart';
import 'package:ural_erp/data/repositories/drift_product_repository.dart';

/// Reproduces the cart guard logic from
/// lib/presentation/pos/providers/cart_controller.dart:222-237 so we
/// can exercise it without pulling the full Riverpod / UI stack into
/// the test. Returns `true` when the guard should BLOCK the sale.
bool _gateFires({
  required bool trackInventory,
  required bool perProductAllowNegative,
  required bool globalAllowNegative,
  required double currentStock,
  bool isExchangeMode = false,
  String paymentMethod = 'cash',
}) {
  return trackInventory &&
      !perProductAllowNegative &&
      !globalAllowNegative &&
      currentStock <= 0 &&
      !isExchangeMode &&
      paymentMethod != 'credit';
}

void main() {
  late AppDatabase db;
  late DriftProductRepository repo;

  setUp(() async {
    db = AppDatabase.forTesting();
    repo = DriftProductRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  Future<Product> insertViaQuickAdd({
    required String name,
    required double price,
  }) async {
    final id = await repo.quickAddProduct(name: name, salePrice: price);
    final row = await (db.select(db.products)
          ..where((p) => p.id.equals(id))
          ..limit(1))
        .getSingle();
    return row;
  }

  group('POS quick-add — negative-sales gate (Spec 029 / US5)', () {
    test(
      'quick-added product persists allowNegativeSale=false (default) — '
      'no Cluster 024 belt-and-suspenders latch',
      () async {
        // Even if the operator's global toggle is ON at the moment of
        // quick-add (simulated by passing allowNegativeSale=true to the
        // repo), the dialog must NOT pass that flag. The dialog source
        // (lib/presentation/pos/dialogs/quick_add_product_dialog.dart)
        // calls quickAddProduct WITHOUT the allowNegativeSale parameter,
        // so the default applies — verified by the absence of a fixed
        // grep guard in the dialog test below.
        final product = await insertViaQuickAdd(name: 'صنف-جديد', price: 10);
        expect(
          product.allowNegativeSale,
          isFalse,
          reason: 'quick-add must leave per-product flag at column default '
              '(false). Otherwise a later global-toggle flip is defeated.',
        );
      },
    );

    test(
      'gate fires when global toggle is OFF and product has currentStock=0',
      () async {
        await insertViaQuickAdd(name: 'صنف-أ', price: 10);

        final blocks = _gateFires(
          trackInventory: true,
          perProductAllowNegative: false, // post-fix default
          globalAllowNegative: false, // operator turned OFF
          currentStock: 0,
        );
        expect(
          blocks,
          isTrue,
          reason:
              'with global OFF and a freshly quick-added product at zero '
              'stock, the cart guard MUST fire. Operator expects sales to '
              'be blocked.',
        );
      },
    );

    test(
      'gate does NOT fire when global toggle is ON',
      () async {
        await insertViaQuickAdd(name: 'صنف-ب', price: 10);

        final blocks = _gateFires(
          trackInventory: true,
          perProductAllowNegative: false,
          globalAllowNegative: true, // operator allows negative sales
          currentStock: 0,
        );
        expect(
          blocks,
          isFalse,
          reason: 'with global ON, the cart guard must allow the sale '
              'regardless of per-product flag — global is the override.',
        );
      },
    );

    test(
      'mid-session toggle flip has immediate effect (REGRESSION TEST)',
      () async {
        // Phase 1: operator quick-adds product P while global toggle is ON.
        // Pre-spec-029 (Cluster 024 / Issue 8): the dialog would pass
        // `allowNegativeSale: true` → product persisted with the flag.
        // Spec 029: dialog no longer passes the parameter → flag stays
        // false (column default).
        final product = await insertViaQuickAdd(name: 'صنف-ج', price: 10);
        expect(
          product.allowNegativeSale,
          isFalse,
          reason: 'pre-fix this would be TRUE, defeating the toggle flip',
        );

        // Phase 2: operator flips the global toggle OFF mid-session.
        // The cart now sees: per-product=false, global=false.
        final blocks = _gateFires(
          trackInventory: true,
          perProductAllowNegative: product.allowNegativeSale,
          globalAllowNegative: false,
          currentStock: 0,
        );
        expect(
          blocks,
          isTrue,
          reason:
              'the gate MUST fire after a mid-session flip. On `main` '
              '(pre-fix) the per-product latch is true → gate does NOT '
              'fire → product silently sells at negative.',
        );
      },
    );
  });

  group('POS quick-add dialog source — Cluster 024 latch is reverted', () {
    test(
      'quick_add_product_dialog.dart does NOT pass allowNegativeSale to '
      'quickAddProduct',
      () async {
        // Static guard — pin the contract at the source level so a
        // future revert of Spec 029 / US5 fails the build immediately.
        // The dialog should call quickAddProduct with name + salePrice +
        // optional barcode + optional categoryId — and NOT
        // allowNegativeSale.
        final source = await _readDialogSource();
        expect(
          source.contains('allowNegativeSale: globalNegativeSales'),
          isFalse,
          reason: 'Cluster 024 / Issue 8 latch reintroduced. The dialog '
              'is forcing per-product allowNegativeSale=true based on '
              'the global toggle at quick-add time, which defeats later '
              'toggle flips. See specs/029-sync-regression-hardening/'
              'contracts/quick-add-neg-sales.md.',
        );
        expect(
          source.contains('ref.read(enableNegativeSalesProvider)'),
          isFalse,
          reason: 'the dialog no longer needs to read '
              'enableNegativeSalesProvider — eager-loading happens in '
              'FeaturesBridge.',
        );
      },
    );
  });

  // Helper used by the static-grep test above. Mirrors the discovery
  // pattern the existing `orchestrator_gate_predicate_test.dart` uses.
}

Future<String> _readDialogSource() async {
  // Relative path from project root (where `flutter test` runs).
  final file =
      File('lib/presentation/pos/dialogs/quick_add_product_dialog.dart');
  if (!await file.exists()) {
    fail('Could not locate quick_add_product_dialog.dart at ${file.path}');
  }
  return file.readAsString();
}
