import 'dart:convert';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/core/permissions/permission_codes.dart';
import 'package:picpos_erp/data/providers/providers.dart';
import 'package:picpos_erp/domain/entities/cart_item_entity.dart';
import 'package:picpos_erp/services/conflict_resolution_service.dart';
import 'package:picpos_erp/services/delta_pull_service.dart';
import 'package:picpos_erp/services/invoice_integrity_service.dart';

void main() {
  late AppDatabase db;
  String? integritySecret;

  setUp(() async {
    db = AppDatabase.forTesting();
    await InvoiceIntegrityService.initialize(
      readSetting: (_) async => integritySecret,
      writeSetting: (_, value) async => integritySecret = value,
    );
    ConflictResolutionService.instance.initialize(db);
    DeltaPullService.instance.initialize(db);
  });

  tearDown(() => db.close());

  Future<int> userWithModifyPermission() async {
    final roleId = await db.into(db.roles).insert(RolesCompanion.insert(
          name: 'Phase 6 invoice editor',
          isSystemRole: const Value(false),
        ));
    final userId = await db.createUser(
      username: 'phase6-${DateTime.now().microsecondsSinceEpoch}',
      password: 'pw',
      displayName: 'Phase 6 editor',
      roleId: roleId,
    );
    final permission = await (db.select(db.permissions)
          ..where((row) => row.code.equals(PermissionCodes.modifyLockedInvoice))
          ..limit(1))
        .getSingle();
    await db.addPermissionToRole(roleId, permission.id);
    return userId;
  }

  Future<(int, int, int)> seedPostedSale(int userId) async {
    final warehouse = (await db.getDefaultWarehouse())!;
    final productId = await db.insertProduct(ProductsCompanion.insert(
      code: 'PH6-${DateTime.now().microsecondsSinceEpoch}',
      name: 'Phase 6 product',
      salePrice: const Value(100.0),
      costPrice: const Value(0.0),
      trackInventory: const Value(false),
    ));
    final invoiceId = await db.createSalesInvoice(
      invoiceNumber: 'PH6-${DateTime.now().microsecondsSinceEpoch}',
      warehouseId: warehouse.id,
      userId: userId,
      subtotal: 200,
      discount: 0,
      tax: 0,
      total: 200,
      paid: 200,
      paymentMethod: 'cash',
      items: [
        SalesInvoiceItemsCompanion.insert(
          invoiceId: 0,
          productId: productId,
          quantity: 2,
          unitPrice: 100,
          total: 200,
        ),
      ],
    );
    final invoice = await db.getSalesInvoiceById(invoiceId);
    await db.autoPostCashSale(invoice!);
    return (invoiceId, warehouse.id, productId);
  }

  Future<SalesInvoiceData> rawSalesInvoice(int invoiceId) =>
      (db.select(db.salesInvoices)..where((row) => row.id.equals(invoiceId)))
          .getSingle();

  bool verifies(SalesInvoiceData invoice) =>
      InvoiceIntegrityService.verifySalesInvoiceHash(
        storedHash: invoice.integrityHash!,
        invoiceNumber: invoice.invoiceNumber,
        invoiceDate: invoice.invoiceDate,
        total: invoice.total,
        subtotal: invoice.subtotal,
        discount: invoice.discount,
        tax: invoice.tax,
        paid: invoice.paid,
        customerId: invoice.customerId,
        userId: invoice.userId,
        paymentMethod: invoice.paymentMethod,
      );

  test('authorized locked edit re-signs invoice and direct tamper fails verification',
      () async {
    final userId = await userWithModifyPermission();
    final (invoiceId, warehouseId, productId) = await seedPostedSale(userId);
    final container = ProviderContainer(
      overrides: [databaseProvider.overrideWithValue(db)],
    );
    addTearDown(container.dispose);

    await container.read(salesRepositoryProvider).updateFullSalesInvoice(
          invoiceId: invoiceId,
          userId: userId,
          warehouseId: warehouseId,
          paid: 300,
          paymentMethod: 'cash',
          items: [
            CartItemEntity(
              productId: productId,
              productName: 'Phase 6 product',
              productCode: 'PH6',
              quantity: 3,
              unitPrice: 100,
            ),
          ],
        );

    final edited = await rawSalesInvoice(invoiceId);
    expect(edited.isLocked, isTrue);
    expect(edited.integrityHash, startsWith('v2:'));
    expect(verifies(edited), isTrue);

    await db.customStatement(
      'UPDATE sales_invoices SET total = 999 WHERE id = ?',
      [invoiceId],
    );
    final tampered = await rawSalesInvoice(invoiceId);
    expect(verifies(tampered), isFalse);
  });

  test('financial pending change records both versions and blocks server soft-delete',
      () async {
    final partyId = await db.into(db.parties).insert(
      PartiesCompanion.insert(
        name: 'Phase 6 party',
        globalId: const Value('phase6-party-local'),
      ),
    );
    final clientPayload = jsonEncode({
      'id': partyId,
      'global_id': 'phase6-party-local',
      'name': 'Local edit',
    });
    await db.into(db.syncOutbox).insert(
      SyncOutboxCompanion.insert(
        targetTable: 'parties',
        recordId: partyId.toString(),
        operation: 'update',
        payload: clientPayload,
      ),
    );

    await DeltaPullService.instance.upsertRowForTest('parties', {
      'id': partyId,
      'global_id': 'phase6-party-local',
      'name': 'Server edit',
      'deleted_at': 1700000000,
      'row_version': 2,
    });

    final local = await (db.select(db.parties)
          ..where((row) => row.id.equals(partyId)))
        .getSingle();
    final conflicts = await (db.select(db.syncConflictLog)
          ..where((row) => row.conflictTable.equals('parties')))
        .get();
    final pending = await (db.select(db.syncOutbox)
          ..where((row) => row.recordId.equals(partyId.toString())))
        .getSingle();

    expect(local.deletedAt, isNull);
    expect(conflicts.single.resolution, 'pending_review');
    expect(conflicts.single.clientPayload, clientPayload);
    expect(conflicts.single.serverPayload, contains('Server edit'));
    expect(pending.status, 'pending');
  });

  test('id fallback refuses a local row with a different global_id', () async {
    await db.into(db.products).insert(
      ProductsCompanion.insert(
        id: const Value(41),
        code: 'PH6-ID',
        name: 'Local product',
        globalId: const Value('local-global-id'),
      ),
    );

    final apply = await ConflictResolutionService.instance.shouldApplyServerRow(
      'products',
      {
        'id': 41,
        'global_id': 'server-global-id',
        'row_version': 1,
      },
      policy: ConflictPolicy.newerWins,
    );

    expect(apply, isTrue);
  });

  test('equal row versions within clock skew prefer the server', () async {
    await db.customStatement(
      "INSERT INTO parties (name, global_id, row_version, last_modified_at) "
      "VALUES ('Clock local', 'phase6-clock', 4, 1700000000)",
    );

    final apply = await ConflictResolutionService.instance.shouldApplyServerRow(
      'parties',
      {
        'id': 1,
        'global_id': 'phase6-clock',
        'row_version': 4,
        'last_modified_at': 1700000050,
        'origin_client_id': 'server',
      },
      policy: ConflictPolicy.newerWins,
    );

    expect(apply, isTrue);
  });
}
