import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:picpos_erp/presentation/widgets/settings/lan_pairing_dialog.dart';
import 'package:picpos_erp/services/api/lan_pairing_service.dart';

void main() {
  testWidgets('pairing dialog shows the one-time code', (tester) async {
    final offer = PairingOffer(
      code: 'ABCD2345',
      expiresAt: DateTime.now().add(const Duration(minutes: 10)),
      qrPayload: '{"pairingCode":"ABCD2345"}',
    );
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: LanPairingDialog(offer: offer)),
    ));
    expect(find.text('ABCD2345'), findsOneWidget);
    expect(find.text('إقران جهاز'), findsOneWidget);
  });
}
