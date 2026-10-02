// J2 (قرارُ المالك) — سجلّا مرتجعات المبيعات والمشتريات.
//
// ما يُقاس:
//   • الشاشتان ترسمان في RTL/LTR × فاتح/داكن على ١٣٦٦×٧٦٨ بلا فيض، والعرضُ
//     الإنجليزيُّ بلا نصٍّ عربيّ؛
//   • شرائحُ الحالة (الكلّ · مسودة · معتمد · ملغى) ترشّح، والبحثُ يرشّح،
//     وصفُّ المجاميع يجمع الضريبةَ والإجماليّ؛
//   • أفعالُ الصفّ بحسب الحالة والصلاحية — «مراجعة واعتماد» معطّلٌ بلا
//     `*_return_approve`؛
//   • «جديد» يفتح الاستمارةَ صفحةً، وفيها «حفظ مسودة»، واعتمادُها محكومٌ
//     بالصلاحية.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/core/i18n/tr.dart';
import 'package:ural_erp/core/theme/app_theme.dart';
import 'package:ural_erp/data/providers/document_record_providers.dart';
import 'package:ural_erp/data/providers/manufacturing_providers.dart';
import 'package:ural_erp/data/providers/providers.dart';
import 'package:ural_erp/data/providers/return_records_providers.dart';
import 'package:ural_erp/domain/models/document_record.dart';
import 'package:ural_erp/domain/models/return_draft.dart';
import 'package:ural_erp/presentation/providers/purchase_return_provider.dart';
import 'package:ural_erp/presentation/providers/sales_return_provider.dart';
import 'package:ural_erp/presentation/purchase_returns_picpos/screens/purchase_return_records_picpos_screen.dart';
import 'package:ural_erp/presentation/purchase_returns_picpos/screens/purchase_returns_picpos_screen.dart';
import 'package:ural_erp/presentation/sales_returns_picpos/screens/sales_return_records_picpos_screen.dart';
import 'package:ural_erp/presentation/sales_returns_picpos/screens/sales_returns_picpos_screen.dart';
import 'package:ural_erp/presentation/shared_widgets/return_records_view.dart';

import '../helpers/attachments_test_overrides.dart';

final _now = DateTime.now();
final _arabic = RegExp(r'[\u0600-\u06FF]');

SalesInvoiceData _salesInvoice() => SalesInvoiceData(
      id: 1,
      invoiceNumber: 'INV-0201',
      customerId: 5,
      warehouseId: 1,
      userId: 1,
      invoiceDate: _now,
      subtotal: 700,
      discount: 0,
      tax: 0,
      total: 700,
      paid: 0,
      paidUnallocated: 0,
      roundingAdjustment: 0,
      cashPaid: 0,
      bankPaid: 0,
      clickPaid: 0,
      paymentMethod: 'credit',
      saleType: 'retail',
      status: 'partial_return',
      deliveryFee: 0,
      isLocked: false,
      isDeleted: false,
      updatedAt: _now,
      rowVersion: 1,
      createdAt: _now,
    );

ReturnRecordRow _row(
  String key,
  ReturnRecordStatus status,
  String number, {
  required double total,
  required double tax,
  String settlement = 'cash',
  int? draftId,
  int? documentId,
}) =>
    ReturnRecordRow(
      key: key,
      status: status,
      number: number,
      date: _now,
      originalInvoiceId: 1,
      originalInvoiceNumber: 'INV-0201',
      partyName: 'Nour Trading',
      reason: 'Damaged',
      settlement: settlement,
      tax: tax,
      total: total,
      draftId: draftId,
      documentId: documentId,
    );

final _salesEntries = [
  SalesReturnRecordEntry(
    row: _row('d1', ReturnRecordStatus.draft, 'D-1',
        total: 100, tax: 10, settlement: 'balance', draftId: 1),
  ),
  SalesReturnRecordEntry(
    row: _row('p1', ReturnRecordStatus.posted, 'SRET-7', total: 200, tax: 20),
    originalInvoice: _salesInvoice(),
  ),
  SalesReturnRecordEntry(
    row: _row('d2', ReturnRecordStatus.cancelled, 'SRET-5',
        total: 50, tax: 5, draftId: 2),
  ),
];

