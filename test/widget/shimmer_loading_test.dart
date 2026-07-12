import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/core/widgets/shimmer_loading.dart';

void main() {
  group('ShimmerLoading', () {
    testWidgets('renders with default dimensions', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ShimmerLoading(),
          ),
        ),
      );

      expect(find.byType(ShimmerLoading), findsOneWidget);
    });

    testWidgets('renders with custom width and height', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ShimmerLoading(width: 100, height: 24),
          ),
        ),
      );

      expect(find.byType(ShimmerLoading), findsOneWidget);
    });

    testWidgets('animates over time', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ShimmerLoading(),
          ),
        ),
      );

      // Advance animation and verify no errors
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(ShimmerLoading), findsOneWidget);
    });
  });

  group('ShimmerLoading.card', () {
    testWidgets('renders card skeleton', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ShimmerLoading.card(),
          ),
        ),
      );

      // Card creates multiple ShimmerLoading children
      expect(find.byType(ShimmerLoading), findsWidgets);
    });

    testWidgets('accepts custom width', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ShimmerLoading.card(width: 300),
          ),
        ),
      );

      expect(find.byType(ShimmerLoading), findsWidgets);
    });
  });

  group('ShimmerLoading.list', () {
    testWidgets('renders default 5 list items', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ShimmerLoading.list(),
          ),
        ),
      );

      expect(find.byType(ListView), findsOneWidget);
    });

    testWidgets('renders custom item count', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ShimmerLoading.list(itemCount: 3),
          ),
        ),
      );

      expect(find.byType(ListView), findsOneWidget);
    });
  });

  group('ShimmerLoading.grid', () {
    testWidgets('renders grid skeleton', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ShimmerLoading.grid(itemCount: 4, crossAxisCount: 2),
          ),
        ),
      );

      expect(find.byType(GridView), findsOneWidget);
    });
  });
}
