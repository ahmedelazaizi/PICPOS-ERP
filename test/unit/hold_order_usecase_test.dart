// ═══════════════════════════════════════════════════════════════════════════
// HoldOrderUseCase — Unit Tests (coverage: hold_order_usecase.dart)
// ═══════════════════════════════════════════════════════════════════════════
//
// Uses a real ProviderContainer with databaseProvider overridden to
// AppDatabase.forTesting() so the use case's `_ref.read()` calls resolve.
// authProvider defaults to empty AuthState (no logged-in user) — that's fine
// because the use case wraps the activity-log call in try/catch.

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ural_erp/data/providers/providers.dart';
import 'package:ural_erp/domain/entities/cart_item_entity.dart';
import 'package:ural_erp/domain/usecases/sales/hold_order_usecase.dart';
import 'package:ural_erp/presentation/pos/widgets/modifier_selection_dialog.dart';
import 'package:ural_erp/data/database/database.dart' show ProductsCompanion;

void main() {
  late AppDatabase db;
  late ProviderContainer container;
  late HoldOrderUseCase useCase;

  setUp(() async {
    db = AppDatabase.forTesting();
    // held_order_items.product_id FKs to products — seed the product the
    // executeHold tests reference (products is empty in a fresh DB; the first
    // insert lands at id 1). FK is enforced in tests now (mirrors production).
    await db.into(db.products).insert(
        ProductsCompanion.insert(code: 'HELD-1', name: 'Held Item'));
    container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWith((ref) => db),
      ],
    );
    useCase = container.read(holdOrderUseCaseProvider);
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  // ── HoldOrderRequest data class ─────────────────────────────────────────────
  group('HoldOrderRequest', () {
    test('stores all required and optional fields', () {
      final items = [
        const CartItemEntity(
          productId: 1,
          productName: 'Coffee',
          productCode: 'CF-001',
          quantity: 2,
          unitPrice: 30,
        ),
      ];
      final req = HoldOrderRequest(
        items: items,
        subtotal: 60,
        discountPercent: 10,
        customerId: 5,
        customerName: 'Ali',
      );
      expect(req.items.length, 1);
      expect(req.subtotal, 60);
      expect(req.discountPercent, 10);
      expect(req.customerId, 5);
      expect(req.customerName, 'Ali');
    });

    test('optional fields default to null', () {
      final req = HoldOrderRequest(
        items: const [],
        subtotal: 0,
        discountPercent: 0,
      );
      expect(req.customerId, isNull);
      expect(req.customerName, isNull);
    });
  });

  // ── RetrieveHeldOrderResponse data class ────────────────────────────────────
  group('RetrieveHeldOrderResponse', () {
    test('stores all fields', () {
      final items = [
        const CartItemEntity(
          productId: 1,
          productName: 'Tea',
          productCode: 'TE-001',
          quantity: 1,
          unitPrice: 15,
        ),
      ];
      final res = RetrieveHeldOrderResponse(
        items: items,
        discountPercent: 5,
        customerId: 7,
        customerName: 'Sara',
      );
      expect(res.items.length, 1);
      expect(res.discountPercent, 5);
      expect(res.customerId, 7);
      expect(res.customerName, 'Sara');
    });

    test('optional customer fields default to null', () {
      final res = RetrieveHeldOrderResponse(
        items: const [],
        discountPercent: 0,
      );
      expect(res.customerId, isNull);
      expect(res.customerName, isNull);
    });
  });

  // ── executeHold ─────────────────────────────────────────────────────────────
  group('executeHold', () {
    test('returns null when items list is empty', () async {
      final req = HoldOrderRequest(
        items: const [],
        subtotal: 0,
        discountPercent: 0,
      );
      final result = await useCase.executeHold(req);
      expect(result, isNull);
    });

    test('returns hold number on success', () async {
      final req = HoldOrderRequest(
        items: const [
          CartItemEntity(
            productId: 1,
            productName: 'Item',
            productCode: 'I-001',
            quantity: 1,
            unitPrice: 10,
          ),
        ],
        subtotal: 10,
        discountPercent: 0,
      );
      final result = await useCase.executeHold(req);
      expect(result, isNotNull);
      expect(result, startsWith('H'));
      expect(result!.length, 7); // H + 6 digits (HHMMSS)
    });

    test('serializes itemNote and modifiers via _serializeCartItemMeta', () async {
      final req = HoldOrderRequest(
        items: [
          CartItemEntity(
            productId: 1,
            productName: 'Pizza',
            productCode: 'PZ-001',
            quantity: 1,
            unitPrice: 100,
            itemNote: 'extra spicy',
            modifiers: [
              SelectedModifier(
                itemId: 10,
                itemName: 'Cheese',
                groupName: 'Toppings',
                extraPrice: 5.0,
              ),
            ],
          ),
        ],
        subtotal: 105,
        discountPercent: 0,
        customerId: 1,
        customerName: 'X',
      );
      final result = await useCase.executeHold(req);
      expect(result, isNotNull);
    });

    test('handles items without notes or modifiers', () async {
      final req = HoldOrderRequest(
        items: const [
          CartItemEntity(
            productId: 1,
            productName: 'Plain',
            productCode: 'P-001',
            quantity: 1,
            unitPrice: 5,
          ),
        ],
        subtotal: 5,
        discountPercent: 0,
      );
      final result = await useCase.executeHold(req);
      expect(result, isNotNull);
    });
  });

  // ── executeRetrieve ─────────────────────────────────────────────────────────
  group('executeRetrieve', () {
    test('returns null for non-existent id', () async {
      final result = await useCase.executeRetrieve(99999);
      expect(result, isNull);
    });

    test('returns null when DB call throws', () async {
      // Closing the DB causes subsequent queries to throw → covers catch branch
      await db.close();
      final result = await useCase.executeRetrieve(1);
      expect(result, isNull);
      // Re-open so tearDown's close() doesn't fail
      db = AppDatabase.forTesting();
    });
  });

  // ── executeDelete ───────────────────────────────────────────────────────────
  group('executeDelete', () {
    test('completes without throwing for non-existent id', () async {
      await expectLater(useCase.executeDelete(99999), completes);
    });

    test('handles errors silently (caught internally)', () async {
      // Closing DB causes deleteHeldOrder to throw, but executeDelete swallows it
      await db.close();
      await expectLater(useCase.executeDelete(1), completes);
      db = AppDatabase.forTesting();
    });
  });
}
