import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/presentation/screens/products/widgets/barcode_label_batch_dialog.dart';
import 'package:picpos_erp/presentation/pos/services/scale_barcode_encoder.dart';
import 'package:picpos_erp/services/printing/barcode_label_spec.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('weighted label shows round-trip barcode and blocks overflow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BarcodeLabelBatchDialog(
            items: const [
              BarcodeLabelItem(
                name: 'Apples',
                barcode: '111',
                price: 2.5,
                scalePluNumber: 123,
                isSoldByWeight: true,
              ),
            ],
            scaleTemplateId: 77,
            scaleSettings: const {
              // منذ 2026-11-04 يلزم تفعيلُ باركود الوزن لإتاحة ملصق الميزان.
              'scale_weight_enabled': 'true',
              'scale_weight_prefix': '21',
              'scale_weight_item_code_len': '5',
              'scale_weight_divider': '1000',
            },
            onPrint: (_, _) async => true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // القائمة الثانية «scale_label_template_dropdown» وُحّدت في قائمة القوالب.
    expect(find.byKey(const Key('scale_template_option')), findsWidgets);
    expect(find.byKey(const Key('scale_label_weight_input')), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('scale_label_weight_input')),
      '1.234',
    );
    await tester.pump();
    final expected = ScaleBarcodeEncoder.encode(
      plu: '123',
      value: 1.234,
      kind: ScaleBarcodeValueKind.weight,
    );
    expect(
      tester
          .widget<SelectableText>(
            find.byKey(const Key('scale_label_barcode_preview')),
          )
          .data,
      expected,
    );
    expect(
      tester
          .widget<ElevatedButton>(find.byKey(const Key('label_print_button')))
          .onPressed,
      isNotNull,
    );

    await tester.enterText(
      find.byKey(const Key('scale_label_weight_input')),
      '100',
    );
    await tester.pump();
    expect(
      tester
          .widget<ElevatedButton>(find.byKey(const Key('label_print_button')))
          .onPressed,
      isNull,
    );
    expect(find.text('قيمة خارج النطاق المسموح'), findsOneWidget);
  });
}
