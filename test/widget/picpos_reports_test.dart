import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/presentation/reports_picpos/screens/reports_picpos_screen.dart';

void main() {
  testWidgets('ReportsPicposScreen موجودة وقابلة للإنشاء', (t) async {
    expect(const ReportsPicposScreen(), isA<Widget>());
  });
}
