-- ═══════════════════════════════════════════════════════════════════════════
--  UralCash ERP — سكربت تصحيح بيانات ما قبل الإصدار 3.1.2
--  الهدف: مطابقة البيانات القائمة مع الإصلاحات المحاسبية الجديدة.
--  المنصة: PostgreSQL (خادم المركز).
-- ═══════════════════════════════════════════════════════════════════════════
--
--  ⚠️ اقرأ كل هذا قبل التشغيل.
--
--  السكربت مقسوم إلى مرحلتين:
--    • المرحلة 1 (تشخيص) — قراءة فقط. شغّلها أولاً واقرأ النتائج.
--    • المرحلة 2 (تصحيح) — كتابة. **معطّلة افتراضياً** داخل كتلة تراجع.
--
--  ما **لا** يفعله هذا السكربت عمداً:
--    • لا يُنشئ قيود تسوية محاسبية. القيد قرار محاسبي يحمل تاريخاً وفترةً
--      ومسؤولاً — لا يُولَّد آلياً. السكربت يُخرج لك **قوائم** بما يحتاج تسوية.
--    • لا يحذف أو يعدّل أي قيد يومية قائم. الدفاتر التاريخية لا تُعاد كتابتها.
--
--  قبل التشغيل:
--    1) خذ نسخة احتياطية كاملة:  pg_dump -Fc -d <db> -f backup_pre_3.1.2.dump
--    2) شغّل المرحلة 1 واحتفظ بمخرجاتها — هي دليل التسوية.
--    3) لا تشغّل المرحلة 2 إلا بعد مراجعة محاسبية للمخرجات.
-- ═══════════════════════════════════════════════════════════════════════════

\timing on
\set ON_ERROR_STOP on

-- ═══════════════════════════════════════════════════════════════════════════
--  المرحلة 1 — التشخيص (قراءة فقط، آمنة تماماً)
-- ═══════════════════════════════════════════════════════════════════════════

\echo ''
\echo '════════ 1/6 · تكرارات رقم فاتورة المورد ════════'
\echo 'يجب أن تكون فارغة قبل إضافة أي فهرس فريد.'
\echo 'الحارس التطبيقي يمنع الجديد؛ هذه هي التكرارات التاريخية.'

SELECT supplier_id,
       supplier_invoice_number,
       COUNT(*)                          AS duplicate_count,
       string_agg(id::text, ', ' ORDER BY id) AS invoice_ids,
       string_agg(to_char(invoice_date, 'YYYY-MM-DD'), ', ' ORDER BY id) AS dates,
       SUM(total)                        AS combined_total
FROM purchase_invoices
WHERE supplier_invoice_number IS NOT NULL
  AND supplier_invoice_number <> ''
  AND COALESCE(is_deleted, false) = false
GROUP BY supplier_id, supplier_invoice_number
HAVING COUNT(*) > 1
ORDER BY duplicate_count DESC, supplier_id;

\echo ''
\echo '════════ 2/6 · ذمم وهمية من الخصم المُهمَل ════════'
\echo 'فواتير حُفظت بإجمالي إجمالي بينما دُفع الصافي ⇒ متبقٍ لن يُسدَّد أبداً.'
\echo 'العمود remediation_hint يوضّح الإجراء لكل صف.'

SELECT pi.id,
       pi.invoice_number,
       p.name                                   AS supplier_name,
       pi.invoice_date,
       pi.subtotal,
       pi.discount,
       pi.tax,
       pi.total,
       pi.paid,
       ROUND((pi.total - pi.paid)::numeric, 3)  AS remaining,
       pi.status,
       CASE
         WHEN pi.discount > 0
              AND ABS((pi.subtotal + pi.tax) - pi.total) < 0.01
           THEN 'الخصم مسجّل لكنه لم يُخصم من الإجمالي — ذمة وهمية بمقدار الخصم'
         WHEN pi.discount > 0
           THEN 'راجع يدوياً: خصم موجود والحساب غير قياسي'
         ELSE 'لا خصم'
       END                                      AS remediation_hint
FROM purchase_invoices pi
LEFT JOIN parties p ON p.id = pi.supplier_id
WHERE COALESCE(pi.is_deleted, false) = false
  AND COALESCE(pi.discount, 0) > 0
  AND ABS((pi.subtotal + pi.tax) - pi.total) < 0.01
ORDER BY pi.invoice_date DESC;

