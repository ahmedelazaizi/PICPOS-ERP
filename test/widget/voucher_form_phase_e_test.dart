// المرحلة هـ — استمارةُ السند الحديثة (E2 + E3).
//
// ‏١) المستفيدُ والخزينةُ يُختاران من دليل الحسابات بالبحث.
// ‏٢) خزينةٌ ليست خزنةً تُوسَم «تحويل محاسبي — بلا حركة خزنة».
// ‏٣) حسابُ طرفٍ يُستعاد طرفاً (فيبقى كشفُه)، وحسابٌ عامٌّ يُمرَّر حساباً.
// ‏٤) دفترُ السندات: الورقةُ المقترحةُ تُمرَّر، وما خرج عن المدى يمنع الاعتماد.
// ‏٥) بلا فيضٍ عند 1366×768 في RTL/LTR × فاتح/غامق.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ural_erp/presentation/treasury_picpos/screens/voucher_form_picpos.dart';

const _accounts = <VoucherAccountOption>[
  (id: 1, code: '1111', name: 'الصندوق الرئيسي', partyId: null, safeId: 1),
  (id: 2, code: '1199', name: 'حساب وسيط', partyId: null, safeId: null),
  (id: 3, code: '1211', name: 'عميل النور', partyId: 5, safeId: null),
  (id: 4, code: '4299', name: 'إيرادات متنوعة', partyId: null, safeId: null),
];

const _books = <VoucherBookOption>[
  (id: 9, label: 'دفتر R', prefix: 'R-', rangeFrom: 100, rangeTo: 150, suggested: 104),
];

void main() {
  late List<VoucherSubmission> submitted;
  setUp(() => submitted = []);

  Future<void> pump(
    WidgetTester tester, {
    TextDirection dir = TextDirection.rtl,
    Brightness brightness = Brightness.light,
    PicPosVoucherKind kind = PicPosVoucherKind.receipt,
  }) async {
    tester.view.physicalSize = const Size(1366, 768);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(brightness: brightness),
      home: Directionality(
        textDirection: dir,
        child: PicPosVoucherForm(
          kind: kind,
          parties: const [
            (id: 5, name: 'عميل النور', meta: null, isDeliveryCompany: false),
          ],
          safes: const [(id: 1, name: 'الصندوق الرئيسي', type: 'cash')],
          costCenters: const [],
          openInvoices: const [],
          accounts: _accounts,
          voucherBooks: _books,
          initialBookId: 9,
          onSubmit: (v) async => submitted.add(v),
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  Future<void> pick(WidgetTester tester, String fieldKey, int accountId) async {
    await tester.tap(find.byKey(Key(fieldKey)));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(Key('voucher_account_$accountId')));
    await tester.pumpAndSettle();
  }

  testWidgets('رأسُ المستند: الرقمُ من الدفتر وشارةُ الحالة', (tester) async {
    await pump(tester);
    expect(find.byKey(const Key('voucher_status_chip')), findsOneWidget);
    expect(find.text('ورقة الدفتر: R-104'), findsOneWidget,
        reason: 'دفترُ المستخدم يُختار افتراضاً والورقةُ التالية تُقترَح');
    expect(find.byKey(const Key('voucher_transfer_chip')), findsNothing,
        reason: 'الخزينةُ الافتراضيّةُ خزنةٌ حقيقيّة');
  });

  testWidgets('حسابُ الطرف يُستعاد طرفاً، والورقةُ تُمرَّر', (tester) async {
    await pump(tester);
    await pick(tester, 'voucher_party', 3);
    await tester.enterText(find.byKey(const Key('voucher_amount')), '500');
    await tester.pumpAndSettle();
    await tester.tap(find.text('مراجعة واعتماد'));
    await tester.pumpAndSettle();
    final v = submitted.single;
    expect(v.partyId, 5, reason: 'رصيدُ الطرف وكشفُه يتحرّكان كما اليوم');
    expect(v.beneficiaryAccountId, isNull);
    expect(v.safeId, 1);
    expect(v.treasuryAccountId, 1);
    expect(v.bookId, 9);
    expect(v.bookNumber, 104);
  });

  testWidgets('خزينةٌ ليست خزنة = تحويلٌ محاسبيّ، ومستفيدٌ عامّ', (tester) async {
    await pump(tester);
    await pick(tester, 'voucher_party', 4);
    await pick(tester, 'voucher_safe', 2);
    expect(find.byKey(const Key('voucher_transfer_chip')), findsOneWidget);
    await tester.enterText(find.byKey(const Key('voucher_amount')), '75');
    await tester.pumpAndSettle();
    await tester.tap(find.text('مراجعة واعتماد'));
    await tester.pumpAndSettle();
    final v = submitted.single;
    expect(v.partyId, isNull);
    expect(v.beneficiaryAccountId, 4);
    expect(v.safeId, isNull, reason: 'لا خزنةَ — فلا حركةَ خزنة');
    expect(v.treasuryAccountId, 2);
  });

  testWidgets('البحثُ في الدليل بالرمز', (tester) async {
    await pump(tester);
    await tester.tap(find.byKey(const Key('voucher_party')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('voucher_account_search')), '4299');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('voucher_account_4')), findsOneWidget);
    expect(find.byKey(const Key('voucher_account_1')), findsNothing);
  });

  testWidgets('رقمُ الورقة خارجَ المدى يمنع الاعتماد', (tester) async {
    await pump(tester);
    await pick(tester, 'voucher_party', 3);
    await tester.enterText(find.byKey(const Key('voucher_amount')), '10');
    await tester.enterText(find.byKey(const Key('voucher_book_number')), '999');
    await tester.pumpAndSettle();
    expect(find.textContaining('خارج مدى الدفتر'), findsOneWidget);
    final btn = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'مراجعة واعتماد'));
    expect(btn.onPressed, isNull);
  });

  testWidgets('شيكُ القبض يحمل الساحب', (tester) async {
    await pump(tester);
    await tester.tap(find.byKey(const Key('voucher_method_check')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('voucher_cheque_drawer_0')), findsOneWidget);
  });

  for (final dir in TextDirection.values) {
    for (final b in Brightness.values) {
      for (final kind in PicPosVoucherKind.values) {
        testWidgets('بلا فيض 1366×768 — ${dir.name} ${b.name} ${kind.name}',
            (tester) async {
          await pump(tester, dir: dir, brightness: b, kind: kind);
          expect(tester.takeException(), isNull);
          await pick(tester, 'voucher_safe', 2);
          expect(tester.takeException(), isNull);
          await tester.tap(find.byKey(const Key('voucher_method_check')));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        });
      }
    }
  }
}
