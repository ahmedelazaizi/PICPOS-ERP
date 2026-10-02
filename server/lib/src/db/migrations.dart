/// Ordered, append-only schema migrations for the cloud database.
///
/// Table and column names mirror the desktop (ural_erp) schema so the I-3
/// desktop<->cloud mapper is a column copy. Every replicated table carries the
/// desktop v167 sync columns: global_id, last_modified_at (epoch ms here),
/// deleted_at, origin_client_id, row_version. `touch_row()` maintains
/// last_modified_at / row_version on every insert and update.
/// Never edit an applied migration; append a new one.
library;

class Migration {
  const Migration(this.version, this.name, this.sql);
  final int version;
  final String name;
  final String sql;
}

const String _sync = '''
  global_id TEXT NOT NULL UNIQUE,
  last_modified_at BIGINT NOT NULL DEFAULT 0,
  deleted_at BIGINT,
  origin_client_id TEXT,
  row_version INTEGER NOT NULL DEFAULT 0''';

const _syncedTables = [
  'companies',
  'employees',
  'parties',
  'products',
  'warehouses',
  'safes',
  'inventory_balances',
  'sales_routes',
  'route_customers',
  'rep_resources',
  'voucher_books',
  'device_number_leases',
  'sales_invoices',
  'safe_transactions',
];

