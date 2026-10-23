import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/presentation/inventory_bonds_picpos/screens/inventory_bonds_picpos_screen.dart';

void main() {
  testWidgets('InventoryBondsPicposScreen موجودة وقابلة للإنشاء', (t) async {
    expect(const InventoryBondsPicposScreen(), isA<Widget>());
  });
}
