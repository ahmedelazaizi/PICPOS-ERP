import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/presentation/purchase_returns_picpos/screens/purchase_returns_picpos_screen.dart';

void main() {
  testWidgets('PurchaseReturnsPicposScreen موجودة وقابلة للإنشاء', (t) async {
    expect(const PurchaseReturnsPicposScreen(), isA<Widget>());
  });
}
