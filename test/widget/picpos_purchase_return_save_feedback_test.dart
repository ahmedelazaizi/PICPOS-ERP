// 🔴 Owner bug report (PicPos «مرتجع مشتريات جديد»): invoice #1 (93000.00,
// «مسددة», supplier «نقدي», «المخزن الرئيسي»), reason «فائض», four tax-exempt
// lines returned 100/50/10/70 at cost 3/4/5/6 → net 970.00, settled entirely as
// «استرداد نقدي». Pressing «تأكيد المرتجع» closed the dialog and NOTHING
// happened — no message, no saved return.
//
// Root cause: `PurchaseReturnNotifier.processReturn` swallowed every failure
// (the cash refund's `ShiftRequiredException` included) into `state.error` and
// returned `false`; the PicPos screen never read `error` and did nothing on
// `false`. And `clearError()` could not clear (`copyWith(error: null)` meant
// "no change"), so a repeated identical failure could not re-fire a listener.
//
// These tests drive the REAL notifier `processReturn` (only the repository is
// faked) through the redesigned form's «مراجعة واعتماد» → «تأكيد المرتجع».
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/core/errors/app_exceptions.dart';
import 'package:ural_erp/core/i18n/tr.dart';
import 'package:ural_erp/core/theme/app_theme.dart';
import 'package:ural_erp/data/providers/manufacturing_providers.dart';
import 'package:ural_erp/data/providers/providers.dart';
import 'package:ural_erp/domain/repositories/purchases_repository.dart';
import 'package:ural_erp/presentation/providers/purchase_return_provider.dart';
import 'package:ural_erp/presentation/purchase_returns_picpos/screens/purchase_returns_picpos_screen.dart';

final _now = DateTime(2026, 10, 1, 10);

// ── Owner fixture ─────────────────────────────────────────────────────────

PurchaseInvoiceData _ownerInvoice() => PurchaseInvoiceData(
      id: 1,
      invoiceNumber: '1',
      supplierId: 7,
      warehouseId: 1,
      invoiceDate: _now,
      subtotal: 93000,
      discount: 0,
      tax: 0,
      total: 93000,
      paid: 93000,
      paymentMethod: 'cash',
      status: 'paid',
      isLocked: false,
      isDeleted: false,
      updatedAt: _now,
      rowVersion: 1,
      createdAt: _now,
    );

Product _product(int id, String name) => Product(
      id: id, code: 'C$id', name: name, salePrice: 10, priceTalabat: 0,
      priceCareem: 0, priceAshyae: 0, wholesalePrice: 0, costPrice: 3,
      minStock: 0, currentStock: 10000, isActive: true, isLocked: false,
      trackInventory: true, trackExpiry: false, defaultShelfDays: 0,
      alertDaysBefore: 0, isSoldByWeight: false, weightUnit: 'kg',
      allowNegativeSale: false, productType: 'standard', isKitchenSet: false,
      taxRate: 0, scaleType: 'none', itemTaxType: 'V009',
      itemTaxSubtype: 'V009', createdAt: _now, updatedAt: _now, sortOrder: 0,
      rowVersion: 1, createdOnServer: false,
    );

/// (line id, product id, purchased qty, unit cost) — 93000 in total.
const _lines = [
  (31, 301, 5000.0, 3.0),
  (32, 302, 6000.0, 4.0),
  (33, 303, 6000.0, 5.0),
  (34, 304, 4000.0, 6.0),
];

/// The owner's return quantities, per line id.
const _ownerQty = {31: 100.0, 32: 50.0, 33: 10.0, 34: 70.0};

PurchaseReturnState _seed() => PurchaseReturnState(
      fromDate: _now.subtract(const Duration(days: 30)),
      toDate: _now,
      invoices: [_ownerInvoice()],
      selectedInvoice: _ownerInvoice(),
      invoiceItems: [
        for (final l in _lines)
          PurchaseInvoiceItemWithProduct(
            item: PurchaseInvoiceItem(
              id: l.$1, invoiceId: 1, productId: l.$2, quantity: l.$3,
              unitCost: l.$4, discount: 0, total: l.$3 * l.$4, taxRate: 0,
              taxAmount: 0, quantityInBase: l.$3, rowVersion: 0,
            ),
            product: _product(l.$2, 'Item ${l.$2}'),
          ),
      ],
      returnQuantities: {for (final l in _lines) l.$1: 0},
    );

