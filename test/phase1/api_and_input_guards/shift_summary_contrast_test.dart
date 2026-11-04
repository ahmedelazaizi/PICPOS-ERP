import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/presentation/shift_close_picpos/widgets/shift_closing_summary_label.dart';
import 'package:picpos_erp/presentation/picpos_shell/picpos_surface.dart';

import '../../support/contrast_audit.dart';

void main() {
  for (final brightness in [Brightness.light, Brightness.dark]) {
    testWidgets('shift summary labels meet WCAG contrast in $brightness', (tester) async {
      await tester.pumpWidget(auditApp(
        brightness: brightness,
        home: Scaffold(body: Builder(builder: (context) => ColoredBox(
          color: context.picposField,
          child: const Padding(
            padding: EdgeInsets.all(8),
            child: ShiftClosingSummaryLabel('إجمالي المدفوعات من الصندوق'),
          ),
        ))),
      ));
      final violations = auditContrast(tester);
      expect(violations, isEmpty, reason: describeViolations(violations));
    });
  }
}
