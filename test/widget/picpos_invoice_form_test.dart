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
import 'package:phosphor_flutter/phosphor_flutter.dart';
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
  const parties = [
    PicPosPartyOption(
        id: 5, name: 'شركة النيل', meta: 'آجل', paymentTermsDays: 30),
    // طرفٌ **بلا مهلة** — الحالةُ التي يجب ألّا تُعرَض فيها تواريخُ أصلاً.
    PicPosPartyOption(id: 6, name: 'مؤسسة الفور', meta: 'نقدي'),
  ];
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
              // خصمُ المستند وفرعيُّه وضريبتُه — الثلاثةُ تصل المحرّكَ معاً،
              // وقياسُ الصافي وحدَه لا يفرّق بين خصمٍ وصل وسعرٍ نزل.
              'subtotal': subtotal,
              'discount': discount,
              'tax': tax,
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

  /// يختار الطرفَ عبر حوار الاختيار — الحفظُ ممنوعٌ بدونه.
  Future<void> pickParty(WidgetTester tester) async {
    await tester.tap(find.text('اختر العميل'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('شركة النيل'));
    await tester.pumpAndSettle();
  }

  /// حبّاتُ طريقةِ الدفع تُنقَر **بأيقونتها** لا بنصّها: نصُّ «آجل» يظهر
  /// أيضاً وصفاً للطرف (`meta`)، فالبحثُ بالنصّ يجد اثنين ويفشل غامضاً.
  Future<void> tapMethod(WidgetTester tester, IconData icon) async {
    await tester.tap(find.byIcon(icon));
    await tester.pumpAndSettle();
  }

  // ── بلاغُ المالك (2026-08-23) ─────────────────────────────────────────────
  // «عميلٌ تم إعدادُ فاتورة مبيعات له واختيارُ وسيلة الدفع نقدي، بتظهر على
  //  شاشة الفواتير أنها غير مدفوعة، وبتظهر في الحسابات وكشف الحساب أنها
  //  مديونيةٌ على العميل».
  //
  // السببُ المقيس: `_paymentMethod` يبدأ `'cash'` و`_paidController` يبدأ
  // `'0'`، والتهيئةُ التي تملأ المبلغَ تعيش **داخل `onTap` الحبّة وحدَها**.
  // فمن قبِل الافتراضَ ولم ينقر «نقدي» يحفظ بـ`paid = 0` — فتُقيَّد الفاتورةُ
  // ديناً على العميل. والحبّةُ معروضةٌ مختارةً طوالَ الوقت، فالشاشةُ تقول
  // «نقدي» والمالُ يقول «آجل».
  group('«نقدي» المعروضُ يساوي «نقدي» المحفوظ', () {
    testWidgets('نقديٌّ افتراضيٌّ بلا نقرةٍ ⇒ المحصَّلُ يساوي الصافي',
        (tester) async {
      final saves = await pump(
        tester,
        kind: PicPosInvoiceKind.sales,
        initialWarehouseId: 2,
      );
      await pickParty(tester);
      await addLine(tester);
      await tester.tap(find.text('حفظ الفاتورة'));
      await tester.pump();

      expect(saves, hasLength(1), reason: 'التجهيزةُ سليمةٌ: الحفظُ وصل فعلاً');
      expect(saves.single['paid'], saves.single['net'],
          reason: 'الحبّةُ تُعرَض مختارةً، فالمالُ يجب أن يتبعها بلا نقرة');
      expect(saves.single['paid'], greaterThan(0),
          reason: 'صفرٌ هنا يعني ديناً على عميلٍ دفع نقداً');
    });

    testWidgets('بندٌ يُضاف بعد اختيار «نقدي» ⇒ المحصَّلُ يلحق الصافي',
        (tester) async {
      final saves = await pump(
        tester,
        kind: PicPosInvoiceKind.sales,
        initialWarehouseId: 2,
      );
      await pickParty(tester);
      await addLine(tester);
      await tapMethod(tester, PhosphorIconsBold.money);
      // بندٌ ثانٍ بعد النقرة: القيمةُ المجمّدةُ عند لحظةِ النقر كانت تترك
      // فرقَ البندِ الثاني ديناً.
      await addLine(tester);
      await tester.tap(find.text('حفظ الفاتورة'));
      await tester.pump();

      expect(saves, hasLength(1));
      expect(saves.single['paid'], saves.single['net'],
          reason: 'التهيئةُ تتبع الصافيَ ما دام المستخدمُ لم يكتب رقماً بيده');
    });

    testWidgets('«آجل» يُصفِّر المحصَّل', (tester) async {
      final saves = await pump(
        tester,
        kind: PicPosInvoiceKind.sales,
        initialWarehouseId: 2,
      );
      await pickParty(tester);
      await addLine(tester);
      await tapMethod(tester, PhosphorIconsBold.calendarDot);
      await tester.tap(find.text('حفظ الفاتورة'));
      await tester.pump();

      expect(saves, hasLength(1));
      expect(saves.single['paid'], 0,
          reason: 'الآجلُ دينٌ مقصود — ولا يجوز أن تفرض التهيئةُ سداداً');
    });
  });

  // ── بلاغُ المالك (2026-08-23) ─────────────────────────────────────────────
  // «الكمّيّةُ لا تُكتب في فاتورة جديدة» — كانت `Text` بين زرَّي `+`/`−`،
  // فإدخالُ ٥٠ يعني ٤٩ نقرة.
  //
  // والحدُّ المحفوظُ عمداً: صفرٌ سطرٌ بلا أثرٍ ماليّ، وسالبٌ يقلب اتّجاهَ
  // حركةِ المخزون — فكلاهما مرفوضٌ ولو كُتب بالحرف.
  group('الكمّيّةُ تُكتب لا تُنقَر', () {
    /// يكتب في حقلِ كمّيّةِ الصنفِ ١ ثمّ يُنهي التحرير.
    Future<void> typeQty(WidgetTester tester, String value) async {
      await tester.enterText(find.byKey(const ValueKey('qty_1')), value);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
    }

    Future<List<Map<String, dynamic>>> pumpWithLine(WidgetTester tester) async {
      final saves = await pump(
        tester,
        kind: PicPosInvoiceKind.sales,
        initialWarehouseId: 2,
      );
      await pickParty(tester);
      await addLine(tester);
      return saves;
    }

    Future<void> save(WidgetTester tester) async {
      await tester.tap(find.text('حفظ الفاتورة'));
      await tester.pump();
    }

    /// كمّيّةُ البندِ الوحيدِ في نداءِ الحفظ — مُنمَّطةً، فخريطةُ الحفظ
    /// `dynamic` و`avoid_dynamic_calls` يعدّها خرقاً.
    double savedQty(List<Map<String, dynamic>> saves) {
      final items = saves.single['items'] as List<Map<String, dynamic>>;
      return items.single['quantity'] as double;
    }

    testWidgets('٥٠ تُكتب مرّةً واحدةً لا ٤٩ نقرة', (tester) async {
      final saves = await pumpWithLine(tester);
      await typeQty(tester, '50');
      await save(tester);
      expect(savedQty(saves),50);
    });

    testWidgets('الكسرُ يُقبل — الوزنُ ‎1.25 قائم', (tester) async {
      final saves = await pumpWithLine(tester);
      await typeQty(tester, '1.25');
      await save(tester);
      expect(savedQty(saves),1.25);
    });

    testWidgets('الأرقامُ العربيّةُ تُقبل', (tester) async {
      final saves = await pumpWithLine(tester);
      await typeQty(tester, '٧');
      await save(tester);
      expect(savedQty(saves),7,
          reason: 'الحقلُ يقرأ بـtryParseLocale لا بـdouble.parse');
    });

    testWidgets('الصفرُ يُرفَض ويعود إلى ما كان', (tester) async {
      final saves = await pumpWithLine(tester);
      await typeQty(tester, '3');
      await typeQty(tester, '0');
      await save(tester);
      expect(savedQty(saves),3,
          reason: 'صفرٌ سطرٌ بلا أثرٍ ماليّ — الحدُّ محفوظٌ ولو كُتب بالحرف');
    });

    testWidgets('السالبُ يُرفَض — لا يقلب اتّجاهَ حركةِ المخزون',
        (tester) async {
      final saves = await pumpWithLine(tester);
      await typeQty(tester, '4');
      await typeQty(tester, '-2');
      await save(tester);
      expect(savedQty(saves),4);
    });

    testWidgets('نصٌّ لا يُقرأ رقماً يعود إلى ما كان', (tester) async {
      final saves = await pumpWithLine(tester);
      await typeQty(tester, '5');
      await typeQty(tester, 'أبجد');
      await save(tester);
      expect(savedQty(saves),5);
    });

    testWidgets('تغييرُ الكمّيّةِ كتابةً يجرّ المحصَّلَ معه', (tester) async {
      // تقاطعُ الإصلاحين: الكمّيّةُ تغيّر الصافيَ، والتهيئةُ تتبعه.
      final saves = await pumpWithLine(tester);
      await typeQty(tester, '3');
      await save(tester);
      expect(saves.single['paid'], saves.single['net'],
          reason: 'وإلّا عاد الدَّينُ من بابِ الكمّيّة');
    });
  });

  // ═══ «تاريخ الاستحقاق» مرآةٌ مشتقّة — قرارُ المالك 2026-09-18 ═══════════
  //
  // التصميمُ يرسمه حقلَ تاريخٍ يُكتَب بنجمةِ إلزام، والمحرّكُ يشتقّه من مهلة
  // الطرف ولا يقرأ ما يكتبه المستخدم (ح‑١). فالمقيسُ هنا أنّ المعروضَ يتبع
  // مصدرَه — الطرفَ وتاريخَ الفاتورة — لا أن يُرسَم حقلٌ جميل.
  group('مرآةُ تاريخ الاستحقاق', () {
    testWidgets('بلا طرفٍ ⇒ «بلا مهلة متفقة» لا تاريخَ اليوم', (tester) async {
      // 🔴 عرضُ تاريخ الفاتورة هنا يوهم بأجلٍ متّفقٍ مدّتُه صفر، والعمودُ في
      // القاعدة يبقى فارغاً — فالمعروضُ ليس المحفوظ.
      await pump(tester, kind: PicPosInvoiceKind.purchase);
      expect(find.text('تاريخ الاستحقاق'), findsOneWidget);
      expect(find.text('بلا مهلة متفقة'), findsOneWidget);
    });

    testWidgets('وطرفٌ بمهلة ٣٠ يوماً ⇒ تاريخٌ محسوبٌ ومدّةٌ مذكورة',
        (tester) async {
      await pump(tester, kind: PicPosInvoiceKind.purchase);
      await tester.tap(find.text('اختر المورد'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('شركة النيل'));
      await tester.pumpAndSettle();

      final due = DateTime.now().add(const Duration(days: 30));
      expect(find.text(due.toString().substring(0, 10)), findsOneWidget,
          reason: 'المرآةُ لم تتبع مهلةَ الطرف');
      expect(find.text('سداد 30 يوماً'), findsOneWidget);
      expect(find.text('بلا مهلة متفقة'), findsNothing);
    });

    testWidgets('وطرفٌ بلا مهلةٍ يعيدها إلى «بلا مهلة متفقة»', (tester) async {
      // ⚠️ الرجوعُ مقصود: من اختار طرفاً بمهلةٍ ثمّ بدّله يجب ألّا يبقى
      // ناظراً إلى استحقاقِ الأوّل.
      await pump(tester, kind: PicPosInvoiceKind.purchase);
      await tester.tap(find.text('اختر المورد'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('شركة النيل'));
      await tester.pumpAndSettle();
      expect(find.text('بلا مهلة متفقة'), findsNothing);

      await tester.tap(find.text('شركة النيل').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('مؤسسة الفور'));
      await tester.pumpAndSettle();
      expect(find.text('بلا مهلة متفقة'), findsOneWidget);
    });

    testWidgets('والمبيعاتُ تقول «سماح» لا «سداد»', (tester) async {
      await pump(tester, kind: PicPosInvoiceKind.sales);
      await tester.tap(find.text('اختر العميل'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('شركة النيل'));
      await tester.pumpAndSettle();
      expect(find.text('سماح 30 يوماً'), findsOneWidget);
    });

    testWidgets('ولا منتقيَ تاريخٍ ولا حقلَ كتابةٍ في كتلة الاستحقاق',
        (tester) async {
      // المرآةُ مقفولةٌ صراحةً: نقرةٌ عليها لا تفتح شيئاً.
      await pump(tester, kind: PicPosInvoiceKind.purchase);
      await tester.tap(find.text('تاريخ الاستحقاق'), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(find.byType(DatePickerDialog), findsNothing,
          reason: 'منتقٍ يُفتَح لقيمةٍ لا تُقرأ عند الحفظ');
    });
  });

  // ═══ الخصمُ لكلّ صنف — قرارُ المالك 2026-09-18 ═══════════════════════════
  //
  // 🔴 **المقيسُ أنّ ما يُكتَب في العمود يصل نداءَ الحفظ**، لا أنّ العمودَ
  // مرسوم. حقلٌ يُعرَض ولا يُقرأ هو عينُ العطب الذي كان مكتوباً في رأس
  // `PicPosInvoiceLine` قبل هذا الوصل.
  group('عمودُ الخصم', () {
    /// يملأ ما يمنع حفظَ فاتورةِ مشترياتٍ عدا البنود.
    Future<List<Map<String, dynamic>>> pumpPurchase(WidgetTester tester) async {
      final saves = await pump(
        tester,
        kind: PicPosInvoiceKind.purchase,
        initialWarehouseId: 2,
      );
      await tester.tap(find.text('اختر المورد'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('شركة النيل'));
      await tester.pumpAndSettle();
      // رقمُ فاتورةِ المورد مطلوبٌ للحفظ — وحقلُه بلا مفتاح، فيُلتقَط بتلميحه.
      await tester.enterText(
        find.byWidgetPredicate(
            (w) => w is TextField && w.decoration?.hintText == 'مطلوب'),
        'SUP-771',
      );
      await tester.pumpAndSettle();
      await addLine(tester);
      return saves;
    }

    Future<void> typeDiscount(WidgetTester tester, String v) async {
      await tester.enterText(find.byKey(const ValueKey('discount_1')), v);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
    }

    testWidgets('يظهر في المشتريات ولا يظهر في المبيعات', (tester) async {
      await pump(tester, kind: PicPosInvoiceKind.purchase);
      expect(find.text('الخصم'), findsOneWidget,
          reason: 'قرارُ المالك: الخصمُ لكلّ صنف — يُثبَّت لا يُفتَح بمفتاح');

      await pump(tester, kind: PicPosInvoiceKind.sales);
      expect(find.text('الخصم'), findsNothing,
          reason: 'مسارُ حفظ المبيعات لا يقرأ خصمَ سطرٍ — فعمودٌ هنا يبتلع');
    });

    testWidgets('وحقلُه غائبٌ عن صفِّ المبيعات لا معطَّلٌ فيه', (tester) async {
      await pump(tester, kind: PicPosInvoiceKind.sales, initialWarehouseId: 2);
      await addLine(tester);
      expect(find.byKey(const ValueKey('discount_1')), findsNothing);
    });

    testWidgets('ما يُكتَب فيه يصل بندَ الحفظ', (tester) async {
      final saves = await pumpPurchase(tester);
      await typeDiscount(tester, '25');
      await tester.tap(find.text('حفظ الفاتورة'));
      await tester.pump();

      expect(saves, hasLength(1), reason: 'الحفظُ مُنع لسببٍ غيرِ الخصم');
      final items = saves.single['items'] as List<Map<String, dynamic>>;
      expect(items.single['discount'], 25,
          reason: 'العمودُ يُعرَض ويُكتَب فيه ولا يصل الحفظَ — حقلٌ يبتلع');
    });

    testWidgets('ويبلغ خصمَ المستند الذي يقرؤه المحرّك', (tester) async {
      // 🔴 `resolvePurchaseLineNets` تقرأ خصمَ المستند على أنّه **المجموع**.
      // فلو مُرّر حقلُ الترويسة وحدَه (صفرٌ هنا) لكتب المحرّكُ ترويسةً بلا
      // خصمٍ وسطوراً مخصومة.
      final saves = await pumpPurchase(tester);
      await typeDiscount(tester, '25');
      await tester.tap(find.text('حفظ الفاتورة'));
      await tester.pump();
      expect(saves.single['discount'], 25);
    });

    testWidgets('والصافي ينزل بالخصمِ **وبضريبتِه** معاً', (tester) async {
      // ⚠️ **والنزولُ أكبرُ من الخصم بالضبط بضريبته.** السطرُ ٦٠ بضريبة ١٤٪
      // ⇒ صافٍ ٦٨٫٤. وبخصمِ ٢٥ يصير الوعاءُ ٣٥ وضريبتُه ٤٫٩ ⇒ ٣٩٫٩.
      // فالفرقُ ٢٨٫٥ = ٢٥ + ٣٫٥.
      //
      // 🔴 ولو حُسبت الضريبةُ على الإجماليّ لبقيت ٨٫٤ وصار الصافي ٤٣٫٤ —
      // أي إقرارُ ضريبةِ مدخلاتٍ على مبلغٍ لم يُدفَع للمورّد.
      final saves = await pumpPurchase(tester);
      await tester.tap(find.text('حفظ الفاتورة'));
      await tester.pump();
      expect(saves.single['net'], closeTo(68.4, 0.001));
      expect(saves.single['tax'], closeTo(8.4, 0.001));
      saves.clear();

      await typeDiscount(tester, '25');
      await tester.tap(find.text('حفظ الفاتورة'));
      await tester.pump();
      expect(saves.single['net'], closeTo(39.9, 0.001),
          reason: 'الخصمُ لا يبلغ الصافيَ — يرى المستخدمُ رقماً ويدفع آخر');
      expect(saves.single['tax'], closeTo(4.9, 0.001),
          reason: 'وعاءُ الضريبة لم ينزل بالخصم');
      expect(saves.single['subtotal'], closeTo(60, 0.001),
          reason: '«المجموع» قبل الخصم — والتصميمُ يعرضهما رقمَين منفصلَين');
    });

    testWidgets('وخصمٌ أكبرُ من قيمة السطر يُحصَر عند قيمته', (tester) async {
      // بلا الحصر تطرح الترويسةُ مبلغاً لم يوجد في السطر، فينفصل المستندُ
      // عن سطوره.
      final saves = await pumpPurchase(tester);
      await typeDiscount(tester, '9999');
      await tester.tap(find.text('حفظ الفاتورة'));
      await tester.pump();

      final items = saves.single['items'] as List<Map<String, dynamic>>;
      // سطرٌ واحدٌ بكمّيّة ١ وتكلفةِ ٦٠ (costPrice في التجهيزة).
      expect(items.single['discount'], 60);
      expect(saves.single['discount'], 60);
      expect(saves.single['net'], 0);
    });
  });
}
