/// Day-22 Widget Tests — POS Shortcut Bar & Invoice Safety Guards
///
/// 10 tests across two closely related feature areas:
///
///   • PosShortcutBar        — renders keyboard-shortcut hints in the POS footer
///   • CreditLimitWarningBanner — safety banner that appears when a customer's
///                               credit limit is at risk during checkout
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/presentation/pos/widgets/pos_shortcut_bar.dart';
import 'package:ural_erp/presentation/widgets/invoice_safety_guards.dart';
import 'package:ural_erp/domain/entities/party_entity.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────────────────────

/// Wraps the widget in a minimal RTL MaterialApp with a fixed size so that
/// Row / Container children don't overflow in headless test environments.
Widget _wrap(Widget child) => MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 1200,
          height: 60,
          child: child,
        ),
      ),
    );

PartyEntity _customer({
  double balance = 0,
  double creditLimit = 0,
}) =>
    PartyEntity(
      id: 1,
      name: 'عميل تجريبي',
      isCustomer: true,
      balance: balance,
      creditLimit: creditLimit,
    );

// ─────────────────────────────────────────────────────────────────────────────
// PosShortcutBar — keyboard-shortcut hint strip
// ─────────────────────────────────────────────────────────────────────────────

void main() {
  group('PosShortcutBar — shortcut hint display', () {
    testWidgets('renders keyLabel text for every provided shortcut',
        (tester) async {
      await tester.pumpWidget(
        _wrap(
          PosShortcutBar(
            shortcuts: [
              ShortcutHintDef(keyLabel: 'F1', label: 'بحث'),
              ShortcutHintDef(keyLabel: 'F8', label: 'دفع'),
            ],
          ),
        ),
      );
      expect(find.text('F1'), findsOneWidget);
      expect(find.text('F8'), findsOneWidget);
    });

    testWidgets('renders descriptive label text for every shortcut',
        (tester) async {
      await tester.pumpWidget(
        _wrap(
          PosShortcutBar(
            shortcuts: [
              ShortcutHintDef(keyLabel: 'F2', label: 'تعليق'),
              ShortcutHintDef(keyLabel: 'F5', label: 'مرتجع'),
            ],
          ),
        ),
      );
      expect(find.text('تعليق'), findsOneWidget);
      expect(find.text('مرتجع'), findsOneWidget);
    });

    testWidgets('isHot shortcut renders keyLabel in orange', (tester) async {
      await tester.pumpWidget(
        _wrap(
          PosShortcutBar(
            shortcuts: [
              ShortcutHintDef(keyLabel: 'F8', label: 'دفع', isHot: true),
            ],
          ),
        ),
      );
      // Find the keyLabel Text (first Text in the hot hint)
      final texts = tester.widgetList<Text>(find.text('F8')).toList();
      expect(texts, isNotEmpty);
      expect(texts.first.style?.color, equals(Colors.orange));
    });

    testWidgets('isReturn shortcut renders keyLabel in red', (tester) async {
      await tester.pumpWidget(
        _wrap(
          PosShortcutBar(
            shortcuts: [
              ShortcutHintDef(keyLabel: 'F5', label: 'مرتجع', isReturn: true),
            ],
          ),
        ),
      );
      final texts = tester.widgetList<Text>(find.text('F5')).toList();
      expect(texts, isNotEmpty);
      expect(texts.first.style?.color, equals(Colors.red));
    });

    testWidgets('normal shortcut (not hot, not return) does not use orange or red',
        (tester) async {
      await tester.pumpWidget(
        _wrap(
          PosShortcutBar(
            shortcuts: [
              ShortcutHintDef(keyLabel: 'F1', label: 'بحث'),
            ],
          ),
        ),
      );
      final texts = tester.widgetList<Text>(find.text('F1')).toList();
      expect(texts, isNotEmpty);
      final color = texts.first.style?.color;
      expect(color, isNot(equals(Colors.orange)));
      expect(color, isNot(equals(Colors.red)));
    });
  });

// ─────────────────────────────────────────────────────────────────────────────
// CreditLimitWarningBanner — credit-limit safety indicator
// ─────────────────────────────────────────────────────────────────────────────

  group('CreditLimitWarningBanner — credit-limit safety display', () {
    testWidgets('hidden when customer is null', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: CreditLimitWarningBanner(customer: null),
          ),
        ),
      );
      // Widget collapses to SizedBox.shrink() — no visible text
      expect(find.text('⛔ الحد الائتماني متجاوز!'), findsNothing);
      expect(find.text('⚠️ هذه الفاتورة ستتجاوز الحد الائتماني'), findsNothing);
    });

    testWidgets('hidden when customer has no credit limit (creditLimit = 0)',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CreditLimitWarningBanner(
              customer: _customer(balance: 5000, creditLimit: 0),
            ),
          ),
        ),
      );
      expect(find.text('⛔ الحد الائتماني متجاوز!'), findsNothing);
    });

    testWidgets('hidden when balance + invoice total is within the credit limit',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CreditLimitWarningBanner(
              // balance=200, total=100, limit=500 → afterSale=300 < 500
              customer: _customer(balance: 200, creditLimit: 500),
              invoiceTotal: 100,
            ),
          ),
        ),
      );
      expect(find.text('⚠️ هذه الفاتورة ستتجاوز الحد الائتماني'), findsNothing);
      expect(find.text('⛔ الحد الائتماني متجاوز!'), findsNothing);
    });

    testWidgets(
        'shows "will exceed" warning when invoice pushes customer over limit',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CreditLimitWarningBanner(
              // balance=400, total=200, limit=500 → afterSale=600 > 500
              customer: _customer(balance: 400, creditLimit: 500),
              invoiceTotal: 200,
            ),
          ),
        ),
      );
      expect(
        find.text('⚠️ هذه الفاتورة ستتجاوز الحد الائتماني'),
        findsOneWidget,
      );
      expect(find.text('⛔ الحد الائتماني متجاوز!'), findsNothing);
    });

    testWidgets(
        'shows "already exceeded" error when customer balance is over limit',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CreditLimitWarningBanner(
              // balance=600 > limit=500 → creditExceeded = true
              customer: _customer(balance: 600, creditLimit: 500),
            ),
          ),
        ),
      );
      expect(find.text('⛔ الحد الائتماني متجاوز!'), findsOneWidget);
    });
  });
}
