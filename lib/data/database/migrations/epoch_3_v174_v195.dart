part of '../database.dart';

/// Epoch 3 migration steps v174–v195 (pure move out of `epoch_3.dart`;
/// no behaviour change). Called in order by `_migrateEpoch3`.
///
/// Contains the v174 step twice (two separate blocks) exactly as before.
///
extension Epoch3MigrationsV174ToV195 on AppDatabase {
  Future<void> _migrateEpoch3V174ToV195(Migrator m, int from) async {
    // ═══════════════════════════════════════════════════════════════════
    // v174 — بنيةُ إعادة تصميم الشاشات (بلاغُ المالك 2026-09-18)
    // ═══════════════════════════════════════════════════════════════════
    //
    // ⚠️ **ولمن هذه الكتلة؟ لعملاء SQLite وحدَهم.**
    //
    // ثلاثةُ مسالكَ تصل الجداولَ الجديدة، وهذا أضيقُها:
    //   • تنصيبةٌ جديدة  ⇒ `onCreate` يبني من كيانات drift مباشرةً
    //   • خادمُ PostgreSQL ⇒ مُصحِّحُ التكافؤ يُنشئ الناقصَ عند الإقلاع
    //                       (`[PG-PARITY-HEAL] action=created`) — مقيسٌ في
    //                       لوج الميدان لا مفترَض
    //   • عميلُ SQLite قائم ⇒ **هنا**، ولا مسلكَ له غيرُها
    //
    // ولهذا لا يُستغنى عنها بحجّة أنّ الخادمَ يُصلح نفسَه.
    if (from < 174) {
      await _safeMigrate('v174 جداولُ وأعمدةُ إعادة تصميم الشاشات', () async {
        // ─── أوّلاً: الجداولُ الأربعةُ الجديدة ───────────────────────────
        //
        // `createTable` تُولّد `CREATE TABLE IF NOT EXISTS`، فهي بلا أثرٍ على
        // قاعدةٍ نالتها من `createAll` — ولذلك تُنفَّذ بلا شرط.
        for (final entry in <String, TableInfo>{
          'asset_disposals': assetDisposals,
          'cheque_books': chequeBooks,
          'floor_plan_items': floorPlanItems,
          'import_purchase_details': importPurchaseDetails,
        }.entries) {
          try {
            await m.createTable(entry.value);
          } catch (e) {
            debugPrint('[Migration] v174 ${entry.key} (safe-skip): $e');
          }
        }

        // ─── ثانياً: الأعمدةُ الخمسةَ عشرَ ──────────────────────────────
        //
        // ⚠️ **ولا عمودَ `UNIQUE` بينها عمداً**: SQLite ترفض
        // `ADD COLUMN ... UNIQUE` على جدولٍ قائم، وهي مصيدةٌ قتلت الإقلاعَ في
        // v132 — انظر `isIdempotentMigrationError`.
        //
        // و`NOT NULL` مقبولةٌ ما دام لها `DEFAULT`، فالصفوفُ القائمةُ تُملأ.
        const columns = <String, List<String>>{
          'table_sections': [
            'canvas_width REAL',
            'canvas_height REAL',
            'origin_x REAL',
            'origin_y REAL',
            'sort_order INTEGER NOT NULL DEFAULT 0',
            'color TEXT',
          ],
          'restaurant_tables': [
            'width REAL',
            'height REAL',
            'rotation REAL NOT NULL DEFAULT 0',
          ],
          'fixed_assets': ['custodian_user_id INTEGER'],
          'commercial_papers': [
            'source_voucher_id INTEGER',
            'cheque_book_id INTEGER',
          ],
          'journal_entries': ['reference TEXT'],
          'purchase_invoices': [
            'currency_id INTEGER',
            'exchange_rate REAL',
          ],
        };

        for (final table in columns.entries) {
          for (final col in table.value) {
            try {
              await m.database.customStatement(
                'ALTER TABLE ${table.key} ADD COLUMN $col',
              );
            } catch (e) {
              debugPrint(
                '[Migration] v174 ${table.key}.$col (safe-skip): $e',
              );
            }
          }
        }

        debugPrint('[Migration] v174: أربعةُ جداولَ وخمسةَ عشرَ عموداً');
      });
    }

    // ⚠️ كتلتا v174 أدناه من **فرعَين مختلفَين** دُمِجا في 2026-09-20:
    //   • الأولى أعلاه — جداولُ وأعمدةُ إعادة تصميم الشاشات.
    //   • وهذه — إعفاءُ نقلِ الأصل من فهرس إزالة التكرار.
    // وهما مستقلّتان (جداولٌ مقابلَ فهرسٍ)، وكلٌّ منهما تحمل حارسَها
    // `from < 174` بنفسِها — فلا تُدمجان في كتلةٍ واحدة: إخفاقُ
    // إحداهما تحت `_safeMigrate` كان سيبتلع الأخرى معها.

    // ═════════════════════════════════════════════════════════════════════
    // v174 — إعفاءُ نقلِ الأصل وإعادةِ تقييمه من فهرس إزالة التكرار
    //
    // نفسُ فئةِ عطبِ v168 بمفتاحٍ آخر: `asset_transfer` مفتاحُه رقمُ الأصل
    // **بلا وجهة**، فالنقلةُ الأولى تُرحَّل وكلُّ نقلةٍ تاليةٍ لنفس الأصل
    // تُعَدّ تكراراً فتُبتلَع — والأستاذُ يُبقي القيمةَ في المركز الوسيط إلى
    // الأبد بينما البطاقةُ تتقدّم. و`asset_revaluation` نفسُ الشكل.
    //
    // والقائمتان تُرفعان معاً — الحارسُ البرمجيُّ في `createJournalEntry`
    // والـ`NOT IN` في الفهرس — وإلّا مرّ القيدُ الحارسَ واصطدم بالفهرس
    // بـ`UNIQUE constraint failed`، وهو ما وقع في v168 حرفاً.
    // و`e_je_dedup_lockstep_test.dart` يثبّت التطابق.
    //
    // و`DROP` ثمّ `CREATE` لأنّ `CREATE ... IF NOT EXISTS` لا يبدّل شكلَ
    // فهرسٍ قائم — نفسُ صيغةِ v150 وv168 حرفاً.
    // ═════════════════════════════════════════════════════════════════════
    if (from < 174) {
      await _safeMigrate('v174 إعفاءُ نقلِ الأصل وتقييمه من فهرس إزالة التكرار',
          () async {
        await m.database
            .customStatement('DROP INDEX IF EXISTS $kJeAutopostDedupIndexName');
        await m.database.customStatement(kCreateJeAutopostDedupIndexSql);
        debugPrint('[Migration] v174: نقلةُ الأصل الثانيةُ صارت تُرحَّل');
      });
    }

    // ═══════════════════════════════════════════════════════════════════
    // v175 — قاعدةُ حسابِ `sales_invoices.paid`
    // ═══════════════════════════════════════════════════════════════════
    //
    // قرارُ المالك 2026-09-19 (الخيار أ): `paid` يُبنى من قاعدةٍ مخزَّنةٍ
    // زائدَ مجموعِ التخصيصات — راجع شرحَ `paidUnallocated`.
    //
    // 🔴 **والملءُ أهمُّ من الإضافة.** عمودٌ يُضاف بـ`DEFAULT 0` يجعل كلَّ
    // فاتورةٍ قائمةٍ تقول «لم يُسدَّد منّي شيءٌ خارجَ التخصيصات» — وهو كذبٌ
    // على كلّ تاريخِ التنصيبة. وأوّلُ إعادةِ حسابٍ بعدها تُصفِّر `paid` لكلّ
    // ما مضى.
    //
    // والملءُ `paid_unallocated = paid` **صحيحٌ حرفيّاً اليوم**: جدولُ
    // التخصيصات بلا كاتبٍ واحدٍ في `lib/` (مقيسٌ)، فكلُّ قرشٍ مسجَّلٍ في
    // `paid` وقع خارجَ تخصيص. ولو وُصِل الكاتبُ قبلَ هذه الهجرةِ لصار الملءُ
    // يضاعف المخصَّص — ولذلك العمودُ والكاتبُ في كوميتٍ واحد.
    if (from < 175) {
      await _safeMigrate('v175 قاعدةُ حسابِ المسدَّد', () async {
        try {
          await m.database.customStatement(
            'ALTER TABLE sales_invoices '
            'ADD COLUMN paid_unallocated REAL NOT NULL DEFAULT 0',
          );
        } catch (e) {
          debugPrint('[Migration] v175 paid_unallocated (safe-skip): $e');
        }

        // الملءُ يُنفَّذُ **على كلّ حال**، لا داخلَ `catch` الإضافة: قاعدةٌ
        // نالت العمودَ من `createAll` تحتاجُ الملءَ أيضاً لو حملت صفوفاً
        // (مرآةٌ مُزامَنةٌ مثلاً)، وهو بلا أثرٍ على الفارغة.
        try {
          await m.database.customStatement(
            'UPDATE sales_invoices SET paid_unallocated = paid '
            'WHERE paid_unallocated = 0 AND paid <> 0',
          );
        } catch (e) {
          debugPrint('[Migration] v175 backfill (safe-skip): $e');
        }

        debugPrint('[Migration] v175: paid_unallocated + ملءٌ');
      });
    }

    // ══════════════════════════════════════════════════════════════════
    // v176 — المرفقات (§٨ من خطّة إعادة تصميم الشاشات)
    // ══════════════════════════════════════════════════════════════════
    //
    // جدولان: `attachments` الوصفُ (يُزامَن)،
    // و`attachment_blobs` البايتاتُ (خارجَ كلِّ قائمةِ سحبٍ عمداً).
    //
    // ⚠️ **ولمن هذه الكتلة؟ لعملاء SQLite القائمين وحدَهم** —
    //    التنصيبةُ الجديدةُ تنالُهما من `onCreate`، والخادمُ
    //    من مُصحِّح التكافؤ عند الإقلاع.
    if (from < 176) {
      await _safeMigrate('v176 جدولا المرفقات', () async {
        for (final entry in <String, TableInfo>{
          'attachments': attachments,
          'attachment_blobs': attachmentBlobs,
        }.entries) {
          try {
            await m.createTable(entry.value);
          } catch (e) {
            debugPrint('[Migration] v176 ${entry.key} (safe-skip): $e');
          }
        }
        debugPrint('[Migration] v176: جدولا المرفقات');
      });
    }

    // ═══════════════════════════════════════════════════════════════════
    // v177 — إعفاءُ إعادةِ ترحيلِ البيع بعد تعديلٍ مُجاز
    // ═══════════════════════════════════════════════════════════════════
    // البيعُ قد يحمل قيوداً تلقائيّةً عدّةً عبر عمر الفاتورة: الأصلي ثمّ
    // إعادةُ الترحيل بعد عكسه. تفرّدُ كلّ حدثٍ محمولٌ على `global_id`.
    if (from < 177) {
      await _safeMigrate('v177 sale-repost autopost dedup index', () async {
        await m.database
            .customStatement('DROP INDEX IF EXISTS $kJeAutopostDedupIndexName');
        await m.database.customStatement(kCreateJeAutopostDedupIndexSql);
        debugPrint('[Migration] v177: sale reposts exempted from dedup index');
      });
    }

    // v178 — reassert the salary-payment database guard on upgraded stores.
    if (from < 178) {
      await _safeMigrate('v178 salary payment dedup guard', () async {
        await m.database.customStatement(kCreateSalaryPaymentDedupIndexSql);
        debugPrint('[Migration] v178: salary payment dedup guard verified');
      });
    }

    // ═══════════════════════════════════════════════════════════════════
    // v179 — فروق صرف التسوية وإعادة التقييم
    // ═══════════════════════════════════════════════════════════════════
    if (from < 179) {
      await _safeMigrate('v179 أعمدة فروق الصرف', () async {
        const columns = <String, List<String>>{
          'parties': [
            'currency_id INTEGER REFERENCES currencies(id)',
          ],
          'sales_invoices': [
            'currency_id INTEGER REFERENCES currencies(id)',
            'exchange_rate REAL',
          ],
          'safe_transactions': [
            'currency_id INTEGER REFERENCES currencies(id)',
            'exchange_rate REAL',
            'foreign_amount REAL',
          ],
        };
        for (final table in columns.entries) {
          for (final column in table.value) {
            try {
              await m.database.customStatement(
                'ALTER TABLE ${table.key} ADD COLUMN $column',
              );
            } catch (e) {
              debugPrint('[Migration] v179 ${table.key}.$column (safe-skip): $e');
            }
          }
        }
      });
    }

    // ═══════════════════════════════════════════════════════════════════
    // v180 — BOM costing, output weights, and carcass breakdown
    // ═══════════════════════════════════════════════════════════════════
    if (from < 180) {
      await _safeMigrate('v180 manufacturing raw schema', () async {
        for (final statement in [
          ..._manufacturingV180CreateStatements,
          ..._manufacturingV180ColumnStatements,
          ..._manufacturingV180IndexStatements,
        ]) {
          try {
            await m.database.customStatement(statement);
          } catch (error) {
            if (!isIdempotentMigrationError(error.toString())) rethrow;
          }
        }
        await ensureManufacturingV180Schema();
        await recalculateStoredBomCosts();
      });
    }

    // v181 — raw LAN pairing registry (kept outside Drift codegen).
    if (from < 181) {
      await _safeMigrate('v181 LAN pairing registry', ensureLanPairingSchema);
    }

    // v182 — products.tax_exempt: the product form's «معفى من الضريبة» flag
    // (raw column; tax calculation keeps reading tax_rate only).
    if (from < 182) {
      await _safeMigrate(
          'v182 products.tax_exempt', ensureProductTaxExemptSchema);
    }

    // v183 — sales_invoices.revenue_account_id: the invoice's chosen revenue
    // account (raw column; NULL ⇒ mapped 'sales' default, old invoices).
    if (from < 183) {
      await _safeMigrate('v183 sales_invoices.revenue_account_id',
          ensureSalesInvoiceRevenueAccountSchema);
    }

    // v184 — voucher_books + voucher_book_leaves_cancelled, and
    // safe_transactions.book_id/book_number/treasury_account_id (raw).
    if (from < 184) {
      await _safeMigrate('v184 voucher books', ensureVoucherBooksSchema);
    }

    // v185 — distribution model (phase F): distribution_areas,
    // route_customers, route_rep_history, rep_resources; raw columns
    // sales_routes.area_id/visit_days and rep_employee_id/route_id stamps.
    if (from < 185) {
      await _safeMigrate(
          'v185 distribution model', ensureDistributionModelSchema);
    }

    // v186 — commercial_papers.drawer_account_id + drawer_name (raw): the
    // cheque's drawer (received) / payee (issued) from the chart of accounts.
    if (from < 186) {
      await _safeMigrate('v186 cheque drawer', ensureChequeDrawerSchema);
    }

    // v187 — cloud_sync_documents (raw, I-3): cloud field documents posted
    // on this desktop or held as conflicts.
    if (from < 187) {
      await _safeMigrate('v187 cloud sync documents', ensureCloudSyncSchema);
    }

    // v188 — purchase_invoices.purchase_account_id: the invoice's chosen
    // «حساب المشتريات» (raw column; NULL ⇒ mapped 'inventory' default).
    if (from < 188) {
      await _safeMigrate('v188 purchase_invoices.purchase_account_id',
          ensurePurchaseInvoicePurchaseAccountSchema);
    }

    // v189 — return_drafts (raw, J2): sales/purchase return drafts — saved
    // before «مراجعة واعتماد» posts them through the existing return path.
    if (from < 189) {
      await _safeMigrate('v189 return drafts', ensureReturnDraftsSchema);
    }

    // v190 — parties.system_role (raw, J3): the system cash customer / cash
    // supplier; seeded or adopted on startup by ensureSystemCashParties.
    if (from < 190) {
      await _safeMigrate(
          'v190 parties.system_role', ensureSystemPartiesSchema);
    }

    // v191 — employee file (raw, J4): employees personal/job/contract/pay
    // columns + user link, and hr_departments / hr_job_titles /
    // employee_allowances / employee_documents / employee_history. Existing
    // rows are back-filled (code, job title, status) by backfillHrCoreData
    // on the next non-client startup.
    if (from < 191) {
      await _safeMigrate('v191 employee file', ensureHrCoreSchema);
    }

    // v192 — shifts, attendance, holidays and leave (raw, J4 part 2):
    // hr_shifts / hr_shift_assignments / hr_attendance_days /
    // hr_public_holidays / hr_leave_types / hr_leave_entitlements /
    // hr_leave_requests. The legacy attendance / leave / balance rows are
    // copied by migrateLegacyHrAttendance on the next non-client startup.
    if (from < 192) {
      await _safeMigrate('v192 attendance & leave', ensureHrAttendanceSchema);
    }

    // v193 — payroll, advances, adjustments and rep commissions (raw, J4
    // part 3): hr_payroll_settings / hr_salary_components /
    // hr_commission_plans / hr_employee_advances / hr_advance_repayments /
    // hr_payroll_adjustments / hr_payroll_runs / hr_payroll_lines /
    // hr_payroll_items. The legacy salary_payments / employee_transactions
    // rows are copied by migrateLegacyPayroll on the next non-client startup.
    if (from < 193) {
      await _safeMigrate('v193 payroll', ensureHrPayrollSchema);
    }

    // v194 — rep field expense categories (raw field_expense_categories,
    // seeded with the owner's defaults) and the van GPS stamp
    // (route_visits.latitude/longitude/field_geo, sales_invoices.field_geo,
    // safe_transactions.field_geo).
    if (from < 194) {
      await _safeMigrate('v194 field expenses + geo', ensureFieldExpenseSchema);
    }

    // v195 — bin projection and historical DEFAULT-bin backfill.
    if (from < 195) {
      await _safeMigrate('v195 warehouse locations', ensureWarehouseLocationsSchema);
    }
  }
}
