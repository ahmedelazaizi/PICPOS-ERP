-- ═══════════════════════════════════════════════════════════════════════════
--  PicPos / UralCash ERP — تسوية قيود PostgreSQL على السيرفرات القايمة
--  المنصة: PostgreSQL (خادم المركز فقط — لا يخص SQLite على الأجهزة).
-- ═══════════════════════════════════════════════════════════════════════════
--
--  ⚠️ اقرأ كل هذا قبل التشغيل.
--
--  السكربت مقسوم إلى مرحلتين:
--    • المرحلة 1 (تشخيص) — قراءة فقط. شغّلها أولاً واقرأ النتائج.
--    • المرحلة 2 (تصحيح) — كتابة. **معطّلة افتراضياً** داخل كتلة تراجع.
--
--  ───────────────────────────────────────────────────────────────────────
--  لماذا هذا السكربت موجود، ولماذا هو **يدوي** وليس في مسار الإقلاع
--  ───────────────────────────────────────────────────────────────────────
--
--  قياس 2026-08-03 على خادم PostgreSQL حيّ أثبت أن **التنصيبة الجديدة سليمة**:
--    155 جدول · 154 PRIMARY KEY · 53 UNIQUE · 269 FOREIGN KEY · 120 CHECK
--  والجداول الثمانية التي ظنّناها بلا مفاتيح، كلها تحمل مفاتيحها المركّبة.
--  السبب أن `_createAllForPostgres` المرحلة 1 تستدعي `m.create()` من drift
--  نفسه، وهو واعٍ باللهجة ويُخرج القيود صحيحة على PG.
--
--  ⇒ هذا السكربت **لا يلزم** خادماً أُنشئ حديثاً. يلزم فقط:
--    (أ) خادماً بُني بإصدار أقدم سقطت فيه القيود عبر المسار الاحتياطي، أو
--    (ب) خادماً بُني من `supabase_migration_v118.sql` اليدوي (شكل مختلف
--        لجدول processed_messages — انظر القسم 3).
--
--  ولماذا يدوي: `ALTER TABLE ... ADD CONSTRAINT` على بيانات تحمل تكرارات
--  **يفشل**. وجملة فاشلة داخل مسار الإقلاع = شاشة Fatal تمنع التشغيل — وهي
--  بالضبط فئة العطل v132 التي كلّفت هذا المشروع إصداراً كاملاً. القرار في
--  حذف صف مكرر قرار مالك، لا قرار كود يعمل وقت بدء التشغيل.
--
--  ما **لا** يفعله هذا السكربت عمداً:
--    • لا يحذف شيئاً في المرحلة 1 — ولا حتى صفاً واحداً.
--    • لا يضيف قيداً على جدول تظهر فيه تكرارات؛ يُخرج لك القائمة وتقرّر أنت.
--    • لا يلمس القيود الأربعة التي يُصلحها التطبيق تلقائياً عند الإقلاع
--      (‏`_ensureDatabaseIntegrity`): role_permissions PK · settings PK ·
--      permissions.code UNIQUE · accounts.code UNIQUE. تكرارها هنا عبث.
--
--  قبل التشغيل:
--    1) خذ نسخة احتياطية كاملة:
--         pg_dump -Fc -d <db> -f backup_pre_constraints.dump
--    2) أوقف كل العملاء والخادم. القيود تُضاف بقفل ACCESS EXCLUSIVE.
--    3) شغّل المرحلة 1 واحتفظ بمخرجاتها — هي دليل التسوية.
-- ═══════════════════════════════════════════════════════════════════════════

\timing on
\set ON_ERROR_STOP on

\echo ''
\echo '═══════════════════════════════════════════════════════════════════'
\echo '  المرحلة 1 — تشخيص (قراءة فقط، لا يكتب شيئاً)'
\echo '═══════════════════════════════════════════════════════════════════'

-- ───────────────────────────────────────────────────────────────────────────
-- 1-أ. لقطة عامة: هل هذا الخادم يحتاج السكربت أصلاً؟
--     المرجع المقيس على تنصيبة سليمة: 154 PK · 53 UNIQUE · 269 FK.
--     أرقام أقل بكثير ⇒ الخادم وُلد من مسار احتياطي وفقد قيوده.
-- ───────────────────────────────────────────────────────────────────────────
\echo ''
\echo '── 1-أ. جرد القيود الحالي (قارنه بـ 154 / 53 / 269) ──'
SELECT
    (SELECT count(*) FROM information_schema.tables
      WHERE table_schema = 'public' AND table_type = 'BASE TABLE') AS tables,
    (SELECT count(*) FROM pg_constraint
      WHERE connamespace = 'public'::regnamespace AND contype = 'p') AS primary_keys,
    (SELECT count(*) FROM pg_constraint
      WHERE connamespace = 'public'::regnamespace AND contype = 'u') AS uniques,
    (SELECT count(*) FROM pg_constraint
      WHERE connamespace = 'public'::regnamespace AND contype = 'f') AS foreign_keys;

