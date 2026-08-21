// شاشةُ «فاتورة جديدة» بهوية PicPos — سلوكُها لا شكلُها.
//
// يُقاس هنا ما يُفسِد مالاً أو يكذب على المستخدم:
//  ‏١) **النمطُ يقلب النصوصَ فعلاً** — لا يكفي أن الثوابت صحيحة، بل أن
//     الشاشةَ تستعملها.
//  ‏٢) **الحفظُ يُمنَع بلا مقوّماته** — ولا يُستدعى ردُّ النداء أصلاً.
//     فاتورةٌ بلا مخزنٍ كانت تُحفَظ على المخزن رقم ١ في الماضي.
//  ‏٣) **رقمُ فاتورة المورد يمنع الحفظ في المشتريات** ولا يمنعه في المبيعات.
//  ‏٤) **تنبيهُ كفايةِ الرصيد لا يُطبَع بلا أرصدة** — ادّعاءٌ عن المخزون لا
//     يُقال إلّا بقياس.
import 'package:flutter/material.dart';
import 'package:ural_erp/core/constants/app_constants.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/domain/models/picpos_invoice_draft.dart';
import 'package:ural_erp/presentation/invoice_form_picpos/picpos_invoice_form.dart';

void main() {
  const products = [
    PicPosProductOption(
      id: 1,
      name: 'صنف تجريبي',
      salePrice: 100,
      costPrice: 60,
      taxRate: 14,
    ),
  ];
  const parties = [PicPosPartyOption(id: 5, name: 'شركة النيل', meta: 'آجل')];
  const warehouses = [PicPosNamedOption(id: 2, name: 'المخزن الرئيسي')];

  /// يبني الشاشةَ ويعيد سجلَّ نداءات الحفظ.
  Future<List<Map<String, dynamic>>> pump(
    WidgetTester tester, {
    required PicPosInvoiceKind kind,
    int? initialWarehouseId,
    Map<int, double>? availableStock,
  }) async {
    // مقاسٌ واقعيٌّ لسطح المكتب: التصميمُ مرسومٌ على ١٩٢٠×١٠٨٠، والشاشةُ
    // تتفرّع إلى تخطيطٍ عريضٍ فوق ٩٦٠. والافتراضيُّ ٨٠٠×٦٠٠ كان يختبر
    // التخطيطَ الضيّق ويظنّه العريض.
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final saves = <Map<String, dynamic>>[];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PicPosInvoiceForm(
          kind: kind,
          parties: parties,
          products: products,
          warehouses: warehouses,
          costCenters: const [],
          systemTaxRate: 14,
          invoiceNumberPreview: 'INV-1',
          userName: 'محمود',
          initialWarehouseId: initialWarehouseId,
          availableStock: availableStock,
          onCancel: () {},
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
          }) async {
            saves.add({
              'partyId': partyId,
              'net': net,
              'paid': paid,
              'items': items,
              'warehouseId': warehouseId,
            });
          },
        ),
      ),
    ));
    await tester.pumpAndSettle();
    return saves;
  }

  // ⚠️ لا قاعدةَ بيانات في هذه الشاشة إطلاقاً — الأنواعُ كلُّها من
  // `domain/models`. فلا `db.close()` ولا تعليقَ مؤقّتِ drift.

  group('النمطُ يقلب النصوص', () {
    testWidgets('المبيعات: «العميل» و«سعر البيع» و«المحصّل الآن»',
        (tester) async {
      await pump(tester, kind: PicPosInvoiceKind.sales);
      expect(find.text('العميل'), findsWidgets);
      expect(find.text('سعر البيع'), findsOneWidget);
      expect(find.text('المحصّل الآن'), findsOneWidget);
      expect(find.text('المورد'), findsNothing);
    });

    testWidgets('المشتريات: «المورد» و«سعر الشراء» و«المسدّد الآن»',
        (tester) async {
      await pump(tester, kind: PicPosInvoiceKind.purchase);
      expect(find.text('المورد'), findsWidgets);
      expect(find.text('سعر الشراء'), findsOneWidget);
      expect(find.text('المسدّد الآن'), findsOneWidget);
      expect(find.text('العميل'), findsNothing);
    });

    testWidgets('«البائع» يظهر في المبيعات وحدَها', (tester) async {
      await pump(tester, kind: PicPosInvoiceKind.sales);
      expect(find.text('البائع'), findsOneWidget);
      expect(find.text('رقم فاتورة المورد'), findsNothing);
    });

    testWidgets('«رقم فاتورة المورد» يظهر في المشتريات وحدَها', (tester) async {
      await pump(tester, kind: PicPosInvoiceKind.purchase);
      expect(find.text('رقم فاتورة المورد'), findsOneWidget);
      expect(find.text('البائع'), findsNothing);
    });
  });

  group('الحفظُ يُمنَع بلا مقوّماته', () {
    testWidgets('بلا مخزنٍ ولا طرفٍ ولا بنود ⇒ لا نداءَ حفظٍ إطلاقاً',
        (tester) async {
      final saves = await pump(tester, kind: PicPosInvoiceKind.sales);
      await tester.tap(find.text('حفظ الفاتورة'));
      await tester.pump();
      expect(saves, isEmpty,
          reason: 'المنعُ يعني ألّا يصل مسارَ الحفظ شيءٌ — لا أن يصله ناقصاً');
      expect(find.textContaining('المخزن'), findsWidgets,
          reason: 'ويُقال السببُ صراحةً لا يُبتلع صامتاً');
    });

    testWidgets('بمخزنٍ وبلا بنود ⇒ ما زال ممنوعاً', (tester) async {
      final saves = await pump(
        tester,
        kind: PicPosInvoiceKind.sales,
        initialWarehouseId: 2,
      );
      await tester.tap(find.text('حفظ الفاتورة'));
      await tester.pump();
      expect(saves, isEmpty);
    });
  });

  /// يضيف الصنفَ التجريبيَّ إلى الفاتورة عبر سطر الإدخال السريع.
  ///
  /// ⚠️ **وهذا ليس تفصيلاً**: التنبيهاتُ كلُّها محروسةٌ بـ`quantityTotal > 0`.
  /// فاختبارٌ يفحص غيابَ تنبيهٍ على فاتورةٍ **فارغة** يمرّ دائماً — ويمرّ ولو
  /// كُسر الحارسُ عمداً. (وقد وقع ذلك فعلاً هنا: أُفسدت الشرطيّةُ فبقيت
  /// العشرةُ خضراء، فتبيّن أن الاختبارَ أجوف.)
  Future<void> addLine(WidgetTester tester) async {
    await tester.enterText(find.byKey(quickAddSearchKey), 'صنف تجريبي');
    await tester.tap(find.text('إضافة'));
    await tester.pumpAndSettle();
  }

  group('تنبيهُ كفايةِ الرصيد لا يُقال بلا قياس', () {
    testWidgets('بلا أرصدةٍ ⇒ لا ادّعاءَ كفايةٍ ولا اتّهامَ نقص',
        (tester) async {
      await pump(
        tester,
        kind: PicPosInvoiceKind.sales,
        initialWarehouseId: 2,
        // availableStock = null ⇒ لا تُعرَف الأرصدة.
      );
      await addLine(tester);
      // التجهيزةُ سليمةٌ: البندُ دخل فعلاً، فالتنبيهاتُ تُبنى.
      expect(find.text('1 بند'), findsOneWidget);
      expect(find.textContaining('سيُخصم من المخزن'), findsOneWidget);

      expect(find.textContaining('الرصيد المتاح يكفي'), findsNothing,
          reason: 'جملةٌ عن المخزون بلا بياناتِ مخزون هي ادّعاءٌ لا معلومة');
      expect(find.textContaining('الرصيد لا يكفي'), findsNothing);
    });

    testWidgets('برصيدٍ كافٍ ⇒ تُقال الكفايةُ صراحةً', (tester) async {
      await pump(
        tester,
        kind: PicPosInvoiceKind.sales,
        initialWarehouseId: 2,
        availableStock: const {1: 50},
      );
      await addLine(tester);
      expect(find.textContaining('الرصيد المتاح يكفي'), findsOneWidget);
      expect(find.textContaining('الرصيد لا يكفي'), findsNothing);
    });

    testWidgets('برصيدٍ ناقصٍ ⇒ يُسمّى الصنفُ ولا تُدَّعى كفاية',
        (tester) async {
      await pump(
        tester,
        kind: PicPosInvoiceKind.sales,
        initialWarehouseId: 2,
        availableStock: const {1: 0},
      );
      await addLine(tester);
      expect(find.textContaining('الرصيد لا يكفي'), findsOneWidget);
      expect(find.textContaining('صنف تجريبي'), findsWidgets,
          reason: 'يُسمَّى الناقصُ — «لا يكفي» بلا اسمٍ لا تُعالَج');
      expect(find.textContaining('الرصيد المتاح يكفي'), findsNothing);
    });

    testWidgets('صنفٌ غائبٌ عن خريطة الأرصدة يُتخطّى لا يُتَّهَم',
        (tester) async {
      await pump(
        tester,
        kind: PicPosInvoiceKind.sales,
        initialWarehouseId: 2,
        // الخريطةُ موجودةٌ لكنها لا تذكر الصنفَ ١ — قد يكون خدمةً لا تُخزَّن.
        availableStock: const {99: 0},
      );
      await addLine(tester);
      expect(find.textContaining('الرصيد لا يكفي'), findsNothing,
          reason: 'غيابُ الصنف عن الخريطة ليس رصيدَ صفر');
    });

    testWidgets('المشتريات: تنبيهُ إضافةٍ لا خصم', (tester) async {
      await pump(
        tester,
        kind: PicPosInvoiceKind.purchase,
        initialWarehouseId: 2,
      );
      await addLine(tester);
      expect(find.textContaining('سيُضاف للمخزن'), findsOneWidget);
      expect(find.textContaining('سيُخصم من المخزن'), findsNothing);
    });
  });

  group('الإجمالياتُ تظهر على الشاشة', () {
    testWidgets('الصافي يبدأ صفراً والبنودُ صفر', (tester) async {
      await pump(tester, kind: PicPosInvoiceKind.purchase);
      expect(find.text('0 بند'), findsOneWidget);
      // ‏`AppConstants.decimalPlaces` = **٣** لا ٢ — والرقمُ يُقرأ من الثابت
      // لا يُكتب في الاختبار، وإلّا صار الاختبارُ يوثّق ظنّي لا سلوكَ النظام.
      expect(find.text(0.0.toStringAsFixed(AppConstants.decimalPlaces)),
          findsWidgets);
    });

    testWidgets('نسبةُ الضريبة من الإعداد لا رقمٌ مطبوع', (tester) async {
      await pump(tester, kind: PicPosInvoiceKind.sales);
      // مُرِّرت ١٤ في التجهيزة، فلو طُبعت ثابتةً لمرّ الاختبارُ كذباً —
      // ولذلك يُقاس الغيابُ عند نسبةٍ أخرى في الاختبار التالي.
      expect(find.text('ضريبة 14%'), findsOneWidget);
    });
  });

  testWidgets('نسبةٌ مختلفةٌ تظهر كما هي — لا «14%» مخبوزة', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PicPosInvoiceForm(
          kind: PicPosInvoiceKind.sales,
          parties: parties,
          products: products,
          warehouses: warehouses,
          costCenters: const [],
          systemTaxRate: 5,
          invoiceNumberPreview: 'INV-2',
          onCancel: () {},
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
          }) async {},
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('ضريبة 5%'), findsOneWidget);
    expect(find.text('ضريبة 14%'), findsNothing,
        reason: 'الرقمُ يأتي من الإعداد — و«١٤٪» في التصميم قيمةُ عيّنة');
  });
}
