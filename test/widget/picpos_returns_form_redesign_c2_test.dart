// C2 (owner item 3) — the PicPos SALES RETURN and PURCHASE RETURN forms on the
// owner's reference layout: page header (title + number + status chip),
// header card (original-invoice picker, original value, payment status, date,
// party, warehouse, reason), returned-items table, settlement block beside the
// collapsible «تفاصيل إضافية», bottom action bar.
//
// Measured here:
//   • both screens render in RTL + LTR × light + dark at 1366×768 with zero
//     overflow reports — and the English (LTR) render shows no Arabic UI text;
//   • the lines table shows SOLD qty on sales returns and PURCHASED qty on
//     purchase returns, plus previously-returned / available columns;
//   • a return qty above «available» is rejected (error shown, the provider
//     keeps its previous value) exactly as the old +/− stepper capped it;
//   • «مراجعة واعتماد» reaches the SAME handler (`processReturn` → its
//     confirmation dialog), «طريقة التسوية» is a read-only field, and there
//     is no draft button.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/core/constants/app_constants.dart';
import 'package:ural_erp/core/i18n/tr.dart';
import 'package:ural_erp/core/theme/app_theme.dart';
import 'package:ural_erp/data/providers/manufacturing_providers.dart';
import 'package:ural_erp/data/providers/providers.dart';
import 'package:ural_erp/domain/entities/product_entity.dart';
import 'package:ural_erp/presentation/providers/purchase_return_provider.dart';
import 'package:ural_erp/presentation/providers/sales_return_provider.dart';
import 'package:ural_erp/presentation/purchase_returns_picpos/screens/purchase_returns_picpos_screen.dart';
import 'package:ural_erp/presentation/sales_returns_picpos/screens/sales_returns_picpos_screen.dart';

final _now = DateTime(2026, 9, 8);
final _arabic = RegExp(r'[\u0600-\u06FF]');

// ── Fixtures ──────────────────────────────────────────────────────────────

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
      status: 'completed',
      deliveryFee: 0,
      isLocked: false,
      isDeleted: false,
      updatedAt: _now,
      rowVersion: 1,
      createdAt: _now,
    );

const _soldItems = [
  SalesInvoiceItem(
    id: 11, invoiceId: 1, productId: 101,
    quantity: 5, unitPrice: 100, discount: 0, total: 500,
    costPrice: 60, sortOrder: 0, taxRate: 0, taxAmount: 0,
    quantityInBase: 5, rowVersion: 0,
  ),
  SalesInvoiceItem(
    id: 12, invoiceId: 1, productId: 102,
    quantity: 2, unitPrice: 100, discount: 0, total: 200,
    costPrice: 60, sortOrder: 1, taxRate: 0, taxAmount: 0,
    quantityInBase: 2, rowVersion: 0,
  ),
];

SalesReturnState _salesSeed({bool selected = true}) => SalesReturnState(
      fromDate: _now.subtract(const Duration(days: 30)),
      toDate: _now,
      invoices: [_salesInvoice()],
      customerNames: const {5: 'Nour Trading'},
      selectedInvoice: selected ? _salesInvoice() : null,
      invoiceItems: selected ? _soldItems : const [],
      // Item 11: 5 sold, 2 returned before ⇒ 3 available.
      previouslyReturnedQty: selected ? const {11: 2} : const {},
      returnQuantities: selected ? const {11: 0, 12: 0} : const {},
      productCache: const {
        101: ProductEntity(
          id: 101, code: 'P1', name: 'Printer Ink', salePrice: 100,
          costPrice: 60, currentStock: 10, minStock: 0,
        ),
        102: ProductEntity(
          id: 102, code: 'P2', name: 'Paper A4', salePrice: 100,
          costPrice: 60, currentStock: 10, minStock: 0,
        ),
      },
    );

/// Invoice ids handed to `selectInvoice` by the original-invoice picker.
final _salesSelected = <int>[];

class _FakeSalesNotifier extends SalesReturnNotifier {
  _FakeSalesNotifier(this.seed);
  final SalesReturnState seed;
  @override
  SalesReturnState build() => seed;
  @override
  Future<void> loadInvoices() async {}
  @override
  Future<void> selectInvoice(SalesInvoiceData invoice) async =>
      _salesSelected.add(invoice.id);
}

PurchaseInvoiceData _purchaseInvoice() => PurchaseInvoiceData(
      id: 2,
      invoiceNumber: 'PINV-0201',
      supplierId: 7,
      warehouseId: 1,
      invoiceDate: _now,
      subtotal: 900,
      discount: 0,
      tax: 0,
      total: 900,
      paid: 0,
      paymentMethod: 'credit',
      status: 'completed',
      isLocked: false,
      isDeleted: false,
      updatedAt: _now,
      rowVersion: 1,
      createdAt: _now,
    );

