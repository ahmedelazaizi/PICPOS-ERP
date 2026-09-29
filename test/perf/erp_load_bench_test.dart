@Tags(['perf'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide isNotNull;
import 'package:shelf/shelf.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/database/database.dart';
import 'package:ural_erp/data/repositories/inventory_repository_impl.dart';
import 'package:ural_erp/services/api/api_sales_handler.dart';
import 'package:ural_erp/services/api/api_user_context.dart';

/// Repeatable disk-backed ERP/POS benchmark.
///
/// `PERF_PROFILE=smoke` is intentionally small enough for local iteration.
/// `PERF_PROFILE=full` uses the requested 20k/5k/150k/10k dataset.
/// The seed uses the real Drift schema and real DAO posting for the measured
/// transactions; the historical bulk is inserted with consistent invoices,
/// four-line items, balanced journal entries, and aggregate stock movements.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('disk-backed workload reports latency and integrity metrics', () async {
    final profile = _BenchProfile.fromEnvironment();
    final context = await _BenchContext.open(profile);
    final report = <String, _Metric>{};
    try {
      await context.seed();
      stdout.writeln(
        'PERF_DATASET|profile=${profile.name}|products=${profile.products}|'
        'parties=${profile.parties}|sales=${profile.sales}|purchases=${profile.purchases}|'
        'seedSeconds=${context.seedSeconds.toStringAsFixed(2)}',
      );

      await _measureHotPaths(context, report);
      await _measureConcurrency(context, report);
      await _verifyIntegrity(context);
      await _measureColdOpen(context, report);

      for (final entry in report.entries) {
        stdout.writeln('PERF_METRIC|${entry.key}|${entry.value.format()}');
      }
      stdout.writeln('PERF_ERRORS|${context.errors.join(' || ')}');
    } finally {
      await context.dispose();
    }
  }, timeout: const Timeout(Duration(minutes: 110)));
}

class _BenchProfile {
  final String name;
  final int products;
  final int parties;
  final int sales;
  final int purchases;
  final int samples;
  final int concurrency;
  final Duration concurrencyDuration;

  const _BenchProfile({
    required this.name,
    required this.products,
    required this.parties,
    required this.sales,
    required this.purchases,
    required this.samples,
    required this.concurrency,
    required this.concurrencyDuration,
  });

  factory _BenchProfile.fromEnvironment() {
    final env = Platform.environment;
    final full = env['PERF_PROFILE']?.toLowerCase() == 'full';
    final requested = full
        ? const _BenchProfile(
            name: 'full',
            products: 20000,
            parties: 5000,
            sales: 150000,
            purchases: 10000,
            samples: 20,
            concurrency: 20,
            concurrencyDuration: Duration(seconds: 60),
          )
        : const _BenchProfile(
            name: 'smoke',
            products: 500,
            parties: 100,
            sales: 1000,
            purchases: 100,
            samples: 8,
            concurrency: 5,
            concurrencyDuration: Duration(seconds: 5),
          );
    final seconds = int.tryParse(env['PERF_CONCURRENCY_SECONDS'] ?? '');
    final workers = int.tryParse(env['PERF_CONCURRENCY_CLIENTS'] ?? '');
    return _BenchProfile(
      name: env['PERF_PROFILE'] ?? requested.name,
      products: int.tryParse(env['PERF_PRODUCTS'] ?? '') ?? requested.products,
      parties: int.tryParse(env['PERF_PARTIES'] ?? '') ?? requested.parties,
      sales: int.tryParse(env['PERF_SALES'] ?? '') ?? requested.sales,
      purchases: int.tryParse(env['PERF_PURCHASES'] ?? '') ?? requested.purchases,
      samples: int.tryParse(env['PERF_SAMPLES'] ?? '') ?? requested.samples,
      concurrency: workers ?? requested.concurrency,
      concurrencyDuration: Duration(seconds: seconds ?? requested.concurrencyDuration.inSeconds),
    );
  }
}

