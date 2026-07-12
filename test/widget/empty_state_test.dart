import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:ural_erp/presentation/widgets/enhanced_components.dart';

void main() {
  group('EmptyStateWidget', () {
    testWidgets('displays message text', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: EmptyStateWidget(
              icon: PhosphorIconsBold.package,
              message: 'لا توجد منتجات',
            ),
          ),
        ),
      );

      expect(find.text('لا توجد منتجات'), findsOneWidget);
    });

    testWidgets('displays description when provided', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: EmptyStateWidget(
              icon: PhosphorIconsBold.shoppingCart,
              message: 'السلة فارغة',
              description: 'لم يتم إضافة أي عنصر',
            ),
          ),
        ),
      );

      expect(find.text('السلة فارغة'), findsOneWidget);
      expect(find.text('لم يتم إضافة أي عنصر'), findsOneWidget);
    });

    testWidgets('renders icon', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: EmptyStateWidget(
              icon: PhosphorIconsBold.shoppingCart,
              message: 'فارغ',
            ),
          ),
        ),
      );

      expect(find.byType(Icon), findsOneWidget);
    });

    testWidgets('renders action button when provided', (tester) async {
      bool actionTapped = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EmptyStateWidget(
              icon: PhosphorIconsBold.plus,
              message: 'لا توجد بيانات',
              description: 'اضغط لإضافة',
              actionLabel: 'إضافة جديد',
              onAction: () => actionTapped = true,
            ),
          ),
        ),
      );

      expect(find.text('إضافة جديد'), findsOneWidget);
      await tester.tap(find.text('إضافة جديد'));
      expect(actionTapped, isTrue);
    });

    testWidgets('does not render button when no action', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: EmptyStateWidget(
              icon: PhosphorIconsBold.warning,
              message: 'فارغ',
            ),
          ),
        ),
      );

      expect(find.byType(ElevatedButton), findsNothing);
    });
  });
}