-- ───────────────────────────────────────────────────────────────────────────
-- 1-ب. الجداول الستة التي لا يُصلحها التطبيق تلقائياً.
--     (role_permissions و settings مستبعدان — `_ensureDatabaseIntegrity`
--      يتكفّل بهما عند كل إقلاع.)
-- ───────────────────────────────────────────────────────────────────────────
\echo ''
\echo '── 1-ب. أي من الجداول الستة يفتقد مفتاحه الأساسي؟ ──'
WITH expected(tbl, cols) AS (
    VALUES
        ('document_sequences',    'prefix'),
        ('processed_messages',    'idempotency_key'),
        ('user_branch_access',    'user_id, branch_id'),
        ('user_warehouse_access', 'user_id, warehouse_id'),
        ('user_region_access',    'user_id, region_id'),
        ('category_branches',     'category_id, branch_id')
)
SELECT
    e.tbl                       AS "الجدول",
    e.cols                      AS "المفتاح المتوقَّع",
    CASE WHEN c.oid IS NULL THEN '❌ مفقود' ELSE '✓ موجود' END AS "الحالة",
    coalesce(pg_get_constraintdef(c.oid), '—') AS "التعريف الفعلي"
FROM expected e
LEFT JOIN pg_class      t ON t.relname = e.tbl
                         AND t.relnamespace = 'public'::regnamespace
LEFT JOIN pg_constraint c ON c.conrelid = t.oid AND c.contype = 'p'
WHERE t.oid IS NOT NULL          -- تجاهل جدولاً غير موجود أصلاً
ORDER BY 3 DESC, 1;

-- ───────────────────────────────────────────────────────────────────────────
-- 1-ج. التكرارات التي **ستُفشل** إضافة كل مفتاح.
--     أي صف يظهر هنا يعني: لا تشغّل المرحلة 2 قبل حسم هذه الصفوف.
-- ───────────────────────────────────────────────────────────────────────────
\echo ''
\echo '── 1-ج. تكرارات تمنع إضافة المفاتيح (فارغ = آمن) ──'
SELECT 'document_sequences' AS "الجدول", prefix::text AS "المفتاح", count(*) AS "عدد"
  FROM document_sequences GROUP BY prefix HAVING count(*) > 1
UNION ALL
SELECT 'processed_messages', idempotency_key::text, count(*)
  FROM processed_messages GROUP BY idempotency_key HAVING count(*) > 1
UNION ALL
SELECT 'user_branch_access', user_id || '/' || branch_id, count(*)
  FROM user_branch_access GROUP BY user_id, branch_id HAVING count(*) > 1
UNION ALL
SELECT 'user_warehouse_access', user_id || '/' || warehouse_id, count(*)
  FROM user_warehouse_access GROUP BY user_id, warehouse_id HAVING count(*) > 1
UNION ALL
SELECT 'user_region_access', user_id || '/' || region_id, count(*)
  FROM user_region_access GROUP BY user_id, region_id HAVING count(*) > 1
UNION ALL
SELECT 'category_branches', category_id || '/' || branch_id, count(*)
  FROM category_branches GROUP BY category_id, branch_id HAVING count(*) > 1
ORDER BY 1, 3 DESC;

-- ───────────────────────────────────────────────────────────────────────────
-- 1-د. شكل processed_messages مقابل تعريف drift.
--     خادم بُني من supabase_migration_v118.sql يختلف في **خمسة** أعمدة،
--     وأخطرها `created_at`: drift يخزّن التاريخ BIGINT (epoch) بينما السكربت
--     اليدوي يستخدم timestamptz ⇒ كل قراءة تُرجع DateTime حيث يُنتظر int،
--     فيصبح منع التكرار ميتاً بالكامل لا مجرد ضعيف.
-- ───────────────────────────────────────────────────────────────────────────
\echo ''
\echo '── 1-د. شكل processed_messages (المتوقَّع: text/text/text-null/bigint) ──'
WITH expected(col, typ, nullable) AS (
    VALUES
        ('idempotency_key',  'text',   'NO'),
        ('response_payload', 'text',   'NO'),
        ('action_type',      'text',   'YES'),
        ('created_at',       'bigint', 'NO')
)
SELECT
    e.col                                   AS "العمود",
    e.typ                                   AS "النوع المتوقَّع",
    coalesce(c.data_type, '❌ غير موجود')    AS "النوع الفعلي",
    e.nullable                              AS "nullable متوقَّع",
    coalesce(c.is_nullable, '—')            AS "nullable فعلي",
    CASE
        WHEN c.column_name IS NULL                          THEN '❌ عمود مفقود'
        WHEN c.data_type <> e.typ                           THEN '❌ نوع مختلف'
        WHEN c.is_nullable <> e.nullable                    THEN '⚠ nullability معكوس'
        ELSE '✓'
    END                                     AS "الحكم"
