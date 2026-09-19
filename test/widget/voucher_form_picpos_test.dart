// نموذجُ سندِ القبض والصرف — تصميمُ المالك `(11)` و`(12)` و`(13)`.
//
// ═══ ما يقيسه هذا الملفّ ═══
//
// ‏١) 🔴 **مبلغُ كلِّ شيكٍ يُكتَب ولا يُقسَّم.** الحواران القائمان يجمعان
//    أرقامَ الشيكات وحدَها ثمّ `amount / count` — فثلاثةُ شيكاتٍ بـ١٠٠٠
//    و٢٠٠٠ و٣٠٠٠ تُكتَب ٢٠٠٠ و٢٠٠٠ و٢٠٠٠. والمجموعُ صحيحٌ فلا شيءَ يبدو
//    معطوباً حتى يحين تحصيلُ أوّلِ شيك.
//
// ‏٢) 🔴 **ورقمُ السند لا يُخمَّن** — Spec 066، كما في فاتورة المبيعات وسند
//    القيد.
//
// ‏٣) 🔴 **والتوزيعُ لا يتجاوز الصافي** — تخصيصٌ أكبرُ يُقفل فواتيرَ بمالٍ
//    لم يُقبَض.
//
// ‏٤) ⚠️ **ولا زرَّ «حفظ مسودة»** — لا حالةَ مسوّدةٍ في المحرّك، وزرٌّ يحفظ
//    مُرحَّلاً وهو يقول «مسودة» أسوأُ من غيابه.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ural_erp/presentation/treasury_picpos/screens/voucher_form_picpos.dart';

const _parties = <VoucherPartyOption>[
  (id: 5, name: 'شركة النور', meta: null, isDeliveryCompany: false),
  (id: 6, name: 'توصيل سريع', meta: null, isDeliveryCompany: true),
];

const _safes = <VoucherSafeOption>[
  (id: 1, name: 'الصندوق الرئيسي', type: 'cash'),
  (id: 2, name: 'البنك الرئيسي', type: 'bank'),
];

final _invoices = <VoucherInvoiceOption>[
  (
    invoiceType: 'sales',
    id: 11,
    number: 'INV-1042',
    date: DateTime(2026, 9, 1),
    total: 1000,
    paid: 300,
  ),
];

Finder _fieldByLabel(String label) => find.byWidgetPredicate(
    (w) => w is TextField && w.decoration?.labelText == label);

