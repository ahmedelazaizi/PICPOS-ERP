import 'package:uuid/uuid.dart';

import 'db/database.dart';
import 'security.dart';

const _uuid = Uuid();

/// Fixed demo identifiers (also used by tests and the docker README).
class Demo {
  static const companyGid = '00000000-0000-4000-8000-000000000001';
  static const rep1Gid = '00000000-0000-4000-8000-0000000000a1';
  static const rep2Gid = '00000000-0000-4000-8000-0000000000a2';
  static const rep1Pin = '1234';
  static const rep2Pin = '5678';
  static const cust1Gid = '00000000-0000-4000-8000-0000000000c1'; // rep1, opted-in WhatsApp, limit 100
  static const cust2Gid = '00000000-0000-4000-8000-0000000000c2'; // rep1, no limit, no WhatsApp
  static const cust3Gid = '00000000-0000-4000-8000-0000000000c3'; // rep2 only
  static const prodWaterGid = '00000000-0000-4000-8000-0000000000b1'; // taxed 16 %
  static const prodBreadGid = '00000000-0000-4000-8000-0000000000b2'; // tax exempt
  static const book1Gid = '00000000-0000-4000-8000-0000000000d1'; // rep1, 1001..1050
  static const book2Gid = '00000000-0000-4000-8000-0000000000d2'; // rep2, 2001..2050
}

/// Seeds one demo company with two reps, two routes, three customers, two
/// products, two van warehouses with stock and one receipt book per rep.
/// Idempotent: does nothing when the demo company exists.
Future<void> seedDemo(CloudDatabase db, {int pinIterations = 120000}) async {
  final exists = await db.query('SELECT 1 FROM companies WHERE global_id=@g', {'g': Demo.companyGid});
  if (exists.isNotEmpty) return;
  await db.tx((s) async {
    Future<int> ins(String sql, Map<String, Object?> p) async =>
        (await db.q(s, '$sql RETURNING id', p)).first[0] as int;

    final c = await ins(
        "INSERT INTO companies (global_id, name, tax_number, currency, default_tax_rate, integrity_secret) "
        "VALUES (@g, 'PicPos Demo', '123456789', 'JOD', 16, @sec)",
        {'g': Demo.companyGid, 'sec': randomToken()});
    final rep1 = await ins(
        "INSERT INTO employees (company_id, global_id, name, pin_hash) VALUES (@c, @g, 'مندوب ١', @p)",
        {'c': c, 'g': Demo.rep1Gid, 'p': hashPin(Demo.rep1Pin, iterations: pinIterations)});
    final rep2 = await ins(
        "INSERT INTO employees (company_id, global_id, name, pin_hash) VALUES (@c, @g, 'مندوب ٢', @p)",
        {'c': c, 'g': Demo.rep2Gid, 'p': hashPin(Demo.rep2Pin, iterations: pinIterations)});

    Future<int> wh(String name) => ins(
        "INSERT INTO warehouses (company_id, global_id, name, type) VALUES (@c, @g, @n, 'van')",
        {'c': c, 'g': _uuid.v4(), 'n': name});
    Future<int> safe(String name) => ins(
        'INSERT INTO safes (company_id, global_id, name) VALUES (@c, @g, @n)',
        {'c': c, 'g': _uuid.v4(), 'n': name});
    final van1 = await wh('سيارة ١'), van2 = await wh('سيارة ٢');
    final safe1 = await safe('عهدة مندوب ١'), safe2 = await safe('عهدة مندوب ٢');
    for (final (e, w, sf) in [(rep1, van1, safe1), (rep2, van2, safe2)]) {
      await ins(
          'INSERT INTO rep_resources (company_id, global_id, employee_id, van_warehouse_id, custody_safe_id) '
          'VALUES (@c, @g, @e, @w, @s)',
          {'c': c, 'g': _uuid.v4(), 'e': e, 'w': w, 's': sf});
    }

    Future<int> party(String gid, String name, double limit, String? wa) => ins(
        'INSERT INTO parties (company_id, global_id, name, phone, whatsapp_phone, whatsapp_opt_in, credit_limit) '
        'VALUES (@c, @g, @n, @ph, @wa, @opt, @l)',
        {'c': c, 'g': gid, 'n': name, 'ph': wa, 'wa': wa, 'opt': wa != null, 'l': limit});
    final c1 = await party(Demo.cust1Gid, 'بقالة الأمل', 100, '+962790000001');
    final c2 = await party(Demo.cust2Gid, 'سوبرماركت النور', 0, null);
    final c3 = await party(Demo.cust3Gid, 'مخبز السلام', 0, null);

    final r1 = await ins(
        "INSERT INTO sales_routes (company_id, global_id, name, sales_rep_id, visit_days) VALUES (@c, @g, 'خط الشمال', @e, 'sun,tue,thu')",
        {'c': c, 'g': _uuid.v4(), 'e': rep1});
    final r2 = await ins(
        "INSERT INTO sales_routes (company_id, global_id, name, sales_rep_id, visit_days) VALUES (@c, @g, 'خط الجنوب', @e, 'mon,wed')",
        {'c': c, 'g': _uuid.v4(), 'e': rep2});
    for (final (r, cu, seq) in [(r1, c1, 1), (r1, c2, 2), (r2, c3, 1)]) {
      await ins(
          'INSERT INTO route_customers (company_id, global_id, route_id, customer_id, sequence, effective_from) '
          "VALUES (@c, @g, @r, @cu, @s, DATE '2020-01-01')",
          {'c': c, 'g': _uuid.v4(), 'r': r, 'cu': cu, 's': seq});
    }

    final water = await ins(
        "INSERT INTO products (company_id, global_id, name, name_en, barcode, unit_name, sale_price, tax_rate) "
        "VALUES (@c, @g, 'مياه ٦ لتر', 'Water 6L', '6251234567890', 'كرتونة', 2.5, 16)",
        {'c': c, 'g': Demo.prodWaterGid});
    final bread = await ins(
        "INSERT INTO products (company_id, global_id, name, name_en, barcode, unit_name, sale_price, tax_rate, tax_exempt) "
        "VALUES (@c, @g, 'خبز', 'Bread', '6250000000017', 'ربطة', 1, 0, TRUE)",
        {'c': c, 'g': Demo.prodBreadGid});
    for (final (p, w, q) in [(water, van1, 50.0), (bread, van1, 20.0), (water, van2, 10.0)]) {
      await ins(
          'INSERT INTO inventory_balances (company_id, global_id, product_id, warehouse_id, quantity) '
          'VALUES (@c, @g, @p, @w, @q)',
          {'c': c, 'g': _uuid.v4(), 'p': p, 'w': w, 'q': q});
    }

    for (final (gid, e, from) in [(Demo.book1Gid, rep1, 1001), (Demo.book2Gid, rep2, 2001)]) {
      await ins(
          "INSERT INTO voucher_books (company_id, global_id, book_type, prefix, label, range_from, range_to, next_number, holder_employee_id) "
          "VALUES (@c, @g, 'receipt', 'R-', 'دفتر قبض', @f, @t, @f, @e)",
          {'c': c, 'g': gid, 'f': from, 't': from + 49, 'e': e});
    }
    await db.q(s,
        "INSERT INTO number_series (company_id, doc_type, prefix, next_block_start, block_size) VALUES "
        "(@c, 'sales_invoice', 'VS-', 100000, 500), (@c, 'sales_return', 'VR-', 100000, 500)",
        {'c': c});
  });
}