/// Real `processReturn`; only the list reload / invoice pick are inert.
class _Notifier extends PurchaseReturnNotifier {
  @override
  PurchaseReturnState build() => _seed();
  @override
  Future<void> loadInvoices() async {}
  @override
  Future<void> selectInvoice(PurchaseInvoiceData invoice) async {}
}

/// Repository double: throws the queued failures in order, then succeeds.
class _Repo implements PurchasesRepository {
  _Repo([List<Object>? failures]) : failures = failures ?? [];
  final List<Object> failures;
  int calls = 0;
  List<PurchaseReturnItem> lastItems = const [];
  String? lastReason;

  @override
  Future<double> processPurchaseReturn({
    required PurchaseInvoiceData invoice,
    required List<PurchaseReturnItem> returnItems,
    String? reason,
  }) async {
    calls++;
    lastItems = returnItems;
    lastReason = reason;
    if (failures.isNotEmpty) throw failures.removeAt(0);
    return returnItems.fold<double>(
        0, (s, i) => s + i.returnQuantity * i.unitCost);
  }

  @override
  dynamic noSuchMethod(Invocation i) =>
      throw UnsupportedError('${i.memberName} not expected');
}

class _SignedInAuth extends AuthNotifier {
  @override
  AuthState build() => AuthState(
        isAuthenticated: true,
        userWithRole: UserWithRole(
          user: User(
            id: 1,
            username: 'owner',
            passwordHash: '',
            passwordSalt: '',
            displayName: 'Owner',
            defaultScreen: '0',
            isLocked: false,
            isActive: true,
            discountLimitIsPercent: true,
            forcePasswordChange: false,
            createdAt: _now,
            rowVersion: 1,
          ),
        ),
      );
}

// ── Harness ───────────────────────────────────────────────────────────────

