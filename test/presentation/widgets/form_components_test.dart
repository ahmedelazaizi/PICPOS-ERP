import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:picpos_erp/presentation/widgets/enhanced_components.dart';
import 'package:picpos_erp/presentation/shared_widgets/form_components.dart';

void main() {
  group('SectionHeader', () {
    testWidgets('displays title and icon', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SectionHeader(
              title: 'المعلومات الأساسية',
              icon: PhosphorIconsBold.info,
            ),
          ),
        ),
      );

      expect(find.text('المعلومات الأساسية'), findsOneWidget);
      expect(find.byIcon(PhosphorIconsBold.info), findsOneWidget);
    });

    testWidgets('uses custom styling', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SectionHeader(
              title: 'Custom',
              icon: PhosphorIconsBold.star,
            ),
          ),
        ),
      );

      final icon = tester.widget<Icon>(find.byIcon(PhosphorIconsBold.star));
      expect(icon.color, isNotNull);
    });
  });

  group('CompactTextField', () {
    testWidgets('displays label and allows input', (tester) async {
      final controller = TextEditingController();
      
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CompactTextField(
              controller: controller,
              label: 'اسم المنتج',
            ),
          ),
        ),
      );

      expect(find.text('اسم المنتج'), findsOneWidget);
      
      await tester.enterText(find.byType(TextField), 'تفاح');
      expect(controller.text, 'تفاح');
    });

    testWidgets('shows prefix icon when provided', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CompactTextField(
              controller: TextEditingController(),
              label: 'كود المنتج',
              icon: PhosphorIconsBold.barcode,
            ),
          ),
        ),
      );

      expect(find.byIcon(PhosphorIconsBold.barcode), findsOneWidget);
    });

    testWidgets('uses number keyboard when isNumber is true', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CompactTextField(
              controller: TextEditingController(),
              label: 'السعر',
              isNumber: true,
            ),
          ),
        ),
      );

      final textField = tester.widget<TextField>(find.byType(TextField));
      expect(textField.keyboardType, const TextInputType.numberWithOptions(decimal: true));
    });
  });

  group('MiniTextField', () {
    testWidgets('renders correctly with label', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MiniTextField(
              controller: TextEditingController(),
              label: 'الكمية',
            ),
          ),
        ),
      );

      expect(find.text('الكمية'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
    });
  });

  group('LabeledSwitch', () {
    testWidgets('displays label and current value', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LabeledSwitch(
              label: 'تتبع المخزون',
              value: true,
              onChanged: (_) {},
            ),
          ),
        ),
      );

      expect(find.text('تتبع المخزون'), findsOneWidget);
      expect(find.byType(Switch), findsOneWidget);
    });

    testWidgets('calls onChanged when toggled', (tester) async {
      bool value = false;
      
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => LabeledSwitch(
                label: 'Toggle',
                value: value,
                onChanged: (newValue) => setState(() => value = newValue),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.byType(Switch));
      await tester.pump();
      
      expect(value, true);
    });

    testWidgets('shows icon when provided', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LabeledSwitch(
              label: 'With Icon',
              value: true,
              onChanged: (_) {},
              icon: PhosphorIconsBold.scales,
            ),
          ),
        ),
      );

      expect(find.byIcon(PhosphorIconsBold.scales), findsOneWidget);
    });
  });
}
