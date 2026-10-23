import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/domain/models/picpos_party_view.dart';
import 'package:ural_erp/presentation/parties_picpos/screens/parties_picpos_screen.dart';

PartyCardActions _actions() => PartyCardActions(
      onStatement: (_) {},
      onEdit: (_) {},
      onVoucher: (_) {},
      onDelete: (_) {},
      onWhatsApp: (_) {},
    );

PicPosPartyCard _party() => const PicPosPartyCard(
      id: 1,
      name: 'عميل اختبار',
      balance: 1250,
      creditLimit: 2000,
      isCustomer: true,
    );

void main() {
  testWidgets('party figures stay masked without figure access', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PartyCard(
            party: _party(),
            actions: _actions(),
            canSeeFigures: false,
          ),
        ),
      ),
    );

    expect(find.text('عميل اختبار'), findsOneWidget);
    expect(find.textContaining('1250'), findsNothing);
    expect(find.textContaining('2000'), findsNothing);
    expect(find.text('—'), findsNWidgets(2));
  });

  testWidgets('party figures are visible with figure access', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PartyCard(
            party: _party(),
            actions: _actions(),
            canSeeFigures: true,
          ),
        ),
      ),
    );

    expect(find.textContaining('1250'), findsOneWidget);
    expect(find.textContaining('2000'), findsOneWidget);
  });
}
