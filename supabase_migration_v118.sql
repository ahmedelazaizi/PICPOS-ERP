-- Migration V118: Inject UUID-First Architecture & Branch Visibility
-- This script adds the missing columns to existing tables without dropping them.

-- 1. Extend Categories
ALTER TABLE public.categories 
ADD COLUMN IF NOT EXISTS global_id uuid DEFAULT gen_random_uuid() UNIQUE,
ADD COLUMN IF NOT EXISTS is_global boolean DEFAULT true,
ADD COLUMN IF NOT EXISTS branch_ids text;

-- 2. Extend Parties (Customers/Suppliers)
ALTER TABLE public.parties 
ADD COLUMN IF NOT EXISTS global_id uuid DEFAULT gen_random_uuid() UNIQUE,
ADD COLUMN IF NOT EXISTS is_global boolean DEFAULT true,
ADD COLUMN IF NOT EXISTS branch_ids text;

-- 3. Extend Products (For UUID-first reference)
ALTER TABLE public.products 
ADD COLUMN IF NOT EXISTS global_id uuid DEFAULT gen_random_uuid() UNIQUE;

-- 4. Extend Sales Invoices
ALTER TABLE public.sales_invoices 
ADD COLUMN IF NOT EXISTS global_id uuid DEFAULT gen_random_uuid() UNIQUE,
ADD COLUMN IF NOT EXISTS idempotency_key uuid;

-- 5. Extend Purchase Invoices
ALTER TABLE public.purchase_invoices 
ADD COLUMN IF NOT EXISTS global_id uuid DEFAULT gen_random_uuid() UNIQUE,
ADD COLUMN IF NOT EXISTS idempotency_key uuid;

-- 6. Extend Journal Entries
ALTER TABLE public.journal_entries 
ADD COLUMN IF NOT EXISTS global_id uuid DEFAULT gen_random_uuid() UNIQUE,
ADD COLUMN IF NOT EXISTS idempotency_key uuid;

-- 7. Add Processed Messages (Replay Prevention)
CREATE TABLE IF NOT EXISTS public.processed_messages (
    idempotency_key uuid PRIMARY KEY,
    created_at timestamptz DEFAULT now(),
    branch_id int,
    action_type text NOT NULL
);

-- Index for fast lookup on global_id
CREATE INDEX IF NOT EXISTS idx_categories_global_id ON public.categories (global_id);
CREATE INDEX IF NOT EXISTS idx_parties_global_id ON public.parties (global_id);
CREATE INDEX IF NOT EXISTS idx_products_global_id ON public.products (global_id);
CREATE INDEX IF NOT EXISTS idx_sales_invoices_global_id ON public.sales_invoices (global_id);
CREATE INDEX IF NOT EXISTS idx_purchase_invoices_global_id ON public.purchase_invoices (global_id);
CREATE INDEX IF NOT EXISTS idx_journal_entries_global_id ON public.journal_entries (global_id);

-- 8. Data Integrity Remediation: Fix Orphan Journal Entries & Safes
-- Ensures all financial operations are correctly visible when filtering by branch
UPDATE public.safes SET branch_id = 1 WHERE branch_id IS NULL;
UPDATE public.journal_entries SET branch_id = 1 WHERE branch_id IS NULL;

-- 9. Backfill Missing Cost Centers on Existing Journal Entries
-- Fixes issue where POS failed to sync warehouse/branch cost centers resulting in null/GEN fallbacks
UPDATE public.journal_entries
SET cost_center_id = COALESCE(w.cost_center_id, b.cost_center_id)
FROM public.sales_invoices si
JOIN public.warehouses w ON si.warehouse_id = w.id
LEFT JOIN public.branches b ON w.branch_id = b.id
WHERE public.journal_entries.reference_type = 'sale' 
  AND public.journal_entries.reference_id = si.id 
  AND public.journal_entries.cost_center_id IS NULL
  AND COALESCE(w.cost_center_id, b.cost_center_id) IS NOT NULL;

-- Repair journal entries that incorrectly defaulted to GEN instead of the warehouse/branch CC
UPDATE public.journal_entries
SET cost_center_id = COALESCE(w.cost_center_id, b.cost_center_id)
FROM public.sales_invoices si
JOIN public.warehouses w ON si.warehouse_id = w.id
LEFT JOIN public.branches b ON w.branch_id = b.id
JOIN public.cost_centers cc ON cc.code = 'GEN'
WHERE public.journal_entries.reference_type = 'sale' 
  AND public.journal_entries.reference_id = si.id 
  AND public.journal_entries.cost_center_id = cc.id
  AND COALESCE(w.cost_center_id, b.cost_center_id) IS NOT NULL;
