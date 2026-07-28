import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/presentation/users_picpos/screens/users_management_picpos_screen.dart';

void main() {
  testWidgets('UsersManagementPicposScreen موجودة وقابلة للإنشاء', (t) async {
    expect(const UsersManagementPicposScreen(), isA<Widget>());
  });
}
