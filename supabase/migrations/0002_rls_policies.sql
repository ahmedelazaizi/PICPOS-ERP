-- ============================================================================
-- URAL-ERP — Row Level Security Policies
-- ============================================================================
-- Default deny: enable RLS on every table. Only explicit policies grant access.
-- All policies key off current_tenant_id() (reads user_profiles.tenant_id).
-- ============================================================================

-- ============================================================================
-- TENANTS: user can only see their own tenant row
-- ============================================================================
ALTER TABLE tenants ENABLE ROW LEVEL SECURITY;

CREATE POLICY tenants_select ON tenants
    FOR SELECT USING (id = current_tenant_id());

-- Updates/inserts/deletes on tenants are NOT exposed via API; managed by admin
-- through service_role key only (which bypasses RLS).

-- ============================================================================
-- USER_PROFILES: self-read + tenant-admin read; writes only by admin
-- ============================================================================
ALTER TABLE user_profiles ENABLE ROW LEVEL SECURITY;

CREATE POLICY user_profiles_self_read ON user_profiles
    FOR SELECT USING (id = auth.uid());

CREATE POLICY user_profiles_tenant_admin_read ON user_profiles
    FOR SELECT USING (
        tenant_id = current_tenant_id()
        AND current_user_role() IN ('admin', 'manager')
    );

CREATE POLICY user_profiles_admin_write ON user_profiles
    FOR ALL USING (
        tenant_id = current_tenant_id()
        AND current_user_role() = 'admin'
    )
    WITH CHECK (
        tenant_id = current_tenant_id()
        AND current_user_role() = 'admin'
    );

CREATE POLICY user_profiles_self_update ON user_profiles
    FOR UPDATE USING (id = auth.uid())
    WITH CHECK (
        id = auth.uid()
        AND tenant_id = current_tenant_id()  -- prevent moving self across tenants
        AND role = (SELECT role FROM user_profiles WHERE id = auth.uid())  -- prevent self-escalation
    );

-- ============================================================================
-- Generic tenant-scoped CRUD policy generator
-- ============================================================================
-- For each content table: anyone in the tenant can SELECT; INSERT/UPDATE/DELETE
-- require either role-based check or explicit permission.
-- ============================================================================

-- BRANCHES
ALTER TABLE branches ENABLE ROW LEVEL SECURITY;

CREATE POLICY branches_tenant_select ON branches
    FOR SELECT USING (tenant_id = current_tenant_id());

CREATE POLICY branches_admin_write ON branches
    FOR ALL USING (
        tenant_id = current_tenant_id()
        AND current_user_role() IN ('admin', 'manager')
    )
    WITH CHECK (tenant_id = current_tenant_id());

-- WAREHOUSES
ALTER TABLE warehouses ENABLE ROW LEVEL SECURITY;

CREATE POLICY warehouses_tenant_select ON warehouses
    FOR SELECT USING (tenant_id = current_tenant_id());

CREATE POLICY warehouses_admin_write ON warehouses
    FOR ALL USING (
        tenant_id = current_tenant_id()
        AND current_user_role() IN ('admin', 'manager')
    )
    WITH CHECK (tenant_id = current_tenant_id());

-- CATEGORIES
ALTER TABLE categories ENABLE ROW LEVEL SECURITY;

CREATE POLICY categories_tenant_select ON categories
    FOR SELECT USING (tenant_id = current_tenant_id());

CREATE POLICY categories_manager_write ON categories
    FOR ALL USING (
        tenant_id = current_tenant_id()
        AND current_user_role() IN ('admin', 'manager')
    )
    WITH CHECK (tenant_id = current_tenant_id());

-- PRODUCTS
ALTER TABLE products ENABLE ROW LEVEL SECURITY;

CREATE POLICY products_tenant_select ON products
    FOR SELECT USING (tenant_id = current_tenant_id());

CREATE POLICY products_manager_write ON products
    FOR ALL USING (
        tenant_id = current_tenant_id()
        AND current_user_role() IN ('admin', 'manager')
    )
    WITH CHECK (tenant_id = current_tenant_id());

-- CUSTOMERS
ALTER TABLE customers ENABLE ROW LEVEL SECURITY;

CREATE POLICY customers_tenant_select ON customers
    FOR SELECT USING (tenant_id = current_tenant_id());

CREATE POLICY customers_write ON customers
    FOR ALL USING (
        tenant_id = current_tenant_id()
        AND current_user_role() IN ('admin', 'manager', 'cashier')
    )
    WITH CHECK (tenant_id = current_tenant_id());

-- SUPPLIERS
ALTER TABLE suppliers ENABLE ROW LEVEL SECURITY;

CREATE POLICY suppliers_tenant_select ON suppliers
    FOR SELECT USING (tenant_id = current_tenant_id());

CREATE POLICY suppliers_manager_write ON suppliers
    FOR ALL USING (
        tenant_id = current_tenant_id()
        AND current_user_role() IN ('admin', 'manager')
    )
    WITH CHECK (tenant_id = current_tenant_id());

-- STOCK_BALANCES (read-only from client — writes go through RPC functions)
ALTER TABLE stock_balances ENABLE ROW LEVEL SECURITY;

CREATE POLICY stock_tenant_select ON stock_balances
    FOR SELECT USING (tenant_id = current_tenant_id());

-- No client-side INSERT/UPDATE/DELETE for stock_balances.
-- All stock changes must go through Edge Functions or RPCs (future migration).
