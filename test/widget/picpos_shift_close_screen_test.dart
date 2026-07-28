import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/presentation/screens/shift_close_screen.dart';

void main() {
  testWidgets('ShiftCloseScreen موجودة وقابلة للإنشاء', (t) async {
    expect(const ShiftCloseScreen(), isA<Widget>());
  });
}
