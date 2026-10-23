import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/presentation/widgets/status_badge.dart';
import 'package:picpos_erp/core/theme/app_colors.dart';

void main() {
  group('StatusBadge', () {
    testWidgets('displays text correctly', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: StatusBadge(
              text: 'مدفوع',
              color: AppColors.success,
            ),
          ),
        ),
      );

      expect(find.text('مدفوع'), findsOneWidget);
    });

    testWidgets('applies correct background color', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: StatusBadge(
              text: 'معلق',
              color: AppColors.error,
            ),
          ),
        ),
      );

      final container = tester.widget<Container>(find.byType(Container));
      final decoration = container.decoration as BoxDecoration;
      expect(decoration.color, equals(AppColors.error.withValues(alpha: 0.1)));
    });
  });

  group('StatusBadge.fromPaymentStatus', () {
    testWidgets('creates paid badge correctly', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatusBadge.fromPaymentStatus(PaymentStatus.paid),
          ),
        ),
      );

      expect(find.text('مدفوع'), findsOneWidget);
    });

    testWidgets('creates partial badge correctly', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatusBadge.fromPaymentStatus(PaymentStatus.partial),
          ),
        ),
      );

      expect(find.text('جزئي'), findsOneWidget);
    });

    testWidgets('creates pending badge correctly', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatusBadge.fromPaymentStatus(PaymentStatus.pending),
          ),
        ),
      );

      expect(find.text('معلق'), findsOneWidget);
    });
  });

  group('StatusBadge.fromPaymentStatusString', () {
    testWidgets('creates badge from "paid" string', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatusBadge.fromPaymentStatusString('paid'),
          ),
        ),
      );

      expect(find.text('مدفوع'), findsOneWidget);
    });

    testWidgets('creates badge from "partial" string', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatusBadge.fromPaymentStatusString('partial'),
          ),
        ),
      );

      expect(find.text('جزئي'), findsOneWidget);
    });

    testWidgets('defaults to pending for unknown status', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatusBadge.fromPaymentStatusString('unknown'),
          ),
        ),
      );

      expect(find.text('معلق'), findsOneWidget);
    });
  });

  group('StatusBadge.forStock', () {
    testWidgets('shows available for stock above minimum', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatusBadge.forStock(currentStock: 100, minStock: 10),
          ),
        ),
      );

      expect(find.text('متوفر'), findsOneWidget);
    });

    testWidgets('shows low for stock at minimum', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatusBadge.forStock(currentStock: 10, minStock: 10),
          ),
        ),
      );

      expect(find.text('منخفض'), findsOneWidget);
    });

    testWidgets('shows out of stock for zero stock', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatusBadge.forStock(currentStock: 0, minStock: 10),
          ),
        ),
      );

      expect(find.text('نفذ'), findsOneWidget);
    });
  });
}