Future<ProviderContainer> _pump(WidgetTester tester, _Repo repo) async {
  tester.view.physicalSize = const Size(1366, 768);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  I18nCatalog.setLocale(const Locale('ar', 'EG'));

  await tester.pumpWidget(ProviderScope(
    overrides: [
      purchaseReturnProvider.overrideWith(_Notifier.new),
      purchasesRepositoryProvider.overrideWithValue(repo),
      // The manager-approval threshold read is wrapped in try/catch by the
      // screen; a throwing database keeps the test off the real file DB.
      databaseProvider.overrideWith(
          (ref) => throw UnsupportedError('no database in this test')),
      authProvider.overrideWith(_SignedInAuth.new),
      warehouseNameMapProvider
          .overrideWith((ref) => const {1: 'المخزن الرئيسي'}),
      partyNamesMapProvider.overrideWith((ref, ids) async => const {7: 'نقدي'}),
    ],
    child: MaterialApp(
      theme: AppTheme.lightTheme,
      locale: const Locale('ar'),
      supportedLocales: const [Locale('ar'), Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: const PurchaseReturnsPicposScreen(),
    ),
  ));
  await tester.pumpAndSettle();
  return ProviderScope.containerOf(
      tester.element(find.byType(PurchaseReturnsPicposScreen)));
}

/// Fills the owner's form and presses «مراجعة واعتماد» → «تأكيد المرتجع».
Future<void> _fillAndConfirm(WidgetTester tester, ProviderContainer c) async {
  final notifier = c.read(purchaseReturnProvider.notifier);
  if (c.read(purchaseReturnProvider).returnReason == null) {
    notifier.updateReturnReason(tr('فائض'));
  }
  _ownerQty.forEach(notifier.updateReturnQuantity);
  await tester.pumpAndSettle();
  expect(notifier.calculateReturnTotal(), 970);
  expect(notifier.calculateReturnVat(), 0, reason: 'all lines tax-exempt');
  final s = notifier.settlement!;
  expect(s.apPortion, 0, reason: 'invoice fully paid ⇒ no AP deduction');
  expect(s.cashPortion, 970, reason: '«استرداد نقدي» of the whole return');

  await tester.tap(find.byKey(const Key('picpos_return_approve')));
  await tester.pumpAndSettle();
  expect(find.text(tr('تأكيد مرتجع المشتريات')), findsOneWidget);
  await tester.tap(find.text(tr('تأكيد المرتجع')));
  await tester.pump();
  await tester.pump();
}

/// Lets the toast's 2.5 s dismiss timer and its animation finish.
Future<void> _drainToasts(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 3));
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

  testWidgets(
      'owner scenario: confirm saves through the repository, shows success '
      'and resets the form', (tester) async {
    final repo = _Repo();
    final c = await _pump(tester, repo);
    await _fillAndConfirm(tester, c);
    await tester.pumpAndSettle();

    expect(repo.calls, 1, reason: 'confirm must reach the repository');
    expect(repo.lastReason, tr('فائض'));
    expect(
        {for (final i in repo.lastItems) i.productId: i.returnQuantity},
        {301: 100.0, 302: 50.0, 303: 10.0, 304: 70.0});
    expect(repo.lastItems.every((i) => i.taxAmount == 0), isTrue);

    expect(find.text(tr('تم مرتجع المشتريات بنجاح!')), findsOneWidget,
        reason: 'a saved return must say so');
    await tester.tap(find.text(tr('لا')));
    await tester.pumpAndSettle();

    final st = c.read(purchaseReturnProvider);
    expect(st.selectedInvoice, isNull, reason: 'the form resets after save');
    expect(st.isProcessing, isFalse);
    expect(st.error, isNull);
  });

  testWidgets(
      'a failing save shows the Arabic reason in a dialog — never a silent '
      'no-op — and keeps the form for a retry', (tester) async {
    const reason = 'لا توجد خزنة نقدية صالحة لاستلام مرتجع المشتريات. '
        'اضبط الخزائن من الإعدادات ← الخزينة (المرتجع لم يُحفَظ).';
    final repo = _Repo([Exception(reason), Exception(reason)]);
    final c = await _pump(tester, repo);

    for (var attempt = 1; attempt <= 2; attempt++) {
      await _fillAndConfirm(tester, c);
      await tester.pumpAndSettle();
      expect(repo.calls, attempt);
      expect(find.byKey(const Key('purchase_return_save_error')),
          findsOneWidget,
          reason: 'attempt $attempt: the failure must be visible '
              '(the second, identical failure used to be silent too)');
      expect(find.text(tr('تعذّر حفظ مرتجع المشتريات')), findsOneWidget);
      expect(find.text(reason), findsOneWidget,
          reason: 'the message is shown without the "Exception: " prefix');
      await tester.tap(find.text(tr('حسناً')));
      await tester.pumpAndSettle();

      final st = c.read(purchaseReturnProvider);
      expect(st.selectedInvoice?.id, 1, reason: 'nothing saved ⇒ keep form');
      expect(st.returnQuantities, _ownerQty);
      expect(st.isProcessing, isFalse);
      expect(st.error, isNull, reason: 'clearError() must really clear');
    }
    expect(find.text(tr('تم مرتجع المشتريات بنجاح!')), findsNothing);
    await _drainToasts(tester);
  });

  testWidgets(
      'cash refund without an open shift offers to open one instead of '
      'failing silently; cancelling says so', (tester) async {
    final repo = _Repo([ShiftRequiredException(cashAmount: 970)]);
    final c = await _pump(tester, repo);
    await _fillAndConfirm(tester, c);
    await tester.pumpAndSettle();

    expect(repo.calls, 1);
    expect(find.text(tr('افتتاح وردية جديدة')), findsOneWidget,
        reason: 'ShiftRequiredException must reach the open-shift prompt');
    await tester.tap(find.text(tr('إلغاء')).last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text(tr('أُلغي المرتجع — لم تُفتَح وردية')), findsOneWidget,
        reason: 'declining the shift must be reported, not silent');
    final st = c.read(purchaseReturnProvider);
    expect(st.isProcessing, isFalse, reason: 'the action bar is not stuck');
    expect(st.selectedInvoice?.id, 1);
    await _drainToasts(tester);
  });
}
