import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/presentation/shift_close_picpos/screens/shift_close_picpos_screen.dart';
import 'package:picpos_erp/presentation/shift_close_picpos/widgets/picpos_cashier_closing_dialog.dart';
import 'package:picpos_erp/presentation/shift_close_picpos/widgets/picpos_opening_balance_dialog.dart';

void main() {
  testWidgets('ShiftClosePicposScreen موجودة وقابلة للإنشاء', (t) async {
    expect(const ShiftClosePicposScreen(), isA<Widget>());
  });

  testWidgets('PicposOpeningBalanceDialog موجود وقابل للإنشاء', (t) async {
    expect(const PicposOpeningBalanceDialog(userName: 'x'), isA<Widget>());
  });

  testWidgets('PicposCashierClosingDialog موجود وقابل للإنشاء', (t) async {
    expect(const PicposCashierClosingDialog(), isA<Widget>());
  });
}
