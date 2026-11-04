import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/domain/printing/label_design.dart';
import 'package:picpos_erp/presentation/screens/products/widgets/barcode_label_batch_dialog.dart';
import 'package:picpos_erp/services/printing/barcode_label_spec.dart';
import 'package:picpos_erp/services/printing/label_preset_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _items = [
  BarcodeLabelItem(name: 'Alpha', barcode: '111', copies: 2),
  BarcodeLabelItem(name: 'Beta', barcode: '222', copies: 1),
];

Future<void> _open(
  WidgetTester tester, {
  required LabelPrintCallback onPrint,
  LabelDefaultsLoader? loadDefaults,
}) async {
  tester.view.physicalSize = const Size(1200, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: BarcodeLabelBatchDialog(
          items: _items,
          onPrint: onPrint,
          loadDefaults: loadDefaults,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Text _summary(WidgetTester t) =>
    t.widget<Text>(find.byKey(const Key('label_summary')));

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('اختيار قالب محفوظ يمرر هويته لمسار الطباعة المحقون', (
    tester,
  ) async {
    int? printedTemplateId;
    LabelSpec? printedSpec;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BarcodeLabelBatchDialog(
            items: _items,
            templates: const [
              BarcodeLabelTemplateOption(
                id: 23,
                name: 'قالب مخصص',
                widthMm: 58,
                heightMm: 40,
              ),
            ],
            onPrintTemplate: (_, spec, id) async {
              printedSpec = spec;
              printedTemplateId = id;
              return true;
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('barcode_template_dropdown')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('قالب مخصص').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('label_print_button')));
    await tester.pumpAndSettle(const Duration(seconds: 10));
    expect(printedTemplateId, 23);
    expect(printedSpec?.pageWidthMm, 58);
    expect(printedSpec?.pageHeightMm, 40);
  });

  testWidgets('قالبٌ محفوظ: المعاينةُ ترسم عناصرَه كلَّها (اسم/سعر/باركود)', (
    tester,
  ) async {
    // التحقّق الحيّ 2026-11-03: «QA 58x40» عرضت الاسمَ وحده بينما الورقةُ
    // تحمل السعرَ والباركود.
    const design = LabelDesign(
      templateId: 23,
      name: 'QA 58x40',
      widthMm: 58,
      heightMm: 40,
      elements: [
        LabelElement(key: 'e1', type: 'product_name', xMm: 2, yMm: 2, wMm: 54, hMm: 8),
        LabelElement(key: 'e2', type: 'barcode_image', xMm: 2, yMm: 11, wMm: 54, hMm: 16, content: 'code128'),
        LabelElement(key: 'e3', type: 'product_price', xMm: 2, yMm: 29, wMm: 54, hMm: 8, fontSize: 9),
      ],
    );
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: BarcodeLabelBatchDialog(
            items: [BarcodeLabelItem(name: 'Milk', barcode: '6221234567891', price: 12.5)],
            templates: [
              BarcodeLabelTemplateOption(
                id: 23,
                name: 'QA 58x40',
                widthMm: 58,
                heightMm: 40,
                design: design,
              ),
            ],
            defaultTemplateId: 23,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('label_template_preview')), findsOneWidget);
    for (final key in ['e1', 'e2', 'e3']) {
      expect(find.byKey(Key('label_template_op_$key')), findsOneWidget);
    }
    expect(find.text('Milk'), findsWidgets);
    expect(find.text('12.50'), findsOneWidget);
    expect(find.text('6221234567891'), findsOneWidget);
    // مقاسُ المعاينة بنسبة القالب ٥٨:٤٠.
    final size = tester.getSize(find.byKey(const Key('label_template_preview')));
    expect(size.width / size.height, closeTo(58 / 40, 0.01));
  });

  testWidgets('الملخص والمعاينة وتمرير النسخ إلى الطباعة', (tester) async {
    List<BarcodeLabelItem>? printed;
    LabelSpec? usedSpec;
    await _open(
      tester,
      onPrint: (items, spec) async {
        printed = items;
        usedSpec = spec;
        return true;
      },
    );

    expect(_summary(tester).data, contains('3'));
    expect(find.byKey(const Key('label_preview_cell_0')), findsOneWidget);

    await tester.enterText(find.byKey(const Key('label_item_copies_1')), '5');
    await tester.pump();
    expect(_summary(tester).data, contains('7'));

    await tester.tap(find.byKey(const Key('label_item_check_0')));
    await tester.pump();
    expect(_summary(tester).data, contains('5'));

    await tester.tap(find.byKey(const Key('label_print_button')));
    await tester.pumpAndSettle(const Duration(seconds: 10));
    expect(printed!.map((i) => '${i.name}x${i.copies}').toList(), ['Betax5']);
    expect(usedSpec!.id, 'roll_50x25');
  });

  testWidgets('اختيار A4 3×8 يعرض 24 خلية وتُحفظ كمقاس نشط', (tester) async {
    await _open(tester, onPrint: (_, _) async => true);
    await tester.tap(find.byKey(const Key('label_size_dropdown')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('A4 3×8').last);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('label_preview_cell_23')), findsOneWidget);
    expect(find.byKey(const Key('label_preview_cell_24')), findsNothing);

    await tester.tap(find.byKey(const Key('label_print_button')));
    await tester.pumpAndSettle(const Duration(seconds: 10));
    expect((await LabelPresetStore.activeSpec()).id, 'a4_3x8');
  });

  testWidgets('مقاس مخصص صالح يُحفظ، وغير الصالح يعطّل الطباعة', (
    tester,
  ) async {
    await _open(tester, onPrint: (_, _) async => true);
    await tester.tap(find.byKey(const Key('label_size_dropdown')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('مقاس مخصص...').last);
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('label_custom_name')), 'Mine');
    await tester.enterText(find.byKey(const Key('label_custom_width')), '60');
    await tester.enterText(find.byKey(const Key('label_custom_height')), '30');
    await tester.enterText(find.byKey(const Key('label_custom_columns')), '2');
    await tester.pump();
    await tester.tap(find.byKey(const Key('label_custom_save')));
    await tester.pumpAndSettle();

    final saved = await LabelPresetStore.loadCustom();
    expect(saved.single.name, 'Mine');
    expect(saved.single.columns, 2);

    await tester.enterText(find.byKey(const Key('label_custom_width')), '3');
    await tester.pump();
    final btn = tester.widget<ElevatedButton>(
      find.byKey(const Key('label_print_button')),
    );
    expect(btn.onPressed, isNull);
  });

  testWidgets('النسخ الافتراضية تُحمَّل من loadDefaults', (tester) async {
    await _open(
      tester,
      onPrint: (_, _) async => true,
      loadDefaults: (items) async => [items[0].withCopies(12), items[1]],
    );
    expect(find.text('12'), findsOneWidget);
    expect(_summary(tester).data, contains('13'));
  });
}
