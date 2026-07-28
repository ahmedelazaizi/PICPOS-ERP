import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/presentation/sales_returns_picpos/screens/sales_returns_picpos_screen.dart';

void main() {
  testWidgets('SalesReturnsPicposScreen موجودة وقابلة للإنشاء', (t) async {
    expect(const SalesReturnsPicposScreen(), isA<Widget>());
  });
}