final List<Migration> kMigrations = [
  Migration(1, 'init', '''
CREATE OR REPLACE FUNCTION now_ms() RETURNS BIGINT AS \$\$
  SELECT (EXTRACT(EPOCH FROM clock_timestamp()) * 1000)::BIGINT
\$\$ LANGUAGE SQL VOLATILE;

CREATE OR REPLACE FUNCTION touch_row() RETURNS TRIGGER AS \$\$
BEGIN
  NEW.last_modified_at := now_ms();
  IF TG_OP = 'UPDATE' THEN
    NEW.row_version := COALESCE(OLD.row_version, 0) + 1;
  END IF;
  RETURN NEW;
END;
\$\$ LANGUAGE plpgsql;

CREATE TABLE companies (
  id SERIAL PRIMARY KEY,
  name TEXT NOT NULL,
  tax_number TEXT,
  currency TEXT NOT NULL DEFAULT 'JOD',
  default_tax_rate NUMERIC(9,4) NOT NULL DEFAULT 0,
  integrity_secret TEXT NOT NULL,
  $_sync
);

CREATE TABLE employees (
  id SERIAL PRIMARY KEY,
  company_id INT NOT NULL REFERENCES companies(id),
  name TEXT NOT NULL,
  phone TEXT,
  pin_hash TEXT,
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  $_sync
);

CREATE TABLE devices (
  id SERIAL PRIMARY KEY,
  company_id INT NOT NULL REFERENCES companies(id),
  device_id TEXT NOT NULL UNIQUE,
  name TEXT,
  employee_id INT NOT NULL REFERENCES employees(id),
  token_hash TEXT NOT NULL,
  paired_at BIGINT NOT NULL,
  last_seen_at BIGINT,
  last_seen_ip TEXT,
  revoked_at BIGINT
);

CREATE TABLE pairing_codes (
  id SERIAL PRIMARY KEY,
  company_id INT NOT NULL REFERENCES companies(id),
  employee_id INT NOT NULL REFERENCES employees(id),
  code_hash TEXT NOT NULL,
  expires_at BIGINT NOT NULL,
  used_at BIGINT,
  created_at BIGINT NOT NULL
);

CREATE TABLE parties (
  id SERIAL PRIMARY KEY,
  company_id INT NOT NULL REFERENCES companies(id),
  name TEXT NOT NULL,
  phone TEXT,
  whatsapp_phone TEXT,
  whatsapp_opt_in BOOLEAN NOT NULL DEFAULT FALSE,
  whatsapp_opt_in_at BIGINT,
  balance NUMERIC(18,4) NOT NULL DEFAULT 0,
  credit_limit NUMERIC(18,4) NOT NULL DEFAULT 0,
  price_level TEXT,
  is_customer BOOLEAN NOT NULL DEFAULT TRUE,
  $_sync
);

CREATE TABLE products (
  id SERIAL PRIMARY KEY,
  company_id INT NOT NULL REFERENCES companies(id),
  name TEXT NOT NULL,
  name_en TEXT,
  barcode TEXT,
  unit_name TEXT,
  sale_price NUMERIC(18,4) NOT NULL DEFAULT 0,
  wholesale_price NUMERIC(18,4),
  tax_rate NUMERIC(9,4) NOT NULL DEFAULT 0,
  tax_exempt BOOLEAN NOT NULL DEFAULT FALSE,
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  $_sync
);
CREATE INDEX products_barcode_idx ON products(company_id, barcode);

CREATE TABLE warehouses (
  id SERIAL PRIMARY KEY,
  company_id INT NOT NULL REFERENCES companies(id),
  name TEXT NOT NULL,
  type TEXT NOT NULL DEFAULT 'main',
  $_sync
);

CREATE TABLE safes (
  id SERIAL PRIMARY KEY,
  company_id INT NOT NULL REFERENCES companies(id),
  name TEXT NOT NULL,
  $_sync
);

CREATE TABLE inventory_balances (
  id SERIAL PRIMARY KEY,
  company_id INT NOT NULL REFERENCES companies(id),
  product_id INT NOT NULL REFERENCES products(id),
  warehouse_id INT NOT NULL REFERENCES warehouses(id),
  quantity NUMERIC(18,4) NOT NULL DEFAULT 0,
  UNIQUE (product_id, warehouse_id),
  $_sync
);

CREATE TABLE stock_movements (
  id SERIAL PRIMARY KEY,
  company_id INT NOT NULL REFERENCES companies(id),
  product_id INT NOT NULL REFERENCES products(id),
  warehouse_id INT NOT NULL REFERENCES warehouses(id),
  movement_type TEXT NOT NULL,
  quantity NUMERIC(18,4) NOT NULL,
  balance_after NUMERIC(18,4) NOT NULL,
  reference_type TEXT NOT NULL,
  reference_global_id TEXT NOT NULL,
  created_at BIGINT NOT NULL
);

CREATE TABLE sales_routes (
  id SERIAL PRIMARY KEY,
  company_id INT NOT NULL REFERENCES companies(id),
  name TEXT NOT NULL,
  sales_rep_id INT REFERENCES employees(id),
  area_id INT,
  visit_days TEXT,
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  $_sync
);

CREATE TABLE route_customers (
  id SERIAL PRIMARY KEY,
  company_id INT NOT NULL REFERENCES companies(id),
  route_id INT NOT NULL REFERENCES sales_routes(id),
  customer_id INT NOT NULL REFERENCES parties(id),
  sequence INT NOT NULL DEFAULT 0,
  effective_from DATE NOT NULL,
  effective_to DATE,
  $_sync
);

CREATE TABLE rep_resources (
  id SERIAL PRIMARY KEY,
  company_id INT NOT NULL REFERENCES companies(id),
  employee_id INT NOT NULL UNIQUE REFERENCES employees(id),
  van_warehouse_id INT REFERENCES warehouses(id),
  custody_safe_id INT REFERENCES safes(id),
  $_sync
);

CREATE TABLE voucher_books (
  id SERIAL PRIMARY KEY,
  company_id INT NOT NULL REFERENCES companies(id),
  book_type TEXT NOT NULL DEFAULT 'receipt',
  prefix TEXT,
  label TEXT,
  range_from INT NOT NULL,
  range_to INT NOT NULL,
  next_number INT NOT NULL,
  holder_employee_id INT REFERENCES employees(id),
  status TEXT NOT NULL DEFAULT 'active',
  $_sync
);

CREATE TABLE voucher_book_leaves_cancelled (
  id SERIAL PRIMARY KEY,
  book_id INT NOT NULL REFERENCES voucher_books(id),
  number INT NOT NULL,
  reason TEXT,
  cancelled_at BIGINT NOT NULL,
  UNIQUE (book_id, number)
);

CREATE TABLE number_series (
  company_id INT NOT NULL REFERENCES companies(id),
  doc_type TEXT NOT NULL,
  prefix TEXT NOT NULL,
  next_block_start BIGINT NOT NULL,
  block_size INT NOT NULL DEFAULT 500,
  PRIMARY KEY (company_id, doc_type)
);

CREATE TABLE device_number_leases (
  id SERIAL PRIMARY KEY,
  company_id INT NOT NULL REFERENCES companies(id),
  device_pk INT NOT NULL REFERENCES devices(id),
  doc_type TEXT NOT NULL,
  prefix TEXT NOT NULL,
  range_from BIGINT NOT NULL,
  range_to BIGINT NOT NULL,
  next_number BIGINT NOT NULL,
  status TEXT NOT NULL DEFAULT 'active',
  leased_at BIGINT NOT NULL,
  $_sync
);

CREATE TABLE sales_invoices (
  id SERIAL PRIMARY KEY,
  company_id INT NOT NULL REFERENCES companies(id),
  invoice_number TEXT NOT NULL,
  customer_id INT NOT NULL REFERENCES parties(id),
  warehouse_id INT NOT NULL REFERENCES warehouses(id),
  safe_id INT REFERENCES safes(id),
  rep_employee_id INT NOT NULL REFERENCES employees(id),
  route_id INT REFERENCES sales_routes(id),
  device_pk INT NOT NULL REFERENCES devices(id),
  invoice_date TEXT NOT NULL,
  subtotal NUMERIC(18,4) NOT NULL,
  discount NUMERIC(18,4) NOT NULL DEFAULT 0,
  tax NUMERIC(18,4) NOT NULL,
  total NUMERIC(18,4) NOT NULL,
  paid NUMERIC(18,4) NOT NULL,
  payment_method TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'accepted',
  posted_on_desktop_at BIGINT,
  integrity_hash TEXT NOT NULL,
  source TEXT NOT NULL DEFAULT 'mobile',
  created_at BIGINT NOT NULL,
  UNIQUE (company_id, invoice_number),
  $_sync
);

CREATE TABLE sales_invoice_items (
  id SERIAL PRIMARY KEY,
  invoice_id INT NOT NULL REFERENCES sales_invoices(id),
  product_id INT NOT NULL REFERENCES products(id),
  quantity NUMERIC(18,4) NOT NULL,
  unit_price NUMERIC(18,4) NOT NULL,
  discount NUMERIC(18,4) NOT NULL DEFAULT 0,
  tax_rate NUMERIC(9,4) NOT NULL,
  tax_amount NUMERIC(18,4) NOT NULL,
  total NUMERIC(18,4) NOT NULL
);

CREATE TABLE safe_transactions (
  id SERIAL PRIMARY KEY,
  company_id INT NOT NULL REFERENCES companies(id),
  voucher_number TEXT,
  safe_id INT REFERENCES safes(id),
  transaction_type TEXT NOT NULL,
  category TEXT NOT NULL,
  amount NUMERIC(18,4) NOT NULL,
  party_id INT REFERENCES parties(id),
  employee_id INT REFERENCES employees(id),
  rep_employee_id INT REFERENCES employees(id),
  route_id INT REFERENCES sales_routes(id),
  book_id INT REFERENCES voucher_books(id),
  book_number INT,
  reference_type TEXT,
  reference_global_id TEXT,
  device_pk INT REFERENCES devices(id),
  created_at BIGINT NOT NULL,
  $_sync
);
CREATE UNIQUE INDEX safe_tx_book_leaf_uq ON safe_transactions(book_id, book_number)
  WHERE book_id IS NOT NULL;

CREATE TABLE sync_idempotency (
  company_id INT NOT NULL REFERENCES companies(id),
  global_id TEXT NOT NULL,
  kind TEXT NOT NULL,
  device_pk INT NOT NULL REFERENCES devices(id),
  result TEXT NOT NULL,
  created_at BIGINT NOT NULL,
  PRIMARY KEY (company_id, global_id)
);

CREATE TABLE whatsapp_outbox (
  id SERIAL PRIMARY KEY,
  company_id INT NOT NULL REFERENCES companies(id),
  party_id INT NOT NULL REFERENCES parties(id),
  to_phone TEXT NOT NULL,
  template TEXT NOT NULL,
  language TEXT NOT NULL,
  params TEXT NOT NULL,
  document_global_id TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'queued',
  attempts INT NOT NULL DEFAULT 0,
  next_attempt_at BIGINT NOT NULL,
  provider_message_id TEXT,
  last_error TEXT,
  created_at BIGINT NOT NULL,
  UNIQUE (document_global_id, template)
);

CREATE TABLE audit_log (
  id BIGSERIAL PRIMARY KEY,
  company_id INT,
  device_pk INT,
  employee_id INT,
  action TEXT NOT NULL,
  entity TEXT,
  global_id TEXT,
  ip TEXT,
  detail TEXT,
  at BIGINT NOT NULL
);
${_syncedTables.map((t) => 'CREATE TRIGGER ${t}_touch BEFORE INSERT OR UPDATE ON $t FOR EACH ROW EXECUTE FUNCTION touch_row();').join('\n')}
'''),
  // I-2: price lists, tax-inclusive pricing, returns, visits, token rotation.
  Migration(2, 'i2_returns_visits_pricing', '''
ALTER TABLE companies ADD COLUMN prices_include_tax BOOLEAN NOT NULL DEFAULT FALSE;
ALTER TABLE companies ADD COLUMN decimal_places INT NOT NULL DEFAULT 2;
ALTER TABLE employees ADD COLUMN can_override_price BOOLEAN NOT NULL DEFAULT FALSE;
ALTER TABLE devices ADD COLUMN previous_token_hash TEXT;
ALTER TABLE devices ADD COLUMN token_rotated_at BIGINT;
ALTER TABLE sales_invoices ADD COLUMN returned_total NUMERIC(18,4) NOT NULL DEFAULT 0;
ALTER TABLE sales_invoices ADD COLUMN return_ar_offset NUMERIC(18,4) NOT NULL DEFAULT 0;
ALTER TABLE sales_invoices ADD COLUMN prices_include_tax BOOLEAN NOT NULL DEFAULT FALSE;

-- Desktop: commercial_finance_tables.dart PriceLists / PriceListItems.
CREATE TABLE price_lists (
  id SERIAL PRIMARY KEY,
  company_id INT NOT NULL REFERENCES companies(id),
  name TEXT NOT NULL,
  code TEXT,
  is_default BOOLEAN NOT NULL DEFAULT FALSE,
  start_date DATE,
  end_date DATE,
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  $_sync
);

CREATE TABLE price_list_items (
  id SERIAL PRIMARY KEY,
  company_id INT NOT NULL REFERENCES companies(id),
  price_list_id INT NOT NULL REFERENCES price_lists(id),
  product_id INT NOT NULL REFERENCES products(id),
  price NUMERIC(18,4) NOT NULL,
  min_quantity NUMERIC(18,4) NOT NULL DEFAULT 1,
  max_discount NUMERIC(9,4) NOT NULL DEFAULT 0,
  $_sync
);

-- Field credit notes (mobile). Desktop stores returns as sales_invoices
-- with sale_type='return' (I-3 mapper).
CREATE TABLE sales_returns (
  id SERIAL PRIMARY KEY,
  company_id INT NOT NULL REFERENCES companies(id),
  return_number TEXT NOT NULL,
  original_invoice_id INT NOT NULL REFERENCES sales_invoices(id),
  customer_id INT NOT NULL REFERENCES parties(id),
  warehouse_id INT NOT NULL REFERENCES warehouses(id),
  safe_id INT REFERENCES safes(id),
  rep_employee_id INT NOT NULL REFERENCES employees(id),
  route_id INT REFERENCES sales_routes(id),
  device_pk INT NOT NULL REFERENCES devices(id),
  return_date TEXT NOT NULL,
  subtotal NUMERIC(18,4) NOT NULL,
  tax NUMERIC(18,4) NOT NULL,
  total NUMERIC(18,4) NOT NULL,
  ar_offset NUMERIC(18,4) NOT NULL,
  cash_refund NUMERIC(18,4) NOT NULL,
  reason TEXT,
  status TEXT NOT NULL DEFAULT 'accepted',
  posted_on_desktop_at BIGINT,
  integrity_hash TEXT NOT NULL,
  created_at BIGINT NOT NULL,
  UNIQUE (company_id, return_number),
  $_sync
);

CREATE TABLE sales_return_items (
  id SERIAL PRIMARY KEY,
  return_id INT NOT NULL REFERENCES sales_returns(id),
  product_id INT NOT NULL REFERENCES products(id),
  quantity NUMERIC(18,4) NOT NULL,
  unit_price NUMERIC(18,4) NOT NULL,
  tax_amount NUMERIC(18,4) NOT NULL,
  total NUMERIC(18,4) NOT NULL
);
CREATE INDEX sales_return_items_return_idx ON sales_return_items(return_id);
CREATE INDEX sales_returns_invoice_idx ON sales_returns(original_invoice_id);

CREATE TABLE customer_visits (
  id SERIAL PRIMARY KEY,
  company_id INT NOT NULL REFERENCES companies(id),
  customer_id INT NOT NULL REFERENCES parties(id),
  route_id INT REFERENCES sales_routes(id),
  rep_employee_id INT NOT NULL REFERENCES employees(id),
  device_pk INT NOT NULL REFERENCES devices(id),
  visit_date TEXT NOT NULL,
  outcome TEXT NOT NULL,
  no_sale_reason TEXT,
  note TEXT,
  latitude DOUBLE PRECISION,
  longitude DOUBLE PRECISION,
  sequence INT,
  created_at BIGINT NOT NULL,
  $_sync
);
CREATE INDEX customer_visits_rep_idx ON customer_visits(rep_employee_id, visit_date);

CREATE TRIGGER price_lists_touch BEFORE INSERT OR UPDATE ON price_lists FOR EACH ROW EXECUTE FUNCTION touch_row();
CREATE TRIGGER price_list_items_touch BEFORE INSERT OR UPDATE ON price_list_items FOR EACH ROW EXECUTE FUNCTION touch_row();
CREATE TRIGGER sales_returns_touch BEFORE INSERT OR UPDATE ON sales_returns FOR EACH ROW EXECUTE FUNCTION touch_row();
CREATE TRIGGER customer_visits_touch BEFORE INSERT OR UPDATE ON customer_visits FOR EACH ROW EXECUTE FUNCTION touch_row();
'''),
];
