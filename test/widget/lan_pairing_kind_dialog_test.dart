// M1: the administrator chooses the device kind (and, for branch devices, the
// branch) when issuing a pairing code; the new device picks neither.
import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:picpos_erp/data/database/database.dart';
import 'package:picpos_erp/presentation/widgets/settings/lan_pairing_kind_dialog.dart';

void main() {
  late AppDatabase db;
  late List<Branche> branches;

  setUp(() async {
    await TestWidgetsFlutterBinding.ensureInitialized().runAsync(() async {
      db = AppDatabase.forTesting();
      await db.into(db.branches).insert(
          BranchesCompanion.insert(name: 'Branch North', code: const Value('N1')));
      branches = await db.select(db.branches).get();
    });
  });

  tearDown(() async {
    await TestWidgetsFlutterBinding.ensureInitialized()
        .runAsync(() => db.close());
  });

  Future<LanPairingKindChoice?> open(WidgetTester tester) async {
    LanPairingKindChoice? result;
    var done = false;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () async {
              result = await showLanPairingKindDialog(context, branches);
              done = true;
            },
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(done, isFalse);
    return result;
  }

  testWidgets('client (default) needs a branch before Continue is enabled',
      (tester) async {
    await open(tester);
    final cont = find.widgetWithText(FilledButton, 'متابعة');
    expect(tester.widget<FilledButton>(cont).onPressed, isNull);
    await tester.tap(find.byType(DropdownButtonFormField<int>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Branch North').last);
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(cont).onPressed, isNotNull);
  });

  testWidgets('a mirror code is branchless: no branch picker, Continue is '
      'enabled at once', (tester) async {
    await open(tester);
    await tester.tap(find.text('كونسول مدير الفروع (المرآة)'));
    await tester.pumpAndSettle();
    expect(find.byType(DropdownButtonFormField<int>), findsNothing);
    final cont = find.widgetWithText(FilledButton, 'متابعة');
    expect(tester.widget<FilledButton>(cont).onPressed, isNotNull);
  });

  testWidgets('Cancel returns nothing', (tester) async {
    await open(tester);
    await tester.tap(find.text('إلغاء'));
    await tester.pumpAndSettle();
    expect(find.text('متابعة'), findsNothing);
  });
}
