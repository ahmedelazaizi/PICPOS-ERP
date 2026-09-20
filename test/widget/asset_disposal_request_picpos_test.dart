// «طلب استبعاد أصل» — نموذجُ التصميم `(6)`.
//
// ═══ ما يقيسه هذا الملفّ ═══
//
// ‏١) 🔴 **النتيجةُ باسمها الموافق لعلامتها.** التصميمُ يسمّي الحقلَ
//    «الخسارة المتوقعة» دائماً، وبيعٌ فوقَ الدفتريّة **ربحٌ** — فعرضُه تحت
//    «خسارة» يقلب إشارةَ رقمٍ يدخل قائمةَ الدخل.
//
// ‏٢) 🔴 **والزرّان يفترقان في الأثر**: المسوّدةُ بلا قيد، والاعتمادُ يُخرج
//    الأصلَ من الدفاتر.
//
// ‏٣) 🔴 **والخزنةُ تمنع الاعتمادَ ولا تمنع المسوّدة** — اشتراطُها على
//    المسوّدة كان يمنع تحريرَ طلبٍ يراجعه غيرُ مَن كتبه.
//
// ‏٤) **وطريقةٌ بلا ثمنٍ تُسقط التحصيلَ كلَّه** — ولا يُعرَض «نقدي» على
//    تبرّعٍ فيُقرأ أنّ مالاً قُبض.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ural_erp/presentation/fixed_assets_picpos/screens/asset_disposal_request_picpos.dart';

const _asset = (
  id: 1,
  code: 'FA-001',
  name: 'جهاز حاسوب',
  originalCost: 12000.0,
  accumulatedDepreciation: 2000.0,
  status: 'active',
);

