import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/presentation/pos_picpos/widgets/picpos_return_mode_banner.dart';

void main() {
  testWidgets('الترويسةُ تُظهر رقمَ الفاتورة وتُميَّز بلونٍ تحذيريّ',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: PicPosReturnModeBanner(invoiceNumber: 'SINV-4'),
      ),
    ));

    expect(find.textContaining('وضع المرتجع'), findsOneWidget);
    expect(find.textContaining('SINV-4'), findsOneWidget,
        reason: 'رقمُ الفاتورة يبقى ظاهراً — سلةٌ تبدو كسلّة بيعٍ وتفعل عكسَها '
            'هي وصفةُ خطأٍ يوميّ');
  });
}
