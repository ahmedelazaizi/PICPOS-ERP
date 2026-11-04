// المرحلة 7: حوار «مراجعة الأرصدة» يعرض مقارنة الصندوق بالأستاذ ومعها 1111.
// الأرقام هي أرقام قاعدة التحقق الحي 2026-11-03 حرفياً.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:picpos_erp/data/providers/providers.dart';
import 'package:picpos_erp/presentation/treasury_picpos/widgets/cash_box_ledger_reconciliation_card.dart';

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  testWidgets('card lists linked cash box vs ledger and unlinked 1111', (tester) async {
    final prev = FlutterError.onError;
    FlutterError.onError = (d) {
      if (d.exceptionAsString().contains('google_fonts')) return;
      prev?.call(d);
    };
    addTearDown(() => FlutterError.onError = prev);

    await tester.pumpWidget(ProviderScope(
      overrides: [
        cashBoxLedgerReconciliationProvider.overrideWith((ref) async => const [
              CashBoxLedgerComparison(
                safeName: 'صندوق الكاشير',
                safeBalance: 95.86,
                accountCode: '111-00001',
                ledgerBalance: 144.79,
                isUnlinkedCashControl: false,
              ),
              CashBoxLedgerComparison(
                safeName: null,
                safeBalance: 0,
                accountCode: '1111',
                ledgerBalance: -48.93,
                isUnlinkedCashControl: true,
              ),
            ]),
      ],
      child: const MaterialApp(
          home: Scaffold(body: CashBoxLedgerReconciliationCard())),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(ExpansionTile));
    await tester.pumpAndSettle();

    expect(find.textContaining('111-00001'), findsOneWidget);
    expect(find.textContaining('1111'), findsWidgets);
    expect(find.textContaining('95.86'), findsOneWidget);
    expect(find.textContaining('144.79'), findsOneWidget);
    expect(find.textContaining('-48.93'), findsWidgets);
  });

  test('treasury reconciliation dialog renders the card', () {
    final src = File(
            'lib/presentation/treasury_picpos/screens/treasury_picpos_screen.dart')
        .readAsStringSync();
    expect(src, contains('const CashBoxLedgerReconciliationCard()'));
  });
}
