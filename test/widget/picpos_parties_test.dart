import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/presentation/parties_picpos/screens/parties_picpos_screen.dart';

void main() {
  testWidgets('PartiesPicposScreen موجودة وقابلة للإنشاء', (t) async {
    expect(const PartiesPicposScreen(), isA<Widget>());
  });
}
