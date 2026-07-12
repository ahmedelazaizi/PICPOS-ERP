import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:ural_erp/presentation/shared_widgets/dashboard_widgets.dart';

void main() {
  group('SummaryCard', () {
    testWidgets('displays title, value, and icon', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SummaryCard(
              title: 'Total Sales',
              value: '1,234',
              icon: PhosphorIconsBold.currencyDollar,
            ),
          ),
        ),
      );

      expect(find.text('Total Sales'), findsOneWidget);
      expect(find.text('1,234'), findsOneWidget);
      expect(find.byIcon(PhosphorIconsBold.currencyDollar), findsOneWidget);
    });

    testWidgets('shows arrow when onTap is provided', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SummaryCard(
              title: 'Test',
              value: '100',
              icon: PhosphorIconsBold.package,
              onTap: () {},
            ),
          ),
        ),
      );

      expect(find.byIcon(PhosphorIconsBold.arrowRight), findsOneWidget);
    });

    testWidgets('calls onTap when tapped', (tester) async {
      bool tapped = false;
      
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SummaryCard(
              title: 'Test',
              value: '100',
              icon: PhosphorIconsBold.package,
              onTap: () => tapped = true,
            ),
          ),
        ),
      );

      await tester.tap(find.byType(SummaryCard));
      expect(tapped, true);
    });
  });

  group('AlertBadge', () {
    testWidgets('shows count when greater than 0', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AlertBadge(count: 5),
          ),
        ),
      );

      expect(find.text('5'), findsOneWidget);
    });

    testWidgets('hides when count is 0', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AlertBadge(count: 0),
          ),
        ),
      );

      expect(find.byType(Container), findsNothing);
    });

    testWidgets('shows 99+ when count exceeds 99', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AlertBadge(count: 150),
          ),
        ),
      );

      expect(find.text('99+'), findsOneWidget);
    });
  });

  group('StatusDot', () {
    testWidgets('displays with correct color and size', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: StatusDot(color: Colors.green, size: 12),
          ),
        ),
      );

      final container = tester.widget<Container>(find.byType(Container));
      expect(container.constraints?.maxWidth, 12);
    });
  });

  group('EmptyStateWidget', () {
    testWidgets('displays icon and message', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: EmptyStateWidget(
              icon: PhosphorIconsBold.package,
              message: 'No items found',
            ),
          ),
        ),
      );

      expect(find.text('No items found'), findsOneWidget);
      expect(find.byIcon(PhosphorIconsBold.package), findsOneWidget);
    });

    testWidgets('shows action button when provided', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EmptyStateWidget(
              icon: PhosphorIconsBold.plus,
              message: 'No items',
              actionLabel: 'Add Item',
              onAction: () {},
            ),
          ),
        ),
      );

      expect(find.text('Add Item'), findsOneWidget);
      expect(find.byType(ElevatedButton), findsOneWidget);
    });
  });

  group('LoadingOverlay', () {
    testWidgets('shows loading indicator when isLoading is true', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: LoadingOverlay(
              isLoading: true,
              child: Text('Content'),
            ),
          ),
        ),
      );

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Content'), findsOneWidget);
    });

    testWidgets('hides loading indicator when isLoading is false', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: LoadingOverlay(
              isLoading: false,
              child: Text('Content'),
            ),
          ),
        ),
      );

      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('Content'), findsOneWidget);
    });
  });
}
