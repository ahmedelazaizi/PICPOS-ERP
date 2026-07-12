-- ============================================================
-- URAL ERP — Migration v122: Region Layer
-- تطبيق على قاعدة بيانات PostgreSQL موجودة (بدون حذف وإعادة بناء)
-- ============================================================
-- التشغيل: psql -U <user> -d <database> -f migration_v122_regions.sql
-- ============================================================

BEGIN;

-- ──────────────────────────────────────────────────────────────
-- 1. جدول المناطق (regions)
-- ──────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS regions (
    id              SERIAL PRIMARY KEY,
    name            TEXT    NOT NULL,
    address         TEXT,
    phone           TEXT,
    cost_center_id  INTEGER REFERENCES cost_centers(id),
    is_active       BOOLEAN NOT NULL DEFAULT TRUE,
    global_id       TEXT    UNIQUE
);

CREATE INDEX IF NOT EXISTS idx_regions_active
    ON regions(is_active);

-- ──────────────────────────────────────────────────────────────
-- 2. إضافة region_id إلى branches
-- ──────────────────────────────────────────────────────────────
ALTER TABLE branches
    ADD COLUMN IF NOT EXISTS region_id INTEGER REFERENCES regions(id);

CREATE INDEX IF NOT EXISTS idx_branches_region
    ON branches(region_id);

-- ──────────────────────────────────────────────────────────────
-- 3. إضافة region_id إلى warehouses
-- ──────────────────────────────────────────────────────────────
ALTER TABLE warehouses
    ADD COLUMN IF NOT EXISTS region_id INTEGER REFERENCES regions(id);

CREATE INDEX IF NOT EXISTS idx_warehouses_region
    ON warehouses(region_id);

-- ──────────────────────────────────────────────────────────────
-- 4. إضافة region_id إلى safes
-- ──────────────────────────────────────────────────────────────
ALTER TABLE safes
    ADD COLUMN IF NOT EXISTS region_id INTEGER REFERENCES regions(id);

-- ──────────────────────────────────────────────────────────────
-- 5. جدول صلاحيات المناطق للمستخدمين (user_region_access)
-- ──────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS user_region_access (
    user_id     INTEGER NOT NULL REFERENCES users(id)   ON DELETE CASCADE,
    region_id   INTEGER NOT NULL REFERENCES regions(id) ON DELETE CASCADE,
    PRIMARY KEY (user_id, region_id)
);

CREATE INDEX IF NOT EXISTS idx_user_region_access_user
    ON user_region_access(user_id);

CREATE INDEX IF NOT EXISTS idx_user_region_access_region
    ON user_region_access(region_id);

-- ──────────────────────────────────────────────────────────────
-- 6. (اختياري) تسجيل رقم الإصدار في جدول schema_version إن وُجد
--    عدّل اسم الجدول/العمود حسب إعداداتك إن كان مختلفاً
-- ──────────────────────────────────────────────────────────────
-- UPDATE schema_migrations SET version = 122 WHERE id = 1;

COMMIT;

-- ============================================================
-- ملاحظات ما بعد التطبيق:
-- 1. تأكد أن schemaVersion في database.dart = 122
-- 2. شغّل: dart run build_runner build --delete-conflicting-outputs
--    لإعادة توليد database.g.dart بعد تعديل الجداول
-- 3. اختبار:
--    - أنشئ منطقة جديدة من شاشة المناطق
--    - ارتبط فرع موجود بالمنطقة
--    - تأكد أن قيود المبيعات تحمل اسم المنطقة في الوصف
-- ============================================================