FROM expected e
LEFT JOIN information_schema.columns c
       ON c.table_schema = 'public'
      AND c.table_name   = 'processed_messages'
      AND c.column_name  = e.col;

\echo ''
\echo '── 1-د2. أعمدة زائدة في processed_messages ليست في تعريف drift ──'
\echo '   (‏branch_id مثلاً يأتي من v118. زائد nullable = غير ضار.'
\echo '    زائد NOT NULL = يكسر كل INSERT من التطبيق.)'
SELECT column_name AS "العمود", data_type AS "النوع", is_nullable AS "nullable"
  FROM information_schema.columns
 WHERE table_schema = 'public' AND table_name = 'processed_messages'
   AND column_name NOT IN
       ('idempotency_key', 'response_payload', 'action_type', 'created_at');

-- ───────────────────────────────────────────────────────────────────────────
-- 1-هـ. قيود UNIQUE على global_id.
--     منظومة منع تكرار الفواتير مبنية عليها. على خادم فقدها يصبح المسار
--     check-then-insert بلا قيد خلفه ⇒ طلبان متزامنان يُدخِلان فاتورتين.
-- ───────────────────────────────────────────────────────────────────────────
\echo ''
\echo '── 1-هـ. جداول فيها global_id بلا قيد UNIQUE (فارغ = آمن) ──'
-- استثناء واحد مقصود: `remote_id_mappings.global_id` معرَّف في drift
-- (‏sync_tables.dart) بـ `text().nullable()` **بلا** `.unique()` — هو جدول
-- ربط بين المعرّف المحلي والبعيد، ونفس الـglobal_id يظهر فيه لصفوف مختلفة
-- بشكل مشروع. إدراجه هنا كان يُرسل المشغّل خلف مشكلة غير موجودة.
SELECT c.table_name AS "الجدول"
  FROM information_schema.columns c
 WHERE c.table_schema = 'public'
   AND c.column_name  = 'global_id'
   AND c.table_name  <> 'remote_id_mappings'
   AND NOT EXISTS (
       SELECT 1
         FROM pg_constraint k
        WHERE k.conrelid = (quote_ident(c.table_name))::regclass
          AND k.contype IN ('u', 'p')
          AND pg_get_constraintdef(k.oid) LIKE '%(global_id)%')
 ORDER BY 1;

\echo ''
\echo '── 1-هـ2. لكل جدول ظهر في 1-هـ، افحص تكراراته قبل إضافة القيد ──'
\echo '   SELECT global_id, count(*) FROM <الجدول>'
\echo '    WHERE global_id IS NOT NULL'
\echo '    GROUP BY global_id HAVING count(*) > 1;'

\echo ''
\echo '═══════════════════════════════════════════════════════════════════'
\echo '  انتهت المرحلة 1. اقرأ المخرجات أعلاه قبل المتابعة.'
\echo ''
\echo '  • كل الأقسام تقول ✓ / فارغة  ⇒ خادمك سليم، لا تشغّل المرحلة 2.'
\echo '  • القسم 1-ج أظهر صفوفاً       ⇒ احسم التكرارات يدوياً أولاً.'
\echo '  • القسم 1-د أظهر ❌            ⇒ خادمك من v118؛ راجع القسم 3 أدناه.'
\echo '═══════════════════════════════════════════════════════════════════'


-- ═══════════════════════════════════════════════════════════════════════════
--  المرحلة 2 — تصحيح (كتابة)
--
--  ⚠️ معطّلة افتراضياً: الكتلة تنتهي بـ ROLLBACK.
--  بعد مراجعة مخرجات المرحلة 1، غيّر السطر الأخير إلى COMMIT وأعد التشغيل.
--
--  المرحلة 2 **لا تحذف أي صف**. إذا وجدت تكراراً تتخطّى الجدول وتُبلغ.
--  حذف الصفوف المكرّرة قرارك أنت، بعد أن ترى ما هي في القسم 1-ج.
-- ═══════════════════════════════════════════════════════════════════════════

\echo ''
\echo '═══════════════════════════════════════════════════════════════════'
\echo '  المرحلة 2 — تصحيح (ستنتهي بـ ROLLBACK ما لم تغيّرها)'
\echo '═══════════════════════════════════════════════════════════════════'

BEGIN;

DO $$
DECLARE
    r          record;
    dup_count  bigint;
    sql_text   text;
