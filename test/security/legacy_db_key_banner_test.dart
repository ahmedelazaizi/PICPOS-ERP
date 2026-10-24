// SEC-005 — upgraded installs that still use the legacy device-derived SQLCipher
// key show a persistent, non-dismissable admin warning until migrated.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/data/providers/providers.dart';
import 'package:picpos_erp/presentation/settings_picpos/widgets/database_encryption_block.dart';
import 'package:picpos_erp/presentation/widgets/legacy_db_key_banner.dart';
import 'package:picpos_erp/services/db_encryption_actions.dart';

class _FakeActions implements DbEncryptionActions {
  _FakeActions(this.state);
  final DbEncryptionState state;
  @override
  Future<DbEncryptionStatus> status() async => DbEncryptionStatus(state: state);
  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget _app({
  required DbEncryptionState state,
  required List<String> perms,
  bool supported = true,
}) =>
    ProviderScope(
      overrides: [
        dbEncryptionSupportedProvider.overrideWithValue(supported),
        dbEncryptionActionsProvider.overrideWithValue(_FakeActions(state)),
        currentUserPermissionsProvider.overrideWith((ref) async => perms),
      ],
      child: const MaterialApp(home: Scaffold(body: Column(children: [LegacyDbKeyBanner()]))),
    );

void main() {
  testWidgets('admin on the legacy key sees the warning', (tester) async {
    await tester.pumpWidget(_app(state: DbEncryptionState.legacy, perms: ['system_admin']));
    await tester.pumpAndSettle();
    expect(find.textContaining('مفتاح قديم'), findsOneWidget);
  });

  testWidgets('the banner has no close / dismiss button', (tester) async {
    await tester.pumpWidget(_app(state: DbEncryptionState.legacy, perms: ['*']));
    await tester.pumpAndSettle();
    expect(find.byType(IconButton), findsNothing);
    expect(find.byType(TextButton), findsNothing);
    expect(find.byIcon(Icons.close), findsNothing);
  });

  testWidgets('non-admin users never see it', (tester) async {
    await tester.pumpWidget(_app(state: DbEncryptionState.legacy, perms: ['sales_view']));
    await tester.pumpAndSettle();
    expect(find.byType(Text), findsNothing);
  });

  testWidgets('migrated / requested / unsupported installs show nothing', (tester) async {
    for (final s in [DbEncryptionState.migrated, DbEncryptionState.pendingConfirm, DbEncryptionState.requested]) {
      await tester.pumpWidget(_app(state: s, perms: ['system_admin']));
      await tester.pumpAndSettle();
      expect(find.byType(Text), findsNothing, reason: '$s');
    }
    await tester.pumpWidget(_app(state: DbEncryptionState.legacy, perms: ['system_admin'], supported: false));
    await tester.pumpAndSettle();
    expect(find.byType(Text), findsNothing);
  });
}
