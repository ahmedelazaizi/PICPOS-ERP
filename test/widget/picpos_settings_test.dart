import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/presentation/settings_picpos/screens/settings_picpos_screen.dart';

void main() {
  testWidgets('SettingsPicposScreen موجودة وقابلة للإنشاء', (t) async {
    expect(const SettingsPicposScreen(), isA<Widget>());
  });
}
