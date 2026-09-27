import 'dart:convert';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:ural_erp/data/database/pg_config.dart';
import 'package:ural_erp/data/repositories/drift_accounting_repository.dart';
import 'package:ural_erp/data/repositories/treasury_repository_impl.dart';
import 'package:ural_erp/services/accounting_service.dart';
import 'package:ural_erp/domain/entities/accounting_entities.dart';
import 'package:ural_erp/core/permissions/permission_codes.dart';
import 'package:ural_erp/data/providers/providers.dart';
import 'package:ural_erp/domain/usecases/treasury/create_voucher_usecase.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

void main() {
  late AppDatabase db;
  late int restrictedUserId;

  setUp(() async {
    db = AppDatabase.forTesting();
    await db.syncDefaultAccounts();
    final roleId = await db.into(db.roles).insert(
          RolesCompanion.insert(
            name: 'دور أمني للاختبار',
            isSystemRole: const Value(false),
          ),
        );
    restrictedUserId = await db.createUser(
      username: 'security-gates-user',
      password: 'pw',
      displayName: 'مستخدم اختبار الصلاحيات',
      roleId: roleId,
    );
  });

  tearDown(() => db.close());

  test('system voucher paths do not require manual-entry permissions', () async {
    await db.createReceiptVoucher(
      amount: 1,
      category: 'test',
      userId: restrictedUserId,
    );
    await db.createPaymentVoucher(
      amount: 1,
      category: 'test',
      userId: restrictedUserId,
    );
  });

  test('manual receipt and payment vouchers enforce their permissions at the use-case boundary', () async {
    final allowedRoleId = await db.into(db.roles).insert(
      RolesCompanion.insert(
        name: 'دور سندات يدوية',
        isSystemRole: const Value(false),
      ),
    );
    final allowedUserId = await db.createUser(
      username: 'voucher-allowed-${DateTime.now().microsecondsSinceEpoch}',
      // Distinct from the setUp user's password: the system (correctly)
      // refuses two accounts sharing one password.
      password: 'pw-allowed',
      displayName: 'مستخدم سندات',
      roleId: allowedRoleId,
    );
    for (final code in [
      PermissionCodes.treasuryReceiptsCreate,
      PermissionCodes.treasuryPaymentsCreate,
    ]) {
      final permission = await (db.select(db.permissions)
            ..where((p) => p.code.equals(code))
            ..limit(1))
          .getSingle();
      await db.addPermissionToRole(allowedRoleId, permission.id);
    }

    final container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(db),
        // Build the accounting service with a repository instance that does
        // not itself come from accountingServiceProvider. The production
        // providers form a lazy cycle through TreasuryRepositoryImpl's
        // accounting-service accessor; this boundary test needs the real
        // repository but must avoid resolving that cycle during setup.
        accountingServiceProvider.overrideWith((ref) {
          final treasury = TreasuryRepositoryImpl(db, ref);
          return AccountingService(
            ref.watch(accountingRepositoryProvider),
            ref.watch(partiesRepositoryProvider),
            treasury,
            ref.watch(productRepositoryProvider),
            ref.watch(inventoryRepositoryProvider),
            ref.watch(settingsRepositoryProvider),
            ref.watch(auditRepositoryProvider),
          );
        }),
      ],
    );
    addTearDown(container.dispose);
    final useCase = CreateVoucherUseCase(
      container.read(treasuryRepositoryProvider),
    );

    await expectLater(
      () => useCase.createReceipt(
        amount: 1, category: 'اختبار', safeId: 1, userId: restrictedUserId),
      throwsA(isA<PermissionDeniedException>()),
    );
    await expectLater(
      () => useCase.createPayment(
        amount: 1, category: 'اختبار', safeId: 1, userId: restrictedUserId),
      throwsA(isA<PermissionDeniedException>()),
    );

    await db.openShift(allowedUserId, 0);
    await useCase.createReceipt(
      amount: 1, category: 'اختبار', safeId: 1, userId: allowedUserId);
    await useCase.createPayment(
      amount: 1, category: 'اختبار', safeId: 1, userId: allowedUserId);
  });

  test('legacy postgres password migrates to secure storage', () async {
    SharedPreferences.setMockInitialValues({
      'pg_config': jsonEncode({
        'host': 'legacy-host',
        'port': 5432,
        'database': 'db',
        'username': 'user',
        'password': 'legacy-secret',
      }),
    });
    FlutterSecureStorage.setMockInitialValues({});

    final config = await PostgresConfig.load();
    final prefs = await SharedPreferences.getInstance();
    final rewritten =
        jsonDecode(prefs.getString('pg_config')!) as Map<String, dynamic>;
    const storage = FlutterSecureStorage();

    expect(config.password, 'legacy-secret');
    expect(rewritten.containsKey('password'), isFalse);
    expect(await storage.read(key: 'pg_password'), 'legacy-secret');
  });

  test('manual journal creation is gated while auto-post is allowed', () async {
    final accounts = await (db.select(db.accounts)
          ..where((account) => account.accountNature.equals('detail')))
        .get();
    final repository = DriftAccountingRepository(db);
    final lines = [
      JournalLine(accountId: accounts[0].id, debit: 2),
      JournalLine(accountId: accounts[1].id, credit: 2),
    ];
    await expectLater(
      () => repository.createJournalEntry(
        description: 'قيد يدوي محمي',
        date: DateTime.now(),
        lines: lines,
        createdBy: restrictedUserId,
        isAutoPosted: false,
      ),
      throwsA(isA<PermissionDeniedException>()),
    );

    await repository.createJournalEntry(
      description: 'قيد آلي مسموح',
      date: DateTime.now(),
      lines: lines,
      createdBy: restrictedUserId,
      isAutoPosted: true,
    );
  });
}
