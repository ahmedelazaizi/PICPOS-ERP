// «فاتورة مبيعات» — تصميمُ المالك `12.02.29`.
//
// ═══ ما يقيسه هذا الملفّ ═══
//
// ‏١) 🔴 **«الفرع» يُعرَض مقفولاً على فرع المخزن.** المحرّكُ يشتقّ `branchId`
//    من `warehouses.branch_id` حين لا يمرّره المنادي — وهذه الشاشةُ لا
//    تمرّره. فمنتقي فرعٍ كان يَعِد بما لا يقع: يختار المستخدمُ فرعاً ويُختَم
//    المستندُ على فرع المخزن، ثمّ يبحث عن فاتورته في تقارير فرعٍ آخر.
//
// ‏٢) 🔴 **ومخزنٌ بلا فرعٍ يُقال صراحةً.** `branch_id = NULL` يُختَم على
//    الفاتورة فتسقط من كلّ تقريرٍ مرشَّحٍ بفرع. وقولُ ذلك قبل الحفظ أرخصُ من
//    اكتشافه آخرَ الشهر.
//
// ‏٣) 🔴 **ومعاينةُ A4 قبل الحفظ تمرّر ما يُعرَض** — ورقةُ معاينةٍ تحسب
//    بنفسها ليست معاينة. والزرُّ **يتبع الرابطَ**: بلا مسارِ معاينةٍ لا
//    يُعرَض أصلاً.
//
// ‏٤) **ولا معاينةَ لفاتورةٍ فارغة**: ورقةٌ بلا سطرٍ لا تعني شيئاً، والمنعُ
//    يُقال ولا يُبتلَع.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/domain/models/picpos_invoice_draft.dart';
import 'package:picpos_erp/presentation/invoice_form_picpos/picpos_invoice_form.dart';

const _products = [
  PicPosProductOption(
    id: 1,
    name: 'ورق طباعة A4',
    salePrice: 60,
    costPrice: 40,
    taxRate: 0,
  ),
];

const _parties = [
  PicPosPartyOption(
      id: 5, name: 'شركة النور', meta: 'آجل', paymentTermsDays: 30),
];

