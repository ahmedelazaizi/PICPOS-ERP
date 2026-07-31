import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/presentation/pos_picpos/widgets/picpos_pos_shortcuts.dart';

/// Guards the PicPos POS key map (طلب ٤).
///
/// The bottom shortcut bar was removed, and with it the on-screen labels that
/// used to document these keys. `picposShortcutLabels` is what replaced that
/// documentation, and `_PicPosPosScreenState._keyActions()` asserts its own key
/// set matches this map — so the two cannot drift without failing loudly.
///
/// This test pins the CONTENTS of that map. If someone rebinds a key they have
/// to change it here too, which is the point: the rebinding becomes a visible,
/// reviewed decision instead of a silent one.
void main() {
  group('picposShortcutLabels', () {
    test('covers exactly the documented keys', () {
      expect(
        picposShortcutLabels.keys.toSet(),
        {
          LogicalKeyboardKey.f2,
          LogicalKeyboardKey.f3,
          LogicalKeyboardKey.f4,
          LogicalKeyboardKey.f6,
          LogicalKeyboardKey.f8,
          LogicalKeyboardKey.escape,
          LogicalKeyboardKey.arrowDown,
          LogicalKeyboardKey.arrowUp,
        },
      );
    });

    test('F3 is the last-invoice key, not print', () {
      // Printing moved inside «دفع» (طلب ١), so the old F3=طباعة binding had no
      // action left. It was rebound to «الفاتورة السابقة» rather than dropped,
      // so a cashier's muscle memory still lands on a print-related screen.
      expect(picposShortcutLabels[LogicalKeyboardKey.f3],
          'الفاتورة السابقة');
    });

    test('F4 documents that pay also prints and opens the drawer', () {
      // The merge is the whole of طلب ١; if this label ever loses the promise,
      // the docs stopped describing what the button does.
      final label = picposShortcutLabels[LogicalKeyboardKey.f4]!;
      expect(label, contains('دفع'));
      expect(label, contains('طباعة'));
      expect(label, contains('درج'));
    });

    test('F2 stays a plain save — no print, no drawer', () {
      expect(picposShortcutLabels[LogicalKeyboardKey.f2], 'حفظ');
    });

    test('every key has a non-empty Arabic label', () {
      for (final entry in picposShortcutLabels.entries) {
        expect(entry.value.trim(), isNotEmpty,
            reason: 'المفتاح ${entry.key} بلا تسمية');
      }
    });
  });
}