Future<List<DisposalSubmission>> _pump(
  WidgetTester tester, {
  DisposalRequestValue? value,
  DisposalAssetSummary asset = _asset,
  List<DisposalSafeOption> safes = const [],
  double width = 1440,
}) async {
  final out = <DisposalSubmission>[];
  tester.view.physicalSize = Size(width, 1200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: AssetDisposalRequestForm(
        asset: asset,
        value: value,
        parties: const [(id: 7, name: 'عميل تجريبي')],
        safes: safes,
        costCenters: const [(id: 3, name: 'الإدارة')],
        onSubmit: (v) async => out.add(v),
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

String _textOf(WidgetTester tester, String key) =>
    tester.widget<Text>(find.byKey(Key(key))).data!;

Future<void> _pickMethod(WidgetTester tester, String label) async {
  await tester.tap(find.byKey(const Key('disposal_method')));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

void main() {
  group('🔴 النتيجةُ باسمها', () {
    testWidgets('بيعٌ دون الدفتريّة يُعرَض «الخسارة المتوقَّعة»',
        (tester) async {
      await _pump(tester, safes: const [(id: 2, name: 'الرئيسية')]);
      expect(_textOf(tester, 'disposal_book_value'), '10,000.00');

      await tester.enterText(find.byKey(const Key('disposal_value')), '9500');
      await tester.pumpAndSettle();
      expect(find.text('الخسارة المتوقَّعة'), findsOneWidget);
      expect(_textOf(tester, 'disposal_outcome'), '500.00');
      await _teardownTree(tester);
    });

    testWidgets('🔴 وبيعٌ فوقَها يُعرَض «الربح المتوقَّع» لا سالباً تحت «خسارة»',
        (tester) async {
      await _pump(tester, safes: const [(id: 2, name: 'الرئيسية')]);
      await tester.enterText(find.byKey(const Key('disposal_value')), '11000');
      await tester.pumpAndSettle();
      expect(find.text('الربح المتوقَّع'), findsOneWidget);
      expect(find.text('الخسارة المتوقَّعة'), findsNothing,
          reason: '🔴 ربحٌ معروضٌ تحت «خسارة» يقلب إشارةَ رقمٍ يدخل قائمةَ '
              'الدخل');
      expect(_textOf(tester, 'disposal_outcome'), '1,000.00');
      await _teardownTree(tester);
    });
  });

  group('🔴 الطريقةُ تحكم', () {
    testWidgets('الإعدامُ يمسح الثمنَ ويُسقط قسمَ التحصيل', (tester) async {
      await _pump(tester, safes: const [(id: 2, name: 'الرئيسية')]);
      await tester.enterText(find.byKey(const Key('disposal_value')), '9500');
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('disposal_collection_cash')), findsOneWidget);

      await _pickMethod(tester, 'إعدام');

      // 🔴 رقمٌ باقٍ بعد التبديل يُرفَض عند الحفظ بلا أن يُفهَم سببُه.
      expect(
          tester.widget<TextField>(find.byKey(const Key('disposal_value')))
              .controller!
              .text,
          isEmpty);
      // ⚠️ ولا «نقدي» على إعدامٍ — يُقرأ أنّ مالاً قُبض.
      expect(find.byKey(const Key('disposal_collection_cash')), findsNothing);
      expect(find.byKey(const Key('disposal_no_collection')), findsOneWidget);
      await _teardownTree(tester);
    });

    testWidgets('والخسارةُ في الإعدامِ هي الدفتريّةُ كلُّها', (tester) async {
      await _pump(tester);
      await _pickMethod(tester, 'تخريد');
      expect(_textOf(tester, 'disposal_outcome'), '10,000.00');
      expect(find.text('الخسارة المتوقَّعة'), findsOneWidget);
      await _teardownTree(tester);
    });
  });

  group('🔴 الزرّان يفترقان', () {
    testWidgets('المسوّدةُ تمرّ بلا خزنةٍ والاعتمادُ لا', (tester) async {
      final out = await _pump(tester, safes: const []);
      await tester.enterText(find.byKey(const Key('disposal_value')), '9500');
      await tester.enterText(
          find.byKey(const Key('disposal_reason')), 'استبدال الجهاز');
      await tester.pumpAndSettle();

      // 🔴 الاعتمادُ ممنوعٌ: نقدٌ يزيد في الدفتر ولا يزيد في أيّ درج.
      final approve =
          tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'مراجعة واعتماد'));
      expect(approve.onPressed, isNull);
      expect(find.byKey(const Key('disposal_block_reason')), findsOneWidget);

      // ⚠️ والمسوّدةُ تمرّ — الخزنةُ قرارُ لحظةِ الاعتماد.
      await tester.tap(find.widgetWithText(OutlinedButton, 'حفظ مسودة'));
      await tester.pumpAndSettle();
      expect(out, hasLength(1));
      expect(out.single.approve, isFalse);
      expect(out.single.safeId, isNull);
      await _teardownTree(tester);
    });

    testWidgets('🔴 والاعتمادُ يمرّ بخزنةٍ ويحمل رايتَه', (tester) async {
      final out = await _pump(tester, safes: const [(id: 2, name: 'الرئيسية')]);
      await tester.enterText(find.byKey(const Key('disposal_value')), '9500');
      await tester.enterText(
          find.byKey(const Key('disposal_reason')), 'استبدال الجهاز');
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('disposal_block_reason')), findsNothing);
      await tester.tap(find.widgetWithText(FilledButton, 'مراجعة واعتماد'));
      await tester.pumpAndSettle();

      expect(out.single.approve, isTrue,
          reason: '🔴 اعتمادٌ يُحفَظ مسوّدةً يترك الأصلَ في الدفاتر والمستخدمُ '
              'يظنّه خرج');
      // خزنةٌ واحدةٌ تُختار تلقائيّاً — وإلّا لزم نقرٌ لا معنى له.
      expect(out.single.safeId, 2);
      expect(out.single.disposalValue, 9500);
      expect(out.single.collectionMethod, 'cash');
      await _teardownTree(tester);
    });

    testWidgets('🔴 والآجلُ بلا مشترٍ يمنع الزرَّين معاً', (tester) async {
      await _pump(tester, safes: const [(id: 2, name: 'الرئيسية')]);
      await tester.enterText(find.byKey(const Key('disposal_value')), '9500');
      await tester.enterText(
          find.byKey(const Key('disposal_reason')), 'استبدال');
      await tester.tap(find.byKey(const Key('disposal_collection_credit')));
      await tester.pumpAndSettle();

      // 🔴 بلا طرفٍ مسجَّلٍ لا ذمّةَ تُحمَّل — ولا يُحفَظ طلبٌ يستحيل اعتمادُه.
      expect(
          tester
              .widget<FilledButton>(
                  find.widgetWithText(FilledButton, 'مراجعة واعتماد'))
              .onPressed,
          isNull);
      expect(
          tester
              .widget<OutlinedButton>(
                  find.widgetWithText(OutlinedButton, 'حفظ مسودة'))
              .onPressed,
          isNull);
      await _teardownTree(tester);
    });

    testWidgets('والآجلُ بمشترٍ لا يمرّر خزنةً', (tester) async {
      final out = await _pump(tester, safes: const [(id: 2, name: 'الرئيسية')]);
      await tester.enterText(find.byKey(const Key('disposal_value')), '9500');
      await tester.enterText(
          find.byKey(const Key('disposal_reason')), 'استبدال');
      await tester.tap(find.byKey(const Key('disposal_collection_credit')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('disposal_buyer')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('عميل تجريبي').last);
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'مراجعة واعتماد'));
      await tester.pumpAndSettle();
      expect(out.single.buyerPartyId, 7);
      expect(out.single.safeId, isNull,
          reason: '🔴 خزنةٌ مع آجلٍ تحرّك درجاً لم يدخله مال');
      await _teardownTree(tester);
    });

    testWidgets('وسببٌ فارغٌ يمنع الحفظ ويقول سببَه', (tester) async {
      await _pump(tester, safes: const [(id: 2, name: 'الرئيسية')]);
      await tester.enterText(find.byKey(const Key('disposal_value')), '9500');
      await tester.pumpAndSettle();
      expect(find.text('اكتب سبب الاستبعاد'), findsOneWidget);
      await _teardownTree(tester);
    });
  });

  group('⚠️ الطلبُ المُعتمَد', () {
    const approved = (
      id: 5,
      number: 'ADP-0001',
      status: 'approved',
      method: 'sale',
      disposalValue: 9500.0,
      collectionMethod: 'cash',
      buyerPartyId: 7,
      costCenterId: 3,
      reason: 'استبدال',
    );

    testWidgets('يُعرَض ولا يُحرَّر ولا يُحفَظ', (tester) async {
      await _pump(
        tester,
        asset: (
          id: 1,
          code: 'FA-001',
          name: 'جهاز حاسوب',
          originalCost: 12000.0,
          accumulatedDepreciation: 2000.0,
          status: 'sold',
        ),
        value: (
          id: approved.id,
          number: approved.number,
          status: approved.status,
          disposalDate: DateTime(2026, 6, 30),
          method: approved.method,
          disposalValue: approved.disposalValue,
          collectionMethod: approved.collectionMethod,
          buyerPartyId: approved.buyerPartyId,
          costCenterId: approved.costCenterId,
          reason: approved.reason,
        ),
        safes: const [(id: 2, name: 'الرئيسية')],
      );

      expect(find.text('معتمد'), findsOneWidget);
      expect(find.text('ADP-0001'), findsOneWidget);
      expect(
          tester
              .widget<FilledButton>(
                  find.widgetWithText(FilledButton, 'مراجعة واعتماد'))
              .onPressed,
          isNull,
          reason: '🔴 اعتمادٌ ثانٍ يقيّد التكلفةَ والمجمَّعَ مرّةً أخرى');
      expect(
          tester
              .widget<TextField>(find.byKey(const Key('disposal_reason')))
              .enabled,
          isFalse);
      await _teardownTree(tester);
    });
  });

  test('⚠️ ورقمُ الطلب لا يُخمَّن قبل الحفظ', () {
    // مواصفة ٠٦٦ — المولّدُ داخلَ معاملة الحفظ.
    expect(kDisposalNumberPlaceholder, isNotEmpty);
  });

  testWidgets('⚠️ ورقمُ الطلب placeholder في الجديد', (tester) async {
    await _pump(tester);
    expect(find.text(kDisposalNumberPlaceholder), findsOneWidget);
    await _teardownTree(tester);
  });

  group('ومراسي تركيب', () {
    for (final w in const [1100.0, 1440.0, 1920.0]) {
      testWidgets('بلا فيضٍ عند ${w ~/ 1}', (tester) async {
        await _pump(tester, width: w, safes: const [(id: 2, name: 'الرئيسية')]);
        expect(tester.takeException(), isNull);
        await _pickMethod(tester, 'تبرّع');
        expect(tester.takeException(), isNull);
        await _teardownTree(tester);
      });
    }
  });
}
