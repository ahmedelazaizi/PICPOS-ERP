-- ═══════════════════════════════════════════════════════════════════════════
-- Migration V119: Smart Sync Expansion — UUID Coverage + Soft Delete + New Tables
-- Run after V118. All statements are idempotent (IF NOT EXISTS / IF NOT EXISTS column).
-- ═══════════════════════════════════════════════════════════════════════════
-- Applies schema changes matching Drift schemaVersion = 119
-- Corresponding Dart migration: epoch_3.dart → "v119 sync expansion"
-- ═══════════════════════════════════════════════════════════════════════════

-- ─────────────────────────────────────────────────────────────────────────────
-- SECTION 1: Extend master/static tables with global_id for UUID-first sync
-- Tables: units, accounts, cost_centers, fiscal_years, accounting_periods,
--         safes, safe_transactions, warehouses, branches, users, stock_movements
-- ─────────────────────────────────────────────────────────────────────────────

-- 1.1 Units
ALTER TABLE public.units
  ADD COLUMN IF NOT EXISTS global_id uuid DEFAULT gen_random_uuid() UNIQUE;

-- 1.2 Accounts (Chart of Accounts)
ALTER TABLE public.accounts
  ADD COLUMN IF NOT EXISTS global_id uuid DEFAULT gen_random_uuid() UNIQUE;

-- 1.3 Cost Centers
ALTER TABLE public.cost_centers
  ADD COLUMN IF NOT EXISTS global_id uuid DEFAULT gen_random_uuid() UNIQUE;

-- 1.4 Fiscal Years
ALTER TABLE public.fiscal_years
  ADD COLUMN IF NOT EXISTS global_id uuid DEFAULT gen_random_uuid() UNIQUE;

-- 1.5 Accounting Periods
ALTER TABLE public.accounting_periods
  ADD COLUMN IF NOT EXISTS global_id uuid DEFAULT gen_random_uuid() UNIQUE;

-- 1.6 Safes (Treasuries)
ALTER TABLE public.safes
  ADD COLUMN IF NOT EXISTS global_id uuid DEFAULT gen_random_uuid() UNIQUE;

-- 1.7 Safe Transactions
ALTER TABLE public.safe_transactions
  ADD COLUMN IF NOT EXISTS global_id uuid DEFAULT gen_random_uuid() UNIQUE;

-- 1.8 Warehouses (branches + global_id already in v118 for branches; warehouses is new)
ALTER TABLE public.warehouses
  ADD COLUMN IF NOT EXISTS global_id uuid DEFAULT gen_random_uuid() UNIQUE;

-- 1.9 Branches (global_id added in v118; add is_global + branch_ids for consistency)
-- Note: global_id already exists from v118 — only add missing columns
ALTER TABLE public.branches
  ADD COLUMN IF NOT EXISTS is_global boolean DEFAULT true;

-- 1.10 Users
ALTER TABLE public.users
  ADD COLUMN IF NOT EXISTS global_id uuid DEFAULT gen_random_uuid() UNIQUE;

-- 1.11 Stock Movements (global_id + idempotency_key — Phase 4 sync reliability)
ALTER TABLE public.stock_movements
  ADD COLUMN IF NOT EXISTS global_id uuid DEFAULT gen_random_uuid() UNIQUE,
  ADD COLUMN IF NOT EXISTS idempotency_key text;

-- ─────────────────────────────────────────────────────────────────────────────
-- SECTION 2: Soft Delete + Audit columns on transactional tables
-- (sales_invoices, purchase_invoices, journal_entries, payments)
-- ─────────────────────────────────────────────────────────────────────────────

-- 2.1 Sales Invoices — soft delete + click payment split
ALTER TABLE public.sales_invoices
  ADD COLUMN IF NOT EXISTS click_paid     numeric(19,4) DEFAULT 0,
  ADD COLUMN IF NOT EXISTS is_deleted     boolean DEFAULT false,
  ADD COLUMN IF NOT EXISTS deleted_at     timestamptz,
  ADD COLUMN IF NOT EXISTS updated_at     bigint DEFAULT EXTRACT(EPOCH FROM now())::bigint;

