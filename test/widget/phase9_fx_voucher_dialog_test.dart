import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/data/providers/providers.dart';
import 'package:picpos_erp/l10n/app_localizations.dart';
import 'package:picpos_erp/presentation/treasury_picpos/widgets/payment_voucher_dialog_picpos.dart';

Party _party({int? currencyId}) => Party(
      id: 7,
      name: 'Phase 9 Supplier',
      isCustomer: false,
      isSupplier: true,
      isDeliveryCompany: false,
      isFavorite: false,
      balance: 0,
      creditLimit: 0,
      paymentTermsDays: 0,
      earlyPaymentDiscountPct: 0,
      earlyPaymentDiscountDays: 0,
      fixedDiscount: 0,
      priceLevel: 'default',
      accountId: null,
      currencyId: currencyId,
      isActive: true,
      createdAt: DateTime(2026, 1, 1),
      isGlobal: true,
      isSystemDefault: false,
      rowVersion: 0,
    );

Future<void> _pumpDialog(
  WidgetTester tester, {
  required AppDatabase db,
  required Party party,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        allPartiesProvider.overrideWith((ref) => Stream.value([party])),
        scopedSafesProvider.overrideWith(
          (ref) => Stream.value(const [
            SafeData(
              id: 1,
              name: 'Phase 9 Safe',
              safeType: 'cash',
              balance: 1000,
              isDefault: true,
              isActive: true,
            ),
          ]),
        ),
      ],
      child: MaterialApp(
        localizationsDelegates: [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [Locale('ar')],
        locale: const Locale('ar'),
        home: Scaffold(body: PaymentVoucherDialogPicpos(initialParty: party)),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  late AppDatabase db;
  late int usdId;

  setUp(() async {
    db = AppDatabase.forTesting();
    final currency = await db.into(db.currencies).insertReturning(
          CurrenciesCompanion.insert(
            code: 'USD',
            name: 'US Dollar',
            symbol: '\$',
            exchangeRate: const Value(50),
            globalId: const Value('phase9-widget-usd'),
          ),
        );
    usdId = currency.id;
  });

  tearDown(() => db.close());

  testWidgets('foreign fields appear only for a foreign-currency party',
      (tester) async {
    await _pumpDialog(tester, db: db, party: _party(currencyId: usdId));
    expect(find.text('المبلغ الأجنبي'), findsOneWidget);
    expect(find.text('سعر الدفع'), findsOneWidget);
  });

  testWidgets('local-currency party does not show foreign fields',
      (tester) async {
    await _pumpDialog(tester, db: db, party: _party());
    expect(find.text('المبلغ الأجنبي'), findsNothing);
    expect(find.text('سعر الدفع'), findsNothing);
  });
}
