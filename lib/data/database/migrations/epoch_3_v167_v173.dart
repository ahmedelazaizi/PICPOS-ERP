part of '../database.dart';

/// Epoch 3 migration steps v167–v173 (pure move out of `epoch_3.dart`;
/// no behaviour change). Called in order by `_migrateEpoch3`.
///
extension Epoch3MigrationsV167ToV173 on AppDatabase {
  Future<void> _migrateEpoch3V167ToV173(Migrator m, int from) async {

    // ═══════════════════════════════════════════════════════════════════
    // v167 — المرحلة ٣: أعمدةُ المزامنة للفئةِ التشغيليّة (ثمانيةَ عشرَ جدولاً)
    // ═══════════════════════════════════════════════════════════════════
    //
    // ═══ العطبُ الذي تسدّه ═══
    //
    // المطاعمُ والمطبخُ والحجوزاتُ والتوزيعُ كلُّها **محلّيّةٌ بالكامل**:
    // طلبُ طاولةٍ يُفتَح على جهازٍ ولا يراه جهازٌ ثانٍ، وأمرُ تحضيرٍ يُطبَع
    // في المطبخ ولا يُغلَق من الكاشير، وحجزٌ يُؤخَذ على الاستقبال فتُباع
    // الطاولةُ نفسُها مرّتين. وهذه ليست تقارير — إنّها **حالةُ تشغيلٍ
    // لحظيّةٌ** يقرؤها أكثرُ من جهازٍ في آنٍ واحد، وهي أكثرُ ما يُشترى
    // النظامُ من أجله في مطعمٍ متعدّدِ النقاط.
    //
    // ═══ لماذا هذه الفئةُ أرخصُ من المرحلة ٢ ═══
    //
    // مقيسٌ لا مقدَّر: `tables_dao.dart` و`kitchen_dao.dart` فيهما **صفرُ**
    // استدعاءٍ لـ`createJournalEntry` وصفرُ حركةِ خزنةٍ أو مخزون، و
    // `bookings_dao.dart` فيه **واحد**. فالفئةُ في جوهرها **مسارٌ واردٌ
    // فقط** — أعمدةٌ وهجرةٌ وعضويّةُ قوائم — ولا تحتاج مسارَ الدفعِ الثقيلَ
    // الذي بنته المرحلة ٢ إلّا في موضعِ خصمِ العربونِ وحدَه.
    //
    // ═══ الصيغةُ نفسُها لنفسِ الأسباب ═══
    //
    // عمودٌ عاديٌّ ثمّ فهرسٌ فريدٌ جزئيّ (`ADD COLUMN … UNIQUE` مرفوضةٌ في
    // SQLite)، وتعبئةٌ بـ`UuidV7` **قبلَ** المُشغِّل، ومُشغِّلٌ يرفع
    // `row_version` بحارسِ `WHEN` يمنع الدور. انظر v166 أعلاه للتفصيل.
    //
    // ⚠️ و`booking_resources` و`booking_services` و`booking_reminders` لها
    //    `deleted_at` سلفاً (‏وُلدت به في `createTable`) — الـsafe-skip
    //    يتكفّل به، ولذلك تعريفُ الـDart لا يكرّره.
    if (from < 167) {
      await _safeMigrate('v167 أعمدةُ مزامنةٍ للفئةِ التشغيليّة', () async {
        const phase3Tables = [
          // الموظَّفُ — أبٌ لخمسةٍ من الفئة، وثلاثةٌ منها تشير إليه بإشارةٍ
          // غيرِ قابلةٍ للإفراغ. وليس فتحاً لشؤون الموظّفين.
          'employees',
          // المطاعمُ — الطاولاتُ وطلباتُها
          'table_sections', 'restaurant_tables', 'table_orders',
          'table_order_items', 'table_reservations', 'table_order_payments',
          // المطبخُ — أوامرُ التحضير ومحطّاتُها
          'kitchen_stations', 'category_station_mappings',
          'work_orders', 'work_order_items',
          // الحجوزاتُ — الموارد والخدمات والتذكيرات
          'booking_resources', 'booking_services', 'bookings',
          'booking_reminders',
          // التوزيعُ — خطوطُ السير وزياراتُها وتحصيلاتُ المندوبين
          'sales_routes', 'route_visits', 'sales_rep_targets',
          'sales_rep_collections',
        ];

        for (final t in phase3Tables) {
          // ١. المعرّفُ العالميّ — عمودٌ عاديٌّ ثمّ فهرسٌ فريدٌ جزئيّ.
          try {
            await m.database.customStatement(
              'ALTER TABLE $t ADD COLUMN global_id TEXT',
            );
          } catch (e) {
            debugPrint('[Migration] v167 ADD $t.global_id (safe-skip): $e');
          }
          try {
            await m.database.customStatement(
              'CREATE UNIQUE INDEX IF NOT EXISTS idx_${t}_global_id '
              'ON $t(global_id) WHERE global_id IS NOT NULL',
            );
          } catch (e) {
            debugPrint('[Migration] v167 IX $t.global_id (safe-skip): $e');
          }

          // ٢. تعبئةُ الصفوفِ القائمة — **قبلَ** المُشغِّل عمداً.
          try {
            final existing = await m.database
                .customSelect(
                  "SELECT id FROM $t WHERE global_id IS NULL OR global_id = ''",
                )
                .get();
            for (final row in existing) {
              await m.database.customStatement(
                'UPDATE $t SET global_id = ? WHERE id = ?',
                [UuidV7.generate(), row.data['id']],
              );
            }
          } catch (e) {
            debugPrint('[Migration] v167 backfill $t.global_id (safe-skip): $e');
          }

          // ٣. أعمدةُ الدلتا الأربعة.
          for (final ddl in [
            'ALTER TABLE $t ADD COLUMN last_modified_at INTEGER',
            'ALTER TABLE $t ADD COLUMN deleted_at INTEGER',
            'ALTER TABLE $t ADD COLUMN origin_client_id TEXT',
            'ALTER TABLE $t ADD COLUMN row_version INTEGER NOT NULL DEFAULT 0',
          ]) {
            try {
              await m.database.customStatement(ddl);
            } catch (_) {} // safe-skip: العمودُ موجودٌ سلفاً
          }

          // ٤. مُشغِّلُ رفعِ النسخة.
          try {
            await m.database.customStatement('''
              CREATE TRIGGER IF NOT EXISTS ${t}_bump_version
              AFTER UPDATE ON $t FOR EACH ROW
              WHEN NEW.row_version = OLD.row_version
              BEGIN
                UPDATE $t SET
                  last_modified_at = strftime('%s', 'now'),
                  row_version = OLD.row_version + 1
                WHERE id = NEW.id;
              END
            ''');
          } catch (e) {
            debugPrint('[Migration] v167 trigger $t: $e');
          }
        }

        debugPrint(
          '[Migration] v167: أعمدةُ المزامنة على '
          '${phase3Tables.length} جدولاً تشغيليّاً',
        );
      });
    }

    // ═══════════════════════════════════════════════════════════════════
    // v168 — إهلاكُ الأصول يُرحَّل كلَّ شهرٍ لا شهراً واحداً ثمّ صمت
    // ═══════════════════════════════════════════════════════════════════
    //
    // 🔴 كشفته مصالحةُ الأصول في المرحلة ٤، ولا يظهر في أيّ اختبارِ وحدة.
    //
    // فهرسُ v120 `idx_je_autopost_dedup` فريدٌ على
    // `(reference_type, reference_id)` للقيود التلقائيّة، ويستثني أنواعاً
    // تُنتج قيداً لكلِّ حدث. و`asset_depreciation` **لم يكن** منها بينما
    // `referenceId` فيه رقمُ الأصل **بلا فترة**.
    //
    // فالنتيجةُ قبلَ هذه الخطوة: أصلٌ يُهلَك شهريّاً يُرحَّل في شهره الأوّل
    // فقط، ويُبتلَع كلُّ شهرٍ تالٍ بحجّة التكرار — بينما صفُّ
    // `asset_depreciations` يُكتَب والبطاقةُ تتقدّم. مجمَّعُ الإهلاك في
    // الأستاذ يتجمّد، فالأصولُ مضخَّمةٌ في الميزانيّة ومصروفُ الإهلاك
    // منقوصٌ في قائمة الدخل — وضريبةُ دخلٍ على أساسٍ خاطئ.
    //
    // ⚠️ **ورفعُ الحارس البرمجيِّ وحدَه لا يكفي بل يزيد الطينَ بلّة:**
    //    القيدُ يمرّ الحارسَ ثمّ يصطدم بالفهرس بـ`UNIQUE constraint
    //    failed`، و`runMonthlyDepreciation` يلتقط الاستثناءَ لكلِّ أصلٍ
    //    ويتخطّاه، فتتراجع المعاملةُ كلُّها — لا قيدَ ولا صفَّ إهلاكٍ ولا
    //    بطاقةً متقدّمة. أي أنّ الإهلاكَ **يتوقّف** بدل أن يُنقَص، و
    //    المصالحةُ تمرّ خضراءَ لأنّ الطرفَين تساويا عند الرقم الخاطئ.
    //    فالطرفان يُصلَحان معاً أو لا يُصلَح أحدُهما.
    //
    // و`DROP` ثمّ `CREATE` لأنّ `CREATE ... IF NOT EXISTS` لا يبدّل شكلَ
    // فهرسٍ قائم — نفسُ صيغةِ v150 حرفاً.
    if (from < 168) {
      await _safeMigrate('v168 إعفاءُ الإهلاك من فهرس إزالة التكرار', () async {
        await m.database
            .customStatement('DROP INDEX IF EXISTS $kJeAutopostDedupIndexName');
        await m.database.customStatement(kCreateJeAutopostDedupIndexSql);
        debugPrint('[Migration] v168: الإهلاكُ صار يُرحَّل شهريّاً');
      });
    }

    if (from < 169) {
      await _safeMigrate('v169 نموذجُ النطاقات ورابطاتُ القوالب', () async {
        // ── لماذا ALTER خامٌّ لا m.addColumn ─────────────────────────────
        // نفسُ نمطِ ما سبقه في هذا الملفّ: كلُّ عبارةٍ في try مستقلٍّ، فعمودٌ
        // موجودٌ سلفاً لا يوقف البقيّة. والأعمدةُ **مُعلَنةٌ أيضاً في أصناف
        // الجداول**، فالتنصيبُ الجديدُ يأخذها من onCreate — والإعلانُ في
        // مكانٍ واحدٍ فقط هو كيف غاب approved_by عن كلِّ قاعدةٍ جديدة.
        //
        // وكلُّها بلا افتراضٍ عمداً: الصفرُ موضعٌ حقيقيٌّ عند الحافّة، و
        // null وحدَها تقول «لم يُهاجَر بعد».
        for (final ddl in [
          'ALTER TABLE invoice_template_elements ADD COLUMN band_id TEXT',
          'ALTER TABLE invoice_template_elements ADD COLUMN x_mm REAL',
          'ALTER TABLE invoice_template_elements ADD COLUMN y_mm REAL',
          'ALTER TABLE invoice_template_elements ADD COLUMN w_mm REAL',
          'ALTER TABLE invoice_template_elements ADD COLUMN h_mm REAL',
          'ALTER TABLE invoice_template_elements ADD COLUMN condition TEXT',
          'ALTER TABLE invoice_templates '
              'ADD COLUMN layout_version INTEGER NOT NULL DEFAULT 1',
          "ALTER TABLE invoice_table_settings "
              "ADD COLUMN table_kind TEXT NOT NULL DEFAULT 'items'",
          'ALTER TABLE invoice_table_settings ADD COLUMN columns_json TEXT',
        ]) {
          try {
            await m.database.customStatement(ddl);
          } catch (e) {
            debugPrint('[Migration] v169 (safe-skip): $e');
          }
        }

        // جدولُ الرابطات. تمريرةُ `allSchemaEntities` في ensureSchemaDefaults
        // تغطّيه كذلك على كلِّ إقلاع، وهذا صريحٌ لئلّا يعتمد إنشاؤه على أثرٍ
        // جانبيٍّ في مكانٍ آخر.
        try {
          await m.createTable(templateBindings);
        } catch (e) {
          debugPrint('[Migration] v169 template_bindings (safe-skip): $e');
        }

        debugPrint('[Migration] v169: النطاقاتُ والرابطاتُ جاهزة');
      });
    }

    if (from < 170) {
      await _safeMigrate('v170 ارتفاعاتُ النطاقات تُحفَظ', () async {
        // ── لماذا عمودٌ أصلاً ──────────────────────────────────────────
        // كان ارتفاعُ النطاق مشتقّاً — أبعدُ قاعِ عنصرٍ فيه. فزرّا `+`/`−`
        // في لوحة «ارتفاع النطاق» يعملان في الجلسة ثمّ يعود الرقمُ عند
        // إعادة الفتح، والحشوةُ السفليّةُ التي يطلبها التصميمُ لا مكانَ لها.
        //
        // ⚠️ **ومُعلَنٌ في صنف الجدول كذلك** (`InvoiceTemplates.bandHeights`):
        //    الإعلانُ في مكانٍ واحدٍ فقط هو كيف غاب `approved_by` عن كلِّ
        //    قاعدةٍ جديدة — `onCreate` يبني من كيانات drift لا من هذه الخطوة.
        //
        // و`null` بلا افتراضٍ عمداً: تعني «اشتقّ كما كنتَ تفعل»، لا صفراً.
        // القوالبُ القائمةُ كلُّها ستقرؤها فارغةً فتبقى على سلوكها.
        try {
          await m.database.customStatement(
            'ALTER TABLE invoice_templates ADD COLUMN band_heights TEXT',
          );
        } catch (e) {
          debugPrint('[Migration] v170 (safe-skip): $e');
        }
        debugPrint('[Migration] v170: ارتفاعُ النطاق صار يُحفَظ');
      });
    }

    if (from < 171) {
      await _safeMigrate('v171 فرقُ تقريب الإجماليّ', () async {
        // ── لماذا عمودٌ لا اشتقاق ──────────────────────────────────────
        // سياسةُ `pos_total_rounding` تُقرِّب **المقبوض** ويبقى `total`
        // حقيقيّاً. والفرقُ بينهما ليس ديناً على العميل — فبلا عمودٍ يحمله
        // كانت الفاتورةُ تُقرأ `pending` إلى الأبد، أو يُرمى القيدُ كلُّه
        // بـ«المدين لا يساوي الدائن» بعدما خرج المخزونُ ودخل النقدُ الدرجَ
        // فعلاً (‏المقبوضُ صعوداً)، أو تُفتح ذمّةٌ وهميّةٌ على حساب المراقبة
        // لزبونٍ عابرٍ بلا حسابٍ فرعيّ (‏هبوطاً).
        //
        // ⚠️ **ومُعلَنٌ في صنف الجدول كذلك** (`SalesInvoices.roundingAdjustment`):
        //    الإعلانُ في مكانٍ واحدٍ فقط هو كيف غاب `approved_by` عن كلِّ
        //    قاعدةٍ جديدة — `onCreate` يبني من كيانات drift لا من هذه الخطوة.
        //
        // و`NOT NULL DEFAULT 0` لا nullable: صفرٌ يعني «بلا تقريب»، وهو
        // الحقُّ حرفيّاً لكلِّ فاتورةٍ سابقةٍ — فالسياسةُ لم تكن تعمل أصلاً.
        // فلا تكتب الهجرةُ صفّاً واحداً ويبقى سلوكُ ما قبلَها حرفيّاً.
        try {
          await m.database.customStatement(
            'ALTER TABLE sales_invoices '
            'ADD COLUMN rounding_adjustment REAL NOT NULL DEFAULT 0',
          );
        } catch (e) {
          debugPrint('[Migration] v171 (safe-skip): $e');
        }
        debugPrint('[Migration] v171: فرقُ التقريب صار له عمودٌ صريح');
      });
    }

    if (from < 172) {
      await _safeMigrate('v172 مستندُ مرتجع المشتريات', () async {
        // §٦‑٢ — الطرفُ الثاني الغائبُ في تسوية ض.ق.م.
        //
        // مرتجعُ الشراء كان بلا صفٍّ في أيِّ جدولِ مستندات، فضريبتُه تُشتقّ
        // من الأستاذ نفسِه ⇒ الطرفان يقرآن مصدراً واحداً ويتّفقان بالبناء.
        //
        // ⚠️ **ومُعلَنٌ في `@DriftDatabase` كذلك** (`PurchaseReturns`):
        //    `onCreate` يبني من كيانات drift لا من هذه الخطوة، والإعلانُ في
        //    مكانٍ واحدٍ فقط هو كيف غاب `approved_by` عن كلِّ قاعدةٍ جديدة.
        //    فالخطوةُ هنا للقواعد المُرقّاة وحدَها، والكيانُ للجديدة.
        //
        // و`createTable` تُولّد `CREATE TABLE IF NOT EXISTS`، فهي no-op على
        // قاعدةٍ نالته من `createAll`.
        try {
          await m.createTable(purchaseReturns);
        } catch (e) {
          debugPrint('[Migration] v172 (safe-skip): $e');
        }
        debugPrint('[Migration] v172: مرتجعُ الشراء صار مستنداً بضريبته');
      });
    }

    // ═══════════════════════════════════════════════════════════════════
    // v173 — المرحلة ٤: أعمدةُ المزامنة للسجلِّ الرقابيِّ والتشغيلِ العابر
    // ═══════════════════════════════════════════════════════════════════
    //
    // ═══ العطبُ الذي تسدّه ═══
    //
    // ستّةٌ وعشرون جدولاً كانت محلّيّةً بالكامل وحكمُها في
    // `sync_coverage_guard_test` 🔴 «يجب أن تُزامَن»:
    //
    //   • **سجلٌّ قانونيٌّ ورقابيّ** — تقديماتُ الفاتورة الإلكترونيّة وسجلُّ
    //     حالاتها، وسجلُّ تغييرات الحقول، وفشلُ الترحيل، وسيرُ الاعتماد
    //     بطلباته وقراراته، وتعارضاتُ فصل المهامّ وانتهاكاتُها، وفحوصُ
    //     الامتثال. ضياعُ الجهاز ضياعُ الإثبات، ولا يُعاد بناؤه.
    //   • **تشغيلٌ عابرٌ للأجهزة** — الجردُ الدوريُّ وجردُ المخزون وطلباتُ
    //     الصرف، ونقاطُ الولاء، وشركاتُ التوصيل ومندوبوها، والمطابقةُ
    //     البنكيّةُ بأسطر كشفها، وأسعارُ المخازن. جهازٌ يطابق كشفاً لا يراه
    //     جهازٌ آخرُ فيطابقه ثانية.
    //
    // ⚠️ و`e_invoice_configs` **مستثنًى عمداً**: يحمل `client_secret` نصّاً،
    //    ومسارُ السحب يُرسل `SELECT *`. استبعادُ العمود على السلك يُسقط
    //    الإدراجَ على العميل (‏`NOT NULL` بلا افتراض) صامتاً، وإرسالُ قيمةٍ
    //    بديلةٍ يدهس سرَّ العميل المحلّيَّ بـ`INSERT OR REPLACE`. فبقاؤه
    //    محلّيّاً هو الحكمُ المكتوبُ في الحارس، لا سهو.
    //
    // ═══ الصيغةُ نسخةُ v167 حرفاً ═══
    //
    // عمودٌ عاديٌّ + فهرسٌ فريدٌ جزئيّ (‏`ADD COLUMN … UNIQUE` مرفوضةٌ في
    // SQLite)، وتعبئةٌ بـ`UuidV7` **قبلَ** المُشغِّل، ومُشغِّلٌ يرفع
    // `row_version` بحارسِ `WHEN` يمنع الدور.
    //
    // ⚠️ و`stock_requisitions` لها `global_id` وفهرسُه منذ v149 — الـsafe-skip
    //    يتكفّل بهما والتعبئةُ تملأ الفارغَ وحدَه. و`e_invoice_status_log`
    //    كانت جدولاً بلا كيانٍ (٦‑١) وصارت كياناً في v173، فهذه الخطوةُ
    //    تُلحِق الأعمدةَ بالقواعد المُرقّاة و`createAll` يبنيها للجديدة.
    if (from < 173) {
      await _safeMigrate('v173 أعمدةُ مزامنةٍ للسجلِّ الرقابيِّ والتشغيلِ العابر',
          () async {
        const phase4Tables = [
          // التشغيلُ العابرُ للأجهزة
          'loyalty_programs', 'delivery_companies', 'couriers',
          'customer_loyalty_points', 'loyalty_transactions',
          'warehouse_prices',
          'cycle_count_plans', 'cycle_count_tasks', 'cycle_count_items',
          'stock_audits', 'stock_audit_items',
          'stock_requisitions', 'stock_requisition_items',
          'bank_reconciliations', 'bank_statement_lines',
          // السجلُّ القانونيُّ والرقابيّ
          'e_invoice_submissions', 'e_invoice_status_log',
          'field_audit_logs', 'failed_autoposts',
          'approval_workflows', 'approval_steps', 'approval_requests',
          'approval_decisions', 'sod_conflicts', 'sod_violations',
          'compliance_checks',
        ];

        for (final t in phase4Tables) {
          // ١. المعرّفُ العالميّ — عمودٌ عاديٌّ ثمّ فهرسٌ فريدٌ جزئيّ.
          try {
            await m.database.customStatement(
              'ALTER TABLE $t ADD COLUMN global_id TEXT',
            );
          } catch (e) {
            debugPrint('[Migration] v173 ADD $t.global_id (safe-skip): $e');
          }
          try {
            await m.database.customStatement(
              'CREATE UNIQUE INDEX IF NOT EXISTS idx_${t}_global_id '
              'ON $t(global_id) WHERE global_id IS NOT NULL',
            );
          } catch (e) {
            debugPrint('[Migration] v173 IX $t.global_id (safe-skip): $e');
          }

          // ٢. تعبئةُ الصفوفِ القائمة — **قبلَ** المُشغِّل عمداً.
          try {
            final existing = await m.database
                .customSelect(
                  "SELECT id FROM $t WHERE global_id IS NULL OR global_id = ''",
                )
                .get();
            for (final row in existing) {
              await m.database.customStatement(
                'UPDATE $t SET global_id = ? WHERE id = ?',
                [UuidV7.generate(), row.data['id']],
              );
            }
          } catch (e) {
            debugPrint('[Migration] v173 backfill $t.global_id (safe-skip): $e');
          }

          // ٣. أعمدةُ الدلتا الأربعة.
          for (final ddl in [
            'ALTER TABLE $t ADD COLUMN last_modified_at INTEGER',
            'ALTER TABLE $t ADD COLUMN deleted_at INTEGER',
            'ALTER TABLE $t ADD COLUMN origin_client_id TEXT',
            'ALTER TABLE $t ADD COLUMN row_version INTEGER NOT NULL DEFAULT 0',
          ]) {
            try {
              await m.database.customStatement(ddl);
            } catch (_) {} // safe-skip: العمودُ موجودٌ سلفاً
          }

          // ٤. مُشغِّلُ رفعِ النسخة.
          try {
            await m.database.customStatement('''
              CREATE TRIGGER IF NOT EXISTS ${t}_bump_version
              AFTER UPDATE ON $t FOR EACH ROW
              WHEN NEW.row_version = OLD.row_version
              BEGIN
                UPDATE $t SET
                  last_modified_at = strftime('%s', 'now'),
                  row_version = OLD.row_version + 1
                WHERE id = NEW.id;
              END
            ''');
          } catch (e) {
            debugPrint('[Migration] v173 trigger $t: $e');
          }
        }

        debugPrint(
          '[Migration] v173: أعمدةُ المزامنة على '
          '${phase4Tables.length} جدولاً رقابيّاً وتشغيليّاً',
        );
      });
    }
  }
}