Product _product(int id, String name) => Product(
      id: id, code: 'C$id', name: name, salePrice: 150, priceTalabat: 0,
      priceCareem: 0, priceAshyae: 0, wholesalePrice: 0, costPrice: 100,
      minStock: 0, currentStock: 10, isActive: true, isLocked: false,
      trackInventory: true, trackExpiry: false, defaultShelfDays: 0,
      alertDaysBefore: 0, isSoldByWeight: false, weightUnit: 'kg',
      allowNegativeSale: false, productType: 'standard', isKitchenSet: false,
      taxRate: 0, scaleType: 'none', itemTaxType: 'V009',
      itemTaxSubtype: 'V009', createdAt: _now, updatedAt: _now, sortOrder: 0,
      rowVersion: 1, createdOnServer: false,
    );

PurchaseReturnState _purchaseSeed({bool selected = true}) =>
    PurchaseReturnState(
      fromDate: _now.subtract(const Duration(days: 30)),
      toDate: _now,
      invoices: [_purchaseInvoice()],
      selectedInvoice: selected ? _purchaseInvoice() : null,
      invoiceItems: selected
          ? [
              PurchaseInvoiceItemWithProduct(
                item: const PurchaseInvoiceItem(
                  id: 21, invoiceId: 2, productId: 201, quantity: 5,
                  unitCost: 100, discount: 0, total: 500, taxRate: 0,
                  taxAmount: 0, quantityInBase: 5, rowVersion: 0,
                ),
                product: _product(201, 'Printer Ink'),
              ),
              PurchaseInvoiceItemWithProduct(
                item: const PurchaseInvoiceItem(
                  id: 22, invoiceId: 2, productId: 202, quantity: 4,
                  unitCost: 100, discount: 0, total: 400, taxRate: 0,
                  taxAmount: 0, quantityInBase: 4, rowVersion: 0,
                ),
                product: _product(202, 'Paper A4'),
              ),
            ]
          : const [],
      returnQuantities: selected ? const {21: 0, 22: 0} : const {},
      // Product 201: 5 purchased, 2 returned before ⇒ 3 available.
      alreadyReturnedByProduct: selected ? const {201: 2} : const {},
    );

class _FakePurchaseNotifier extends PurchaseReturnNotifier {
  _FakePurchaseNotifier(this.seed);
  final PurchaseReturnState seed;
  @override
  PurchaseReturnState build() => seed;
  @override
  Future<void> loadInvoices() async {}
  @override
  Future<void> selectInvoice(PurchaseInvoiceData invoice) async {}
}

// ── Harness ───────────────────────────────────────────────────────────────

enum _Kind { sales, purchase }

Future<ProviderContainer> _pump(
  WidgetTester tester, {
  required _Kind kind,
  bool english = false,
  Brightness brightness = Brightness.light,
  bool selected = true,
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
        salesReturnProvider
            .overrideWith(() => _FakeSalesNotifier(_salesSeed(selected: selected))),
        purchaseReturnProvider.overrideWith(
            () => _FakePurchaseNotifier(_purchaseSeed(selected: selected))),
        warehouseNameMapProvider.overrideWith((ref) => const {1: 'Main Store'}),
        partyNamesMapProvider
            .overrideWith((ref, ids) async => const {7: 'Al Noor Supplies'}),
      ],
      child: MaterialApp(
        theme: brightness == Brightness.dark
            ? AppTheme.darkTheme
            : AppTheme.lightTheme,
        locale: english ? const Locale('en') : const Locale('ar'),
        supportedLocales: const [Locale('ar'), Locale('en')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: kind == _Kind.sales
            ? const SalesReturnsPicposScreen()
            : const PurchaseReturnsPicposScreen(),
      ),
    ));
    await tester.pumpAndSettle();
  } finally {
    if (overflows != null) FlutterError.onError = previous;
  }
  return ProviderScope.containerOf(
    tester.element(find.byType(kind == _Kind.sales
        ? SalesReturnsPicposScreen
        : PurchaseReturnsPicposScreen)),
  );
}

Finder _qtyInput(int lineId) => find.descendant(
      of: find.byKey(ValueKey('picpos_return_qty_$lineId')),
      matching: find.byType(TextField),
    );