-- 2.2 Purchase Invoices — soft delete
ALTER TABLE public.purchase_invoices
  ADD COLUMN IF NOT EXISTS is_deleted     boolean DEFAULT false,
  ADD COLUMN IF NOT EXISTS deleted_at     timestamptz,
  ADD COLUMN IF NOT EXISTS updated_at     bigint DEFAULT EXTRACT(EPOCH FROM now())::bigint;

-- 2.3 Journal Entries — soft delete + updated_at
ALTER TABLE public.journal_entries
  ADD COLUMN IF NOT EXISTS is_deleted     boolean DEFAULT false,
  ADD COLUMN IF NOT EXISTS deleted_at     timestamptz,
  ADD COLUMN IF NOT EXISTS updated_at     bigint DEFAULT EXTRACT(EPOCH FROM now())::bigint;

-- 2.4 Payments — global_id + idempotency + soft delete + updated_at
ALTER TABLE public.payments
  ADD COLUMN IF NOT EXISTS global_id        uuid DEFAULT gen_random_uuid() UNIQUE,
  ADD COLUMN IF NOT EXISTS idempotency_key  text,
  ADD COLUMN IF NOT EXISTS is_deleted       boolean DEFAULT false,
  ADD COLUMN IF NOT EXISTS deleted_at       timestamptz,
  ADD COLUMN IF NOT EXISTS updated_at       bigint DEFAULT EXTRACT(EPOCH FROM now())::bigint;

-- ─────────────────────────────────────────────────────────────────────────────
-- SECTION 3: New table — category_branches (PIR R-10 join table)
-- Controls per-branch category visibility
-- ─────────────────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.category_branches (
  category_id int NOT NULL REFERENCES public.categories(id) ON DELETE CASCADE,
  branch_id   int NOT NULL REFERENCES public.branches(id)   ON DELETE CASCADE,
  PRIMARY KEY (category_id, branch_id)
);

-- ─────────────────────────────────────────────────────────────────────────────
-- SECTION 4: New table — sync_outbox (offline queue for client→server sync)
-- ─────────────────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.sync_outbox (
  id               bigserial PRIMARY KEY,
  table_name       text NOT NULL,
  remote_id        text,
  record_id        text NOT NULL,
  idempotency_key  text,
  operation        text NOT NULL CHECK (operation IN ('insert','update','delete','upsert')),
  payload          jsonb NOT NULL,
  status           text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','synced','failed')),
  attempts         int NOT NULL DEFAULT 0,
  last_error       text,
  created_at       timestamptz DEFAULT now(),
  last_attempt_at  timestamptz
);

-- ─────────────────────────────────────────────────────────────────────────────
-- SECTION 5: New table — sync_conflict_log (audit trail for sync conflicts)
-- ─────────────────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.sync_conflict_log (
  id              bigserial PRIMARY KEY,
  table_name      text NOT NULL,
  record_id       text NOT NULL,
  resolution      text NOT NULL, -- server_wins, client_wins, merged, skipped
  client_payload  jsonb NOT NULL,
  server_payload  jsonb,
  reason          text,
  client_id       text,
  detected_at     timestamptz DEFAULT now()
);

-- ─────────────────────────────────────────────────────────────────────────────
-- SECTION 6: processed_messages — upgrade for v119 (was created in v118)
-- Add response_payload column which was missing in v118 definition
-- ─────────────────────────────────────────────────────────────────────────────

ALTER TABLE public.processed_messages
  ADD COLUMN IF NOT EXISTS response_payload  text NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS branch_id         int;

-- ─────────────────────────────────────────────────────────────────────────────
-- SECTION 7: Performance indexes for new columns
-- ─────────────────────────────────────────────────────────────────────────────

-- Units
CREATE INDEX IF NOT EXISTS idx_units_global_id           ON public.units (global_id);

-- Accounts
CREATE INDEX IF NOT EXISTS idx_accounts_global_id        ON public.accounts (global_id);

-- Cost Centers
CREATE INDEX IF NOT EXISTS idx_cost_centers_global_id    ON public.cost_centers (global_id);

-- Fiscal Years
CREATE INDEX IF NOT EXISTS idx_fiscal_years_global_id    ON public.fiscal_years (global_id);