class _BenchContext {
  final _BenchProfile profile;
  final Directory directory;
  AppDatabase db;
  final List<String> errors = [];
  late int productBase;
  late int partyBase;
  late int salesBase;
  late int purchaseBase;
  late int salesJournalBase;
  late int purchaseJournalBase;
  late int warehouseId;
  late int branchId;
  late int userId;
  late int busyPartyId;
  late int cashSafeId;
  late int cashAccountId;
  double seedSeconds = 0;
  int saleSequence = 0;
  int voucherSequence = 0;
  late DateTime shiftStart;
  late DateTime shiftEnd;

  _BenchContext._(this.profile, this.directory, this.db);

  static Future<_BenchContext> open(_BenchProfile profile) async {
    final directory = await Directory.systemTemp.createTemp('ural_erp_perf_');
    final file = File('${directory.path}${Platform.pathSeparator}perf.db');
    final db = AppDatabase.withExecutor(
      NativeDatabase(
        file,
        setup: (database) {
          database.execute('PRAGMA foreign_keys = ON');
          database.execute('PRAGMA journal_mode = WAL');
          database.execute('PRAGMA synchronous = NORMAL');
          database.execute('PRAGMA busy_timeout = 60000');
          database.execute('PRAGMA cache_size = -16000');
          database.execute('PRAGMA temp_store = memory');
        },
      ),
    );
    return _BenchContext._(profile, directory, db);
  }