List<String> _visibleArabic(WidgetTester tester) => [
      for (final t in tester.widgetList<Text>(find.byType(Text)))
        if ((t.data ?? t.textSpan?.toPlainText() ?? '').contains(_arabic))
          t.data ?? t.textSpan!.toPlainText(),
    ];

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
              '${kind.name} · ${english ? 'LTR/en' : 'RTL/ar'} · '
              '${brightness.name} — renders without overflow', (tester) async {
            final overflows = <String>[];
            await _pump(tester,
                kind: kind,
                english: english,
                brightness: brightness,
                overflows: overflows);

            expect(overflows, isEmpty, reason: overflows.join('\n'));
            final dir = Directionality.of(
                tester.element(find.byKey(const Key('picpos_return_scroll'))));
            expect(dir, english ? TextDirection.ltr : TextDirection.rtl);

            // Page header: title + number + status chip ("new", never "draft").
            expect(find.byKey(const Key('picpos_return_status_chip')),
                findsOneWidget);
            expect(find.text(tr('جديد')), findsOneWidget);
            expect(find.text(tr('مسودة')), findsNothing);
            expect(find.text(tr('يُولَّد تلقائياً')), findsOneWidget);

            // Header card.
            expect(find.byKey(const Key('picpos_return_invoice_picker')),
                findsOneWidget);
            expect(
                find.text(kind == _Kind.sales ? 'INV-0201' : 'PINV-0201'),
                findsOneWidget);
            expect(find.text(tr('قيمة الفاتورة الأصلية')), findsOneWidget);
            expect(find.text(tr('غير مسددة')), findsOneWidget);
            expect(find.text('Main Store'), findsOneWidget);
            expect(
                find.text(kind == _Kind.sales
                    ? 'Nour Trading'
                    : 'Al Noor Supplies'),
                findsOneWidget);

            // Lines: sold vs purchased qty column.
            expect(
                find.text(kind == _Kind.sales
                    ? tr('الكمية المباعة')
                    : tr('الكمية المشتراة')),
                findsOneWidget);
            expect(
                find.text(kind == _Kind.sales
                    ? tr('الكمية المشتراة')
                    : tr('الكمية المباعة')),
                findsNothing);
            expect(find.text(tr('المرتجع سابقاً')), findsOneWidget);
            expect(find.text(tr('المتاح حالياً')), findsOneWidget);

            // Settlement: method is a read-only field, not a dropdown.
            final method =
                find.byKey(const Key('picpos_return_settlement_method'));
            expect(method, findsOneWidget);
            expect(
                find.descendant(
                    of: method, matching: find.byType(DropdownButton<String>)),
                findsNothing);

            // Action bar: approve + no draft.
            expect(find.byKey(const Key('picpos_return_approve')),
                findsOneWidget);
            expect(find.text(tr('حفظ مسودة')), findsNothing);

            if (english) {
              expect(_visibleArabic(tester), isEmpty,
                  reason: 'Arabic UI text in the English render');
            }
          });
        }
      }
    }

    testWidgets('no invoice selected — empty form still lays out', (tester) async {
      for (final kind in _Kind.values) {
        final overflows = <String>[];
        await _pump(tester, kind: kind, selected: false, overflows: overflows);
        expect(overflows, isEmpty, reason: overflows.join('\n'));
        expect(find.text(tr('اختر الفاتورة الأصلية')), findsOneWidget);
        expect(find.text(tr('اختر الفاتورة الأصلية لعرض أصنافها')),
            findsWidgets);
        final approve = tester.widget<FilledButton>(
            find.byKey(const Key('picpos_return_approve')));
        expect(approve.onPressed, isNull,
            reason: 'nothing to return before an invoice is chosen');
      }
    });
  });

  group('sales return', () {
    testWidgets('qty above available is rejected; within it reaches provider',
        (tester) async {
      final c = await _pump(tester, kind: _Kind.sales);

      await tester.enterText(_qtyInput(11), '4');
      await tester.pump();
      expect(
          find.text(tr('الكمية تتجاوز المتاح ({p0})', {'p0': '3'})),
          findsOneWidget);
      expect(c.read(salesReturnProvider).returnQuantities[11], 0,
          reason: '4 > 3 available must not reach the provider');

      await tester.enterText(_qtyInput(11), '3');
      await tester.pump();
      expect(find.text(tr('الكمية تتجاوز المتاح ({p0})', {'p0': '3'})),
          findsNothing);
      expect(c.read(salesReturnProvider).returnQuantities[11], 3);
    });

    testWidgets('approve reaches processReturn (its confirmation dialog)',
        (tester) async {
      final c = await _pump(tester, kind: _Kind.sales);
      c.read(salesReturnProvider.notifier).updateReturnQuantity(12, 1);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('picpos_return_approve')));
      await tester.pumpAndSettle();
      expect(find.text(tr('تأكيد المرتجع')), findsOneWidget,
          reason: 'the button no longer reaches processReturn');
      await tester.tap(find.text(tr('إلغاء')));
      await tester.pumpAndSettle();
      expect(c.read(salesReturnProvider).returnQuantities[12], 1);
    });

    testWidgets('full / partial and damaged toggles reach the notifier',
        (tester) async {
      final c = await _pump(tester, kind: _Kind.sales);
      await tester.tap(find.byKey(const Key('picpos_return_full')));
      await tester.pumpAndSettle();
      final s = c.read(salesReturnProvider);
      expect(s.isFullReturn, isTrue);
      expect(s.returnQuantities, {11: 3, 12: 2},
          reason: 'full return fills the AVAILABLE qty, as before');

      await tester.tap(find.byKey(const Key('picpos_return_damaged')));
      await tester.pumpAndSettle();
      expect(c.read(salesReturnProvider).isDamaged, isTrue);
    });

    testWidgets(
        'original-invoice picker lists the period invoices and selects '
        'through notifier.selectInvoice', (tester) async {
      _salesSelected.clear();
      await _pump(tester, kind: _Kind.sales, selected: false);
      final overflows = <String>[];
      final previous = FlutterError.onError;
      FlutterError.onError = (d) {
        final s = d.toString();
        if (s.contains('overflowed')) {
          overflows.add(s.split('\n').first);
        } else {
          previous?.call(d);
        }
      };
      try {
        await tester.tap(find.byKey(const Key('picpos_return_invoice_picker')));
        await tester.pumpAndSettle();
      } finally {
        FlutterError.onError = previous;
      }
      expect(overflows, isEmpty, reason: overflows.join('\n'));
      expect(find.byType(Dialog), findsOneWidget);
      expect(find.text('# INV-0201'), findsOneWidget);

      await tester.tap(find.text('# INV-0201'));
      await tester.pumpAndSettle();
      expect(_salesSelected, [1]);
      expect(find.byType(Dialog), findsNothing);
    });

    testWidgets('«أخرى» reason opens the details panel with the free text',
        (tester) async {
      await _pump(tester, kind: _Kind.sales);
      await tester.tap(find.byKey(const Key('picpos_return_reason')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(tr('أخرى')).last);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('picpos_return_reason_notes')),
          findsOneWidget);
    });
  });

  group('purchase return', () {
    testWidgets('qty above available is rejected; within it reaches provider',
        (tester) async {
      final c = await _pump(tester, kind: _Kind.purchase);

      await tester.enterText(_qtyInput(21), '5');
      await tester.pump();
      expect(
          find.text(tr('الكمية تتجاوز المتاح ({p0})', {'p0': '3'})),
          findsOneWidget);
      expect(c.read(purchaseReturnProvider).returnQuantities[21], 0);

      await tester.enterText(_qtyInput(21), '2');
      await tester.pump();
      expect(c.read(purchaseReturnProvider).returnQuantities[21], 2);
    });

    testWidgets('approve needs a reason, then reaches processReturn',
        (tester) async {
      final c = await _pump(tester, kind: _Kind.purchase);
      c.read(purchaseReturnProvider.notifier).updateReturnQuantity(22, 1);
      await tester.pumpAndSettle();

      FilledButton approve() => tester
          .widget<FilledButton>(find.byKey(const Key('picpos_return_approve')));
      expect(approve().onPressed, isNull,
          reason: 'the reason is mandatory (owner decision)');
      expect(find.text(tr('اختر سبب المردود أولاً')), findsOneWidget);

      // The reason dropdown feeds the provider (→ repository → document row).
      await tester.tap(find.byKey(const Key('picpos_return_reason')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(tr('فائض')).last);
      await tester.pumpAndSettle();
      expect(c.read(purchaseReturnProvider).returnReason, tr('فائض'));
      expect(approve().onPressed, isNotNull);

      await tester.tap(find.byKey(const Key('picpos_return_approve')));
      await tester.pumpAndSettle();
      expect(find.text(tr('تأكيد مرتجع المشتريات')), findsOneWidget,
          reason: 'the button no longer reaches processReturn');
      await tester.tap(find.text(tr('إلغاء')));
      await tester.pumpAndSettle();
    });

    testWidgets('settlement mirrors the engine split (unpaid ⇒ payable)',
        (tester) async {
      final c = await _pump(tester, kind: _Kind.purchase);
      c.read(purchaseReturnProvider.notifier).updateReturnQuantity(22, 1);
      await tester.pumpAndSettle();
      final s = c.read(purchaseReturnProvider.notifier).settlement!;
      expect(
          find.descendant(
              of: find.byKey(const Key('picpos_return_settlement_method')),
              matching: find.text(tr(s.methodLabel))),
          findsOneWidget);
      expect(s.remainingAfter, 800);
      expect(
          find.text(
              s.remainingAfter.toStringAsFixed(AppConstants.decimalPlaces)),
          findsOneWidget,
          reason: '«الرصيد بعد التسوية» is not the engine figure');
    });
  });
}