void main() {
  late List<VoucherSubmission> submitted;

  setUp(() => submitted = []);

  Future<void> pump(
    WidgetTester tester, {
    PicPosVoucherKind kind = PicPosVoucherKind.receipt,
    List<VoucherInvoiceOption> invoices = const [],
    List<VoucherCostCenterOption> costCenters = const [],
    double width = 1440,
  }) async {
    tester.view.physicalSize = Size(width, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      home: PicPosVoucherForm(
        kind: kind,
        parties: _parties,
        safes: _safes,
        costCenters: costCenters,
        openInvoices: invoices,
        onSubmit: (v) async => submitted.add(v),
      ),
    ));
    await tester.pumpAndSettle();
  }

  Future<void> teardownTree(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  }

  Future<void> pickParty(WidgetTester tester, String name) async {
    await tester.tap(find.byKey(const Key('voucher_party')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(name).last);
    await tester.pumpAndSettle();
  }

  Future<void> switchToCheques(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('voucher_method_check')));
    await tester.pumpAndSettle();
  }

  /// يملأ الشيكَ رقمَ [i] (صفريَّ الأساس).
  Future<void> fillCheque(
    WidgetTester tester,
    int i, {
    required String number,
    required double amount,
  }) async {
    await tester.enterText(_fieldByLabel('رقم الشيك').at(i), number);
    await tester.enterText(
        _fieldByLabel('المبلغ').at(i), amount.toStringAsFixed(0));
    await tester.pumpAndSettle();
    // الاستحقاقُ شرطٌ — يُختار من المنتقي.
    //
    // ⚠️ `CompactDatePicker` غلافٌ على `showDatePicker` القياسيّ، وزرُّ
    //    التأكيد **«OK»** ما دامت مندوباتُ التعريب غيرَ مركَّبةٍ في الاختبار.
    await tester.tap(find.widgetWithText(InputDecorator, 'اختر التاريخ').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK').last);
    await tester.pumpAndSettle();
  }

  group('🔴 رقمُ السند', () {
    testWidgets('لا يُخمَّن قبل الحفظ', (tester) async {
      await pump(tester);
      expect(find.textContaining(kVoucherNumberPlaceholder), findsOneWidget,
          reason: '🔴 رقمٌ مخمَّنٌ يُبلَّغ للعميل ثمّ يُحفَظ غيرُه');
      expect(find.textContaining('RV-'), findsNothing);
      await teardownTree(tester);
    });
  });

  group('⚠️ التذييل', () {
    testWidgets('بلا زرِّ «حفظ مسودة»', (tester) async {
      await pump(tester);
      expect(find.text('حفظ مسودة'), findsNothing,
          reason: '⚠️ لا حالةَ مسوّدةٍ في المحرّك — وزرٌّ يحفظ مُرحَّلاً وهو '
              'يقول «مسودة» يجعل المستخدمَ يظنّ أنّه أجّل حركةَ مالٍ وقد وقعت');
      expect(find.text('مراجعة واعتماد'), findsOneWidget);
      await teardownTree(tester);
    });

    testWidgets('🔴 وسببُ المنع يُقال ولا يُبتلَع', (tester) async {
      await pump(tester);
      expect(find.textContaining('اختر العميل'), findsOneWidget);
      await teardownTree(tester);
    });

    testWidgets('⚠️ ومركزُ التكلفة إلزاميٌّ حين يكون معرَّفاً',
        (tester) async {
      await pump(tester, costCenters: const [(id: 1, name: 'الإدارة')]);
      await pickParty(tester, 'شركة النور');
      expect(find.textContaining('اختر مركز التكلفة'), findsOneWidget,
          reason: 'بدونه يسقط القيدُ على «عام» ويُقرأ في تقارير المراكز '
              'على غير موضعه');
      await teardownTree(tester);
    });
  });

  group('🔴 الشيكات', () {
    testWidgets('لكلِّ شيكٍ مبلغُه — والإجماليُّ مجموعُها', (tester) async {
      await pump(tester);
      await pickParty(tester, 'شركة النور');
      await switchToCheques(tester);

      await tester.tap(find.byKey(const Key('voucher_add_cheque')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('voucher_add_cheque')));
      await tester.pumpAndSettle();

      await fillCheque(tester, 0, number: 'CH-1', amount: 1000);
      await fillCheque(tester, 1, number: 'CH-2', amount: 2000);
      await fillCheque(tester, 2, number: 'CH-3', amount: 3000);

      await tester.tap(find.text('مراجعة واعتماد'));
      await tester.pumpAndSettle();

      expect(submitted, hasLength(1));
      final v = submitted.single;
      expect(v.cheques.map((c) => c.amount).toList(), [1000, 2000, 3000],
          reason: '🔴 `amount / count` تكتب ٢٠٠٠ لكلٍّ منها — والمجموعُ '
              'صحيحٌ فلا شيءَ يبدو معطوباً حتى يحين تحصيلُ أوّلِ شيكٍ '
              'فيُقيَّد بمبلغٍ لم يُكتَب على الورقة');
      expect(v.grossAmount, 6000,
          reason: 'الإجماليُّ مشتقٌّ من الشيكات لا العكس');
      await teardownTree(tester);
    });

    testWidgets('🔴 وشيكٌ بلا مبلغٍ يُرفَض', (tester) async {
      await pump(tester);
      await pickParty(tester, 'شركة النور');
      await switchToCheques(tester);
      await tester.enterText(_fieldByLabel('رقم الشيك').first, 'CH-9');
      await tester.pumpAndSettle();
      expect(find.textContaining('اكتب مبلغه'), findsOneWidget,
          reason: '🔴 مبلغٌ فارغٌ كان يعني قسمةً بالتساوي في المسار القديم');
      await teardownTree(tester);
    });

    testWidgets('⚠️ وحالةُ الشيك تُعرَض ولا تُحرَّر', (tester) async {
      await pump(tester);
      await switchToCheques(tester);
      expect(find.text('برسم التحصيل'), findsOneWidget);
      await teardownTree(tester);
    });

    testWidgets('⚠️ وسندُ الصرف يقول «صادر»', (tester) async {
      await pump(tester, kind: PicPosVoucherKind.payment);
      await switchToCheques(tester);
      expect(find.text('صادر'), findsOneWidget);
      expect(find.text('المستفيد'), findsOneWidget,
          reason: 'اسمُ الطرف يتبع نوعَ السند');
      await teardownTree(tester);
    });

    testWidgets('🔴 و«أودِعه فوراً» في القبض وحدَه', (tester) async {
      await pump(tester);
      await switchToCheques(tester);
      expect(find.byKey(const Key('voucher_deposit_now')), findsOneWidget);
      await teardownTree(tester);

      await pump(tester, kind: PicPosVoucherKind.payment);
      await switchToCheques(tester);
      expect(find.byKey(const Key('voucher_deposit_now')), findsNothing,
          reason: 'شيكٌ صادرٌ لا يُودَع للتحصيل');
      await teardownTree(tester);
    });
  });

  group('🔴 توزيعُ المبلغ على الفواتير', () {
    testWidgets('«الباقي» يملأ ما تبقّى ويُمرَّر', (tester) async {
      await pump(tester, invoices: _invoices);
      await pickParty(tester, 'شركة النور');
      await tester.enterText(find.byKey(const Key('voucher_amount')), '700');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('voucher_allocation_toggle')));
      await tester.pumpAndSettle();

      expect(find.text('INV-1042'), findsOneWidget);
      await tester.tap(find.text('الباقي'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('مراجعة واعتماد'));
      await tester.pumpAndSettle();
      expect(submitted.single.allocations, hasLength(1));
      expect(submitted.single.allocations.single.amount, 700);
      expect(submitted.single.allocations.single.invoiceType, 'sales');
      await teardownTree(tester);
    });

    testWidgets('🔴 وتوزيعٌ يتجاوز الصافي يُمنَع', (tester) async {
      await pump(tester, invoices: _invoices);
      await pickParty(tester, 'شركة النور');
      await tester.enterText(find.byKey(const Key('voucher_amount')), '100');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('voucher_allocation_toggle')));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.byKey(const Key('voucher_alloc_sales#11')), '500');
      await tester.pumpAndSettle();

      expect(find.textContaining('يتجاوز الصافي'), findsOneWidget,
          reason: '🔴 تخصيصٌ أكبرُ من المقبوض يُقفل فواتيرَ بمالٍ لم يُقبَض');
      final btn = tester.widget<FilledButton>(
          find.widgetWithText(FilledButton, 'مراجعة واعتماد'));
      expect(btn.onPressed, isNull);
      await teardownTree(tester);
    });

    testWidgets('⚠️ والتوزيعُ اختياريٌّ لا إلزاميّ', (tester) async {
      await pump(tester, invoices: _invoices);
      await pickParty(tester, 'شركة النور');
      await tester.enterText(find.byKey(const Key('voucher_amount')), '700');
      await tester.pumpAndSettle();
      await tester.tap(find.text('مراجعة واعتماد'));
      await tester.pumpAndSettle();
      expect(submitted.single.allocations, isEmpty,
          reason: 'دفعةٌ تحت الحساب بلا فاتورةٍ بعينها حالةٌ مشروعة');
      await teardownTree(tester);
    });
  });

  group('⚠️ العمولة', () {
    testWidgets('تُعرَض لشركة التوصيل وحدَها', (tester) async {
      await pump(tester);
      await pickParty(tester, 'شركة النور');
      expect(_fieldByLabel('عمولة التوصيل ٪'), findsNothing,
          reason: 'حقلٌ يُعرَض لكلّ عميلٍ يُغري بخصمٍ لا مقابلَ له في العقد');
      await pickParty(tester, 'توصيل سريع');
      expect(_fieldByLabel('عمولة التوصيل ٪'), findsOneWidget);
      await teardownTree(tester);
    });
  });

  group('ومراسي تركيب', () {
    for (final w in const [1100.0, 1440.0, 1920.0]) {
      testWidgets('الشاشةُ بلا فيضٍ عند ${w ~/ 1}', (tester) async {
        await pump(tester, width: w, invoices: _invoices);
        expect(tester.takeException(), isNull);
        await switchToCheques(tester);
        expect(tester.takeException(), isNull, reason: 'جدولُ الشيكات فاض');
        await teardownTree(tester);
      });
    }
  });
}