  Future<void> seed() async {
    final timer = Stopwatch()..start();
    final warehouse = await db.getDefaultWarehouse();
    if (warehouse == null) {
      throw StateError('DatabaseStartup did not seed a default warehouse');
    }
    warehouseId = warehouse.id;
    branchId = warehouse.branchId ?? 0;
    final user = await db.customSelect('SELECT id FROM users ORDER BY id LIMIT 1').getSingle();
    userId = user.read<int>('id');
    final safe = await db.getDefaultSafeByType('cash');
    if (safe == null) throw StateError('DatabaseStartup did not seed a cash safe');
    cashSafeId = safe.id;
    final account = await db.customSelect("SELECT id FROM accounts WHERE code = '1111' LIMIT 1").getSingle();
    cashAccountId = account.read<int>('id');
    busyPartyId = 0;

    await db.transaction(() async {
      final oldProduct = await db.customSelect("SELECT COALESCE(MAX(id), 0) AS id FROM products").getSingle();
      productBase = oldProduct.read<int>('id');
      await db.customStatement('''
        WITH RECURSIVE seq(n) AS (
          SELECT 1 UNION ALL SELECT n + 1 FROM seq WHERE n < ${profile.products}
        )
        INSERT INTO products
          (code, barcode, name, search_name, sale_price, cost_price,
           min_stock, current_stock, is_active, track_inventory, created_on_server)
        SELECT
          'PERF-P-' || printf('%05d', n),
          '890PERF' || printf('%08d', n),
          'Performance Product ' || printf('%05d', n),
          'performance product ' || printf('%05d', n),
          100.0, 60.0, 10.0,
          100000.0 - CAST(${profile.sales} / ${profile.products} AS INTEGER)
            - CASE WHEN n <= (${profile.sales} % ${profile.products}) THEN 1 ELSE 0 END,
          1, 1, 1
        FROM seq
      ''');
      final oldParty = await db.customSelect("SELECT COALESCE(MAX(id), 0) AS id FROM parties").getSingle();
      partyBase = oldParty.read<int>('id');
      await db.customStatement('''
        WITH RECURSIVE seq(n) AS (
          SELECT 1 UNION ALL SELECT n + 1 FROM seq WHERE n < ${profile.parties}
        )
        INSERT INTO parties (code, name, is_customer, is_supplier, is_active, is_global)
        SELECT
          'PERF-C-' || printf('%05d', n),
          'Performance Customer ' || printf('%05d', n),
          1, 1, 1, 1
        FROM seq
      ''');
      busyPartyId = partyBase + 1;

      final oldSale = await db.customSelect("SELECT COALESCE(MAX(id), 0) AS id FROM sales_invoices").getSingle();
      salesBase = oldSale.read<int>('id');
      await db.customStatement('''
        WITH RECURSIVE seq(n) AS (
          SELECT 1 UNION ALL SELECT n + 1 FROM seq WHERE n < ${profile.sales}
        )
        INSERT INTO sales_invoices
          (invoice_number, customer_id, warehouse_id, branch_id, user_id,
           invoice_date, subtotal, discount, tax, total, paid, cash_paid,
           payment_method, sale_type, status, is_deleted, global_id,
           created_at, updated_at)
        SELECT
          'PERF-S-' || printf('%07d', n),
          ${partyBase + 1} + CASE WHEN n % 20 = 0 THEN 0 ELSE (n % ${profile.parties}) END,
          $warehouseId, ${branchId == 0 ? 'NULL' : branchId}, $userId,
          CAST(strftime('%s', '2026-01-01', printf('+%d days', (n - 1) % 365)) AS INTEGER) * 1000,
          400.0, 0.0, 0.0, 400.0, 400.0, 400.0,
          'cash', 'default', 'completed', 0, 'perf-sale-' || n,
          CAST(strftime('%s', '2026-01-01', printf('+%d days', (n - 1) % 365)) AS INTEGER) * 1000,
          CAST(strftime('%s', '2026-01-01', printf('+%d days', (n - 1) % 365)) AS INTEGER) * 1000
        FROM seq
      ''');
      await db.customStatement('''
        WITH RECURSIVE seq(n) AS (
          SELECT 1 UNION ALL SELECT n + 1 FROM seq WHERE n < ${profile.sales * 4}
        )
        INSERT INTO sales_invoice_items
          (invoice_id, product_id, quantity, unit_price, total, cost_price,
           tax_rate, tax_amount, quantity_in_base)
        SELECT
          $salesBase + CAST((n - 1) / 4 AS INTEGER) + 1,
          $productBase + ((n - 1) % ${profile.products}) + 1,
          1.0, 100.0, 100.0, 60.0, 0.0, 0.0, 1.0
        FROM seq
      ''');

      final oldPurchase = await db.customSelect("SELECT COALESCE(MAX(id), 0) AS id FROM purchase_invoices").getSingle();
      purchaseBase = oldPurchase.read<int>('id');
      await db.customStatement('''
        WITH RECURSIVE seq(n) AS (
          SELECT 1 UNION ALL SELECT n + 1 FROM seq WHERE n < ${profile.purchases}
        )
        INSERT INTO purchase_invoices
          (invoice_number, supplier_id, warehouse_id, branch_id, invoice_date,
           subtotal, discount, tax, total, paid, payment_method, status,
           is_deleted, global_id, created_at, updated_at)
        SELECT
          'PERF-PUR-' || printf('%06d', n),
          $partyBase + ((n - 1) % ${profile.parties}) + 1,
          $warehouseId, ${branchId == 0 ? 'NULL' : branchId},
          CAST(strftime('%s', '2026-01-01', printf('+%d days', (n - 1) % 365)) AS INTEGER) * 1000,
          200.0, 0.0, 0.0, 200.0, 0.0, 'credit', 'pending', 0,
          'perf-purchase-' || n,
          CAST(strftime('%s', '2026-01-01', printf('+%d days', (n - 1) % 365)) AS INTEGER) * 1000,
          CAST(strftime('%s', '2026-01-01', printf('+%d days', (n - 1) % 365)) AS INTEGER) * 1000
        FROM seq
      ''');
      await db.customStatement('''
        WITH RECURSIVE seq(n) AS (
          SELECT 1 UNION ALL SELECT n + 1 FROM seq WHERE n < ${profile.purchases}
        )
        INSERT INTO purchase_invoice_items
          (invoice_id, product_id, quantity, unit_cost, total, tax_rate, tax_amount, quantity_in_base)
        SELECT
          $purchaseBase + n, $productBase + ((n - 1) % ${profile.products}) + 1,
          1.0, 200.0, 200.0, 0.0, 0.0, 1.0
        FROM seq
      ''');

      final oldSaleJe = await db.customSelect("SELECT COALESCE(MAX(id), 0) AS id FROM journal_entries").getSingle();
      salesJournalBase = oldSaleJe.read<int>('id');
      await db.customStatement('''
        WITH RECURSIVE seq(n) AS (
          SELECT 1 UNION ALL SELECT n + 1 FROM seq WHERE n < ${profile.sales}
        )
        INSERT INTO journal_entries
          (entry_number, entry_date, description, reference_type, reference_id,
           is_posted, is_auto_posted, is_deleted, global_id)
        SELECT
          'PERF-JE-S-' || printf('%07d', n),
          CAST(strftime('%s', '2026-01-01', printf('+%d days', (n - 1) % 365)) AS INTEGER) * 1000,
          'Perf bulk sale', 'sale', $salesBase + n, 1, 1, 0, 'perf-je-sale-' || n
        FROM seq
      ''');
      await db.customStatement('''
        WITH RECURSIVE seq(n) AS (
          SELECT 1 UNION ALL SELECT n + 1 FROM seq WHERE n < ${profile.sales}
        )
        INSERT INTO journal_entry_lines (entry_id, account_id, debit, credit, description)
        SELECT $salesJournalBase + n, $cashAccountId, 400.0, 0.0, 'Perf cash debit' FROM seq
        UNION ALL
        SELECT $salesJournalBase + n,
          (SELECT id FROM accounts WHERE code = '4111' LIMIT 1), 0.0, 400.0, 'Perf sales credit' FROM seq
        UNION ALL
        SELECT $salesJournalBase + n,
          (SELECT id FROM accounts WHERE code = '5211' LIMIT 1), 60.0, 0.0, 'Perf COGS debit' FROM seq
        UNION ALL
        SELECT $salesJournalBase + n,
          (SELECT id FROM accounts WHERE code = '1136' LIMIT 1), 0.0, 60.0, 'Perf inventory credit' FROM seq
      ''');

      final oldPurchaseJe = await db.customSelect("SELECT COALESCE(MAX(id), 0) AS id FROM journal_entries").getSingle();
      purchaseJournalBase = oldPurchaseJe.read<int>('id');
      await db.customStatement('''
        WITH RECURSIVE seq(n) AS (
          SELECT 1 UNION ALL SELECT n + 1 FROM seq WHERE n < ${profile.purchases}
        )
        INSERT INTO journal_entries
          (entry_number, entry_date, description, reference_type, reference_id,
           is_posted, is_auto_posted, is_deleted, global_id)
        SELECT
          'PERF-JE-P-' || printf('%06d', n),
          CAST(strftime('%s', '2026-01-01', printf('+%d days', (n - 1) % 365)) AS INTEGER) * 1000,
          'Perf bulk purchase', 'purchase', $purchaseBase + n, 1, 1, 0,
          'perf-je-purchase-' || n
        FROM seq
      ''');
      await db.customStatement('''
        WITH RECURSIVE seq(n) AS (
          SELECT 1 UNION ALL SELECT n + 1 FROM seq WHERE n < ${profile.purchases}
        )
        INSERT INTO journal_entry_lines (entry_id, account_id, debit, credit, description)
        SELECT $purchaseJournalBase + n,
          (SELECT id FROM accounts WHERE code = '1136' LIMIT 1), 200.0, 0.0, 'Perf purchase inventory' FROM seq
        UNION ALL
        SELECT $purchaseJournalBase + n,
          (SELECT id FROM accounts WHERE code = '2111' LIMIT 1), 0.0, 200.0, 'Perf purchase payable' FROM seq
      ''');

      await db.customStatement('''
        INSERT INTO inventory_balances (product_id, warehouse_id, quantity, average_cost)
        SELECT id, $warehouseId, current_stock, cost_price
        FROM products WHERE code LIKE 'PERF-P-%'
      ''');
      await db.customStatement('''
        INSERT INTO stock_movements
          (product_id, warehouse_id, movement_type, quantity, unit_cost, balance_after,
           reference_type, user_id, branch_id, notes)
        SELECT id, $warehouseId, 'initial', 100000.0, cost_price, 100000.0,
          'perf_seed', $userId, ${branchId == 0 ? 'NULL' : branchId}, 'perf seed'
        FROM products WHERE code LIKE 'PERF-P-%'
        UNION ALL
        SELECT id, $warehouseId, 'sale', -(
          CAST(${profile.sales} / ${profile.products} AS INTEGER) +
          CASE WHEN (id - $productBase) <= (${profile.sales} % ${profile.products}) THEN 1 ELSE 0 END
        ), cost_price, current_stock, 'perf_seed', $userId,
          ${branchId == 0 ? 'NULL' : branchId}, 'perf bulk sales aggregate'
        FROM products WHERE code LIKE 'PERF-P-%'
      ''');
    });
    timer.stop();
    seedSeconds = timer.elapsedMicroseconds / 1000000;
  }

