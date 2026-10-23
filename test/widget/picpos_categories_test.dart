import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/presentation/categories_picpos/screens/categories_picpos_screen.dart';

void main() {
  testWidgets('CategoriesPicposScreen موجودة وقابلة للإنشاء', (t) async {
    expect(const CategoriesPicposScreen(), isA<Widget>());
  });
}
