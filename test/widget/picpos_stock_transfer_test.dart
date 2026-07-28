import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/presentation/stock_transfer_picpos/screens/stock_transfer_picpos_screen.dart';

void main() {
  testWidgets('StockTransferPicposScreen موجودة وقابلة للإنشاء', (t) async {
    expect(const StockTransferPicposScreen(), isA<Widget>());
  });
}