  Future<void> dispose() async {
    await Future<void>.delayed(const Duration(milliseconds: 250));
    await db.close();
    await directory.delete(recursive: true);
  }
}

class _Metric {
  final List<double> samples = [];
  int errors = 0;

  String format() {
    if (samples.isEmpty) return 'n=0;p50=NA;p95=NA;max=NA;errors=$errors';
    final sorted = [...samples]..sort();
    final p50 = sorted[(sorted.length * .50).ceil() - 1];
    final p95 = sorted[(sorted.length * .95).ceil() - 1];
    return 'n=${samples.length};p50=${p50.toStringAsFixed(2)}ms;'
        'p95=${p95.toStringAsFixed(2)}ms;max=${sorted.last.toStringAsFixed(2)}ms;errors=$errors';
  }
}

Future<void> _prepareShiftInvoices(_BenchContext c) async {
  c.shiftStart = DateTime.now().subtract(const Duration(seconds: 1));
  await c.db.openShift(c.userId, 0);
  final nowMs = DateTime.now().millisecondsSinceEpoch;
  final oldJe = await c.db.customSelect(
    'SELECT COALESCE(MAX(id), 0) AS id FROM journal_entries',
  ).getSingle();
  final shiftJournalBase = oldJe.read<int>('id');
  await c.db.customStatement('''
    WITH RECURSIVE seq(n) AS (
      SELECT 1 UNION ALL SELECT n + 1 FROM seq WHERE n < 500
    )
    INSERT INTO sales_invoices
      (invoice_number, customer_id, warehouse_id, branch_id, user_id,
       invoice_date, subtotal, discount, tax, total, paid, cash_paid,
       payment_method, sale_type, status, is_deleted, global_id,
       created_at, updated_at)
    SELECT
      'PERF-SHIFT-' || printf('%04d', n), ${c.busyPartyId}, ${c.warehouseId},
      ${c.branchId == 0 ? 'NULL' : c.branchId}, ${c.userId}, $nowMs,
      100.0, 0.0, 0.0, 100.0, 100.0, 100.0,
      'cash', 'default', 'completed', 0, 'perf-shift-' || n,
      $nowMs, $nowMs
    FROM seq
  ''');
  final shiftInvoice = await c.db.customSelect(
    "SELECT id FROM sales_invoices WHERE invoice_number = 'PERF-SHIFT-0001'",
  ).getSingle();
  final shiftInvoiceBase = shiftInvoice.read<int>('id');
  await c.db.customStatement('''
    WITH RECURSIVE seq(n) AS (
      SELECT 1 UNION ALL SELECT n + 1 FROM seq WHERE n < 500
    )
    INSERT INTO journal_entries
      (entry_number, entry_date, description, reference_type, reference_id,
       is_posted, is_auto_posted, is_deleted, global_id)
    SELECT
      'PERF-JE-SHIFT-' || printf('%04d', n), $nowMs,
      'Perf shift sale', 'sale', $shiftInvoiceBase + n - 1, 1, 1, 0,
      'perf-je-shift-' || n
    FROM seq
  ''');
  await c.db.customStatement('''
    WITH RECURSIVE seq(n) AS (
      SELECT 1 UNION ALL SELECT n + 1 FROM seq WHERE n < 500
    )
    INSERT INTO journal_entry_lines (entry_id, account_id, debit, credit, description)
    SELECT $shiftJournalBase + n, ${c.cashAccountId}, 100.0, 0.0, 'Perf shift cash debit' FROM seq
    UNION ALL
    SELECT $shiftJournalBase + n,
      (SELECT id FROM accounts WHERE code = '4111' LIMIT 1), 0.0, 100.0, 'Perf shift sales credit' FROM seq
  ''');
  c.shiftEnd = DateTime.now().add(const Duration(seconds: 1));
}

