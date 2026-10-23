import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:picpos_erp/presentation/widgets/report_components.dart';
import 'package:picpos_erp/core/theme/app_colors.dart';

void main() {
  group('ReportKpiCard', () {
    testWidgets('displays title and value', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Row(
              children: [
                Expanded(
                  child: ReportKpiCard(
                    title: 'إجمالي المبيعات',
                    value: '1,500.00 JOD',
                    icon: PhosphorIconsBold.chartLineUp,
                    color: AppColors.primary,
                  ),
                ),
              ],
            ),
          ),
        ),
      );

      expect(find.text('إجمالي المبيعات'), findsOneWidget);
      expect(find.text('1,500.00 JOD'), findsOneWidget);
    });

    testWidgets('displays subtitle when provided', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Row(
              children: [
                Expanded(
                  child: ReportKpiCard(
                    title: 'Test',
                    value: '100',
                    icon: PhosphorIconsBold.receipt,
                    color: AppColors.info,
                    subtitle: 'متوسط: 50',
                  ),
                ),
              ],
            ),
          ),
        ),
      );

      expect(find.text('متوسط: 50'), findsOneWidget);
    });

    testWidgets('shows positive change badge with ↑', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Row(
              children: [
                Expanded(
                  child: ReportKpiCard(
                    title: 'مبيعات',
                    value: '2,000',
                    icon: PhosphorIconsBold.trendUp,
                    color: AppColors.success,
                    changePercent: 25.5,
                  ),
                ),
              ],
            ),
          ),
        ),
      );

      expect(find.text('↑'), findsOneWidget);
      expect(find.text('25.5%'), findsOneWidget);
    });

    testWidgets('shows negative change badge with ↓', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Row(
              children: [
                Expanded(
                  child: ReportKpiCard(
                    title: 'أرباح',
                    value: '500',
                    icon: PhosphorIconsBold.trendDown,
                    color: AppColors.error,
                    changePercent: -12.3,
                  ),
                ),
              ],
            ),
          ),
        ),
      );

      expect(find.text('↓'), findsOneWidget);
      expect(find.text('12.3%'), findsOneWidget);
    });

    testWidgets('hides change badge when null', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Row(
              children: [
                Expanded(
                  child: ReportKpiCard(
                    title: 'عدد',
                    value: '10',
                    icon: PhosphorIconsBold.receipt,
                    color: AppColors.info,
                  ),
                ),
              ],
            ),
          ),
        ),
      );

      expect(find.text('↑'), findsNothing);
      expect(find.text('↓'), findsNothing);
    });
  });
}
