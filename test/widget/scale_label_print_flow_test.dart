import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/data/database/database.dart';
import 'package:picpos_erp/presentation/pos/services/scale_barcode_encoder.dart';
import 'package:picpos_erp/presentation/screens/products/widgets/barcode_label_batch_dialog.dart';
import 'package:picpos_erp/services/printing/barcode_label_spec.dart';
import 'package:picpos_erp/services/printing/label_item_sample.dart';
import 'package:picpos_erp/services/templated_invoice_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _enabled = {
  'scale_weight_enabled': 'true',
  'scale_weight_prefix': '23',
  'scale_weight_item_code_len': '5',
  'scale_weight_divider': '1000',
};

const _weighed = BarcodeLabelItem(
  name: 'منتج تجريبي',
  barcode: '111',
  price: 10,
  scalePluNumber: 12345,
  isSoldByWeight: true,
);

const _scaleOption = BarcodeLabelTemplateOption(
  id: 501,
  name: 'ملصق ميزان',
  widthMm: 58,
  heightMm: 40,
);

Widget _dialog({
  required Map<String, String> settings,
  BarcodeLabelItem item = _weighed,
  int? scaleTemplateId = 501,
  List<BarcodeLabelTemplateOption> templates = const [_scaleOption],
  LabelTemplatePrintCallback? onPrintTemplate,
}) => MaterialApp(
  home: Scaffold(
    body: BarcodeLabelBatchDialog(
      key: const Key('dlg'),
      items: [item],
      templates: templates,
      scaleTemplateId: scaleTemplateId,
      scaleSettings: settings,
      onPrint: (_, _) async => true,
      onPrintTemplate: onPrintTemplate,
    ),
  ),
);