Future<void> _measureHotPaths(_BenchContext c, Map<String, _Metric> report) async {
  await _prepareShiftInvoices(c);
  Future<void> measure(String name, Future<void> Function() action) async {
    final metric = report.putIfAbsent(name, _Metric.new);
    for (var i = 0; i < c.profile.samples; i++) {
      final watch = Stopwatch()..start();
      try {
        await action();
        metric.samples.add(watch.elapsedMicroseconds / 1000);
      } catch (e) {
        metric.errors++;
        c.errors.add('$name: $e');
      }
    }
  }

  final productId = c.productBase + 10;
  final thirtyProductIds = [for (var i = 0; i < 30; i++) c.productBase + i + 1];
  await measure('product_search_name_contains', () async {
    await c.db.customSelect(
      '''SELECT id, code, name, sale_price FROM products
         WHERE is_active = 1 AND (search_name LIKE ? OR name LIKE ? OR code LIKE ?)
         ORDER BY name LIMIT 25''',
      variables: [
        Variable.withString('%Product 00010%'),
        Variable.withString('%Product 00010%'),
        Variable.withString('%00010%'),
      ],
    ).get();
  });
  await measure('product_search_barcode_prefix', () async {
    await c.db.customSelect(
      '''SELECT id, code, name, sale_price FROM products
         WHERE is_active = 1 AND barcode LIKE ? ORDER BY name LIMIT 25''',
      variables: [Variable.withString('890PERF00010%')],
    ).get();
  });
  await measure('add_to_cart_price_lookup', () async {
    await (c.db.select(c.db.products)..where((p) => p.id.equals(productId))).getSingle();
  });
  await measure('cash_sale_end_to_end', () async {
    await _createCashSale(c, productIds: [productId]);
  });
  await measure('cash_sale_30_lines', () async {
    await _createCashSale(c, productIds: thirtyProductIds);
  });
  await measure('sales_return_void_path', () async {
    final id = await _createCashSale(c, productIds: [productId], credit: true);
    await c.db.voidSalesInvoice(id, reason: 'perf benchmark', deletedBy: c.userId);
  });
  await measure('receipt_voucher', () async {
    c.voucherSequence++;
    await c.db.createReceiptVoucher(
      amount: 10,
      category: 'sales',
      partyId: c.busyPartyId,
      safeId: c.cashSafeId,
      userId: c.userId,
      globalId: 'perf-voucher-${c.voucherSequence}',
    );
  });
  await measure('sales_invoice_list_page_1', () async {
    await c.db.getSalesInvoicesPaged(limit: 50, offset: 0);
  });
  await measure('customer_statement_12_months', () async {
    await c.db.getPartyStatement(
      c.busyPartyId,
      fromDate: DateTime(2026),
      toDate: DateTime(2026, 12, 31),
    );
  });
  await measure('trial_balance_year', () async {
    await c.db.getTrialBalance(DateTime(2026), DateTime(2026, 12, 31, 23, 59, 59));
  });
  await measure('general_ledger_cash_month', () async {
    await c.db.getAccountLedger(
      c.cashAccountId,
      DateTime(2026, 1),
      DateTime(2026, 1, 31, 23, 59, 59),
      limit: 1000,
    );
  });
  await measure('inventory_valuation', () async {
    await InventoryRepositoryImpl(c.db).getInventoryValuation(warehouseId: c.warehouseId);
  });
  await measure('shift_close_aggregate_500_invoices', () async {
    await c.db.getShiftClosingAggregates(
      userId: c.userId,
      includeAllUsers: false,
      shiftStart: c.shiftStart,
      shiftEnd: c.shiftEnd,
    );
  });
  await _printQueryPlans(c);
}

