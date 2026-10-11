part of '../database.dart';

/// Epoch 3 migration steps v157–v166 (pure move out of `epoch_3.dart`;
/// no behaviour change). Called in order by `_migrateEpoch3`.
///
extension Epoch3MigrationsV157ToV166 on AppDatabase {
  Future<void> _migrateEpoch3V157ToV166(Migrator m, int from) async {

    // ── v157: الحدُّ الأدنى المعقولُ للنسبة، لا مجرّد «فوق الصفر» ──────────
    //
    // قيدُ v156 (`tax_rate > 0`) يقبل `0.0000001`: القيدُ راضٍ، والزرُّ يقول
    // «مفعَّلة»، والمحصَّلُ صفرٌ بعد التقريب — الكذبةُ التي أُغلقت عائدةً
    // بصورةٍ تمرّ من تحت القيد نفسِه. والحدُّ الآن `TaxRateBounds.minRate`
    // (١٪) عند الأبواب الثلاثة: مدخلُ الإعدادات، و`setOrderTax`، والقيد.
    //
    // نفسُ آليّة v156 ونفسُ ترتيبها: التسويةُ **تسبق** إعادةَ البناء
    // بالضرورة — صفٌّ مخالفٌ قائمٌ يُفشل `m.alterTable` فيقتل الإقلاع.
    //
    // وتُطفئ الزرَّ ولا تُلفّق نسبةً: الفاتورةُ خرجت بضريبةٍ تُقرَّب إلى صفرٍ
    // فعلاً، فإطفاءُ الزرِّ هو ما يجعل السجلَّ يطابق ما حُصِّل. ورفعُ اللقطة
    // إلى الحدِّ الآن يعيد تسعيرَ حسابٍ رآه الضيفُ ودُفع.
    //
    // والمطفأُ لا يُمَسّ وإن كانت لقطتُه دون الحدّ — القيدُ لا يطارد مطفأً،
    // واللقطةُ تبقى محفوظةً كما تركها v156.
    if (from < 157) {
      await _safeMigrate('v157 table_orders minimum tax rate', () async {
        await customStatement(
          'UPDATE table_orders SET tax_enabled = 0 '
          'WHERE tax_enabled = 1 AND tax_rate < 0.01',
        );
        await m.alterTable(TableMigration(tableOrders, newColumns: [
          tableOrders.globalId, // v167 — انظر v156 أعلاه
          tableOrders.lastModifiedAt,
          tableOrders.deletedAt,
          tableOrders.originClientId,
          tableOrders.rowVersion,
        ]));
        debugPrint('[Migration] v157 table_orders minimum tax rate OK');
      });
    }

    // ── v158: الحجزُ ثم التثبيت — دفعةٌ بلا فاتورةٍ بعد ──────────────────
    //
    // `invoice_id` يصير معدوماً-مسموحاً ويُضاف `status`، فيصير الصفُّ قابلاً
    // لأن يُدرَج **قبل** الترحيل. وبه تعمل كلُّ حراس `recordPayment` قبل أن
    // تُرحَّل فاتورةٌ — فإن رفضت، لم يصدر شيءٌ يحتاج تسوية.
    //
    // وإسقاطُ `NOT NULL` لا يجري بـ`ALTER TABLE` في SQLite، فالسبيلُ إعادةُ
    // إنشاء الجدول — وهو ما تفعله `m.alterTable` بالخطوات الاثنتَي عشرة.
    // و`addColumn` تسبقها لأن `TableMigration` تنسخ الأعمدةَ القائمةَ فحسب،
    // فعمودٌ لم يوجد بعدُ لا يُنقَل بل يُنشَأ بافتراضه.
    //
    // ولا تسويةَ بيانات: الافتراضُ `settled` وكلُّ صفٍّ قائمٍ له `invoice_id`
    // غيرُ معدوم، فالقيدُ يرضى عن الصفوف القائمة كما هي.
    //
    // ⚠️ ولأن `m.alterTable` تبني تعريفَ **اليوم**: أيُّ تشديدٍ لاحقٍ لهذا
    // القيد يجب أن يُراجَع مع كلِّ خطوةٍ أقدمَ تُعيد بناءَ هذا الجدول.
    if (from < 158) {
      await _safeMigrate('v158 table_order_payments reserve-then-commit',
          () async {
        await m.addColumn(tableOrderPayments, tableOrderPayments.status);
        await m.alterTable(TableMigration(tableOrderPayments, newColumns: [
          tableOrderPayments.globalId, // v167 — انظر v156 أعلاه
          tableOrderPayments.lastModifiedAt,
          tableOrderPayments.deletedAt,
          tableOrderPayments.originClientId,
          tableOrderPayments.rowVersion,
        ]));
        debugPrint('[Migration] v158 table_order_payments reserve/commit OK');
      });
    }

    if (from < 159) {
      await _safeMigrate('v159 booking engine tables', () async {
        // جداولُ جديدةٌ خالصةٌ — لا `alterTable`، فلا خطرَ إعادةِ بناءِ
        // جدولٍ قائمٍ ولا إسقاطَ خطوةٍ أقدمَ تُعيد بناءَ نفس الجدول.
        await m.createTable(bookingResources);
        await m.createTable(bookingServices);
        await m.createTable(bookings);

        // فهرسُ المسار الساخن `(resource_id, starts_at)` — فهرسٌ خامٌّ لا
        // كيانُ drift، فلا `createTable` ولا `createAll` بيصدّروه. وهو
        // **غير فريد** عمداً: التداخلُ يُمنَع بالفحص في الـDAO لا بقيد،
        // وصفّان في نفس اللحظة مشروعان ما دام أحدُهما ملغًى أو لم يحضر.
        //
        // وهنا **قاتلٌ** بخلاف فهرسَي v152: الجدولُ أُنشئ في هذه الخطوةِ
        // نفسِها قبل سطرين، فلا بياناتٌ قائمةٌ تُفشله، وفشلُه يعني خللاً
        // حقيقيّاً يجب أن يظهر.
        await m.database.customStatement(kCreateBookingResourceSlotIndexSql);
        debugPrint('[Migration] v159 booking engine tables OK');
      });
    }

    // ── v160: نقلُ إغلاق الوردية إلى فئة الخزينة ──────────────────────────
    //
    // ⚠️ ‏160 لا 159: هذه الترقيةُ وردت من فرع `pos-flexible-permissions`
    // برقم ١٥٩، وكان ١٥٩ قد أُخذ سلفاً لجداول محرِّك الحجز التي دخلت `main`
    // قبلَها. فرُفعت إلى **١٦٠** — ومعها حارسُها `from < 160`. والشقُّ الثاني
    // هو الذي يُنسى: لو مرَّ الرقمُ وبقي الحارسُ عند ١٥٩ لما طُبِّقت أبداً على
    // قاعدةٍ بلغت ١٥٩ بمحرِّك الحجز.
    if (from < 160) {
      await _safeMigrate('v160 نقلُ إغلاق الوردية إلى فئة الخزينة', () async {
        await m.database.customStatement(
          "UPDATE permissions SET category = 'treasury' "
          "WHERE code = 'pos_shift_close'",
        );
        debugPrint('[Migration] v160 pos_shift_close → treasury OK');
      });
    }

    // ── v161: واجهةُ الحجوزات — حالةُ الحضور وأعمدةُ المورد وجدولُ التذكير ──
    //
    // ثلاثةُ تغييراتٍ في **ترقيةٍ واحدة** عن قصد: قيدُ `bookings.status`
    // وأعمدةُ `booking_resources` كلاهما يستدعي `m.alterTable` بإعادةِ بناءِ
    // جدول. ودفعُها في ترقيتين يدفع الكلفةَ مرّتين على قواعدَ حيّة.
    //
    // ⚠️ و`m.alterTable` تبني تعريفَ **اليوم** لا تعريفَ لحظةِ الترقية. فأيُّ
    // خطوةٍ أقدمَ تعيد بناءَ نفسِ الجدولين تصير تابعةً لهذا التعريف — وهي
    // هنا `v159` التي أنشأتهما بـ`createTable` (وتبني تعريفَ اليوم كذلك)،
    // فلا تعارض. **ومن أضاف عموداً لاحقاً فليقرأ هذا قبل أن يكتب خطوةً
    // بينهما.**
    if (from < 161) {
      await _safeMigrate('v161 حالةُ الحضور وأعمدةُ المورد والتذكيرات',
          () async {
        // ‏١) `bookings.status` يقبل `seated`. إضافةٌ لا استبدال، فلا صفٌّ
        //    قائمٌ يصير مخالفاً — ولا تسويةَ بياناتٍ مطلوبةٌ قبلها.
        // v167 — انظر تحذيرَ `newColumns` أدناه: ينطبق على `bookings` أيضاً،
        // وقاعدةٌ عند v160 لا تملك أعمدةَ المزامنة.
        await m.alterTable(TableMigration(bookings, newColumns: [
          bookings.globalId,
          bookings.lastModifiedAt,
          bookings.deletedAt,
          bookings.originClientId,
          bookings.rowVersion,
        ]));

        // ‏٢) أعمدةُ المورد. `addColumn` لا تكفي وحدَها لأن القيدَ على `kind`
        //    جزءٌ من تعريف الجدول، و`alterTable` تحمل الاثنين معاً.
        //
        // ⚠️ و`newColumns` **إلزاميّة** هنا: `alterTable` تنسخ البياناتِ بـ
        //    `INSERT INTO new SELECT <أعمدةِ اليوم> FROM old`، فعمودٌ لم يكن
        //    في الجدول القديم يُطلَب من مصدرٍ لا يملكه فترمي
        //    `no such column: "role"`. وتصريحُها يجعل drift يكتب الافتراضَ
        //    بدل أن يقرأ. وبدونها ابتلعها `_safeMigrate` (تعدّ
        //    «no such column» خطأً عديمَ الأثر) فخُتمت قاعدةُ المالك 161
        //    بلا أعمدةٍ وسقطت شاشةُ الحجوزات كلُّها.
        await m.alterTable(TableMigration(
          bookingResources,
          newColumns: [
            bookingResources.role,
            bookingResources.kind,
            bookingResources.shiftStartMinutes,
            bookingResources.shiftEndMinutes,
            // v167 — أعمدةُ المزامنة أُضيفت بعد هذه الخطوة بستِّ إصدارات،
            // وقاعدةٌ عند v160 لا تملكها. ونفسُ التحذير أعلاه ينطبق عليها
            // حرفاً: بدونها ترمي `no such column: global_id` ويبتلعها
            // `_safeMigrate` فتضيع أعمدةُ المورد الأربعةُ معها.
            // و`deletedAt` ليس منها — الجدولُ وُلد به.
            bookingResources.globalId,
            bookingResources.lastModifiedAt,
            bookingResources.originClientId,
            bookingResources.rowVersion,
          ],
        ));

        // ‏٣) جدولُ التذكيرات — جديدٌ فلا إعادةَ بناء.
        await m.createTable(bookingReminders);

        debugPrint('[Migration] v161 bookings seated + resource cols + '
            'reminders OK');
      });
    }

    // ‏١٦٢ — إنقاذُ القواعد التي خُتمت 161 وأعمدةُ المورد ناقصةٌ فيها.
    //
    // ⚠️ إصلاحُ خطوةِ 161 أعلاه **لا يكفي**: قاعدةٌ ختمت 161 لا يعود
    //    `from < 161` يفحصها أبداً، فتبقى بلا أعمدةٍ إلى الأبد وشاشةُ
    //    الحجوزات ساقطةٌ بـ`no such column: booking_resources.role`.
    //    (وقع على قاعدة المالك 2026-08-23.)
    //
    // ⚠️ و**بفحصٍ قبل الإصلاح**: تنصيبةٌ وُلدت بـ`onCreate` عند 161 تملك
    //    الأعمدةَ وقد تحمل بياناتٍ فيها. وإعادةُ البناء بـ`newColumns`
    //    تكتب الافتراضاتِ فوقَ القيم — أي أنّ «إصلاحاً» غيرَ مشروطٍ يمسح
    //    أدوارَ الموظّفين ومواعيدَ ورديّاتهم صامتاً.
    if (from < 162) {
      await _safeMigrate('v162 إنقاذُ أعمدةِ المورد الناقصة', () async {
        final info = await customSelect(
          'PRAGMA table_info(booking_resources)',
        ).get();
        final present =
            info.map((r) => r.data['name'] as String).toSet();

        if (present.contains('role')) {
          debugPrint('[Migration] v162 skipped — أعمدةُ المورد موجودةٌ أصلاً');
          return;
        }

        await m.alterTable(TableMigration(
          bookingResources,
          newColumns: [
            bookingResources.role,
            bookingResources.kind,
            bookingResources.shiftStartMinutes,
            bookingResources.shiftEndMinutes,
            // v167 — انظر v161 أعلاه؛ نفسُ السبب حرفاً.
            bookingResources.globalId,
            bookingResources.lastModifiedAt,
            bookingResources.originClientId,
            bookingResources.rowVersion,
          ],
        ));
        debugPrint('[Migration] v162 أعمدةُ المورد أُضيفت — إنقاذُ 161 OK');
      });
    }

    // ‏١٦٣ — نمطُ منح الصلاحية (`role_permissions.grant_mode`).
    //
    // «مشروط» في مصفوفة الأدوار: الصلاحيةُ ممنوحةٌ ويمرّ تنفيذُها بموافقة
    // مسؤول. والعمودُ بافتراض `allow`، فكلُّ منحةٍ قائمةٍ تبقى كما كانت —
    // والاتّجاهُ مقصود: افتراضٌ مشروطٌ كان سيحوّل كلَّ نظامٍ قائمٍ إلى سؤال
    // مسؤولٍ في كلّ ضغطة.
    //
    // ⚠️ **و`addColumn` لا `alterTable`**: الأخيرةُ تعيد بناءَ الجدول من
    //    تعريفِ **اليوم**، و`role_permissions` مفتاحُه مركّبٌ بمرجعَين —
    //    فإعادةُ بنائه تُخاطر بصفوفٍ قائمةٍ بلا مقابل. والإضافةُ بعمودٍ ذي
    //    افتراضٍ لا تحتاج إعادةَ بناءٍ أصلاً.
    if (from < 163) {
      await _safeMigrate('v163 نمطُ منح الصلاحية', () async {
        final info = await customSelect(
          'PRAGMA table_info(role_permissions)',
        ).get();
        final present = info.map((r) => r.data['name'] as String).toSet();
        if (present.contains('grant_mode')) {
          debugPrint('[Migration] v163 skipped — grant_mode موجودٌ أصلاً');
          return;
        }
        await m.addColumn(rolePermissions, rolePermissions.grantMode);
        debugPrint('[Migration] v163 grant_mode أُضيف');
      });
    }

    // ‏١٦٤ — الاستحقاقُ وشروطُ التعامل (أمرُ المالك 2026-08-26).
    //
    // سبعةُ أعمدةٍ في أربعة جداول تجعل «أعمار الدين» و«المستحق» و«ملفَّ
    // الطرف» أرقاماً حقيقيّةً بدل نصوصٍ في تصميم. وقبلها كان التقادمُ
    // يُحسب من **تاريخ الإصدار** لأنّ الاستحقاقَ لا وجودَ له، فيقرأ
    // المشغّلُ عمراً أقصرَ من الحقيقة لكلّ فاتورةٍ لها مهلةُ سداد.
    //
    // ⚠️ **ولا صفَّ واحدٌ يُكتَب هنا.** `due_date` يقبل الفراغَ والفراغُ يعني
    //    «بلا مهلة»، فتُقرأ `COALESCE(due_date, invoice_date)` — وأرقامُ
    //    التقادم لا تتحرّك لحظةَ الترقية. الاتّجاهُ مقصود: ترقيةٌ تُبدّل
    //    أرقامَ دفاترِ المالك بلا أن يطلب ذلك أسوأُ من ترقيةٍ لا تفعل شيئاً.
    //
    // ⚠️ **و`addColumn` لا `alterTable`**: الأخيرةُ تعيد بناءَ الجدول من
    //    تعريفِ **اليوم**، وجداولُ الفواتير والأوامر مرجعيّاتُها كثيرةٌ
    //    وفهارسُها عديدة. والإضافةُ بعمودٍ ذي افتراضٍ أو يقبل الفراغَ لا
    //    تحتاج إعادةَ بناءٍ أصلاً.
    //
    // ⚠️ **وفحصٌ مستقلٌّ لكلّ جدول**: لو أُضيف بعضُها في تشغيلٍ سابقٍ انقطع
    //    قبل تمامه، لا تسقط الخطوةُ كلُّها ولا تُعاد إضافةُ الموجود.
    if (from < 164) {
      await _safeMigrate('v164 الاستحقاقُ وشروطُ التعامل', () async {
        Future<Set<String>> columnsOf(String table) async {
          final info = await customSelect('PRAGMA table_info($table)').get();
          return info.map((r) => r.data['name'] as String).toSet();
        }

        final partyCols = await columnsOf('parties');
        if (!partyCols.contains('payment_terms_days')) {
          await m.addColumn(parties, parties.paymentTermsDays);
        }
        if (!partyCols.contains('early_payment_discount_pct')) {
          await m.addColumn(parties, parties.earlyPaymentDiscountPct);
        }
        if (!partyCols.contains('early_payment_discount_days')) {
          await m.addColumn(parties, parties.earlyPaymentDiscountDays);
        }
        if (!partyCols.contains('supplier_rating')) {
          await m.addColumn(parties, parties.supplierRating);
        }

        final salesCols = await columnsOf('sales_invoices');
        if (!salesCols.contains('due_date')) {
          await m.addColumn(salesInvoices, salesInvoices.dueDate);
        }

        final purchaseCols = await columnsOf('purchase_invoices');
        if (!purchaseCols.contains('due_date')) {
          await m.addColumn(purchaseInvoices, purchaseInvoices.dueDate);
        }

        final poCols = await columnsOf('purchase_orders');
        if (!poCols.contains('received_at')) {
          await m.addColumn(purchaseOrders, purchaseOrders.receivedAt);
        }

        debugPrint('[Migration] v164 الاستحقاقُ وشروطُ التعامل — تمّت');
      });
    }

    // ═══ v165 — متابعةُ التحصيل ومطالبةُ المورد ═══════════════════════════
    //
    // جدولان **جديدان** لا أعمدةٌ على قائم، فلا `alterTable` ولا تسويةَ
    // بيانات: `createTable` وحدَها، ولا صفَّ واحدٌ يُكتَب.
    //
    // ⚠️ **والفحصُ بوجود الجدول لا بالنسخة**: تشغيلةٌ سابقةٌ انقطعت بعد أوّلِ
    //    جدولٍ تترك النسخةَ ٦٤١ والجدولَ الأوّلَ قائماً، فـ`createTable`
    //    عليه يرمي «table already exists» ويُسقط الخطوةَ كلَّها. والفحصُ
    //    المستقلُّ لكلٍّ يجعلها قابلةً للإعادة.
    if (from < 165) {
      await _safeMigrate('v165 متابعةُ التحصيل ومطالبةُ المورد', () async {
        Future<bool> tableExists(String name) async {
          final rows = await customSelect(
            "SELECT name FROM sqlite_master "
            "WHERE type = 'table' AND name = ?",
            variables: [Variable(name)],
          ).get();
          return rows.isNotEmpty;
        }

        if (!await tableExists('party_follow_ups')) {
          await m.createTable(partyFollowUps);
        }
        if (!await tableExists('supplier_claims')) {
          await m.createTable(supplierClaims);
        }

        debugPrint('[Migration] v165 متابعةُ التحصيل ومطالبةُ المورد — تمّت');
      });
    }

    // ═══════════════════════════════════════════════════════════════════
    // v166 — المرحلة ٢: أعمدةُ المزامنة لأحدَ عشرَ جدولاً ذاتِ أثرٍ محاسبيّ
    // ═══════════════════════════════════════════════════════════════════
    //
    // ═══ العطبُ الذي تسدّه ═══
    //
    // تطبيقُ ورقةِ تحميلٍ وترحيلُ إهلاكٍ وتسجيلُ مصروفٍ تشغيليٍّ **تقيّد
    // قيوداً تُزامَن** (‏`journal` استراتيجيّةٌ قائمة) بينما المستندُ
    // المولِّدُ يبقى محلّيّاً. فالخادمُ يرى أثراً ماليّاً بلا مصدرٍ يفسّره —
    // لا يُراجَع ولا يُعكَس من جهازٍ آخر. وجهازٌ ثانٍ لا يعرف أنّ الورقةَ
    // طُبِّقت فيطبّقها ثانيةً، فيتضاعف التحميل على التكلفة.
    //
    // ═══ لماذا هذه الصيغةُ بالذات ═══
    //
    // ١) `ADD COLUMN … UNIQUE` **مرفوضةٌ في SQLite** (‏الجدولُ قد يحمل
    //    مكرَّراً أصلاً). فالعمودُ عاديٌّ ثمّ **فهرسٌ فريدٌ جزئيّ** — نفسُ
    //    علاجِ v119 وv128 بعد أن كُشف أنّ الخطأَ كان مبلوعاً والعمودُ لا
    //    يُنشَأ على أيِّ جدول.
    //
    // ٢) و`row_version` بلا مُشغِّلٍ رقمٌ ميّت: لا شيءَ يرفعه فيبدو كلُّ صفٍّ
    //    أزليّاً وتُبتلَع التعديلات. فالمُشغِّلُ هنا نسخةُ v129، وحارسُ
    //    `WHEN` يمنع الدورَ — التحديثُ داخلَ المُشغِّل يوقظه ثانيةً لولاه.
    //
    // ٣) والتعبئةُ بـ`UuidV7` لا `v4`: مرتّبةٌ زمنيّاً فتبقى الصفوفُ القديمةُ
    //    مرتّبةً عند أوّلِ دفعةٍ إلى الخادم.
    //
    // ⚠️ و`fixed_assets` له `global_id` سلفاً — الـsafe-skip يتكفّل به،
    //    والتعبئةُ تملأ ما كان فارغاً لا غير.
    if (from < 166) {
      await _safeMigrate('v166 أعمدةُ مزامنةٍ للمستندات المحاسبيّة', () async {
        const phase2Tables = [
          // التكاليفُ المحمَّلة
          'landed_cost_sheets', 'landed_cost_items', 'landed_cost_allocations',
          // الأصولُ والإهلاك
          'fixed_assets', 'asset_categories', 'asset_depreciations',
          // المصروفاتُ التشغيليّة
          'op_expenses', 'op_expense_categories',
          // التصنيعُ وتكاليفُه — و`bill_of_materials` أبٌ لاثنين منها
          'bill_of_materials',
          'manufacturing_orders', 'mfg_order_costs', 'bom_components',
        ];

        for (final t in phase2Tables) {
          // ١. المعرّفُ العالميّ — عمودٌ عاديٌّ ثمّ فهرسٌ فريدٌ جزئيّ.
          try {
            await m.database.customStatement(
              'ALTER TABLE $t ADD COLUMN global_id TEXT',
            );
          } catch (e) {
            debugPrint('[Migration] v166 ADD $t.global_id (safe-skip): $e');
          }
          try {
            await m.database.customStatement(
              'CREATE UNIQUE INDEX IF NOT EXISTS idx_${t}_global_id '
              'ON $t(global_id) WHERE global_id IS NOT NULL',
            );
          } catch (e) {
            debugPrint('[Migration] v166 IX $t.global_id (safe-skip): $e');
          }

          // ٢. تعبئةُ الصفوفِ القائمة — **قبلَ** المُشغِّل عمداً: صفٌّ بلا
          //    معرّفٍ عالميٍّ لا يُدفَع أصلاً، والتعبئةُ بعد المُشغِّل تُشعله
          //    مرّةً لكلِّ صفٍّ بلا فائدة.
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
            debugPrint('[Migration] v166 backfill $t.global_id (safe-skip): $e');
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
            debugPrint('[Migration] v166 trigger $t: $e');
          }
        }

        debugPrint(
          '[Migration] v166: أعمدةُ المزامنة على '
          '${phase2Tables.length} جدولاً محاسبيّاً',
        );
      });
    }
  }
}