void _bigView(WidgetTester tester) {
  tester.view.physicalSize = const Size(1200, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

/// يفتح قائمة القوالب ويقرأ عنصر «ملصق ميزان» منها (العناصر لا تُبنى
/// كـ`DropdownMenuItem` إلا داخل القائمة المفتوحة)، ثم يغلقها.
Future<DropdownMenuItem<int?>> _scaleMenuItem(
  WidgetTester tester, {
  int id = 501,
}) async {
  await tester.tap(find.byKey(const Key('barcode_template_dropdown')));
  await tester.pumpAndSettle();
  final item = tester
      .widgetList<DropdownMenuItem<int?>>(find.byType(DropdownMenuItem<int?>))
      .firstWhere((i) => i.value == id);
  await tester.tapAt(const Offset(2, 2));
  await tester.pumpAndSettle();
  return item;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('enabled + weighed: «ملصق ميزان» selectable → weight → '
      'encoder barcode → 58×40 PDF', (tester) async {
    _bigView(tester);
    late AppDatabase db;
    late int templateId;
    await tester.runAsync(() async {
      db = AppDatabase.forTesting();
      await db.seedDefaultTemplates();
      templateId = (await db.getAllTemplates())
          .singleWhere(
            (t) => t.templateCategory == 'barcode' && t.name == 'ملصق ميزان',
          )
          .id;
    });

    List<BarcodeLabelItem>? printedItems;
    int? printedTemplate;
    await tester.pumpWidget(
      _dialog(
        settings: _enabled,
        scaleTemplateId: templateId,
        templates: [
          BarcodeLabelTemplateOption(
            id: templateId,
            name: 'ملصق ميزان',
            widthMm: 58,
            heightMm: 40,
          ),
        ],
        onPrintTemplate: (items, spec, id) async {
          printedItems = items;
          printedTemplate = id;
          expect(spec.pageWidthMm, 58);
          expect(spec.pageHeightMm, 40);
          return true;
        },
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('scale_template_option')), findsWidgets);
    expect(find.byKey(const Key('scale_label_unavailable_hint')), findsNothing);
    expect(
      find.text('ملصق ميزان (غير متاح)', skipOffstage: false),
      findsNothing,
    );

    // تبديلٌ عبر القائمة نفسها: الافتراضي يُخفي حقل الوزن، والميزان يعيده.
    await tester.tap(find.byKey(const Key('barcode_template_dropdown')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('التصميم الافتراضي القديم').last);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('scale_label_weight_input')), findsNothing);
    await tester.tap(find.byKey(const Key('barcode_template_dropdown')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ملصق ميزان').last);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('scale_label_weight_input')), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('scale_label_weight_input')),
      '1.234',
    );
    await tester.pump();
    final expected = ScaleBarcodeEncoder.encode(
      plu: '12345',
      value: 1.234,
      kind: ScaleBarcodeValueKind.weight,
      prefix: '23',
    );
    expect(
      tester
          .widget<SelectableText>(
            find.byKey(const Key('scale_label_barcode_preview')),
          )
          .data,
      expected,
    );

    await tester.tap(find.byKey(const Key('label_print_button')));
    await tester.pumpAndSettle(const Duration(seconds: 2));
    expect(printedTemplate, templateId);
    final item = printedItems!.single;
    expect(item.scaleBarcode, expected);
    expect(item.scaleWeight, 1.234);

    // نفس ما يمرّره BarcodePrintDialog للراسم: labelSampleForItem ⇒ PDF.
    Uint8List? bytes;
    await tester.runAsync(() async {
      final s = labelSampleForItem(item, now: DateTime(2026, 11, 4));
      expect(s.barcodeValue, expected);
      await TemplatedInvoiceService.printBarcodeWithTemplate(
        db: db,
        templateId: templateId,
        barcodeValue: s.barcodeValue,
        productName: s.productName,
        productCode: s.productCode,
        price: s.price,
        weight: s.weight,
        total: s.total,
        packDate: s.packDate,
        directPrint: false,
        debugBuildOnly: true,
        onDebugBytes: (b) => bytes = b,
      );
      await db.close();
    });
    expect(String.fromCharCodes(bytes!.sublist(0, 5)), '%PDF-');
    final box = RegExp(
      r'MediaBox\[0 0 ([\d.]+) ([\d.]+)\]',
    ).firstMatch(String.fromCharCodes(bytes!));
    expect(double.parse(box!.group(1)!), closeTo(58 * 72 / 25.4, 0.01));
    expect(double.parse(box.group(2)!), closeTo(40 * 72 / 25.4, 0.01));
    // مؤقّت إشعار «تمت الطباعة» (AppToast) يُستهلك قبل نهاية الاختبار.
    await tester.pumpAndSettle(const Duration(seconds: 10));
  });

  testWidgets('disabled setting: option disabled with guidance, enabling '
      'refreshes the list', (tester) async {
    _bigView(tester);
    final disabled = Map<String, String>.of(_enabled)
      ..['scale_weight_enabled'] = 'false';
    await tester.pumpWidget(_dialog(settings: disabled));
    await tester.pumpAndSettle();

    expect((await _scaleMenuItem(tester)).enabled, isFalse);
    expect(find.byKey(const Key('scale_label_weight_input')), findsNothing);
    final hint = tester.widget<Text>(
      find.byKey(const Key('scale_label_unavailable_hint')),
    );
    expect(hint.data, contains('فعّله من الإعدادات'));
    expect(hint.data, contains('باركود الميزان'));

    // الإعداد فُعّل (الحوار يُبنى بالقيم الجديدة) ⇒ الخيار يُتاح.
    await tester.pumpWidget(_dialog(settings: _enabled));
    await tester.pumpAndSettle();
    expect((await _scaleMenuItem(tester)).enabled, isTrue);
    expect(find.byKey(const Key('scale_label_unavailable_hint')), findsNothing);
    await tester.tap(find.byKey(const Key('barcode_template_dropdown')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ملصق ميزان').last);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('scale_label_weight_input')), findsOneWidget);

    // أُطفئ مجدداً والحوار مفتوح ⇒ لا يبقى مختاراً.
    await tester.pumpWidget(_dialog(settings: disabled));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('scale_label_weight_input')), findsNothing);
    expect(find.byKey(const Key('scale_label_unavailable_hint')), findsOneWidget);
  });

  testWidgets('non-weighed product: option listed but disabled with reason', (
    tester,
  ) async {
    _bigView(tester);
    await tester.pumpWidget(
      _dialog(
        settings: _enabled,
        item: const BarcodeLabelItem(name: 'Soap', barcode: '6281', price: 3),
      ),
    );
    await tester.pumpAndSettle();
    expect((await _scaleMenuItem(tester)).enabled, isFalse);
    expect(
      find.text('ملصق ميزان (غير متاح)', skipOffstage: false),
      findsWidgets,
    );
    expect(
      tester
          .widget<Text>(find.byKey(const Key('scale_label_unavailable_hint')))
          .data,
      contains('للأصناف المباعة بالوزن فقط'),
    );
    expect(find.byKey(const Key('scale_label_weight_input')), findsNothing);
  });

  testWidgets('weighed product without PLU explains the missing PLU', (
    tester,
  ) async {
    _bigView(tester);
    await tester.pumpWidget(
      _dialog(
        settings: _enabled,
        item: const BarcodeLabelItem(
          name: 'Cheese',
          barcode: '1',
          isSoldByWeight: true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect((await _scaleMenuItem(tester)).enabled, isFalse);
    expect(
      tester
          .widget<Text>(find.byKey(const Key('scale_label_unavailable_hint')))
          .data,
      contains('PLU'),
    );
  });
}