final _purchasePosted = [
  PurchaseReturnRecord(
    id: 31,
    originalInvoiceId: 2,
    returnDate: _now,
    subtotal: 180,
    tax: 20,
    total: 200,
    refundMethod: 'credit',
    isFullReturn: false,
    originalInvoiceNumber: 'PINV-0201',
    supplierId: 7,
    supplierName: 'Al Noor Supplies',
    reason: 'Surplus',
  ),
];

final _purchaseExtras = PurchaseReturnRecordExtras(
  drafts: [
    _row('d3', ReturnRecordStatus.draft, 'D-3',
        total: 100, tax: 10, settlement: 'balance', draftId: 3),
  ],
  voided: [
    _row('p30', ReturnRecordStatus.cancelled, '—',
        total: 50, tax: 5, documentId: 30),
  ],
  vouchers: {
    1: [ReturnVoucherLegs('PRET-1')..balance = true],
    2: [ReturnVoucherLegs('PRET-2')..cash = true],
  },
);

class _FakeSalesNotifier extends SalesReturnNotifier {
  @override
  SalesReturnState build() => SalesReturnState(
        fromDate: _now.subtract(const Duration(days: 30)),
        toDate: _now,
      );
  @override
  Future<void> loadInvoices() async {}
}

class _FakePurchaseNotifier extends PurchaseReturnNotifier {
  @override
  PurchaseReturnState build() => PurchaseReturnState(
        fromDate: _now.subtract(const Duration(days: 30)),
        toDate: _now,
      );
  @override
  Future<void> loadInvoices() async {}
}

enum _Kind { sales, purchase }

const _allPerms = [
  'sales_return_view',
  'sales_return_approve',
  'sales_return_print',
  'sales_return_delete',
  'purchases_return_view',
  'purchases_return_approve',
  'purchases_return_print',
  'purchases_return_edit',
];

Future<void> _pump(
  WidgetTester tester, {
  required _Kind kind,
  bool english = false,
  Brightness brightness = Brightness.light,
  List<String> perms = _allPerms,
  List<String>? overflows,
}) async {
  tester.view.physicalSize = const Size(1366, 768);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  I18nCatalog.setLocale(english ? const Locale('en') : const Locale('ar', 'EG'));
  addTearDown(() => I18nCatalog.setLocale(const Locale('ar', 'EG')));

  final previous = FlutterError.onError;
  if (overflows != null) {
    FlutterError.onError = (d) {
      final s = d.toString();
      if (s.contains('overflowed')) {
        overflows.add(s.split('\n').first);
      } else {
        previous?.call(d);
      }
    };
  }
  try {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        salesReturnRecordsProvider
            .overrideWith((ref, w) async => _salesEntries),
        purchaseReturnRecordsProvider
            .overrideWith((ref, f) => Stream.value(_purchasePosted)),
        purchaseReturnRecordExtrasProvider
            .overrideWith((ref, w) async => _purchaseExtras),
        currentUserPermissionsProvider.overrideWith((ref) async => perms),
        attachmentsRepositoryProvider.overrideWithValue(fakeAttachmentsRepo()),
        salesReturnProvider.overrideWith(_FakeSalesNotifier.new),
        purchaseReturnProvider.overrideWith(_FakePurchaseNotifier.new),
        warehouseNameMapProvider.overrideWith((ref) => const {1: 'Main Store'}),
        partyNamesMapProvider.overrideWith((ref, ids) async => const {}),
      ],
      child: MaterialApp(
        theme: brightness == Brightness.dark
            ? AppTheme.darkTheme
            : AppTheme.lightTheme,
        locale: english ? const Locale('en') : const Locale('ar'),
        supportedLocales: const [Locale('ar'), Locale('en')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: kind == _Kind.sales
            ? const SalesReturnRecordsPicPosScreen()
            : const PurchaseReturnRecordsPicPosScreen(),
      ),
    ));
    await tester.pumpAndSettle();
  } finally {
    if (overflows != null) FlutterError.onError = previous;
  }
}

