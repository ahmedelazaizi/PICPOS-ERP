// ApiHandler - GET /api/sync/pull (watermark-based delta pull).
part of '../api_handler.dart';

/// Delta-pull endpoint (see [ApiHandler]).
extension ApiHandlerSyncPull on ApiHandler {
  // ═══════════════════════════════════════════════════════════════
  // P3.1 — Delta Pull
  // ═══════════════════════════════════════════════════════════════

  /// GET /api/sync/pull?table=X&since=Y[&branch_id=Z]
  ///
  /// Returns all rows from [table] whose `last_modified_at > since` (epoch
  /// seconds). Omitting `since` performs a full table dump (first-time sync).
  /// Rows are scoped to the caller's EFFECTIVE branch scope
  /// ([_resolveBranchScope]) when the table appears in
  /// [_syncPullBranchColumn] — plus any rows where the column is NULL
  /// (owner decision §2-b: a branch-less row stays visible). `cost_centers`
  /// is scoped too, via a reverse-derived id set rather than a column.
  ///
  /// Omitting `branch_id` does NOT mean "all branches": only a genuine
  /// full-access user (system admin / financial manager / id==1) reads
  /// unscoped. Any other caller is scoped to the branches they actually
  /// hold — all of them when they hold several (FR-1), which is the mirror's
  /// «مدير فروع» case.
  ///
  /// Response: `{ "rows": [...], "serverTime": <epoch_seconds>, "count": N }`
  ///
  /// Row keys are raw SQL column names (snake_case). The client's
  /// [DeltaPullService._upsertRow] does `INSERT OR REPLACE INTO $table ($cols)
  /// VALUES (...)` using these keys directly, so changing the shape here
  /// would break the upsert.
  Future<Response> _getSyncPull(Request request) async {
    try {
      final table = request.requestedUri.queryParameters['table'];
      if (table == null || table.isEmpty) {
        return _error('Missing "table" query parameter', statusCode: 400);
      }
      if (!ApiHandlerSyncPullTables._syncPullTables.contains(table)) {
        return _error(
          'Table "$table" is not available for delta pull',
          statusCode: 403,
        );
      }

      final sinceStr = request.requestedUri.queryParameters['since'];
      final int? since = sinceStr == null ? null : int.tryParse(sinceStr);

      // Spec 151 P1-8b — a TRANSACTIONAL table requires a verified identity.
      // Column scoping below only covers tables WITH a branch_id; the rest
      // would leak in FULL to a tokenless caller. Deny outright with NO forward
      // serverTime (null) so a client ignoring its own skip can't advance the
      // watermark and strand its post-login backfill. Reference/master tables
      // fall through and stay readable (tokenless provisioning must work).
      if (ApiUserCtx.userIdOf(request) == null &&
          ApiHandlerSyncPullTables._transactionalPullTables.contains(table)) {
        return _json({'rows': const [], 'count': 0, 'serverTime': null});
      }

      // Phase 5A.1 — derive the branch filter clause. Empty when admin or
      // when the table is universal master data (not in the map).
      //
      // FR-6 — `failClosedOnNoIdentity` is now per-table, not unconditional.
      // The flag's own contract (see [_extractBranchId]) is that REFERENCE
      // endpoints must NOT fail closed, "because the tokenless provisioning
      // path must read the full master set to seed a new client". This call
      // site passed `true` for every table; that was harmless while master
      // tables had no entry in `_syncPullBranchColumn`, but المرحلة ١ / G1
      // added `branches`/`warehouses`/`safes`/`cost_centers` — so a tokenless
      // pull started clamping to the `-1` sentinel and returning ZERO master
      // rows while still handing back a forward `serverTime`. Owner decision:
      // master tables stay FULL for a caller with no identity.
      //
      // TRANSACTIONAL tables keep `true`. They can never reach this line
      // tokenless — the `_transactionalPullTables` early return above already
      // answered them — so this is defence in depth: the day that early
      // return is refactored, the flag still fails them closed rather than
      // silently inheriting the master-table relaxation.
      //
      // ⚠️ This relaxes only the NO-`branch_id` case. A tokenless caller that
      // DOES send `branch_id` is still scoped to it (`requested != null` →
      // honoured), which is what keeps a paired-but-pre-login client on its
      // own branch and keeps an unpaired client's `branch_id=-1`
      // self-lockout at zero rows.
      //
      // FR-1: النطاق **الكامل** لا قيمة واحدة. مستدعٍ بلا `branch_id` ومعه
      // أكثر من فرع (المرآة) يُحصَر على فروعه كلها بدل أن يُقصّ على واحد.
      final branchScope = await _resolveBranchScope(
        request,
        failClosedOnNoIdentity: ApiHandlerSyncPullTables._transactionalPullTables.contains(table),
      );
      final branchCol = ApiHandlerSyncPullTables._syncPullBranchColumn[table];
      // The branch predicate is now assembled with the other conditions
      // below (the two pre-built `branchClause` / `branchClauseStandalone`
      // string fragments are gone — the query is built from a condition list
      // so the cursor predicate can join it without string surgery).
      final bool branchFilterActive = branchScope != null && branchCol != null;

      // المرحلة ١ / G1 — `cost_centers` يُحصَر بمجموعة مشتقّة لا بعمود،
      // فلا يمكن التعبير عنه بمدخل في `_syncPullBranchColumn`.
      final bool costCenterScopeActive =
          table == 'cost_centers' && branchScope != null;
      final List<int> scopedCostCenterIds = costCenterScopeActive
          ? await _resolveBranchesCostCenterIds(branchScope)
          : const <int>[];

      // ── Page size (Spec: bounded delta pull) ────────────────────────────
      // This query used to run with NO LIMIT at all. A table with a large
      // backlog — or any `since=null` first pull — materialised the ENTIRE
      // table into memory, JSON-encoded it, and shipped it in one response,
      // all on the same isolate that serves every other client and the
      // server's own UI. On `activity_logs` / `stock_movements` /
      // `sales_invoice_items` in a store with a year of history that is
      // hundreds of thousands of rows: the server froze and every other
      // client's request queued behind it. That is the single biggest cause
      // of "one or two clients load while the rest are fine" — whichever
      // device had a stale/absent watermark pulled the whole table.
      //
      // The client now drains a table page by page and only advances its
      // watermark once the last page has landed, so the contract is
      // unchanged from its point of view — just bounded per request.
      final rawLimit = int.tryParse(
              request.requestedUri.queryParameters['limit'] ?? '') ??
          ApiHandlerSyncPullTables._syncPullDefaultLimit;
      final limit = rawLimit.clamp(1, ApiHandlerSyncPullTables._syncPullMaxLimit);

      // Keyset cursor for pages 2..N. `(COALESCE(last_modified_at,0), id)` is
      // the sort key, so the tie-breaker on `id` is what makes paging exact
      // when many rows share one timestamp — a plain OFFSET or a
      // timestamp-only cursor would silently skip or repeat those rows.
      final cursorTs =
          int.tryParse(request.requestedUri.queryParameters['cursorTs'] ?? '');
      final cursorId =
          int.tryParse(request.requestedUri.queryParameters['cursorId'] ?? '');
      final bool cursorActive = cursorTs != null && cursorId != null;

      // Build the query. Table is from an allowlist, so interpolation is safe.
      // Ordering by (last_modified_at, id) keeps paging deterministic and the
      // watermark advancing monotonically.
      final conditions = <String>[];
      final vars = <Variable>[];

      if (since != null) {
        conditions.add('last_modified_at IS NOT NULL AND last_modified_at > ?');
        vars.add(Variable.withInt(since));
      }
      if (branchFilterActive) {
        // `IN (...)` بدل `= ?`: بفرع واحد هما متطابقان، وبأكثر من فرع هذا
        // هو اتّساع FR-1. ذراع `IS NULL` قرار المالك §٢-ب (صف بلا فرع يبقى
        // مرئياً) ولا تتأثّر بعدد الفروع.
        final placeholders = List.filled(branchScope.length, '?').join(',');
        conditions.add('($branchCol IN ($placeholders) OR $branchCol IS NULL)');
        vars.addAll(branchScope.map(Variable.withInt));
      }
      if (costCenterScopeActive) {
        if (scopedCostCenterIds.isEmpty) {
          // فرع بلا أي ارتباط. مجموعة فارغة يجب ألّا تنقلب إلى «بلا
          // حصر» — نفس فئة الفشل المفتوح التي أغلقها `_kNoBranchAccess`.
          conditions.add('id = ?');
          vars.add(Variable.withInt(_kNoBranchAccess));
        } else {
          final placeholders =
              List.filled(scopedCostCenterIds.length, '?').join(',');
          conditions.add('id IN ($placeholders)');
          vars.addAll(scopedCostCenterIds.map(Variable.withInt));
        }
      }
      if (cursorActive) {
        conditions.add('(COALESCE(last_modified_at, 0) > ? OR '
            '(COALESCE(last_modified_at, 0) = ? AND id > ?))');
        vars
          ..add(Variable.withInt(cursorTs))
          ..add(Variable.withInt(cursorTs))
          ..add(Variable.withInt(cursorId));
      }

      final whereClause =
          conditions.isEmpty ? '' : 'WHERE ${conditions.join(' AND ')} ';
      vars.add(Variable.withInt(limit + 1));
      final sql = 'SELECT * FROM $table $whereClause'
          'ORDER BY COALESCE(last_modified_at, 0) ASC, id ASC LIMIT ?';

      // Fetch one extra row to detect another page without COUNT(*).
      final fetched = await _db.customSelect(sql, variables: vars).get();
      final bool hasMore = fetched.length > limit;
      final rows = hasMore ? fetched.sublist(0, limit) : fetched;

      // المرحلة ١ / §٣-١ — قياس التعرّض الناتج عن ذراع `OR IS NULL`.
      //
      // `Warehouses.branchId` و`Safes.branchId` كلاهما `nullable()`، فالصف
      // بلا فرع حالة مدعومة مستمرة لا بقية قديمة: أي مخزن يُنشَأ اليوم بلا
      // فرع يبقى مرئياً على كل الأجهزة للأبد. نقيس الحجم قبل أي قرار
      // تشديد بدل أن نفترضه.
      //
      // الشرط `branchFilterActive` وحده: مسار `cost_centers` يحصر بمجموعة
      // مشتقّة (`id IN (...)`) وبلا ذراع NULL أصلاً، فلا شيء ليُقاس فيه.
      //
      // التصفير قبل الشرط لا داخله: بدونه تُرجع قراءة بعد سحب غير محصور
      // (أو سحب `cost_centers`) قيمة السحب المحصور السابق، فاختبار يتوقّع
      // صفراً هناك ينجح لسبب خاطئ.
      ApiHandler.debugLastNullBranchRowCount = 0;
      if (branchFilterActive) {
        final nullRows = rows.where((r) => r.data[branchCol] == null).length;
        ApiHandler.debugLastNullBranchRowCount = nullRows;

        // السجلّ يُكتب في ملف قابل للمراجعة لا في الطرفية وحدها: ملاحظات
        // الإصدار تطلب من المالك «راجعه بعد أسبوع تشغيل»، و`debugPrint`
        // لا يُحفظ ويُخنق تحت الحمل فالمراجعة كانت مستحيلة.
        // مخنوق بالتغيّر — انظر `_lastLoggedNullBranchRows`.
        final lastLogged = _lastLoggedNullBranchRows[table];
        if (lastLogged != nullRows) {
          _lastLoggedNullBranchRows[table] = nullRows;
          await DiagnosticLogger.log(
            'BRANCH-SCOPE-NULL',
            'table=$table branch=${branchScope.join(",")} '
                'nullRows=$nullRows',
          );
        }
      }

      // ── قائمةُ منعِ الأعمدة السرّيّة ──────────────────────────────────────
      //
      // 🔴 هذا المسارُ كان **أوسعَ** ثقبٍ في سطح الـAPI، وأوسعَ من تسريب
      // `GET /api/users` المعروف. الاستعلامُ أعلاه `SELECT * FROM $table`
      // بلا ترشيحِ أعمدةٍ إطلاقاً، و`users` مذكورٌ في `_syncPullTables`
      // **وغائبٌ** عن `_transactionalPullTables` — وتلك قائمةُ منعٍ لا سماح،
      // فحارسُ «الجدولُ المعامليُّ يحتاج هويّةً متحقَّقة» لا يعمل عليه.
      // النتيجةُ المقيسة: أيُّ حاملٍ لتوكن LAN المشترك، **بلا جلسةٍ
      // إطلاقاً**، يقرأ `password_hash` و`password_salt` و`pin` و`card_code`
      // لكلِّ مستخدم. ويتجاوز ذلك استثناءَ الـPIN المقصودَ في `_getUsers`.
      //
      // ولا يصحّ إضافةُ `users` إلى قائمة المنع: التزويدُ قبل الدخول يحتاج
      // الصفوف، والدخولُ محلّيٌّ أوّلاً. فالحارسُ هو الأعمدة، والمفتاحُ
      // نفسُ حارسِ `_getUsers`: جلسةٌ متحقَّقة أو نافذةُ اقترانٍ مفتوحة.
      //
      // و`pin` يُمنَع **دائماً**: ٤–٦ أرقامٍ تُكسَر دون اتّصال، ولا مستهلكَ
      // له أصلاً (`verifyUserPin` بلا مُنادٍ إنتاجيّ) — يُضبَط عبر
      // `POST /api/users/<id>/pin` ويُتحقَّق محلّيّاً.
      const alwaysDeniedColumns = <String, Set<String>>{
        'users': {'pin'},
      };
      const credentialColumns = <String, Set<String>>{
        'users': {'password_hash', 'password_salt', 'card_code'},
      };
      final serveCredentials = WebSessionGuard.mayServeUserCredentials(
        request,
        pairingOpen: ApiAuthMiddleware.isPairingOpen,
        hasIdentity: ApiUserCtx.userIdOf(request) != null,
      );
      final denied = <String>{
        ...?alwaysDeniedColumns[table],
        if (!serveCredentials) ...?credentialColumns[table],
      };

      final jsonRows = rows.map((r) {
        final out = <String, dynamic>{};
        for (final entry in r.data.entries) {
          if (denied.contains(entry.key)) continue;
          final v = entry.value;
          if (v is DateTime) {
            // Drift-native datetime → epoch seconds (matches client schema).
            out[entry.key] = v.millisecondsSinceEpoch ~/ 1000;
          } else if (v is List<int>) {
            // Skip blob columns; master-data tables don't rely on them for
            // cross-device state and JSON-encoding raw bytes is lossy.
            continue;
          } else {
            out[entry.key] = v;
          }
        }
        return out;
      }).toList();

      // Feature 006 / MM.E hot-fix: journal_entry_lines has no
      // `last_modified_at` column, so it can't ride the generic delta
      // pull. Embed the lines for each pulled entry directly in the
      // response — the client's DeltaPull._upsertRow special-cases this
      // table to extract them. Without this the GL screen on mirror /
      // client showed entry headers with empty debit/credit columns.
      if (table == 'journal_entries' && jsonRows.isNotEmpty) {
        final ids = <int>[];
        for (final r in jsonRows) {
          final id = r['id'];
          if (id is int) ids.add(id);
        }
        if (ids.isNotEmpty) {
          final placeholders = List.filled(ids.length, '?').join(',');
          final lineRows = await _db.customSelect(
            'SELECT * FROM journal_entry_lines WHERE entry_id IN ($placeholders) ORDER BY id ASC',
            variables: ids.map(Variable.withInt).toList(),
          ).get();
          final linesByEntry = <int, List<Map<String, dynamic>>>{};
          for (final l in lineRows) {
            final entryId = l.read<int>('entry_id');
            final lineMap = <String, dynamic>{};
            for (final e in l.data.entries) {
              final v = e.value;
              if (v is DateTime) {
                lineMap[e.key] = v.millisecondsSinceEpoch ~/ 1000;
              } else if (v is! List<int>) {
                lineMap[e.key] = v;
              }
            }
            linesByEntry.putIfAbsent(entryId, () => []).add(lineMap);
          }
          for (final r in jsonRows) {
            final id = r['id'];
            if (id is int) {
              r['lines'] = linesByEntry[id] ?? const [];
            }
          }
        }
      }

      return _json({
        'rows': jsonRows,
        'count': jsonRows.length,
        // `hasMore` drives the client's paging loop. Older clients that don't
        // read it still work: they get one bounded page instead of the whole
        // table, and the next poll picks up from the same watermark.
        'hasMore': hasMore,
        'limit': limit,
        'serverTime': DateTime.now().millisecondsSinceEpoch ~/ 1000,
      });
    } catch (e, st) {
      debugPrint('[API] /api/sync/pull failed: $e\n$st');
      return ApiErrors.fail(e, 'Failed to fetch delta');
    }
  }
}
