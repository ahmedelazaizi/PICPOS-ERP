// «المشتريات الخارجيّة» — لوحُ الاستيراد وتحويلُ العملة.
//
// ═══ ما يقيسه هذا الملفّ ═══
//
// ‏١) 🔴 **التحويلُ يقع، وبالاتّجاه الصحيح.** قلبُه لا يُنتج خطأً: يُنتج
//    رقماً بحجمٍ آخر. فالتوكيداتُ على **قيمٍ محسوبةٍ يدويّاً**.
//
// ‏٢) 🔴 **وسعرٌ ناقصٌ يُوقف الحفظ.** عملةٌ بلا سعرٍ تُقرأ لاحقاً سعراً ١،
//    فتُقيَّد ألفُ دولارٍ على المورّد بألفِ وحدةٍ محلّيّة — والقيدُ
//    **متّزنٌ على الرقم الخاطئ**.
//
// ‏٣) **والكمّيّةُ والنسبةُ ليستا مالاً** فلا تُضرَبان — ضربُ النسبة كان
//    يجعل ١٤٪ ضريبةَ ٠٫٢٨٪.
//
// ‏٤) **ووكيلٌ مسجَّلٌ يُسقط حقلَ النصّ** — حقلان لا يقولان اسمَين.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ural_erp/data/database/database.dart' show Currency;
import 'package:ural_erp/domain/models/import_purchase_plan.dart';
import 'package:ural_erp/presentation/import_purchases_picpos/screens/import_purchases_picpos_screen.dart';

const _usd = (
  id: 3,
  code: 'USD',
  name: 'دولار أمريكي',
  symbol: r'$',
  localPerForeign: 0.71,
  isBase: false,
);

