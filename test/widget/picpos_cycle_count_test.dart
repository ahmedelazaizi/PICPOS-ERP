import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/presentation/cycle_count_picpos/screens/cycle_count_picpos_screen.dart';

void main() {
  testWidgets('CycleCountPicposScreen موجودة وقابلة للإنشاء', (t) async {
    expect(const CycleCountPicposScreen(), isA<Widget>());
  });
}
