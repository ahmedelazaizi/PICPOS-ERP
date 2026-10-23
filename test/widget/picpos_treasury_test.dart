import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/presentation/treasury_picpos/screens/treasury_picpos_screen.dart';

void main() {
  testWidgets('TreasuryPicposScreen موجودة وقابلة للإنشاء', (t) async {
    expect(const TreasuryPicposScreen(), isA<Widget>());
  });
}
