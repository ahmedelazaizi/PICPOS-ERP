import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_api_client/picpos_api_client.dart';
import 'package:picpos_erp/core/constants/app_constants.dart';
import 'package:picpos_erp/data/database/database.dart';
import 'package:picpos_erp/domain/entities/accounting_entities.dart';
import 'package:picpos_erp/services/admin_snapshots/admin_snapshot_builder.dart';
import 'package:picpos_erp/services/admin_snapshots/admin_user_mirror.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase db;
  late PayloadSigner signer;
  final at = DateTime(2026, 2, 10, 12);

  setUp(() async {
    db = AppDatabase.forTesting();
    signer = await PayloadSigner.fromSeed(
      List<int>.generate(32, (index) => index),
    );
  });
  tearDown(() => db.close());

  test('seeded ledger net profit matches desktop income statement', () async {
    await db.syncDefaultAccounts();
    final cash = (await db.getAccountByCode('1111'))!.id;
    final revenue = (await db.getAccountByCode('4121'))!.id;
    final branch = await db.into(db.branches).insert(
      BranchesCompanion.insert(name: 'Test branch'),
    );
    await db.createJournalEntry(
      description: 'snapshot income',
      date: DateTime(2026, 2, 2),
      branchId: branch,
      lines: [
        JournalLine(accountId: cash, debit: 150),
        JournalLine(accountId: revenue, credit: 150),
      ],
    );
    final income = await db.getIncomeStatement(
      DateTime(2026, 2),
      DateTime(2026, 2, 10, 23, 59, 59),
    );
    final snapshots = await AdminSnapshotBuilder(db, signer).buildKpis(at);
    final profit = snapshots.firstWhere(
      (snapshot) => snapshot['kind'] == SnapshotKinds.profitMonth,
    );
    final payload = profit['payload'] as Map;
    expect(
      payload['netProfit'],
      (income['netProfit'] as num).toStringAsFixed(AppConstants.decimalPlaces),
    );
  });

  test('desktop microsecond snapshot verifies after cloud millisecond round trip', () async {
    final snapshot = await AdminSnapshotBuilder(db, signer)
        .cash(DateTime.utc(2026, 10, 3, 22, 21, 35, 328, 404));
    final serverAsOf = DateTime.fromMillisecondsSinceEpoch(
      DateTime.parse(snapshot['asOf'] as String).millisecondsSinceEpoch,
      isUtc: true,
    ).toIso8601String();
    final verifier = PayloadVerifier.fromBase64(await signer.publicKeyBase64());
    expect(
      await verifySnapshot(
        SignedPayload.fromJson({...snapshot, 'asOf': serverAsOf}),
        verifier,
      ),
      isTrue,
    );
  });

  test(
    'mobile user projection omits desktop hash and includes disabled users',
    () async {
      await db
          .into(db.users)
          .insert(
            UsersCompanion.insert(
              username: 'enabled',
              passwordHash: 'desktop-secret',
              displayName: 'Enabled',
              globalId: const Value('enabled-id'),
            ),
          );
      await db
          .into(db.users)
          .insert(
            UsersCompanion.insert(
              username: 'disabled',
              passwordHash: 'another-desktop-secret',
              displayName: 'Disabled',
              globalId: const Value('disabled-id'),
              isActive: const Value(false),
            ),
          );
      final users = await AdminUserMirror(db).buildUsers();
      expect(
        users.map((user) => user['globalId']),
        containsAll(['enabled-id', 'disabled-id']),
      );
      expect(
        users.firstWhere(
          (user) => user['globalId'] == 'disabled-id',
        )['mobileEnabled'],
        isFalse,
      );
      expect(users.toString(), isNot(contains('desktop-secret')));
      expect(users.toString(), isNot(contains('another-desktop-secret')));
      expect(users.every((user) => !user.containsKey('passwordHash')), isTrue);
    },
  );
}
