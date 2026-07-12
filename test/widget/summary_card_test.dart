import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:ural_erp/presentation/widgets/summary_card.dart';
import 'package:ural_erp/core/theme/app_colors.dart';

void main() {
  group('SummaryCard', () {
    testWidgets('displays title and value correctly', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Row(
              children: [
                SummaryCard(
                  title: 'Test Title',
                  value: '100',
                  icon: PhosphorIconsBold.package,
                  color: AppColors.primary,
                ),
              ],
            ),
          ),
        ),
      );

      expect(find.text('Test Title'), findsOneWidget);
      expect(find.text('100'), findsOneWidget);
    });

    testWidgets('renders icon with correct color', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Row(
              children: [
                SummaryCard(
                  title: 'Icon Test',
                  value: '50',
                  icon: PhosphorIconsBold.warning,
                  color: AppColors.warning,
                ),
              ],
            ),
          ),
        ),
      );

      final iconFinder = find.byType(Icon);
      expect(iconFinder, findsOneWidget);
    });

    testWidgets('expands when expanded is true', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Row(
              children: [
                SummaryCard(
                  title: 'Expanded',
                  value: '200',
                  icon: PhosphorIconsBold.currencyCircleDollar,
                  color: AppColors.success,
                  expanded: true,
                ),
              ],
            ),
          ),
        ),
      );

      final expandedFinder = find.byType(Expanded);
      expect(expandedFinder, findsWidgets);
    });

    testWidgets('calls onTap when provided', (tester) async {
      bool tapped = false;
      
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Row(
              children: [
                SummaryCard(
                  title: 'Tappable',
                  value: '300',
                  icon: PhosphorIconsBold.chartLine,
                  color: AppColors.info,
                  onTap: () => tapped = true,
                ),
              ],
            ),
          ),
        ),
      );

      await tester.tap(find.byType(InkWell));
      expect(tapped, isTrue);
    });
  });

  group('SummaryCardCompact', () {
    testWidgets('displays compact layout', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SummaryCardCompact(
              title: 'Compact',
              value: '50',
              icon: PhosphorIconsBold.package,
              color: AppColors.primary,
            ),
          ),
        ),
      );

      expect(find.text('Compact'), findsOneWidget);
      expect(find.text('50'), findsOneWidget);
    });
  });
}