void main() {
  /// ما وصل `onPreviewA4` — يُفحَص بدل مراقبة نداءٍ صامت.
  late List<Map<String, dynamic>> previews;

  setUp(() => previews = []);

  Future<void> pump(
    WidgetTester tester, {
    PicPosInvoiceKind kind = PicPosInvoiceKind.sales,
    List<PicPosWarehouseOption> warehouses = const [
      PicPosWarehouseOption(
          id: 2, name: 'المخزن الرئيسي', branchName: 'الفرع الرئيسي'),
    ],
    int? initialWarehouseId = 2,
    bool withPreview = true,
    Size size = const Size(1440, 900),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PicPosInvoiceForm(
          kind: kind,
          parties: _parties,
          products: _products,
          warehouses: warehouses,
          costCenters: const [],
          systemTaxRate: 0,
          invoiceNumberPreview: 'يُولَّد تلقائياً',
          userName: 'أحمد',
          initialWarehouseId: initialWarehouseId,
          onCancel: () {},
          onPreviewA4: !withPreview
              ? null
              : ({
                  required partyId,
                  required date,
                  required items,
                  required subtotal,
                  required discount,
                  required tax,
                  required net,
                  required paid,
                  required notes,
                }) async {
                  previews.add({
                    'partyId': partyId,
                    'items': items,
                    'subtotal': subtotal,
                    'discount': discount,
                    'tax': tax,
                    'net': net,
                  });
                },
          onSave: ({
            required partyId,
            required supplierInvoiceNumber,
            required date,
            required subtotal,
            required discount,
            required tax,
            required net,
            required paid,
            required notes,
            required items,
            required warehouseId,
            required costCenterId,
            required paymentMethod,
            required printAfterSave,
            required sourceOrderId,
          }) async {},
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  Future<void> teardownTree(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  }

  /// يضيف سطراً واحداً عبر شريط الإضافة السريعة.
  Future<void> addLine(WidgetTester tester) async {
    await tester.enterText(find.byKey(quickAddSearchKey), 'ورق طباعة A4');
    await tester.tap(find.text('إضافة'));
    await tester.pumpAndSettle();
  }

  group('🔴 حقلُ الفرع', () {
    testWidgets('يعرض فرعَ المخزن المختار', (tester) async {
      await pump(tester);
      expect(find.text('الفرع'), findsOneWidget);
      expect(find.text('الفرع الرئيسي'), findsOneWidget);
      await teardownTree(tester);
    });

    testWidgets('🔴 ولا يُنقَر — المحرّكُ يشتقّه من المخزن', (tester) async {
      await pump(tester);
      // حقلُ «المخزن» بجواره قابلٌ للنقر، فالمرساةُ أنّ الفرقَ في الحقل لا
      // في الشاشة كلِّها.
      // ⚠️ **يُقاس `onTap` لا وجودُ `InkWell`**: لبنةُ الحقل تلفّ الكلَّ
      //    بـ`InkWell` ثمّ تُمرّر `onTap: null` لغير القابل للنقر. فغيابُ
      //    الودجت ليس هو الشرط — بل غيابُ الفعل.
      final branchInk = tester.widget<InkWell>(find.ancestor(
        of: find.text('الفرع الرئيسي'),
        matching: find.byType(InkWell),
      ));
      expect(branchInk.onTap, isNull,
          reason: '🔴 منتقي فرعٍ يَعِد بما لا يقع: يختار المستخدمُ فرعاً '
              'ويُختَم المستندُ على فرع المخزن');

      // مرساةٌ: المخزنُ بجواره **يُنقَر** فعلاً — فالفرقُ في الحقل لا في
      // الشاشة كلِّها.
      final whInk = tester.widget<InkWell>(find.ancestor(
        of: find.text('المخزن الرئيسي'),
        matching: find.byType(InkWell),
      ));
      expect(whInk.onTap, isNotNull);
      await teardownTree(tester);
    });

    testWidgets('🔴 ومخزنٌ بلا فرعٍ يُقال صراحةً', (tester) async {
      await pump(tester, warehouses: const [
        PicPosWarehouseOption(id: 2, name: 'مخزنٌ عامّ'),
      ]);
      expect(find.text('غير مخصّص لفرع'), findsOneWidget,
          reason: 'خانةٌ فارغةٌ تُقرأ «لم يُحمَّل بعد» — والفاتورةُ تسقط من '
              'كلّ تقريرٍ مرشَّحٍ بفرع');
      await teardownTree(tester);
    });

    testWidgets('وبلا مخزنٍ مختارٍ يقول إنّه يتبعه', (tester) async {
      await pump(tester, initialWarehouseId: null, warehouses: const [
        PicPosWarehouseOption(id: 2, name: 'أ', branchName: 'ب'),
        PicPosWarehouseOption(id: 3, name: 'ج', branchName: 'د'),
      ]);
      expect(find.text('يتبع المخزن'), findsOneWidget);
      await teardownTree(tester);
    });
  });

  group('🔴 معاينةُ A4', () {
    testWidgets('الزرُّ يتبع الرابطَ لا النمط', (tester) async {
      await pump(tester, withPreview: false);
      expect(find.text('معاينة A4'), findsNothing,
          reason: 'زرٌّ يُعرَض بلا ما ينفّذه أسوأُ من غيابه');
      await teardownTree(tester);
    });

    testWidgets('ويظهر حين يُمرَّر', (tester) async {
      await pump(tester);
      expect(find.text('معاينة A4'), findsOneWidget);
      await teardownTree(tester);
    });

    testWidgets('🔴 ولا معاينةَ لفاتورةٍ فارغة', (tester) async {
      await pump(tester);
      await tester.tap(find.text('معاينة A4'));
      await tester.pumpAndSettle();
      expect(previews, isEmpty,
          reason: 'ورقةٌ بلا سطرٍ لا تعني شيئاً');
      expect(find.textContaining('أضف صنفاً واحداً'), findsWidgets,
          reason: 'منعٌ صامتٌ يُقرأ «الزرُّ معطوب»');
      await teardownTree(tester);
    });

    testWidgets('🔴 وتمرّر ما يُعرَض حرفاً', (tester) async {
      await pump(tester);
      await addLine(tester);
      await tester.tap(find.text('معاينة A4'));
      await tester.pumpAndSettle();

      expect(previews, hasLength(1));
      final p = previews.single;
      // صنفٌ واحدٌ بسعر ٦٠ وكمّيّةِ ١ وبلا ضريبة.
      expect(p['subtotal'], 60);
      expect(p['net'], 60);
      expect(p['tax'], 0);
      final items = (p['items'] as List).cast<Map<String, dynamic>>();
      expect(items, hasLength(1));
      expect(items.first['lineTotal'], 60,
          reason: 'إجماليُّ السطر يُمرَّر كما يعرضه الجدول — وحسابٌ ثانٍ '
              'على الورقة يجعلها تخالف الشاشة');
      await teardownTree(tester);
    });
  });

  group('ومراسي تركيب', () {
    for (final w in const [1100.0, 1440.0, 1920.0]) {
      testWidgets('الشاشةُ بلا فيضٍ عند ${w ~/ 1}', (tester) async {
        await pump(tester, size: Size(w, 950));
        expect(tester.takeException(), isNull);
        expect(find.text('الفرع'), findsOneWidget);
        await teardownTree(tester);
      });
    }
  });
}
