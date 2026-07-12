-- Supabase Migration Script for UralCash POS
-- Run this in Supabase SQL Editor

-- ═══════════════════════════════════════════════════════════════════════════
-- USERS
-- ═══════════════════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS users (
  id SERIAL PRIMARY KEY,
  username VARCHAR(50) UNIQUE NOT NULL,
  password_hash TEXT NOT NULL,
  password_salt TEXT DEFAULT '',
  role VARCHAR(20) NOT NULL DEFAULT 'cashier',
  full_name VARCHAR(100),
  display_name VARCHAR(100),
  is_active BOOLEAN DEFAULT TRUE,
  created_at TIMESTAMP DEFAULT NOW()
);

-- ═══════════════════════════════════════════════════════════════════════════
-- CATEGORIES
-- ═══════════════════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS categories (
  id SERIAL PRIMARY KEY,
  name VARCHAR(100) NOT NULL,
  description TEXT,
  color VARCHAR(20) DEFAULT '#2563EB',
  parent_id INTEGER REFERENCES categories(id),
  sort_order INTEGER DEFAULT 0,
  is_active BOOLEAN DEFAULT TRUE,
  created_at TIMESTAMP DEFAULT NOW()
);

-- ═══════════════════════════════════════════════════════════════════════════
-- WAREHOUSES
-- ═══════════════════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS branches (
  id SERIAL PRIMARY KEY,
  name VARCHAR(100) NOT NULL,
  address TEXT,
  phone VARCHAR(50),
  is_active BOOLEAN DEFAULT TRUE,
  created_at TIMESTAMP DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS warehouses (
  id SERIAL PRIMARY KEY,
  name VARCHAR(100) NOT NULL,
  branch_id INTEGER REFERENCES branches(id),
  address TEXT,
  is_default BOOLEAN DEFAULT FALSE,
  is_active BOOLEAN DEFAULT TRUE,
  created_at TIMESTAMP DEFAULT NOW()
);

-- ═══════════════════════════════════════════════════════════════════════════
-- UNITS
-- ═══════════════════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS units (
  id SERIAL PRIMARY KEY,
  name VARCHAR(50) NOT NULL,
  symbol VARCHAR(10) NOT NULL,
  conversion_factor DECIMAL(12,4) DEFAULT 1.0,
  created_at TIMESTAMP DEFAULT NOW()
);

-- ═══════════════════════════════════════════════════════════════════════════
-- PRODUCTS
-- ═══════════════════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS products (
  id SERIAL PRIMARY KEY,
  code VARCHAR(50) UNIQUE NOT NULL,
  name VARCHAR(200) NOT NULL,
  description TEXT,
  category_id INTEGER REFERENCES categories(id),
  unit_id INTEGER REFERENCES units(id),
  sale_price DECIMAL(12,2) DEFAULT 0,
  cost_price DECIMAL(12,2) DEFAULT 0,
  min_stock DECIMAL(12,2) DEFAULT 0,
  current_stock DECIMAL(12,2) DEFAULT 0,
  image_path TEXT,
  image_data BYTEA,
  track_inventory BOOLEAN DEFAULT TRUE,
  is_sold_by_weight BOOLEAN DEFAULT FALSE,
  track_expiry BOOLEAN DEFAULT FALSE,
  default_shelf_days INTEGER DEFAULT 90,
  alert_days_before INTEGER DEFAULT 30,
  allow_negative_sale BOOLEAN DEFAULT FALSE,
  price_per_unit DECIMAL(12,2),
  weight_unit VARCHAR(10) DEFAULT 'kg',
  is_active BOOLEAN DEFAULT TRUE,
  created_at TIMESTAMP DEFAULT NOW()
);

-- Product Barcodes
CREATE TABLE IF NOT EXISTS product_barcodes (
  id SERIAL PRIMARY KEY,
  product_id INTEGER REFERENCES products(id) ON DELETE CASCADE,
  barcode VARCHAR(100) NOT NULL,
  is_primary BOOLEAN DEFAULT FALSE,
  created_at TIMESTAMP DEFAULT NOW()
);

-- Product Units (multiple units per product)
CREATE TABLE IF NOT EXISTS product_units (
  id SERIAL PRIMARY KEY,
  product_id INTEGER REFERENCES products(id) ON DELETE CASCADE,
  unit_id INTEGER REFERENCES units(id),
  conversion_factor DECIMAL(12,4) DEFAULT 1.0,
  price DECIMAL(12,2) DEFAULT 0,
  barcode VARCHAR(100),
  created_at TIMESTAMP DEFAULT NOW()
);

-- Product Batches (for expiry tracking)
CREATE TABLE IF NOT EXISTS product_batches (
  id SERIAL PRIMARY KEY,
  product_id INTEGER REFERENCES products(id) ON DELETE CASCADE,
  batch_number VARCHAR(50),
  production_date TIMESTAMP,
  expiry_date TIMESTAMP,
  initial_quantity DECIMAL(12,2) DEFAULT 0,
  remaining_quantity DECIMAL(12,2) DEFAULT 0,
  cost_price DECIMAL(12,2) DEFAULT 0,
  status VARCHAR(20) DEFAULT 'active',
  created_at TIMESTAMP DEFAULT NOW()
);

-- ═══════════════════════════════════════════════════════════════════════════
-- PARTIES (Customers & Suppliers)
-- ═══════════════════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS parties (
  id SERIAL PRIMARY KEY,
  name VARCHAR(200) NOT NULL,
  phone VARCHAR(50),
  email VARCHAR(100),
  address TEXT,
  tax_id VARCHAR(50),
  is_customer BOOLEAN DEFAULT TRUE,
  is_supplier BOOLEAN DEFAULT FALSE,
  balance DECIMAL(12,2) DEFAULT 0,
  credit_limit DECIMAL(12,2) DEFAULT 0,
  notes TEXT,
  is_active BOOLEAN DEFAULT TRUE,
  created_at TIMESTAMP DEFAULT NOW()
);

-- ═══════════════════════════════════════════════════════════════════════════
-- PURCHASE INVOICES
-- ═══════════════════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS purchase_invoices (
  id SERIAL PRIMARY KEY,
  invoice_number VARCHAR(50) NOT NULL,
  supplier_id INTEGER REFERENCES parties(id),
  warehouse_id INTEGER REFERENCES warehouses(id),
  user_id INTEGER REFERENCES users(id),
  invoice_date TIMESTAMP NOT NULL,
  subtotal DECIMAL(12,2) DEFAULT 0,
  discount DECIMAL(12,2) DEFAULT 0,
  tax DECIMAL(12,2) DEFAULT 0,
  total DECIMAL(12,2) DEFAULT 0,
  paid DECIMAL(12,2) DEFAULT 0,
  payment_method VARCHAR(20) DEFAULT 'cash',
  status VARCHAR(20) DEFAULT 'pending',
  notes TEXT,
  created_at TIMESTAMP DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS purchase_invoice_items (
  id SERIAL PRIMARY KEY,
  invoice_id INTEGER REFERENCES purchase_invoices(id) ON DELETE CASCADE,
  product_id INTEGER REFERENCES products(id),
  quantity DECIMAL(12,2) NOT NULL,
  unit_cost DECIMAL(12,2) NOT NULL,
  discount DECIMAL(12,2) DEFAULT 0,
  total DECIMAL(12,2) NOT NULL,
  batch_number VARCHAR(50),
  production_date TIMESTAMP,
  expiry_date TIMESTAMP
);

-- ═══════════════════════════════════════════════════════════════════════════
-- SALES INVOICES
-- ═══════════════════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS sales_invoices (
  id SERIAL PRIMARY KEY,
  invoice_number VARCHAR(50) NOT NULL,
  customer_id INTEGER REFERENCES parties(id),
  warehouse_id INTEGER REFERENCES warehouses(id),
  user_id INTEGER REFERENCES users(id),
  invoice_date TIMESTAMP NOT NULL,
  subtotal DECIMAL(12,2) DEFAULT 0,
  discount DECIMAL(12,2) DEFAULT 0,
  tax DECIMAL(12,2) DEFAULT 0,
  total DECIMAL(12,2) DEFAULT 0,
  paid DECIMAL(12,2) DEFAULT 0,
  payment_method VARCHAR(20) DEFAULT 'cash',
  status VARCHAR(20) DEFAULT 'completed',
  notes TEXT,
  created_at TIMESTAMP DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS sales_invoice_items (
  id SERIAL PRIMARY KEY,
  invoice_id INTEGER REFERENCES sales_invoices(id) ON DELETE CASCADE,
  product_id INTEGER REFERENCES products(id),
  quantity DECIMAL(12,2) NOT NULL,
  unit_price DECIMAL(12,2) NOT NULL,
  discount DECIMAL(12,2) DEFAULT 0,
  total DECIMAL(12,2) NOT NULL,
  batch_id INTEGER REFERENCES product_batches(id),
  cost_price DECIMAL(12,2) DEFAULT 0
);

-- ═══════════════════════════════════════════════════════════════════════════
-- STOCK MOVEMENTS
-- ═══════════════════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS stock_movements (
  id SERIAL PRIMARY KEY,
  product_id INTEGER REFERENCES products(id),
  warehouse_id INTEGER REFERENCES warehouses(id),
  movement_type VARCHAR(20) NOT NULL,
  quantity DECIMAL(12,2) NOT NULL,
  unit_cost DECIMAL(12,2) DEFAULT 0,
  balance_after DECIMAL(12,2) NOT NULL,
  reference_type VARCHAR(50),
  reference_id INTEGER,
  notes TEXT,
  created_at TIMESTAMP DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS inventory_balances (
  id SERIAL PRIMARY KEY,
  product_id INTEGER REFERENCES products(id),
  warehouse_id INTEGER REFERENCES warehouses(id),
  quantity DECIMAL(12,2) DEFAULT 0,
  average_cost DECIMAL(12,2) DEFAULT 0,
  last_updated TIMESTAMP DEFAULT NOW()
);

-- ═══════════════════════════════════════════════════════════════════════════
-- TREASURY (Safes) - FIXED: Added safe_type column
-- ═══════════════════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS safes (
  id SERIAL PRIMARY KEY,
  name VARCHAR(100) NOT NULL,
  safe_type VARCHAR(20) DEFAULT 'cash',  -- cash, bank
  balance DECIMAL(12,2) DEFAULT 0,
  branch_id INTEGER REFERENCES branches(id),
  is_default BOOLEAN DEFAULT FALSE,
  is_active BOOLEAN DEFAULT TRUE,
  created_at TIMESTAMP DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS safe_transactions (
  id SERIAL PRIMARY KEY,
  voucher_number VARCHAR(50) NOT NULL,
  safe_id INTEGER REFERENCES safes(id),
  transaction_type VARCHAR(20) NOT NULL,  -- receipt, payment, transfer
  category VARCHAR(50) NOT NULL,  -- sales, purchase, expense, salary, advance, other
  amount DECIMAL(12,2) NOT NULL,
  balance_after DECIMAL(12,2) NOT NULL,
  reference_type VARCHAR(50),
  reference_id INTEGER,
  party_id INTEGER REFERENCES parties(id),
  description TEXT,
  user_id INTEGER REFERENCES users(id),
  created_at TIMESTAMP DEFAULT NOW()
);

-- ═══════════════════════════════════════════════════════════════════════════
-- ACCOUNTING
-- ═══════════════════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS accounts (
  id SERIAL PRIMARY KEY,
  code VARCHAR(20) NOT NULL,
  name VARCHAR(100) NOT NULL,
  account_type VARCHAR(20) NOT NULL,  -- asset, liability, equity, revenue, expense
  parent_id INTEGER REFERENCES accounts(id),
  balance DECIMAL(12,2) DEFAULT 0,
  is_system BOOLEAN DEFAULT FALSE,
  is_active BOOLEAN DEFAULT TRUE,
  created_at TIMESTAMP DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS journal_entries (
  id SERIAL PRIMARY KEY,
  entry_number VARCHAR(50) NOT NULL,
  entry_date TIMESTAMP NOT NULL,
  description TEXT,
  reference_type VARCHAR(50),
  reference_id INTEGER,
  is_posted BOOLEAN DEFAULT TRUE,
  created_at TIMESTAMP DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS journal_entry_lines (
  id SERIAL PRIMARY KEY,
  entry_id INTEGER REFERENCES journal_entries(id) ON DELETE CASCADE,
  account_id INTEGER REFERENCES accounts(id),
  debit DECIMAL(12,2) DEFAULT 0,
  credit DECIMAL(12,2) DEFAULT 0,
  description TEXT
);

-- ═══════════════════════════════════════════════════════════════════════════
-- OFFERS
-- ═══════════════════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS offers (
  id SERIAL PRIMARY KEY,
  name VARCHAR(200) NOT NULL,
  description TEXT,
  offer_price DECIMAL(12,2) NOT NULL,
  start_date TIMESTAMP,
  end_date TIMESTAMP,
  is_active BOOLEAN DEFAULT TRUE,
  created_at TIMESTAMP DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS offer_items (
  id SERIAL PRIMARY KEY,
  offer_id INTEGER REFERENCES offers(id) ON DELETE CASCADE,
  product_id INTEGER REFERENCES products(id),
  quantity DECIMAL(12,2) NOT NULL
);

-- ═══════════════════════════════════════════════════════════════════════════
-- RESTAURANT TABLES
-- ═══════════════════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS table_sections (
  id SERIAL PRIMARY KEY,
  name VARCHAR(100) NOT NULL,
  is_active BOOLEAN DEFAULT TRUE,
  created_at TIMESTAMP DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS restaurant_tables (
  id SERIAL PRIMARY KEY,
  section_id INTEGER REFERENCES table_sections(id),
  name VARCHAR(100) NOT NULL,
  table_number VARCHAR(20),
  capacity INTEGER DEFAULT 4,
  status VARCHAR(20) DEFAULT 'available',  -- available, occupied, billing
  is_active BOOLEAN DEFAULT TRUE,
  created_at TIMESTAMP DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS table_orders (
  id SERIAL PRIMARY KEY,
  table_id INTEGER REFERENCES restaurant_tables(id),
  user_id INTEGER REFERENCES users(id),
  status VARCHAR(20) DEFAULT 'open',  -- open, bill_requested, closed, cancelled
  total DECIMAL(12,2) DEFAULT 0,
  opened_at TIMESTAMP DEFAULT NOW(),
  closed_at TIMESTAMP
);

CREATE TABLE IF NOT EXISTS table_order_items (
  id SERIAL PRIMARY KEY,
  table_order_id INTEGER REFERENCES table_orders(id) ON DELETE CASCADE,
  product_id INTEGER REFERENCES products(id),
  quantity DECIMAL(12,2) NOT NULL,
  unit_price DECIMAL(12,2) NOT NULL,
  total DECIMAL(12,2) NOT NULL,
  notes TEXT,
  added_at TIMESTAMP DEFAULT NOW()
);

-- ═══════════════════════════════════════════════════════════════════════════
-- HELD/PENDING ORDERS (POS suspended orders)
-- ═══════════════════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS held_orders (
  id SERIAL PRIMARY KEY,
  hold_number VARCHAR(50) NOT NULL,
  subtotal DECIMAL(12,2) DEFAULT 0,
  discount DECIMAL(12,2) DEFAULT 0,
  discount_is_percent BOOLEAN DEFAULT FALSE,
  note TEXT,
  user_id INTEGER REFERENCES users(id),
  customer_id INTEGER REFERENCES parties(id),
  created_at TIMESTAMP DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS held_order_items (
  id SERIAL PRIMARY KEY,
  held_order_id INTEGER REFERENCES held_orders(id) ON DELETE CASCADE,
  product_id INTEGER REFERENCES products(id),
  quantity DECIMAL(12,2) NOT NULL,
  unit_price DECIMAL(12,2) NOT NULL,
  custom_price DECIMAL(12,2),
  note TEXT
);

-- ═══════════════════════════════════════════════════════════════════════════
-- SETTINGS
-- ═══════════════════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS settings (
  key VARCHAR(100) PRIMARY KEY,
  value TEXT,
  updated_at TIMESTAMP DEFAULT NOW()
);

-- ═══════════════════════════════════════════════════════════════════════════
-- DEFAULT DATA
-- ═══════════════════════════════════════════════════════════════════════════

-- Default branch
INSERT INTO branches (name) 
SELECT 'الفرع الرئيسي' WHERE NOT EXISTS (SELECT 1 FROM branches WHERE name = 'الفرع الرئيسي');

-- Default warehouse (without branch_id to support existing schemas)
INSERT INTO warehouses (name, is_default) 
SELECT 'المخزن الرئيسي', TRUE WHERE NOT EXISTS (SELECT 1 FROM warehouses WHERE name = 'المخزن الرئيسي');

-- Default units
INSERT INTO units (name, symbol) VALUES 
  ('قطعة', 'قطعة'),
  ('كيلو', 'كجم'),
  ('علبة', 'علبة'),
  ('كرتونة', 'كرتون')
ON CONFLICT DO NOTHING;

-- Default category (without color to support existing schemas)
INSERT INTO categories (name) 
SELECT 'عام' WHERE NOT EXISTS (SELECT 1 FROM categories WHERE name = 'عام');

-- Add safe_type column if it doesn't exist
DO $$ 
BEGIN 
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='safes' AND column_name='safe_type') THEN
    ALTER TABLE safes ADD COLUMN safe_type VARCHAR(20) DEFAULT 'cash';
  END IF;
END $$;

-- Default safes
INSERT INTO safes (name, safe_type, balance, is_default, is_active) 
SELECT 'صندوق الكاشير', 'cash', 0, TRUE, TRUE 
WHERE NOT EXISTS (SELECT 1 FROM safes WHERE name = 'صندوق الكاشير');

INSERT INTO safes (name, safe_type, balance, is_default, is_active) 
SELECT 'الحساب البنكي', 'bank', 0, TRUE, TRUE 
WHERE NOT EXISTS (SELECT 1 FROM safes WHERE name = 'الحساب البنكي');

-- Default admin user: intentionally NOT seeded here.
-- A plaintext 'admin'/'admin' seed is a permanent backdoor once this file is
-- published in git. The admin user must be bootstrapped by the app on first run
-- with a randomly generated password + forced change on first login.
-- See bootstrap-admin invariants (Spec 061).

-- Default settings
INSERT INTO settings (key, value) VALUES
  ('storeName', 'UralCash POS'),
  ('storePhone', ''),
  ('storeAddress', ''),
  ('taxRate', '0'),
  ('currency', 'د.أ'),
  ('receiptFooter', 'شكراً لتعاملكم معنا')
ON CONFLICT (key) DO NOTHING;

-- ═══════════════════════════════════════════════════════════════════════════
-- INDEXES FOR PERFORMANCE
-- ═══════════════════════════════════════════════════════════════════════════

CREATE INDEX IF NOT EXISTS idx_products_code ON products(code);
CREATE INDEX IF NOT EXISTS idx_products_category ON products(category_id);
CREATE INDEX IF NOT EXISTS idx_product_barcodes_barcode ON product_barcodes(barcode);
CREATE INDEX IF NOT EXISTS idx_sales_invoices_date ON sales_invoices(invoice_date);
CREATE INDEX IF NOT EXISTS idx_sales_invoices_customer ON sales_invoices(customer_id);
CREATE INDEX IF NOT EXISTS idx_purchase_invoices_date ON purchase_invoices(invoice_date);
CREATE INDEX IF NOT EXISTS idx_purchase_invoices_supplier ON purchase_invoices(supplier_id);
CREATE INDEX IF NOT EXISTS idx_safe_transactions_safe ON safe_transactions(safe_id);
CREATE INDEX IF NOT EXISTS idx_safe_transactions_date ON safe_transactions(created_at);
CREATE INDEX IF NOT EXISTS idx_stock_movements_product ON stock_movements(product_id);
CREATE INDEX IF NOT EXISTS idx_parties_name ON parties(name);

-- ═══════════════════════════════════════════════════════════════════════════
-- ROW LEVEL SECURITY (Optional - Enable if needed)
-- ═══════════════════════════════════════════════════════════════════════════

-- Enable RLS on all tables (uncomment if needed)
-- ALTER TABLE users ENABLE ROW LEVEL SECURITY;
-- ALTER TABLE products ENABLE ROW LEVEL SECURITY;
-- etc.
