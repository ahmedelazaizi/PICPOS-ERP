import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/presentation/activity_log_picpos/screens/activity_log_picpos_screen.dart';

void main() {
  testWidgets('ActivityLogPicposScreen موجودة وقابلة للإنشاء', (t) async {
    expect(const ActivityLogPicposScreen(), isA<Widget>());
  });
}
