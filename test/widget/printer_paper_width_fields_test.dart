import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/presentation/screens/printer_paper_width_fields.dart';

void main() {
  testWidgets('standard and custom widths update the selected printer value', (
    tester,
  ) async {
    var width = 80.0;
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) => Scaffold(
            body: PrinterPaperWidthFields(
              paperWidthMm: width,
              onChanged: (next) => setState(() => width = next),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byType(DropdownButtonFormField<double>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('58 mm').last);
    await tester.pumpAndSettle();
    expect(width, 58.0);

    await tester.enterText(find.byType(TextField), '76.5');
    await tester.pump();
    expect(width, 76.5);
  });
}
