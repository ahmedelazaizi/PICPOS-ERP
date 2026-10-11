part of '../database.dart';

/// Epoch 3 migration steps v148–v156 (pure move out of `epoch_3.dart`;
/// no behaviour change). Called in order by `_migrateEpoch3`.
///
extension Epoch3MigrationsV148ToV156 on AppDatabase {
  Future<void> _migrateEpoch3V148ToV156(Migrator m, int from) async {

    // ═════════════════════════════════════════════════════════════════════
    // v148 — Spec 129 F4: caller-minted globalId on inventory_bonds so
    // mirror local insert + server-side insert agree on identity. Without
    // this column, retried `submitInventoryBond` calls produce duplicate
    // bond rows on the server because the dedup target doesn't exist.
    // ═════════════════════════════════════════════════════════════════════
    if (from < 148) {
      await _safeMigrate('v148 inventory_bonds.global_id', () async {
        try {
          await m.database.customStatement(
            'ALTER TABLE inventory_bonds ADD COLUMN global_id TEXT',
          );
        } catch (e) {
          debugPrint('[Migration] v148 ADD inventory_bonds.global_id (safe-skip): $e');
        }
        try {
          await m.database.customStatement(
            'CREATE UNIQUE INDEX IF NOT EXISTS idx_inventory_bonds_global_id '
            'ON inventory_bonds(global_id) WHERE global_id IS NOT NULL',
          );
        } catch (e) {
          debugPrint('[Migration] v148 CREATE UNIQUE INDEX idx_inventory_bonds_global_id (safe-skip): $e');
        }
        debugPrint('[Migration] v148 inventory_bonds.global_id OK');
      });

      // Spec 129 F6 / FR-601..606 — is_system_default flag on 6 master-data
      // tables (5 standalone + parties for the 3 seeded delivery companies).
      // Backfill marks the earliest-id row matching each canonical seeded
      // name (Q1 tiebreaker per spec clarification 2026-05-25). User-renamed
      // rows leave the flag false; the boot self-heal gates on the flag
      // instead of "is this name missing?", so renames now survive restart.
      await _safeMigrate('v148 is_system_default columns + backfill', () async {
        // 1. Add the column on each of the 5 standalone master-data tables.
        for (final table in const [
          'branches', 'warehouses', 'safes', 'units', 'categories',
        ]) {
          try {
            await m.database.customStatement(
              'ALTER TABLE $table ADD COLUMN is_system_default INTEGER NOT NULL DEFAULT 0',
            );
          } catch (e) {
            debugPrint('[Migration] v148 ADD $table.is_system_default (safe-skip): $e');
          }
        }
        // parties already has lots of rows on production installs; same shape.
        try {
          await m.database.customStatement(
            'ALTER TABLE parties ADD COLUMN is_system_default INTEGER NOT NULL DEFAULT 0',
          );
        } catch (e) {
          debugPrint('[Migration] v148 ADD parties.is_system_default (safe-skip): $e');
        }

        // 2. Backfill: mark earliest-id row matching each canonical seeded
        //    name. Canonical names mirror the actual database_seeder.dart
        //    inserts verbatim (data-model.md §1.2 had stale aspirational
        //    names; the seeder is the ground truth — see Spec 129 commit log
        //    + user confirmation 2026-05-25 that delivery companies are
        //    طلبات / كريم / اشيائي).
        const standaloneCanonicals = <String, List<String>>{
          'branches':   ['الفرع الرئيسي'],
          'warehouses': ['المخزن الرئيسي'],
          'safes':      ['صندوق الكاشير', 'الحساب البنكي', 'صندوق تحويل كليك'],
          'units':      ['قطعة', 'كيلو', 'علبة', 'كرتونة'],
          'categories': ['عام'],
        };
        for (final entry in standaloneCanonicals.entries) {
          final table = entry.key;
          for (final name in entry.value) {
            try {
              await m.database.customStatement(
                'UPDATE $table SET is_system_default = 1 '
                'WHERE id = (SELECT MIN(id) FROM $table WHERE name = ?)',
                [name],
              );
            } catch (e) {
              debugPrint('[Migration] v148 backfill $table name="$name" (safe-skip): $e');
            }
          }
        }

        // parties — only the 3 seeded delivery companies get the flag.
        // Filtered by is_delivery_company=true so a customer who happens
        // to be named 'طلبات' isn't accidentally promoted.
        for (final name in const ['طلبات', 'كريم', 'اشيائي']) {
          try {
            await m.database.customStatement(
              'UPDATE parties SET is_system_default = 1 '
              'WHERE id = (SELECT MIN(id) FROM parties '
              '            WHERE name = ? AND is_delivery_company = 1)',
              [name],
            );
          } catch (e) {
            debugPrint('[Migration] v148 backfill parties name="$name" (safe-skip): $e');
          }
        }

        debugPrint('[Migration] v148 is_system_default columns + backfill OK');
      });
    }

    // ═════════════════════════════════════════════════════════════════════
    // v149 — Spec 148 (S-ISSUE): stock_requisitions gains a caller-minted
    // global_id (for future cross-node sync dedup, mirroring inventory_bonds)
    // and fulfilled_by_transfer_id (audit link to the transfer bond produced
    // when the requisition is approved). Both nullable; no item-table change.
    // ═════════════════════════════════════════════════════════════════════
    if (from < 149) {
      await _safeMigrate('v149 stock_requisitions.global_id + fulfilled_by_transfer_id', () async {
        try {
          await m.database.customStatement(
            'ALTER TABLE stock_requisitions ADD COLUMN global_id TEXT',
          );
        } catch (e) {
          debugPrint('[Migration] v149 ADD stock_requisitions.global_id (safe-skip): $e');
        }
        try {
          await m.database.customStatement(
            'CREATE UNIQUE INDEX IF NOT EXISTS idx_stock_requisitions_global_id '
            'ON stock_requisitions(global_id) WHERE global_id IS NOT NULL',
          );
        } catch (e) {
          debugPrint('[Migration] v149 CREATE UNIQUE INDEX idx_stock_requisitions_global_id (safe-skip): $e');
        }
        try {
          await m.database.customStatement(
            'ALTER TABLE stock_requisitions ADD COLUMN fulfilled_by_transfer_id INTEGER',
          );
        } catch (e) {
          debugPrint('[Migration] v149 ADD stock_requisitions.fulfilled_by_transfer_id (safe-skip): $e');
        }
        debugPrint('[Migration] v149 stock_requisitions sync + fulfilment columns OK');
      });
    }

    // ═════════════════════════════════════════════════════════════════════
    // v150 — Spec 151 (return-key fix). The RETURN JE re-key means multiple
    // partial returns of ONE invoice now share (reference_type, reference_id):
    // both are keyed on the originating invoice id, with per-event uniqueness
    // carried by journal_entries.global_id. The v120 idx_je_autopost_dedup
    // UNIQUE index — created ONLY in the v120 upgrade block — would reject the
    // 2nd partial return and roll the whole return transaction back on any
    // v120-upgraded DB. Drop + recreate it exempting the multi-JE reference
    // types (see kCreateJeAutopostDedupIndexSql), then backfill historical
    // hash-keyed return JEs onto their originating invoice id so the cancel /
    // edit reverse queries (which now match `referenceId == invoice.id`) find
    // them instead of double-posting (purchase) / reversing nothing (sales).
    // ═════════════════════════════════════════════════════════════════════
    if (from < 150) {
      await _safeMigrate('v150 return-exempt autopost dedup index', () async {
        // (a) Index recreate — CRITICAL. The OLD non-exempted index MUST be
        // dropped BEFORE the backfill re-keys return JEs onto shared invoice
        // ids, or the backfill would itself trip the old UNIQUE constraint.
        // A genuine failure here rethrows via _safeMigrate → boot fails loud.
        await m.database
            .customStatement('DROP INDEX IF EXISTS $kJeAutopostDedupIndexName');
        await m.database.customStatement(kCreateJeAutopostDedupIndexSql);

        // (b) Backfill — BEST-EFFORT. Historical return JEs carry
        // referenceId = hash(invoiceId + amount); re-key them to the
        // originating invoice id parsed from the description. Wrapped in its own
        // try/catch so a backfill hiccup never rolls back the critical index
        // recreate above (unmatched rows keep the hash — acceptable, logged).
        try {
          const marker = 'فاتورة '; // literal token that precedes the number

          // Invoice-number extraction: the substring AFTER the 'فاتورة '
          // marker to end-of-description, matched WHOLE (=, never LIKE) to
          // invoice_number. Using the whole tail — not LIKE '%…%' — is exactly
          // what avoids the F-04 collision where editing "12" also swept "120".
          String extractNo(String col) =>
              "substr($col, instr($col, '$marker') + length('$marker'))";

          // Re-key only rows whose extracted number resolves to EXACTLY ONE
          // invoice (COUNT = 1). Ambiguous/unmatched rows are left untouched.
          // Idempotent: re-running resolves to the same invoice id.
          Future<void> backfill(String refType, String invTable) async {
            await m.database.customStatement('''
              UPDATE journal_entries
              SET reference_id = (
                SELECT inv.id FROM $invTable inv
                WHERE inv.invoice_number = ${extractNo('journal_entries.description')}
              )
              WHERE reference_type = '$refType'
                AND is_auto_posted = 1
                AND instr(description, '$marker') > 0
                AND (
                  SELECT COUNT(*) FROM $invTable inv2
                  WHERE inv2.invoice_number = ${extractNo('journal_entries.description')}
                ) = 1
            ''');
          }

          Future<int> untouchedCount(String refType, String invTable) async {
            final row = await m.database.customSelect('''
              SELECT COUNT(*) AS c FROM journal_entries je
              WHERE je.reference_type = '$refType'
                AND je.is_auto_posted = 1
                AND (
                  instr(je.description, '$marker') = 0
                  OR (
                    SELECT COUNT(*) FROM $invTable inv
                    WHERE inv.invoice_number = ${extractNo('je.description')}
                  ) != 1
                )
            ''').getSingle();
            return (row.data['c'] as int?) ?? 0;
          }

          await backfill('sales_return', 'sales_invoices');
          await backfill('purchase_return', 'purchase_invoices');

          final salesLeft = await untouchedCount('sales_return', 'sales_invoices');
          final purchLeft =
              await untouchedCount('purchase_return', 'purchase_invoices');
          debugPrint('[Migration] v150 return-JE referenceId backfill done — '
              'left untouched (ambiguous/unmatched, kept hash): '
              'sales_return=$salesLeft purchase_return=$purchLeft');
        } catch (e) {
          debugPrint('[Migration] v150 return-JE backfill '
              '(best-effort, skipped): $e');
        }
      });
      debugPrint('[Migration] v150: return-exempt autopost dedup index '
          '+ historical backfill applied');
    }

    // ═════════════════════════════════════════════════════════════════════
    // v151 — shifts.closing_snapshot (reprint a closed shift)
    //
    // The closing report is printed once, at close time, and was never
    // recoverable afterwards. Recomputing it is not enough: the ACTUAL
    // counted amounts are cashier input, and only `actual_cash` had a
    // column — the bank and click counts lived inside the free-text `notes`
    // string. A "reprint" built without them would not match the paper the
    // cashier signed.
    //
    // So the close path now stores the exact figures it printed, as JSON.
    // Nullable, no backfill: shifts closed before this point have no
    // snapshot to recover and are recomputed + labelled in the UI. Adding a
    // nullable column is the cheapest possible schema change on the large
    // production databases this runs against.
    // ═════════════════════════════════════════════════════════════════════
    if (from < 151) {
      await _safeMigrate('v151 shifts.closing_snapshot', () async {
        await m.addColumn(shifts, shifts.closingSnapshot);
        debugPrint('[Migration] v151 shifts.closing_snapshot OK');
      });
    }

    // ── v152: قيود قاعدة البيانات لمنعَي B1 و B2 ──────────────────────────
    //
    // الحارسان الموجودان (recordSalaryPayment و importDeviceCheckIn) كودُ
    // تطبيق، فبيقفلوا الضغط المكرر على نفس الجهاز بس. كاتب متزامن من جهاز
    // تاني بيقرا «مفيش صف سابق» في نفس اللحظة فالاتنين بيعدّوا. دي الطبقة
    // اللي بتمنع ده فعلاً.
    if (from < 152) {
      // الحضور: بيتنضّف قبل الفهرس. الصفوف دي **مش سجلات مالية** — بتتحوّل
      // لفلوس عبر العدّ فقط — فدمجها آمن: نبقّي أقدم صف لكل (موظف، يوم)
      // ونضم عليه أبكر دخول وآخر خروج، ونحذف الباقي.
      await _safeMigrate('v152 employee_attendance dedup', () async {
        await m.database.customStatement('''
          UPDATE employee_attendance
          SET check_in = (SELECT MIN(b.check_in) FROM employee_attendance b
                          WHERE b.employee_id = employee_attendance.employee_id
                            AND b.date = employee_attendance.date
                            AND b.check_in IS NOT NULL),
              check_out = (SELECT MAX(b.check_out) FROM employee_attendance b
                           WHERE b.employee_id = employee_attendance.employee_id
                             AND b.date = employee_attendance.date
                             AND b.check_out IS NOT NULL)
          WHERE id IN (SELECT MIN(id) FROM employee_attendance
                       GROUP BY employee_id, date)
        ''');
        await m.database.customStatement('''
          DELETE FROM employee_attendance
          WHERE id NOT IN (SELECT MIN(id) FROM employee_attendance
                           GROUP BY employee_id, date)
        ''');
        debugPrint('[Migration] v152 attendance rows deduped');
      });

      // الفهرسان **غير قاتلين بقصد**. `_safeMigrate` بيرمي أي خطأ غير
      // idempotent، ولو رمى هنا التطبيق ما بيقلعش خالص — وده تمن غالي جداً
      // لطبقة **تحصين**: الحارسان في `recordSalaryPayment` و
      // `importDeviceCheckIn` شغالين على أي حال.
      //
      // والرواتب تحديداً **ما بتتنضّفش تلقائياً**: الصف المكرر سجل مالي مربوط
      // بسند صرف نقدي وقيد يومية، وحذفه من غير عكس الحركتين بيخلّي الخزنة
      // والدفاتر غلط. لو فيه تكرار قائم، الفهرس ما بيتركّبش والبيانات تفضل زي
      // ما هي لحد ما محاسب يسوّيها — والرسالة تحت بتقول له فين بالظبط.
      //
      // PicPos لسه ماطرحش (مفيش تنصيبات) فالاتنين بينجحوا دايماً هناك؛ الفرع
      // ده موجود للنقل لقاعدة فيها بيانات.
      for (final (label, sql) in [
        ('attendance day', kCreateAttendanceDayDedupIndexSql),
        ('salary payment period', kCreateSalaryPaymentDedupIndexSql),
      ]) {
        try {
          await m.database.customStatement(sql);
          debugPrint('[Migration] v152 $label dedup index OK');
        } catch (e) {
          debugPrint(
              '[Migration] v152 $label dedup index SKIPPED — فيه تكرار قائم '
              'في البيانات لازم يتسوّى يدوياً قبل ما القيد يتركّب: $e');
          await DiagnosticLogger.logError(
              DiagnosticLogger.migration, 'v152 $label dedup index', e);
        }
      }
    }

    // ── v153: الأجرُ بالساعة والإضافي المحسوب — جدولُ العطلات وعمودا
    // ساعاتِ اليوم والتجاوز اليدويّ ──────────────────────────────────────
    if (from < 153) {
      await _safeMigrate('v153 work_holidays + hoursPerDay + isManualAmount',
          () async {
        await m.createTable(workHolidays);
        await m.addColumn(employees, employees.hoursPerDay);
        await m.addColumn(overtimeRecords, overtimeRecords.isManualAmount);
        // السجلّاتُ القائمة حُسبت بمقامٍ آخر — تُعلَّم يدويةً فلا يُعاد
        // حسابُها وتتغيّر رواتبُ ماضية.
        await m.database
            .customStatement('UPDATE overtime_records SET is_manual_amount = 1');
        debugPrint('[Migration] v153 work_holidays + hoursPerDay + '
            'isManualAmount OK');
      });
    }

    // ── v154: خدمةُ الطاولات — الحالةُ المدفوعة والخصمُ والدفعاتُ المتعدّدة ──
    if (from < 154) {
      await _safeMigrate('v154 table service columns + table_order_payments',
          () async {
        await m.addColumn(tableOrders, tableOrders.guestCount);
        await m.addColumn(tableOrders, tableOrders.notes);
        await m.addColumn(tableOrders, tableOrders.discountType);
        await m.addColumn(tableOrders, tableOrders.discountValue);
        await m.addColumn(tableOrders, tableOrders.paidAmount);
        await m.addColumn(tableOrderItems, tableOrderItems.notes);
        await m.addColumn(
            tableOrderItems, tableOrderItems.sourceTableOrderId);
        await m.createTable(tableOrderPayments);
        debugPrint('[Migration] v154 table service OK');
      });
    }

    // ── v155: ضريبةُ المبيعات على طلبات الطاولات ────────────────────────
    //
    // العمودان يحملان ما كانت السلّةُ وحدَها تحمله، فيتطابق المشحونُ
    // والمسجَّل. والقائمُ من الطلبات يأخذ الافتراضَين (`0`/`false`) — أي
    // «بلا ضريبة»، وهو حالُها اليوم بالضبط، فلا يتغيّر حسابُ طاولةٍ مفتوحةٍ
    // بمجرّد الترقية.
    if (from < 155) {
      await _safeMigrate('v155 table order tax columns', () async {
        await m.addColumn(tableOrders, tableOrders.taxEnabled);
        await m.addColumn(tableOrders, tableOrders.taxRate);
        debugPrint('[Migration] v155 table order tax OK');
      });
    }

    // ── v156: قيدُ «لا تفعيلَ بلا نسبة» على طلبات الطاولات ───────────────
    //
    // v155 أضاف العمودين وحرسَهما في الخدمة. وهذا يجعل الحالةَ الكاذبةَ
    // (`tax_enabled = 1` و`tax_rate = 0`) **مستحيلةَ التمثيل** لا مرفوضةً
    // عند بابٍ واحد — اقرأ [TableOrders.customConstraints].
    //
    // وSQLite لا تضيف قيداً بـ`ALTER TABLE`، فالسبيلُ الوحيدُ إعادةُ إنشاء
    // الجدول ونقلُ بياناته. `m.alterTable` تفعلها بالخطوات الاثنتَي عشرة
    // التي توصي بها SQLite: إطفاءُ المفاتيح، إنشاءُ بديلٍ بالشكل الجديد،
    // نقلُ الصفوف، إسقاطُ الأصل، `legacy_alter_table` كي لا تُعاد كتابةُ
    // إشاراتِ الأبناء عند التسمية، ثم إعادةُ الفهارس والمشغِّلات.
    //
    // والتسويةُ **تسبق** القيدَ بالضرورة: صفٌّ كاذبٌ قائمٌ يُفشل إعادةَ
    // الإنشاء فيقتل الإقلاع. وهي تُطفئ الزرَّ ولا تُلفّق نسبةً — الفاتورةُ
    // خرجت بضريبةِ صفرٍ فعلاً، فإطفاءُ الزرِّ هو ما يجعل السجلَّ يطابق ما
    // حُصِّل حقّاً. واختراعُ نسبةٍ الآن يعيد تسعيرَ حسابٍ رآه الضيفُ ودُفع.
    //
    // **وعتبةُ التسوية هنا هي عتبةُ اليوم لا عتبةُ ١٥٦.** `m.alterTable` تبني
    // تعريفَ الجدول **الحاليَّ** لا تعريفَه يومَ كُتبت هذه الخطوة، فالقيدُ
    // الذي تُنشئه هذه السطورُ هو ما في [TableOrders.customConstraints] الآن.
    // فلمّا شُدَّ القيدُ في v157 صار صفٌّ نسبتُه `0.005` — وهو ما كانت تُجيزه
    // v156 — يُفشل إعادةَ البناء **هنا**، قبل أن تُشغَّل v157 أصلاً. مقيسٌ لا
    // مفترض: `CHECK constraint failed: NOT tax_enabled OR tax_rate >= 0.01`
    // من خطوة v156 على قاعدةٍ مُرقّاةٍ من ١٥٥.
    //
    // فأيُّ خطوةٍ تُعيد بناءَ جدولٍ تلزمها تسويةٌ تُرضي قيدَه **الحاليّ**.
    if (from < 156) {
      await _safeMigrate('v156 table_orders tax CHECK constraint', () async {
        await customStatement(
          'UPDATE table_orders SET tax_enabled = 0 '
          'WHERE tax_enabled = 1 AND tax_rate < 0.01',
        );
        // v167 — أعمدةُ المزامنة **إلزاميّةٌ هنا** وإن أُضيفت بعد هذه
        // الخطوة بأحدَ عشرَ إصداراً: `alterTable` تنسخ بـ`INSERT INTO new
        // SELECT <أعمدةِ اليوم> FROM old`، وقاعدةٌ عند v155 لا تملكها
        // فترمي `no such column: global_id` — ويبتلعها `_safeMigrate`
        // فتضيع **الخطوةُ كلُّها** بما فيها قيدُ الضريبة.
        await m.alterTable(TableMigration(tableOrders, newColumns: [
          tableOrders.globalId,
          tableOrders.lastModifiedAt,
          tableOrders.deletedAt,
          tableOrders.originClientId,
          tableOrders.rowVersion,
        ]));
        debugPrint('[Migration] v156 table_orders tax CHECK OK');
      });
    }
  }
}
