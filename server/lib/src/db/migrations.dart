/// Ordered, append-only schema migrations for the cloud database.
///
/// Table and column names mirror the desktop (picpos_erp) schema so the I-3
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
  // I-3: desktop link (credential), desktop posting marks, desktop-ledger
  // values the materialized balances/stock are derived from, areas.
  Migration(3, 'i3_desktop_link', '''
CREATE TABLE desktop_links (
  id SERIAL PRIMARY KEY,
  company_id INT NOT NULL REFERENCES companies(id),
  link_id TEXT NOT NULL UNIQUE,
  name TEXT,
  key_hash TEXT NOT NULL,
  created_at BIGINT NOT NULL,
  last_seen_at BIGINT,
  last_seen_ip TEXT,
  revoked_at BIGINT
);

ALTER TABLE sales_invoices ADD COLUMN desktop_id TEXT;
ALTER TABLE sales_invoices ADD COLUMN desktop_number TEXT;
ALTER TABLE sales_invoices ADD COLUMN desktop_error TEXT;
ALTER TABLE sales_returns ADD COLUMN desktop_id TEXT;
ALTER TABLE sales_returns ADD COLUMN desktop_number TEXT;
ALTER TABLE sales_returns ADD COLUMN desktop_error TEXT;
ALTER TABLE safe_transactions ADD COLUMN posted_on_desktop_at BIGINT;
ALTER TABLE safe_transactions ADD COLUMN desktop_id TEXT;
ALTER TABLE safe_transactions ADD COLUMN desktop_number TEXT;
ALTER TABLE safe_transactions ADD COLUMN desktop_error TEXT;
ALTER TABLE customer_visits ADD COLUMN posted_on_desktop_at BIGINT;
ALTER TABLE customer_visits ADD COLUMN desktop_id TEXT;
ALTER TABLE customer_visits ADD COLUMN desktop_error TEXT;

-- Last value pushed by the desktop ledger; the served value adds the
-- accepted field documents the desktop has not posted yet (§2).
ALTER TABLE parties ADD COLUMN desktop_balance NUMERIC(18,4);
ALTER TABLE inventory_balances ADD COLUMN desktop_quantity NUMERIC(18,4);

CREATE TABLE distribution_areas (
  id SERIAL PRIMARY KEY,
  company_id INT NOT NULL REFERENCES companies(id),
  name TEXT NOT NULL,
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  $_sync
);
CREATE TRIGGER distribution_areas_touch BEFORE INSERT OR UPDATE ON distribution_areas FOR EACH ROW EXECUTE FUNCTION touch_row();
CREATE INDEX sales_invoices_unposted_idx ON sales_invoices(company_id) WHERE posted_on_desktop_at IS NULL;
CREATE INDEX sales_returns_unposted_idx ON sales_returns(company_id) WHERE posted_on_desktop_at IS NULL;
'''),
  // I-4: printed company identity (desktop settings company_name_en,
  // company_cr_number, address, phone) and the e-invoicing flag that decides
  // the receipt QR (fiscal gateway QR vs non-fiscal payload).
  Migration(4, 'i4_print_identity', '''
ALTER TABLE companies ADD COLUMN name_en TEXT;
ALTER TABLE companies ADD COLUMN commercial_register TEXT;
ALTER TABLE companies ADD COLUMN address TEXT;
ALTER TABLE companies ADD COLUMN phone TEXT;
ALTER TABLE companies ADD COLUMN einvoice_enabled BOOLEAN NOT NULL DEFAULT FALSE;
'''),
  // J3: the system cash customer (desktop `parties.system_role`, served to
  // every rep), the one-time customer name/phone of a cash-customer sale
  // (desktop `sales_invoices.adhoc_customer_*`), and customers created in the
  // field («حفظ كعميل دائم») waiting for the desktop to post them.
  Migration(5, 'j3_cash_customer_field_customers', '''
ALTER TABLE parties ADD COLUMN system_role TEXT;
ALTER TABLE parties ADD COLUMN address TEXT;
CREATE UNIQUE INDEX parties_system_role_uq ON parties(company_id, system_role)
  WHERE system_role IS NOT NULL;
ALTER TABLE sales_invoices ADD COLUMN adhoc_customer_name TEXT;
ALTER TABLE sales_invoices ADD COLUMN adhoc_customer_phone TEXT;

CREATE TABLE field_customers (
  id SERIAL PRIMARY KEY,
  company_id INT NOT NULL REFERENCES companies(id),
  party_id INT NOT NULL UNIQUE REFERENCES parties(id),
  route_customer_id INT REFERENCES route_customers(id),
  rep_employee_id INT NOT NULL REFERENCES employees(id),
  device_pk INT NOT NULL REFERENCES devices(id),
  posted_on_desktop_at BIGINT,
  desktop_id TEXT,
  desktop_number TEXT,
  desktop_error TEXT,
  created_at BIGINT NOT NULL,
  $_sync
);
CREATE TRIGGER field_customers_touch BEFORE INSERT OR UPDATE ON field_customers FOR EACH ROW EXECUTE FUNCTION touch_row();
CREATE INDEX field_customers_unposted_idx ON field_customers(company_id) WHERE posted_on_desktop_at IS NULL;
'''),
  // K: rep expense (payment) vouchers paid from the custody safe (desktop
  // expense categories, payment voucher books, last desktop custody balance
  // + over-custody policy), the receipt photo, and the field GPS stamp
  // (`field_geo`, JSON text) on every field document.
  Migration(6, 'k_expenses_geo', '''
CREATE TABLE expense_categories (
  id SERIAL PRIMARY KEY,
  company_id INT NOT NULL REFERENCES companies(id),
  name TEXT NOT NULL,
  name_en TEXT,
  sort_order INT NOT NULL DEFAULT 0,
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  $_sync
);
CREATE TRIGGER expense_categories_touch BEFORE INSERT OR UPDATE ON expense_categories FOR EACH ROW EXECUTE FUNCTION touch_row();

ALTER TABLE companies ADD COLUMN expense_over_custody TEXT NOT NULL DEFAULT 'flag';
ALTER TABLE safes ADD COLUMN desktop_balance NUMERIC(18,4);

ALTER TABLE safe_transactions ADD COLUMN expense_category_id INT REFERENCES expense_categories(id);
ALTER TABLE safe_transactions ADD COLUMN note TEXT;
ALTER TABLE safe_transactions ADD COLUMN doc_date TEXT;
ALTER TABLE safe_transactions ADD COLUMN over_custody BOOLEAN NOT NULL DEFAULT FALSE;
ALTER TABLE safe_transactions ADD COLUMN field_geo TEXT;
ALTER TABLE sales_invoices ADD COLUMN field_geo TEXT;
ALTER TABLE sales_returns ADD COLUMN field_geo TEXT;
ALTER TABLE customer_visits ADD COLUMN field_geo TEXT;
CREATE INDEX safe_tx_unposted_idx ON safe_transactions(company_id, category) WHERE posted_on_desktop_at IS NULL;

CREATE TABLE field_attachments (
  id SERIAL PRIMARY KEY,
  company_id INT NOT NULL REFERENCES companies(id),
  document_global_id TEXT NOT NULL UNIQUE,
  mime TEXT NOT NULL,
  size_bytes INT NOT NULL,
  data BYTEA NOT NULL,
  created_at BIGINT NOT NULL
);
'''),
  // M-1 (ARCHITECTURE-M §2.1, read-only part): «PicPos إدارة» users mirrored
  // from the desktop (mobile PBKDF2 hash only, never the desktop Argon2 hash),
  // admin devices, signed desktop snapshots, the desktop's Ed25519 public key
  // and admin pairing codes. Relay queue and notification tables follow in
  // the M-2/M-4 migrations.
  Migration(7, 'm1_admin_snapshots', '''
ALTER TABLE desktop_links ADD COLUMN signing_public_key TEXT;
ALTER TABLE desktop_links ADD COLUMN signing_key_set_at BIGINT;

ALTER TABLE pairing_codes ALTER COLUMN employee_id DROP NOT NULL;
ALTER TABLE pairing_codes ADD COLUMN kind TEXT NOT NULL DEFAULT 'rep';
ALTER TABLE pairing_codes ADD COLUMN user_global_id TEXT;

CREATE TABLE admin_users (
  id SERIAL PRIMARY KEY,
  company_id INT NOT NULL REFERENCES companies(id),
  global_id TEXT NOT NULL,
  username TEXT NOT NULL,
  display_name TEXT,
  locale TEXT,
  mobile_enabled BOOLEAN NOT NULL DEFAULT FALSE,
  password_hash TEXT,
  permissions JSONB NOT NULL DEFAULT '[]',
  branch_scope JSONB NOT NULL DEFAULT '[]',
  require_2fa BOOLEAN NOT NULL DEFAULT FALSE,
  totp_secret_enc TEXT,
  failed_logins INT NOT NULL DEFAULT 0,
  locked_until BIGINT,
  version BIGINT NOT NULL DEFAULT 0,
  updated_at BIGINT NOT NULL,
  UNIQUE (company_id, global_id)
);

CREATE TABLE admin_devices (
  id SERIAL PRIMARY KEY,
  company_id INT NOT NULL REFERENCES companies(id),
  device_id TEXT NOT NULL UNIQUE,
  name TEXT,
  user_id INT NOT NULL REFERENCES admin_users(id),
  token_hash TEXT NOT NULL,
  previous_token_hash TEXT,
  token_rotated_at BIGINT,
  fcm_token TEXT,
  platform TEXT,
  app_version TEXT,
  paired_at BIGINT NOT NULL,
  last_seen_at BIGINT,
  last_seen_ip TEXT,
  revoked_at BIGINT
);
CREATE INDEX admin_devices_user_idx ON admin_devices(user_id);

CREATE TABLE snapshots (
  company_id INT NOT NULL REFERENCES companies(id),
  kind TEXT NOT NULL,
  scope TEXT NOT NULL,
  as_of_day TEXT NOT NULL,
  as_of BIGINT NOT NULL,
  payload TEXT NOT NULL,
  signature TEXT NOT NULL,
  received_at BIGINT NOT NULL,
  PRIMARY KEY (company_id, kind, scope, as_of_day)
);
'''),

  // Server-side logout of «PicPos إدارة»: session tokens are stateless HMAC, so
  // a logged-out token is recorded here by its `jti` until it would expire
  // anyway (expires_at, ms) and then pruned on the next write.
  Migration(8, 'm1_admin_session_revocations', '''
CREATE TABLE admin_session_revocations (
  company_id INT NOT NULL REFERENCES companies(id),
  jti TEXT NOT NULL,
  revoked_at BIGINT NOT NULL,
  expires_at BIGINT NOT NULL,
  PRIMARY KEY (company_id, jti)
);
CREATE INDEX admin_session_revocations_exp_idx ON admin_session_revocations(expires_at);
'''),
];
