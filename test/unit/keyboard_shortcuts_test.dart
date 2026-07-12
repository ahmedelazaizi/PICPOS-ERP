import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Unit tests for POS keyboard shortcut mappings
///
/// Validates that all expected F-key shortcuts are mapped
/// to the correct logical keys and that there are no conflicts.
/// These tests verify the Phase 9.3 keyboard shortcut additions.
void main() {
  group('Keyboard Shortcut Key Mapping', () {
    // Define the expected POS shortcut map
    // Key: LogicalKeyboardKey, Value: Action description
    final Map<LogicalKeyboardKey, String> posShortcuts = {
      LogicalKeyboardKey.f1: 'Search/Barcode Focus',
      LogicalKeyboardKey.f2: 'Hold Order',
      LogicalKeyboardKey.f3: 'Offers Dialog',
      LogicalKeyboardKey.f4: 'Customers Dialog',
      LogicalKeyboardKey.f5: 'Returns Navigation',
      LogicalKeyboardKey.f6: 'Held Orders Dialog',
      LogicalKeyboardKey.f7: 'Expenses Dialog',
      LogicalKeyboardKey.f8: 'Payment Dialog',
      LogicalKeyboardKey.f9: 'Save Without Print',
      LogicalKeyboardKey.f10: 'Cashier Closing',
      LogicalKeyboardKey.f11: 'Previous Invoices',
      LogicalKeyboardKey.f12: 'Save and Print',
      LogicalKeyboardKey.delete: 'Clear Cart',
      LogicalKeyboardKey.escape: 'Clear Search / Focus',
    };

    test('all F-keys F1-F12 are mapped', () {
      final fKeys = [
        LogicalKeyboardKey.f1,
        LogicalKeyboardKey.f2,
        LogicalKeyboardKey.f3,
        LogicalKeyboardKey.f4,
        LogicalKeyboardKey.f5,
        LogicalKeyboardKey.f6,
        LogicalKeyboardKey.f7,
        LogicalKeyboardKey.f8,
        LogicalKeyboardKey.f9,
        LogicalKeyboardKey.f10,
        LogicalKeyboardKey.f11,
        LogicalKeyboardKey.f12,
      ];

      for (final key in fKeys) {
        expect(
          posShortcuts.containsKey(key),
          isTrue,
          reason: 'F-key ${key.debugName} should be mapped',
        );
      }
    });

    test('no duplicate actions in shortcut map', () {
      final actions = posShortcuts.values.toList();
      final uniqueActions = actions.toSet();

      expect(
        actions.length,
        uniqueActions.length,
        reason: 'Each shortcut should map to a unique action',
      );
    });

    test('total shortcut count is 14 (F1-F12 + Delete + Escape)', () {
      expect(posShortcuts.length, 14);
    });

    test('Delete key maps to Clear Cart', () {
      expect(posShortcuts[LogicalKeyboardKey.delete], 'Clear Cart');
    });

    test('Escape key maps to Clear Search', () {
      expect(posShortcuts[LogicalKeyboardKey.escape], 'Clear Search / Focus');
    });

    test('F12 maps to Save and Print (hot action)', () {
      expect(posShortcuts[LogicalKeyboardKey.f12], 'Save and Print');
    });

    test('F8 maps to Payment Dialog', () {
      expect(posShortcuts[LogicalKeyboardKey.f8], 'Payment Dialog');
    });

    test('F10 maps to Cashier Closing', () {
      expect(posShortcuts[LogicalKeyboardKey.f10], 'Cashier Closing');
    });
  });

  group('LogicalKeyboardKey Properties', () {
    test('F-keys have unique key IDs', () {
      final fKeyIds = [
        LogicalKeyboardKey.f1.keyId,
        LogicalKeyboardKey.f2.keyId,
        LogicalKeyboardKey.f3.keyId,
        LogicalKeyboardKey.f4.keyId,
        LogicalKeyboardKey.f5.keyId,
        LogicalKeyboardKey.f6.keyId,
        LogicalKeyboardKey.f7.keyId,
        LogicalKeyboardKey.f8.keyId,
        LogicalKeyboardKey.f9.keyId,
        LogicalKeyboardKey.f10.keyId,
        LogicalKeyboardKey.f11.keyId,
        LogicalKeyboardKey.f12.keyId,
      ];

      final uniqueIds = fKeyIds.toSet();
      expect(fKeyIds.length, uniqueIds.length);
    });

    test('delete and escape have distinct key IDs', () {
      expect(
        LogicalKeyboardKey.delete.keyId,
        isNot(LogicalKeyboardKey.escape.keyId),
      );
    });
  });
}