-- Accounting Periods
CREATE INDEX IF NOT EXISTS idx_accounting_periods_global_id ON public.accounting_periods (global_id);

-- Safes
CREATE INDEX IF NOT EXISTS idx_safes_global_id           ON public.safes (global_id);

-- Safe Transactions
CREATE INDEX IF NOT EXISTS idx_safe_transactions_global_id ON public.safe_transactions (global_id);

-- Warehouses
CREATE INDEX IF NOT EXISTS idx_warehouses_global_id      ON public.warehouses (global_id);

-- Users
CREATE INDEX IF NOT EXISTS idx_users_global_id           ON public.users (global_id);

-- Stock Movements
CREATE INDEX IF NOT EXISTS idx_stock_movements_global_id     ON public.stock_movements (global_id);
CREATE INDEX IF NOT EXISTS idx_stock_movements_idempotency   ON public.stock_movements (idempotency_key);

-- Payments
CREATE INDEX IF NOT EXISTS idx_payments_global_id        ON public.payments (global_id);
CREATE INDEX IF NOT EXISTS idx_payments_idempotency      ON public.payments (idempotency_key);

-- Sales Invoices — soft delete index
CREATE INDEX IF NOT EXISTS idx_sales_invoices_is_deleted ON public.sales_invoices (is_deleted) WHERE is_deleted = false;

-- Purchase Invoices — soft delete index
CREATE INDEX IF NOT EXISTS idx_purchase_invoices_is_deleted ON public.purchase_invoices (is_deleted) WHERE is_deleted = false;

-- Category Branches
CREATE INDEX IF NOT EXISTS idx_category_branches_branch  ON public.category_branches (branch_id);
CREATE INDEX IF NOT EXISTS idx_category_branches_cat     ON public.category_branches (category_id);

-- Sync Outbox
CREATE INDEX IF NOT EXISTS idx_sync_outbox_status        ON public.sync_outbox (status);
CREATE INDEX IF NOT EXISTS idx_sync_outbox_idempotency   ON public.sync_outbox (idempotency_key);

-- ─────────────────────────────────────────────────────────────────────────────
-- SECTION 8: Data backfill — ensure all existing rows have a global_id
-- ─────────────────────────────────────────────────────────────────────────────

-- Backfill any rows where gen_random_uuid() DEFAULT wasn't applied
UPDATE public.units            SET global_id = gen_random_uuid() WHERE global_id IS NULL;
UPDATE public.accounts         SET global_id = gen_random_uuid() WHERE global_id IS NULL;
UPDATE public.cost_centers     SET global_id = gen_random_uuid() WHERE global_id IS NULL;
UPDATE public.fiscal_years     SET global_id = gen_random_uuid() WHERE global_id IS NULL;
UPDATE public.accounting_periods SET global_id = gen_random_uuid() WHERE global_id IS NULL;
UPDATE public.safes            SET global_id = gen_random_uuid() WHERE global_id IS NULL;
UPDATE public.safe_transactions SET global_id = gen_random_uuid() WHERE global_id IS NULL;
UPDATE public.warehouses       SET global_id = gen_random_uuid() WHERE global_id IS NULL;
UPDATE public.users            SET global_id = gen_random_uuid() WHERE global_id IS NULL;
UPDATE public.stock_movements  SET global_id = gen_random_uuid() WHERE global_id IS NULL;
UPDATE public.payments         SET global_id = gen_random_uuid() WHERE global_id IS NULL;

-- Backfill updated_at for existing rows (bigint = Unix epoch seconds)
UPDATE public.sales_invoices    SET updated_at = EXTRACT(EPOCH FROM now())::bigint WHERE updated_at IS NULL;
UPDATE public.purchase_invoices SET updated_at = EXTRACT(EPOCH FROM now())::bigint WHERE updated_at IS NULL;
UPDATE public.journal_entries   SET updated_at = EXTRACT(EPOCH FROM now())::bigint WHERE updated_at IS NULL;
UPDATE public.payments          SET updated_at = EXTRACT(EPOCH FROM now())::bigint WHERE updated_at IS NULL;