Future<void> _printQueryPlans(_BenchContext c) async {
  final plans = <String, String>{
    'product_contains': '''SELECT id FROM products
      WHERE is_active = 1 AND (search_name LIKE '%Product 00010%'
      OR name LIKE '%Product 00010%' OR code LIKE '%00010%')
      ORDER BY name LIMIT 25''',
    'invoice_page': '''SELECT id FROM sales_invoices
      WHERE is_deleted = 0 AND (sale_type != 'return' OR sale_type IS NULL)
      ORDER BY created_at DESC LIMIT 50''',
    'customer_statement': '''SELECT id FROM sales_invoices
      WHERE customer_id = ${c.busyPartyId}
      AND invoice_date BETWEEN 2026 AND 2027 ORDER BY invoice_date''',
    'inventory_valuation': 'SELECT id, current_stock, cost_price FROM products',
  };
  for (final entry in plans.entries) {
    final rows = await c.db.customSelect('EXPLAIN QUERY PLAN ${entry.value}').get();
    final details = rows.map((row) => row.data['detail']).join(' | ');
    stdout.writeln('PERF_PLAN|${entry.key}|$details');
  }
}

Future<int> _createCashSale(_BenchContext c, {required List<int> productIds, bool credit = false}) async {
  c.saleSequence++;
  final total = productIds.length * 100.0;
  return c.db.createSalesInvoice(
    invoiceNumber: 'PERF-LIVE-${c.saleSequence}',
    customerId: c.busyPartyId,
    warehouseId: c.warehouseId,
    userId: c.userId,
    subtotal: total,
    discount: 0,
    tax: 0,
    total: total,
    paid: credit ? 0 : total,
    paymentMethod: credit ? 'credit' : 'cash',
    cashAmount: credit ? null : total,
    cashSafeId: credit ? null : c.cashSafeId,
    items: [
      for (final id in productIds)
        SalesInvoiceItemsCompanion.insert(
          invoiceId: 0,
          productId: id,
          quantity: 1,
          unitPrice: 100,
          total: 100,
          costPrice: const Value(60),
        ),
    ],
  );
}