\echo ''
\echo '════════ 3/6 · فواتير مشتريات أُلغيت دون عكس قيدها ════════'
\echo 'بوابة isLocked كانت تمنع عكس القيد، فالمخزون عاد والخزينة استُردّت'
\echo 'بينما حساب المخزون في الأستاذ احتفظ بالمدين كاملاً.'

SELECT pi.id,
       pi.invoice_number,
       p.name                AS supplier_name,
       pi.invoice_date,
       pi.total,
       pi.paid,
       pi.deleted_at,
       je.id                 AS live_purchase_je_id,
       je.entry_date         AS je_date,
       (SELECT COALESCE(SUM(jel.debit - jel.credit), 0)
          FROM journal_entry_lines jel
         WHERE jel.entry_id = je.id)  AS je_net_effect,
       'قيد المشتريات ما زال حياً رغم إلغاء الفاتورة — يحتاج قيد عكس يدوي'
                             AS remediation_hint
FROM purchase_invoices pi
LEFT JOIN parties p ON p.id = pi.supplier_id
JOIN journal_entries je
       ON je.reference_id = pi.id
      AND je.reference_type IN ('purchase', 'purchase_invoice')
      AND COALESCE(je.is_auto_posted, false) = true
WHERE COALESCE(pi.is_deleted, false) = true
  -- لا يوجد قيد عكس مقابل
  AND NOT EXISTS (
        SELECT 1 FROM journal_entries rev
         WHERE rev.reference_id = pi.id
           AND rev.reference_type = 'purchase_invoice_void'
      )
ORDER BY pi.deleted_at DESC NULLS LAST;

\echo ''
\echo '════════ 4/6 · مطابقة المخزون: الأستاذ مقابل التقييم الفعلي ════════'
\echo 'ينبغي أن يقترب الفرق من صفر. أي انحراف كبير يعود غالباً لـ 3 أعلاه'
\echo 'أو لأصناف خدمية (track_inventory=false) رُسملت في المخزون.'

WITH gl AS (
  SELECT COALESCE(SUM(jel.debit - jel.credit), 0) AS gl_balance
  FROM journal_entry_lines jel
  JOIN accounts a  ON a.id = jel.account_id
  JOIN journal_entries je ON je.id = jel.entry_id
  WHERE a.code = '1136'
    AND COALESCE(je.is_posted, true) = true
),
stock AS (
  SELECT COALESCE(SUM(ib.quantity * COALESCE(pr.cost_price, 0)), 0) AS stock_value
  FROM inventory_balances ib
  JOIN products pr ON pr.id = ib.product_id
  WHERE COALESCE(pr.track_inventory, true) = true
)
SELECT gl.gl_balance                              AS "الأستاذ 1136",
       stock.stock_value                          AS "قيمة المخزون الفعلية",
       ROUND((gl.gl_balance - stock.stock_value)::numeric, 3) AS "الفرق"
FROM gl, stock;

\echo ''
\echo '════════ 5/6 · أصناف خدمية مُرسملة في المخزون ════════'
\echo 'سطور بلا تتبّع مخزني قُيّدت على حساب المخزون ولن تُصرف أبداً.'

SELECT pr.id            AS product_id,
       pr.code,
       pr.name,
       COUNT(pii.id)    AS line_count,
       ROUND(SUM(pii.quantity * pii.unit_cost)::numeric, 3) AS capitalised_amount
FROM purchase_invoice_items pii
JOIN products pr           ON pr.id = pii.product_id
JOIN purchase_invoices pi  ON pi.id = pii.invoice_id
WHERE COALESCE(pr.track_inventory, true) = false
  AND COALESCE(pi.is_deleted, false) = false
GROUP BY pr.id, pr.code, pr.name
ORDER BY capitalised_amount DESC;

\echo ''
\echo '════════ 6/6 · أصناف بنسبة ضريبة خارج السلّم القانوني ════════'
\echo 'السلّم: 0 · 1 · 2 · 4 · 5 · 10 · 16. النسب السالبة تولّد ضريبة سالبة.'

SELECT id, code, name, tax_rate,
       CASE WHEN tax_rate < 0
            THEN 'نسبة سالبة — تولّد ضريبة سالبة في كل سطر بيع وشراء'
            ELSE 'خارج السلّم القانوني'
       END AS issue
FROM products
WHERE COALESCE(tax_rate, 0) NOT IN (0, 1, 2, 4, 5, 10, 16)
ORDER BY tax_rate;