List<String> _visibleArabic(WidgetTester tester) => [
      for (final t in tester.widgetList<Text>(find.byType(Text)))
        if ((t.data ?? t.textSpan?.toPlainText() ?? '').contains(_arabic))
          t.data ?? t.textSpan!.toPlainText(),
    ];

Future<void> _tapChip(WidgetTester tester, String arabicLabel) async {
  await tester.tap(find.text(tr(arabicLabel)).first);
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() {
    final raw = File('assets/i18n/en.json').readAsStringSync();
    I18nCatalog.setCatalog({
      for (final e in (jsonDecode(raw) as Map<String, dynamic>).entries)
        if (e.value is String) e.key: e.value as String,
    });
  });

  group('layout — RTL/LTR × light/dark at 1366×768', () {
    for (final kind in _Kind.values) {
      for (final english in [false, true]) {
        for (final brightness in Brightness.values) {
          testWidgets(
              '${kind.name} records · ${english ? 'LTR/en' : 'RTL/ar'} · '
              '${brightness.name}', (tester) async {
            final overflows = <String>[];
            await _pump(tester,
                kind: kind,
                english: english,
                brightness: brightness,
                overflows: overflows);
            expect(overflows, isEmpty, reason: overflows.join('\n'));
            expect(find.byKey(const Key('return_records_new')), findsOneWidget);
            // صفٌّ واحدٌ من كلّ حالة.
            expect(find.text(kind == _Kind.sales ? 'D-1' : 'D-3'),
                findsOneWidget);
            // اختيارُ صفٍّ يُظهر شريطَ أفعاله بلا فيض.
            await tester.tap(find.text(kind == _Kind.sales ? 'D-1' : 'D-3'));
            await tester.pumpAndSettle();
            expect(find.byKey(const Key('return_record_actions')),
                findsOneWidget);
            expect(overflows, isEmpty, reason: overflows.join('\n'));
            if (english) {
              expect(_visibleArabic(tester), isEmpty,
                  reason: 'Arabic UI text in the English render');
            }
          });
        }
      }
    }
  });

  group('sales records', () {
    testWidgets('status chips filter and the footer totals follow them',
        (tester) async {
      await _pump(tester, kind: _Kind.sales);
      expect(find.text('D-1'), findsOneWidget);
      expect(find.text('SRET-7'), findsOneWidget);
      expect(find.text('SRET-5'), findsOneWidget);
      expect(find.text(returnRecordMoney(350)), findsOneWidget,
          reason: 'total of every shown row');
      expect(find.text(returnRecordMoney(35)), findsOneWidget,
          reason: 'tax of every shown row');

      await _tapChip(tester, 'مسودة');
      expect(find.text('D-1'), findsOneWidget);
      expect(find.text('SRET-7'), findsNothing);
      expect(find.text('SRET-5'), findsNothing);

      await _tapChip(tester, 'معتمد');
      expect(find.text('SRET-7'), findsOneWidget);
      expect(find.text('D-1'), findsNothing);

      await _tapChip(tester, 'ملغى');
      expect(find.text('SRET-5'), findsOneWidget);
      expect(find.text('SRET-7'), findsNothing);
    });

    testWidgets('search narrows by number', (tester) async {
      await _pump(tester, kind: _Kind.sales);
      await tester.enterText(
          find.byKey(const Key('return_records_search')), 'SRET-7');
      await tester.pumpAndSettle();
      expect(find.text('D-1'), findsNothing);
      expect(find.text('SRET-5'), findsNothing);
      expect(find.text(returnRecordMoney(200)), findsWidgets,
          reason: 'the matching row (and its totals) stays');
    });

    testWidgets('row actions follow status and the approve permission',
        (tester) async {
      await _pump(tester, kind: _Kind.sales);
      await tester.tap(find.text('D-1'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('return_row_edit')), findsOneWidget);
      expect(find.byKey(const Key('return_row_delete')), findsOneWidget);
      final approve = tester.widget<OutlinedButton>(
          find.byKey(const Key('return_row_approve')));
      expect(approve.onPressed, isNotNull);

      await tester.tap(find.text('SRET-7'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('return_row_edit')), findsNothing,
          reason: 'a posted return is not edited as a draft');
      expect(find.byTooltip(tr('طباعة المرتجع')), findsOneWidget);
      expect(find.byTooltip(tr('إلغاء المرتجع')), findsOneWidget);

      await tester.tap(find.text('SRET-5'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('return_row_view')), findsOneWidget);
      expect(find.byTooltip(tr('إلغاء المرتجع')), findsNothing,
          reason: 'a cancelled return offers view only');
    });

    testWidgets('without sales_return_approve the row cannot approve',
        (tester) async {
      await _pump(tester,
          kind: _Kind.sales, perms: const ['sales_return_view']);
      await tester.tap(find.text('D-1'));
      await tester.pumpAndSettle();
      final approve = tester.widget<OutlinedButton>(
          find.byKey(const Key('return_row_approve')));
      expect(approve.onPressed, isNull);
    });

    testWidgets('«جديد» opens the return form as a page with «حفظ مسودة»',
        (tester) async {
      await _pump(tester, kind: _Kind.sales);
      await tester.tap(find.byKey(const Key('return_records_new')));
      await tester.pumpAndSettle();
      expect(find.byType(SalesReturnsPicposScreen), findsOneWidget);
      expect(find.text(tr('مرتجع مبيعات جديد')), findsOneWidget);
      expect(find.byKey(const Key('picpos_return_save_draft')),
          findsOneWidget);
      expect(find.byKey(const Key('picpos_return_back')), findsOneWidget,
          reason: 'pushed as a page — «رجوع» returns to the record');
      await tester.tap(find.byKey(const Key('picpos_return_back')));
      await tester.pumpAndSettle();
      expect(find.byType(SalesReturnRecordsPicPosScreen), findsOneWidget);
    });
  });

  group('purchase records', () {
    testWidgets('draft, posted (with its PRET number) and voided rows',
        (tester) async {
      await _pump(tester, kind: _Kind.purchase);
      expect(find.text('D-3'), findsOneWidget);
      expect(find.text('PRET-2'), findsOneWidget,
          reason: 'the posted document carries its own voucher number');
      expect(find.text(returnRecordMoney(350)), findsOneWidget);

      await _tapChip(tester, 'ملغى');
      expect(find.text('PINV-0201'), findsNothing);
      expect(find.text('D-3'), findsNothing);
      expect(find.text(returnRecordMoney(50)), findsWidgets);
    });

    testWidgets('posted row offers print, items and edit by permission',
        (tester) async {
      await _pump(tester, kind: _Kind.purchase);
      await tester.tap(find.text('PRET-2'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('return_row_print')), findsOneWidget);
      expect(find.byKey(const Key('return_row_items')), findsOneWidget);
      expect(find.byKey(const Key('return_row_edit_posted')), findsOneWidget);
    });

    testWidgets('without purchases_return_edit the posted edit is hidden',
        (tester) async {
      await _pump(tester,
          kind: _Kind.purchase,
          perms: const ['purchases_return_view', 'purchases_return_print']);
      await tester.tap(find.text('PRET-2'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('return_row_edit_posted')), findsNothing);
      await tester.tap(find.text('D-3'));
      await tester.pumpAndSettle();
      expect(
          tester
              .widget<OutlinedButton>(
                  find.byKey(const Key('return_row_approve')))
              .onPressed,
          isNull);
    });

    testWidgets('«جديد» opens the purchase return form; approve is gated',
        (tester) async {
      await _pump(tester,
          kind: _Kind.purchase, perms: const ['purchases_return_view']);
      await tester.tap(find.byKey(const Key('return_records_new')));
      await tester.pumpAndSettle();
      expect(find.byType(PurchaseReturnsPicposScreen), findsOneWidget);
      expect(find.text(tr('مرتجع مشتريات جديد')), findsOneWidget);
      expect(
          tester
              .widget<FilledButton>(
                  find.byKey(const Key('picpos_return_approve')))
              .onPressed,
          isNull);
      expect(find.text(tr('طباعة أو تعديل مرتجعٍ سابق')), findsNothing,
          reason: 'the old dialog button gave way to row actions');
    });
  });
}