BEGIN
    FOR r IN
        SELECT * FROM (VALUES
            ('document_sequences',    'prefix',                  'prefix'),
            ('processed_messages',    'idempotency_key',         'idempotency_key'),
            ('user_branch_access',    'user_id, branch_id',      'user_id, branch_id'),
            ('user_warehouse_access', 'user_id, warehouse_id',   'user_id, warehouse_id'),
            ('user_region_access',    'user_id, region_id',      'user_id, region_id'),
            ('category_branches',     'category_id, branch_id',  'category_id, branch_id')
        ) AS t(tbl, cols, groupcols)
    LOOP
        -- الجدول غير موجود على هذا الخادم؟ تخطَّ بصمت.
        IF to_regclass('public.' || r.tbl) IS NULL THEN
            RAISE NOTICE '— %: الجدول غير موجود، تخطٍّ.', r.tbl;
            CONTINUE;
        END IF;

        -- المفتاح موجود بالفعل؟ لا شيء لفعله.
        IF EXISTS (SELECT 1 FROM pg_constraint
                    WHERE conrelid = ('public.' || r.tbl)::regclass
                      AND contype = 'p') THEN
            RAISE NOTICE '✓ %: المفتاح الأساسي موجود.', r.tbl;
            CONTINUE;
        END IF;

        -- تكرارات تمنع الإضافة؟ أبلغ وتخطَّ — لا تحذف.
        EXECUTE format(
            'SELECT count(*) FROM (SELECT %s FROM %I GROUP BY %s HAVING count(*) > 1) d',
            r.groupcols, r.tbl, r.groupcols)
          INTO dup_count;

        IF dup_count > 0 THEN
            RAISE WARNING
              '❌ %: % مجموعة مكرّرة تمنع إضافة المفتاح. احسمها يدوياً (القسم 1-ج) ثم أعد التشغيل.',
              r.tbl, dup_count;
            CONTINUE;
        END IF;

        sql_text := format('ALTER TABLE %I ADD CONSTRAINT %I PRIMARY KEY (%s)',
                           r.tbl, r.tbl || '_pkey', r.cols);
        RAISE NOTICE '→ %', sql_text;
        EXECUTE sql_text;
        RAISE NOTICE '✓ %: أُضيف المفتاح الأساسي.', r.tbl;
    END LOOP;
END $$;

\echo ''
\echo '── جرد القيود بعد التصحيح (داخل الكتلة، قبل الحسم) ──'
SELECT
    (SELECT count(*) FROM pg_constraint
      WHERE connamespace = 'public'::regnamespace AND contype = 'p') AS primary_keys,
    (SELECT count(*) FROM pg_constraint
      WHERE connamespace = 'public'::regnamespace AND contype = 'u') AS uniques;

-- ⬇⬇⬇ غيّر هذا السطر إلى  COMMIT;  بعد مراجعة كل ما سبق ⬇⬇⬇
ROLLBACK;

\echo ''
\echo '═══════════════════════════════════════════════════════════════════'
\echo '  انتهى. إن رأيت ROLLBACK أعلاه فلم يتغيّر شيء في قاعدتك.'
\echo '═══════════════════════════════════════════════════════════════════'


-- ═══════════════════════════════════════════════════════════════════════════
--  القسم 3 — خوادم بُنيت من supabase_migration_v118.sql
--
--  لا يُعالَج آلياً هنا: تصحيح النوع يتطلّب تحويل بيانات قائمة، وقرار
--  التحويل يعتمد على ما إذا كانت هناك سجلات منع تكرار حيّة يُعتدّ بها.
--
--  الفروق الخمسة عن تعريف drift (‏sync_tables.dart):
--    1. response_payload  — مطلوب في drift، **غير موجود** في v118.
--    2. action_type       — nullable في drift، NOT NULL في v118 (معكوس).
--    3. idempotency_key   — text في drift، uuid في v118 (نوع مختلف).
--    4. created_at        — BIGINT epoch في drift، timestamptz في v118.
--    5. branch_id         — غير موجود في drift، موجود في v118 (nullable فغير ضار).
--
--  الأسلم عملياً: `processed_messages` ذاكرة منع تكرار قصيرة الأجل، وليست
--  دفتراً. إعادة بنائها فارغةً تُفقد فقط قدرة إعادة تشغيل الطلبات المعلّقة
--  لحظة التنفيذ. نفّذ والخدمة متوقفة:
--
--    DROP TABLE IF EXISTS processed_messages;
--    CREATE TABLE processed_messages (
--        idempotency_key  text   PRIMARY KEY,
--        response_payload text   NOT NULL,
--        action_type      text,
--        created_at       bigint NOT NULL DEFAULT (EXTRACT(EPOCH FROM NOW())::bigint)
--    );
--
--  ثم أعد تشغيل الخادم: تمريرة التطابق ستقبل هذا الشكل بلا تحذير.
-- ═══════════════════════════════════════════════════════════════════════════