Future<List<ImportPanelValue>> _pump(
  WidgetTester tester, {
  List<ImportCurrencyOption> currencies = const [_usd],
  List<ImportAgentOption> agents = const [(id: 7, name: 'مخلّص جمركي')],
  double width = 1440,
}) async {
  final out = <ImportPanelValue>[];
  tester.view.physicalSize = Size(width, 1400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        child: ImportDocumentPanel(
          currencies: currencies,
          agents: agents,
          onChanged: out.add,
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
  return out;
}

Future<void> _teardownTree(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
}

Future<void> _pickCurrency(WidgetTester tester, String label) async {
  await tester.tap(find.byKey(const Key('import_currency')));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

void main() {
  group('١ · تحويلُ سطورِ النموذج', () {
    const items = [
      {
        'productId': 5,
        'quantity': 10.0,
        'unitCost': 100.0,
        'taxRate': 14.0,
        'taxAmount': 140.0,
        'discount': 0.0,
        'selectedUnitName': 'قطعة',
      }
    ];

    test('🔴 التكلفةُ تُضرَب بالسعر', () {
      final out =
          convertFormItemsToLocal(items: items, localPerForeign: 0.02);
      expect(out.single.unitCost, 2.0);
    });

    test('🔴 والكمّيّةُ لا تُضرَب — عشرُ قطعٍ تبقى عشراً', () {
      final out =
          convertFormItemsToLocal(items: items, localPerForeign: 0.02);
      expect(out.single.quantity, 10.0);
    });

    test('🔴 والنسبةُ لا تُضرَب — ١٤٪ تبقى ١٤٪', () {
      final out =
          convertFormItemsToLocal(items: items, localPerForeign: 0.02);
      expect(out.single.taxRate, 14.0);
    });

    test('ومبلغُ الضريبة يُحوَّل ولا يُعاد حسابُه', () {
      final out =
          convertFormItemsToLocal(items: items, localPerForeign: 0.02);
      expect(out.single.taxAmount, 2.8);
    });

    test('والخصمُ يُحوَّل', () {
      final out = convertFormItemsToLocal(
        items: const [
          {
            'productId': 5,
            'quantity': 1.0,
            'unitCost': 100.0,
            'taxRate': 0.0,
            'taxAmount': 0.0,
            'discount': 50.0,
          }
        ],
        localPerForeign: 0.02,
      );
      expect(out.single.discount, 1.0);
    });

    test('وبسعرِ ١ لا يتغيّر شيء — وهو حالُ الفاتورة المحلّيّة', () {
      final out = convertFormItemsToLocal(items: items, localPerForeign: 1);
      expect(out.single.unitCost, 100.0);
      expect(out.single.taxAmount, 140.0);
    });

    test('ومفتاحٌ غائبٌ يُقرأ صفراً لا يرمي', () {
      final out = convertFormItemsToLocal(
        items: const [
          {'productId': 5, 'quantity': 2.0, 'unitCost': 10.0}
        ],
        localPerForeign: 0.5,
      );
      expect(out.single.taxAmount, 0.0);
      expect(out.single.discount, 0.0);
      expect(out.single.unitCost, 5.0);
    });
  });

  group('٢ · منتقي العملة', () {
    test('🔴 المحلّيّةُ ليست خياراً — غيابُ الاختيار هو المحلّيّة', () {
      final opts = importCurrencyOptions([
        _currency(id: 1, code: 'JOD', isDefault: true, isActive: true),
        _currency(id: 2, code: 'USD', isDefault: false, isActive: true),
      ]);
      expect(opts.map((o) => o.code), ['USD']);
    });

    test('والمعطَّلةُ تُسقَط', () {
      final opts = importCurrencyOptions([
        _currency(id: 2, code: 'USD', isDefault: false, isActive: false),
      ]);
      expect(opts, isEmpty);
    });

    testWidgets('اختيارُ عملةٍ يُظهر حقلَ السعر ويملؤه من المسجَّل',
        (tester) async {
      final out = await _pump(tester);
      expect(find.byKey(const Key('import_rate')), findsNothing);
      await _pickCurrency(tester, 'USD — دولار أمريكي');
      expect(find.byKey(const Key('import_rate')), findsOneWidget);
      expect(out.last.currencyId, 3);
      expect(out.last.localPerForeign, 0.71);
      await _teardownTree(tester);
    });

    testWidgets('والسعرُ يبقى قابلاً للتحرير — سعرُ الصفقة قد يخالف المسجَّل',
        (tester) async {
      final out = await _pump(tester);
      await _pickCurrency(tester, 'USD — دولار أمريكي');
      await tester.enterText(find.byKey(const Key('import_rate')), '0.75');
      await tester.pumpAndSettle();
      expect(out.last.localPerForeign, 0.75);
      await _teardownTree(tester);
    });

    testWidgets('🔴 وسعرٌ ممسوحٌ يوقف الحفظ برسالةٍ صريحة', (tester) async {
      await _pump(tester);
      await _pickCurrency(tester, 'USD — دولار أمريكي');
      expect(find.byKey(const Key('import_block_reason')), findsNothing);
      await tester.enterText(find.byKey(const Key('import_rate')), '');
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('import_block_reason')), findsOneWidget);
      await _teardownTree(tester);
    });

    testWidgets('وسعرُ صفرٍ يوقف الحفظ كذلك', (tester) async {
      await _pump(tester);
      await _pickCurrency(tester, 'USD — دولار أمريكي');
      await tester.enterText(find.byKey(const Key('import_rate')), '0');
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('import_block_reason')), findsOneWidget);
      await _teardownTree(tester);
    });

    testWidgets('والرجوعُ إلى المحلّيّة يمسح السعرَ ويرفع المنع',
        (tester) async {
      final out = await _pump(tester);
      await _pickCurrency(tester, 'USD — دولار أمريكي');
      await _pickCurrency(tester, 'محلّيّة — بلا تحويل');
      expect(find.byKey(const Key('import_rate')), findsNothing);
      expect(find.byKey(const Key('import_block_reason')), findsNothing);
      expect(out.last.currencyId, isNull);
      expect(out.last.localPerForeign, isNull);
      await _teardownTree(tester);
    });

    testWidgets('والتنبيهُ يقول إنّ الذمّةَ محلّيّةٌ فلا فروقَ صرف',
        (tester) async {
      await _pump(tester);
      await _pickCurrency(tester, 'USD — دولار أمريكي');
      expect(find.byKey(const Key('import_rate_hint')), findsOneWidget);
      await _teardownTree(tester);
    });
  });

  group('٣ · الحقولُ المستنديّة', () {
    testWidgets('الستّةُ حاضرةٌ بمفاتيحها', (tester) async {
      await _pump(tester);
      for (final k in const [
        'import_customs',
        'import_bl',
        'import_country',
        'import_port',
        'import_lc',
        'import_agent',
      ]) {
        expect(find.byKey(Key(k)), findsOneWidget, reason: 'غاب الحقل $k');
      }
      await _teardownTree(tester);
    });

    testWidgets('وما يُكتَب يصل المُخرَجَ مقلَّماً', (tester) async {
      final out = await _pump(tester);
      await tester.enterText(
          find.byKey(const Key('import_customs')), '  C-4021  ');
      await tester.pumpAndSettle();
      expect(out.last.doc.customsDeclarationNo, 'C-4021');
      await _teardownTree(tester);
    });

    testWidgets('🔴 ووكيلٌ مسجَّلٌ يُسقط حقلَ النصّ', (tester) async {
      final out = await _pump(tester);
      expect(find.byKey(const Key('import_agent_name')), findsOneWidget);
      await tester.tap(find.byKey(const Key('import_agent')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('مخلّص جمركي').last);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('import_agent_name')), findsNothing);
      expect(out.last.doc.clearingAgentPartyId, 7);
      expect(out.last.doc.clearingAgentName, isNull);
      await _teardownTree(tester);
    });

    testWidgets('وطولٌ يتجاوز العمودَ يُعرَض منعاً قبل الحفظ', (tester) async {
      await _pump(tester);
      await tester.enterText(
          find.byKey(const Key('import_bl')), 'x' * (kBillOfLadingMax + 1));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('import_block_reason')), findsOneWidget);
      await _teardownTree(tester);
    });

    testWidgets('ولوحٌ خالٍ لا يمنع — لا حقلَ إلزاميّ', (tester) async {
      await _pump(tester);
      expect(find.byKey(const Key('import_block_reason')), findsNothing);
      await _teardownTree(tester);
    });
  });
}

Currency _currency({
  required int id,
  required String code,
  required bool isDefault,
  required bool isActive,
  double rate = 1,
}) =>
    Currency(
      id: id,
      code: code,
      name: 'عملة $code',
      symbol: code,
      exchangeRate: rate,
      decimalPlaces: 2,
      isDefault: isDefault,
      isActive: isActive,
      createdAt: DateTime(2026, 1, 1),
      rowVersion: 0,
    );