Future<void> _measureConcurrency(_BenchContext c, Map<String, _Metric> report) async {
  final metric = report.putIfAbsent('concurrent_cashiers_api_handler', _Metric.new);
  final api = ApiSalesHandler(c.db, {});
  final started = DateTime.now();
  var successes = 0;
  var failures = 0;
  final latency = <double>[];
  Future<void> worker(int client) async {
    var n = 0;
    while (DateTime.now().difference(started) < c.profile.concurrencyDuration) {
      final watch = Stopwatch()..start();
      final productId = c.productBase + ((client + n) % c.profile.products) + 1;
      final globalId = 'perf-api-$client-$n';
      try {
        final response = await api.postSale(Request(
          'POST',
          Uri.parse('http://localhost/api/sales'),
          body: jsonEncode({
            'invoiceNumber': 'PERF-API-$client-$n',
            'globalId': globalId,
            'subtotal': 100.0,
            'discount': 0.0,
            'tax': 0.0,
            'total': 100.0,
            'paid': 100.0,
            'paymentMethod': 'cash',
            'cashAmount': 100.0,
            'cashSafeId': c.cashSafeId,
            'warehouseId': c.warehouseId,
            'userId': c.userId,
            'customerId': c.busyPartyId,
            'items': [
              {'productId': productId, 'quantity': 1.0, 'unitPrice': 100.0, 'total': 100.0, 'costPrice': 60.0},
            ],
          }),
          headers: {'Content-Type': 'application/json'},
          context: {ApiUserCtx.userIdKey: c.userId},
        ));
        if (response.statusCode != 200) {
          throw StateError('API status ${response.statusCode}: ${await response.readAsString()}');
        }
        successes++;
        latency.add(watch.elapsedMicroseconds / 1000);
      } catch (e) {
        failures++;
        c.errors.add('API concurrency client=$client: $e');
      }
      n++;
    }
  }
  await Future.wait([for (var i = 0; i < c.profile.concurrency; i++) worker(i)]);
  metric.samples.addAll(latency);
  metric.errors = failures;
  stdout.writeln(
    'PERF_CONCURRENCY|mode=in_process_api_handler|clients=${c.profile.concurrency}|seconds=${c.profile.concurrencyDuration.inSeconds}|'
    'sales=$successes|salesPerMinute=${(successes * 60 / c.profile.concurrencyDuration.inSeconds).toStringAsFixed(2)}|'
    'p95=${_percentile(latency, .95).toStringAsFixed(2)}ms|errors=$failures',
  );
}