-- ═══════════════════════════════════════════════════════════════════════════
--  المرحلة 2 — التصحيح (كتابة)
-- ═══════════════════════════════════════════════════════════════════════════
--
--  ⚠️ هذه الكتلة تنتهي بـ ROLLBACK عمداً. شغّلها كما هي أولاً لترى العدّادات،
--     ثم — بعد مراجعة محاسبية — بدّل السطر الأخير إلى COMMIT.
--
--  ما تصلحه:
--    (أ) رابط المرتجعات: إضافة المعرّف العالمي للفاتورة الأصلية داخل notes
--        حتى يصمد الرابط أمام اختلاف المعرّفات بين الأجهزة.
--    (ب) نسب الضريبة السالبة → صفر (النسبة السالبة لا معنى لها بأي حال).
--
--  ما **لا** تصلحه (يحتاج قراراً بشرياً):
--    • الذمم الوهمية والقيود غير المعكوسة → قيود تسوية يدوية بناءً على 2 و3.
--    • تكاليف المخزون الإجمالية للفواتير المخصومة السابقة → إعادة تقييم
--      المتوسط المرجّح تُغيّر تكلفة المبيعات لفترات مُقفَلة. لا تُفعل آلياً.
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

\echo ''
\echo '──── (أ) تعزيز رابط المرتجعات بالمعرّف العالمي ────'

-- سجلّ ما قبل التعديل — يبقى داخل المعاملة للمراجعة.
CREATE TEMP TABLE _return_link_backup AS
SELECT id, notes
FROM sales_invoices
WHERE sale_type = 'return'
  AND notes LIKE 'Return for invoice #%'
  AND notes NOT LIKE '%|gid:%'
  AND COALESCE(is_deleted, false) = false;

UPDATE sales_invoices r
   SET notes = r.notes || '|gid:' || orig.global_id
  FROM sales_invoices orig
 WHERE r.sale_type = 'return'
   AND r.notes LIKE 'Return for invoice #%'
   AND r.notes NOT LIKE '%|gid:%'
   AND COALESCE(r.is_deleted, false) = false
   AND orig.global_id IS NOT NULL
   AND orig.global_id <> ''
   -- الرقم المخزَّن في notes هو معرّف **هذا** الخادم، فالمطابقة صحيحة هنا.
   AND orig.id = NULLIF(regexp_replace(
                          split_part(r.notes, '#', 2), '\D', '', 'g'), '')::int;

\echo 'صفوف مرتجعات عُزّز رابطها:'
SELECT COUNT(*) AS strengthened_links FROM _return_link_backup;

\echo ''
\echo '──── (ب) نسب ضريبة سالبة → صفر ────'

CREATE TEMP TABLE _neg_tax_backup AS
SELECT id, code, name, tax_rate
FROM products
WHERE COALESCE(tax_rate, 0) < 0;

UPDATE products SET tax_rate = 0 WHERE COALESCE(tax_rate, 0) < 0;

\echo 'أصناف صُحّحت نسبتها السالبة:'
SELECT * FROM _neg_tax_backup;

\echo ''
\echo '════════════════════════════════════════════════════════════'
\echo '  المعاملة ستتراجع الآن (ROLLBACK) — لم يُحفظ أي تغيير.'
\echo '  بعد المراجعة المحاسبية: بدّل ROLLBACK إلى COMMIT وأعد التشغيل.'
\echo '════════════════════════════════════════════════════════════'

ROLLBACK;
-- COMMIT;   ← فعّل هذا بدلاً من ROLLBACK بعد الموافقة


-- ═══════════════════════════════════════════════════════════════════════════
--  المرحلة 3 — الفهرس الفريد (اختياري، بعد تنظيف التكرارات فقط)
-- ═══════════════════════════════════════════════════════════════════════════
--
--  لا تشغّل هذا إلا بعد أن يعود استعلام 1/6 أعلاه **فارغاً**. غير ذلك ستفشل.
--  CONCURRENTLY يتجنّب قفل الجدول، لذا يجب تشغيله خارج أي معاملة.
--
--  CREATE UNIQUE INDEX CONCURRENTLY IF NOT EXISTS
--      ux_purchase_invoices_supplier_invoice_no
--      ON purchase_invoices (supplier_id, supplier_invoice_number)
--      WHERE supplier_invoice_number IS NOT NULL
--        AND supplier_invoice_number <> ''
--        AND COALESCE(is_deleted, false) = false;
--
--  للتراجع:  DROP INDEX CONCURRENTLY ux_purchase_invoices_supplier_invoice_no;
-- ═══════════════════════════════════════════════════════════════════════════
