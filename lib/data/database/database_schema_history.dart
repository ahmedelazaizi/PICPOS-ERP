part of 'database.dart';

// Schema-version history for `AppDatabase.schemaVersion`. Comment-only part: the
// notes below were moved verbatim from the doc comment above the getter.

  // Current schema version.
  //
  // Bump this whenever table definitions or migrations change.
  // See [migration] for the full upgrade path.
  // Schema v49: Phase 5.2-5.3 — Loyalty Points + Distribution
  // Schema v142: Feature 004 (Multi-Branch Governance) — FixedAssets gains
  // `global_id` (UUIDv7) + `linked_account_id` for atomic CoA sub-account linkage.
  //
  // Schema v143: Feature 005 (CoA Hardening) — re-aligns party sub-account
  // parents from the phantom `'1201'`/`'2101'` codes (which were never in
  // the seeder) to the seeded `'1121'`/`'2111'`. The migration attempts to
  // move any orphan sub-accounts off `1201`/`2101` to the seeded counterparts
  // then deletes the orphan parents — best-effort, no-op when those codes
  // aren't present.
  //
  // Schema v144: Feature 005 Phase 8 — archives duplicate safe-linked
  // accounts (orphan no-dash siblings of the canonical `111-XXXXX` rows)
  // that some users created via the manual COA dialog. Soft-delete only,
  // preserves rows that carry JE lines.
  //
  // Schema v145: Spec 008 / FR-001 — adds `branch_id` to `shifts` (nullable)
  // so multi-branch users can record which branch each shift was opened on.
  //
  // Schema v146: Feature 009 (Auto-Deplete BOM on Sale) — adds
  // `auto_deplete_on_sale` + `depletion_policy` columns on `bill_of_materials`,
  // creates the `sale_bom_consumptions` append-only log, creates the
  // `pos_terminals` master-data registry, and adds nullable
  // `pos_terminal_id` on `shifts` for per-terminal policy resolution.
  //
  // Schema v150: Spec 151 (return-key fix) — RETURN journal entries are now
  // keyed on the ORIGINATING invoice id, so multiple partial returns of one
  // invoice share `(reference_type, reference_id)`. Drop + recreate
  // `idx_je_autopost_dedup` with an exemption for the multi-JE reference types
  // (returns + commercial papers + partial collections) so the second partial
  // return no longer violates UNIQUE, and backfill historical hash-keyed
  // return JEs onto their invoice id. Index-only change — no table/column
  // change, so no generated schema regeneration is required.
  //
  // Schema v153: الأجرُ بالساعة والإضافي المحسوب (المهمة ٢) — جدولُ
  // `work_holidays` (تقويمُ العطلات لكلّ فرع)، وعمودُ
  // `employees.hours_per_day` (مقامُ أجر الساعة)، وعمودُ
  // `overtime_records.is_manual_amount` (تعليمُ السجلّات القائمة كي لا
  // يُعاد اشتقاقُها).
  //
  // Schema v155: ضريبةُ المبيعات على طلبات الطاولات — عمودا
  // `table_orders.tax_enabled` (مرآةُ `CartState.taxEnabled`، افتراضُه
  // `false`) و`table_orders.tax_rate` (لقطةُ `pos_default_tax_rate` كسريّةً
  // لحظةَ فتح الطاولة، فلا يُعاد تسعيرُ حسابٍ عُرض على الضيف). بهما يصير
  // المشحونُ على الفاتورة والمسجَّلُ على الطلب رقماً واحداً، فيسكت حارسُ
  // `checkTableCharge` عن حقٍّ لا عن إضعاف.
  //
  // **١٥٦** — قيدُ `CHECK (NOT tax_enabled OR tax_rate > 0)` على
  // `table_orders`: ما حرسته v155 عند مفتاح التفعيل صار مستحيلَ التمثيل في
  // الجدول نفسِه. والترقيةُ تُعيد إنشاءَ الجدول (SQLite لا تضيف قيداً
  // بـ`ALTER TABLE`) بعد تسويةِ أيِّ صفٍّ كاذبٍ قائم.
  //
  // **١٥٧** — شدُّ ذلك القيدِ إلى `tax_rate >= 0.01`: `> 0` كانت تقبل
  // `0.0000001`، فالزرُّ «مفعَّل» والقيدُ راضٍ والمحصَّلُ صفرٌ بعد التقريب —
  // الكذبةُ نفسُها بصورةٍ تمرّ من تحت قيدِ ١٥٦. والحدُّ الآن واحدٌ عند
  // الأبواب الثلاثة: مدخلُ الإعدادات، و`setOrderTax`، وهذا القيد.
  // ⚠️ ‏160: ١٥٩ أخذته جداولُ محرِّك الحجز حين دخلت `main`، وفرعُ
  // `pos-flexible-permissions` كان قد أخذ ١٥٩ نفسَه لترقيةٍ أخرى — نقلِ فئة
  // `pos_shift_close` إلى الخزينة. فرُفعت تلك إلى **١٦٠** عند الدمج، ورُفع
  // حارسُها في [epoch_3] إلى `from < 160` معها. ولا تفصل بينهما: رقمٌ يُرفَع
  // وحارسٌ يبقى قديماً = ترقيةٌ لا تُطبَّق أبداً وتمرّ صامتة.
  // ⚠️ ‏162: ليست ميزةً بل إنقاذ. خطوةُ 161 كانت تنادي `alterTable` بلا
  // `newColumns`، فرمت `no such column: "role"` وابتلعها `_safeMigrate`
  // (تعدُّها خطأً عديمَ الأثر) — فخُتمت القواعدُ 161 وأعمدةُ المورد لم تُضَف،
  // و`from < 161` لا يعود يفحصها. الخطوةُ الجديدةُ تفحص ثمّ تُصلح.
  // ⚠️ **١٧٥ لا ١٧٤ عند الدمج (2026-09-20).** فرعُ الأصول جاء برقم ١٧٤ وهذا
  // الفرعُ عند ١٧٥ (‏طلبُ الاستبعاد)، وحارسُ هجرتِه `from < 174` فيسري على
  // كلِّ قاعدةٍ دون ١٧٤ سواءٌ خُتمت بـ١٧٥ أم لا. والخفضُ إلى ١٧٤ كان يُسقط
  // `migration_numbering_test` (يطابق الرقمَ بأكبر كتلةِ هجرة) **ويُبطِل
  // هجرةَ ١٧٥ على كلّ قاعدةٍ مُرقّاةٍ سلفاً**.
  //
  // Schema v177: sale reposts after an authorized edit may legitimately
  // produce multiple auto-posted JEs for one invoice reference.
  //
  // Schema v196: customers are the single reference for reservations —
  // table_reservations.party_id (bookings.party_id already existed) + the local
  // party_dedup_suspects report; F.1 backfill links/creates customers by phone
  // (migrations/epoch_3_v196_v205.dart, reservation_parties_*.dart).