double _percentile(List<double> values, double percentile) {
  if (values.isEmpty) return double.nan;
  final sorted = [...values]..sort();
  return sorted[(sorted.length * percentile).ceil() - 1];
}

Future<void> _verifyIntegrity(_BenchContext c) async {
  final duplicate = await c.db.customSelect('''
    SELECT COUNT(*) - COUNT(DISTINCT invoice_number) AS duplicates
    FROM sales_invoices WHERE invoice_number LIKE 'PERF-%'
  ''').getSingle();
  final journal = await c.db.customSelect('''
    SELECT COALESCE(SUM(debit), 0) AS debit, COALESCE(SUM(credit), 0) AS credit
    FROM journal_entry_lines l JOIN journal_entries e ON e.id = l.entry_id
    WHERE e.entry_number LIKE 'PERF-JE-%' AND e.is_deleted = 0
  ''').getSingle();
  final stock = await c.db.customSelect('''
    SELECT COUNT(*) AS bad FROM products p
    JOIN inventory_balances b ON b.product_id = p.id AND b.warehouse_id = ?
    WHERE p.code LIKE 'PERF-P-%' AND ABS(p.current_stock - b.quantity) > 0.0001
  ''', variables: [Variable<int>(c.warehouseId)]).getSingle();
  final duplicates = duplicate.read<int>('duplicates');
  final debit = journal.read<double>('debit');
  final credit = journal.read<double>('credit');
  final badStock = stock.read<int>('bad');
  stdout.writeln(
    'PERF_INTEGRITY|duplicateInvoiceNumbers=$duplicates|'
    'journalDifference=${(debit - credit).toStringAsFixed(4)}|stockMismatches=$badStock',
  );
  if (duplicates != 0 || (debit - credit).abs() > 0.01 || badStock != 0) {
    c.errors.add('integrity failed duplicates=$duplicates journal=${debit - credit} stock=$badStock');
  }
}

Future<void> _measureColdOpen(_BenchContext c, Map<String, _Metric> report) async {
  final oldDb = c.db;
  await Future<void>.delayed(const Duration(milliseconds: 250));
  await oldDb.close();
  final path = '${c.directory.path}${Platform.pathSeparator}perf.db';
  final metric = report.putIfAbsent('cold_open_to_first_query', _Metric.new);
  final watch = Stopwatch()..start();
  final reopened = AppDatabase.withExecutor(
    NativeDatabase(
      File(path),
      setup: (database) {
        database.execute('PRAGMA foreign_keys = ON');
        database.execute('PRAGMA journal_mode = WAL');
        database.execute('PRAGMA synchronous = NORMAL');
        database.execute('PRAGMA busy_timeout = 60000');
        database.execute('PRAGMA cache_size = -16000');
        database.execute('PRAGMA temp_store = memory');
      },
    ),
  );
  await reopened.customSelect('SELECT COUNT(*) AS count FROM sales_invoices').getSingle();
  metric.samples.add(watch.elapsedMicroseconds / 1000);
  c.db = reopened;
}
