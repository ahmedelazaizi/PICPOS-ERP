// ApiDataHandler - expenses, operational expenses and fixed assets endpoints.
part of '../api_data_handler.dart';

/// Expense, operational-expense and fixed-asset endpoints of [ApiDataHandler].
extension ApiDataExpensesRoutes on ApiDataHandler {
  // ═══════════════════════════════════════════════════════════════
  // Expenses & Receipts
  // ═══════════════════════════════════════════════════════════════

  Future<Response> postExpense(Request request) async {
    try {
      // Spec 077 Batch 5 (Spec 060 Phase 2): per-user permission gate.
      final perm = await ApiUserCtx.requirePermission(
          request, db, PermissionCodes.posExpense);
      if (perm != null) return perm;
      return await ApiHandlerBase.withBroadcast<Response>(
        endpointLabel: 'postExpense',
        // Cheque branch additionally creates a commercial_paper row; the
        // declared set is the maximum (Spec 129 contract §5 Q2).
        tables: const {
          'safe_transactions', 'accounting', 'journal_entries',
          'commercial_papers',
        },
        body: () async {
      final data =
          json.decode(await request.readAsString()) as Map<String, dynamic>;
      final paperType = data['paperType'] as String?;
      final isCheckPayment = paperType == 'cheque' || paperType == 'check';

      // UUID-First idempotency: if the client passed a globalId and a
      // matching safe_transaction already exists, skip the insert and
      // return the existing id. Prevents the outbox from producing a
      // phantom duplicate when a request is retried after a network blip.
      final incomingGlobalId = data['globalId'] as String?;
      if (incomingGlobalId != null && incomingGlobalId.isNotEmpty) {
        final existing = await (db.select(db.safeTransactions)
              ..where((t) => t.globalId.equals(incomingGlobalId))
              ..limit(1))
            .getSingleOrNull();
        if (existing != null) {
          return jsonResponse({
            'success': true,
            'duplicate': true,
            'serverId': existing.id,
          });
        }
      }

      // Resolve costCenterId — prefer explicit value, otherwise derive from
      // the branchId the client sent (so the journal entry is properly
      // scoped to the cashier's branch instead of the server default).
      int? costCenterId = parseIntNullable(data['costCenterId']);
      final clientBranchId = parseIntNullable(data['branchId']);
      if (costCenterId == null && clientBranchId != null) {
        try {
          final branch = await (db.select(db.branches)
                ..where((b) => b.id.equals(clientBranchId))
                ..limit(1))
              .getSingleOrNull();
          costCenterId = branch?.costCenterId;
        } catch (_) {}
      }

      // P5 (quick-expense fix): The quick-expense flow on the POS is a
      // CASH-only operation by product design — the cashier pulls money out
      // of the till (negative balance allowed; reconciled at shift close).
      // Resolve a cash safe deterministically here so the expense doesn't
      // leak into a bank/click safe that happens to be marked default on
      // the server. Resolution order:
      //   1. The explicit safeId the client sent (validate it's actually a
      //      cash safe; if not, ignore it).
      //   2. The default cash safe for the cashier's branch.
      //   3. Any cash safe (defensive — shouldn't normally fire).
      int? targetSafeId;
      final explicitSafeId = parseIntNullable(data['safeId']);
      if (explicitSafeId != null) {
        final maybeSafe = await (db.select(db.safes)
              ..where((s) => s.id.equals(explicitSafeId) & s.safeType.equals('cash'))
              ..limit(1))
            .getSingleOrNull();
        if (maybeSafe != null) targetSafeId = maybeSafe.id;
      }
      if (targetSafeId == null) {
        // Default cash safe (any branch) — keep `.limit(1)` so a stale
        // duplicate doesn't crash with "Too many elements".
        final defaultCash = await (db.select(db.safes)
              ..where((s) =>
                  s.safeType.equals('cash') &
                  s.isDefault.equals(true) &
                  s.isActive.equals(true))
              ..orderBy([(s) => OrderingTerm.asc(s.id)])
              ..limit(1))
            .getSingleOrNull();
        targetSafeId = defaultCash?.id;
      }
      if (targetSafeId == null) {
        // Defensive last-resort: any active cash safe.
        final anyCash = await (db.select(db.safes)
              ..where((s) => s.safeType.equals('cash') & s.isActive.equals(true))
              ..orderBy([(s) => OrderingTerm.asc(s.id)])
              ..limit(1))
            .getSingleOrNull();
        targetSafeId = anyCash?.id;
      }

      // Feature 044 — remap the client's `partyId` via globalId so the
      // server's FK on `safe_transactions.party_id` resolves cleanly.
      // Field log:
      //   safe_transactions_party_id_fkey: Key (party_id)=(1000000006) is
      //   not present in table "parties"
      // The mirror's high autoincrement local id rarely exists on the
      // server; `resolvePartyId` prefers globalId match, falls back to
      // id, then to name, and auto-creates a placeholder party when only
      // the UUID + name are known. `clientPartyId == null` short-circuits
      // to null — preserves the "no party" expense path used by
      // generic cash outflows.
      final clientPartyId = parseIntNullable(data['partyId']);
      final partyGid = (data['partyGlobalId'] as String?)?.trim();
      final partyName = (data['partyName'] as String?)?.trim();
      int? resolvedPartyId;
      if (clientPartyId != null && clientPartyId > 0) {
        resolvedPartyId = await resolvePartyId(
          clientPartyId: clientPartyId,
          partyGlobalId: partyGid == null || partyGid.isEmpty ? null : partyGid,
          fallbackName: partyName == null || partyName.isEmpty ? null : partyName,
        );
      }

      final id = await db.createPaymentVoucher(
        amount: parseDouble(data['amount']),
        category: data['category'] as String,
        description: data['description'] as String?,
        partyId: resolvedPartyId,
        safeId: targetSafeId,
        userId: await _resolveUserIdNullable(parseIntNullable(data['userId']),
            fallbackUsername: data['createdByUsername'] as String?),
        // P5 FIX: cost center was being silently dropped — every expense from a
        // client landed without branch scope, breaking per-branch P&L reports
        // and producing the user-visible 404 when the server's default cost
        // center didn't exist.
        costCenterId: costCenterId,
        // Carry the client's UUID through so pull-sync dedupes by globalId
        // instead of creating a second row on the client for the same
        // logical voucher.
        globalId: incomingGlobalId,
        // Skip cash JE for cheque payments — commercial papers creates the correct JE
        skipJournalEntry: isCheckPayment,
        // Spec 081 — for cheque payments NO cash leaves any safe at issue
        // time (clearing happens later via commercial-papers screen). Skip
        // the safe transaction too so the server matches the local repo
        // behaviour (treasury_repository_impl.dart:217-219).
        skipSafeTransaction: isCheckPayment,
        // Spec 135 BUG-C — attribute the JE to the operator's branch (sent by
        // the client) instead of the target safe's branch.
        operatingBranchId: clientBranchId,
      );
      // Spec 081 — with skipSafeTransaction the DAO short-circuits and
      // returns id=0. Make the contract explicit so a future client doesn't
      // misinterpret 0 as a real serverId for a cheque.
      if (isCheckPayment) {
        return jsonResponse({'success': true, 'skipped': 'cheque'});
      }
      return jsonResponse({'success': true, 'serverId': id});
        },
      );
    } catch (e) {
      debugPrint('[API] postExpense error: $e');
      return ApiErrors.fail(e, 'Failed to record expense');
    }
  }

  Future<Response> deleteExpense(Request request, String id) async {
    try {
      // Spec 077 Batch 5 (Spec 060 Phase 2): per-user permission gate.
      final perm = await ApiUserCtx.requirePermission(
          request, db, PermissionCodes.posExpenseDelete);
      if (perm != null) return perm;
      final txId = int.parse(id);
      await db.deleteExpenseTransaction(txId);
      broadcast('treasury');
      // The DAO also posts a mirror-reversal journal entry so the ledger
      // balances. Notify subscribers so clients pull the new reversal JE
      // via the delta-sync loop (DeltaPullService dedups by globalId).
      broadcast('journal_entries');
      broadcastRecordDeleted('safe_transactions', txId);
      return jsonResponse({'success': true});
    } catch (e) {
      return ApiErrors.fail(e, 'Failed to delete expense');
    }
  }

  // ═══════════════════════════════════════════════════════════════════════
  // FIXED ASSETS — اقتناءٌ وإهلاكٌ واردان من عميل (v166 / المرحلة ٢)
  // ═══════════════════════════════════════════════════════════════════════

  /// `POST /api/fixed-assets`
  ///
  /// يُنشئ الأصلَ **بهويّته التي سكّها العميل** — هو وحسابُه الفرعيّ. ولو
  /// سكّ الخادمُ هويّتَين جديدتَين لعاد الصفّان بسحب الدلتا مكرَّرَين:
  /// أصلان وحسابان لأصلٍ واحدٍ لا يجمعهما شيء.
  ///
  /// والقيدُ يُرحَّل هنا وحدَه — العميلُ ممتنعٌ صراحةً في
  /// `fixed_assets_dao_ext.dart` لأنّ `referenceId` رقمٌ محلّيّ.
  Future<Response> postFixedAsset(Request request) async {
    try {
      final perm = await ApiUserCtx.requirePermission(
          request, db, PermissionCodes.assetsManage);
      if (perm != null) return perm;

      return await ApiHandlerBase.withBroadcast<Response>(
        endpointLabel: 'postFixedAsset',
        tables: const {
          'fixed_assets', 'asset_categories', 'accounts',
          'journal_entries', 'accounting',
        },
        body: () async {
          final data =
              json.decode(await request.readAsString()) as Map<String, dynamic>;

          final gid = data['globalId'] as String?;
          if (gid == null || gid.isEmpty) {
            return jsonResponse({'success': false, 'error': 'globalId مفقود'},
                statusCode: 400);
          }

          final existing = await (db.select(db.fixedAssets)
                ..where((a) => a.globalId.equals(gid))
                ..limit(1))
              .getSingleOrNull();
          if (existing != null) {
            return jsonResponse({
              'success': true,
              'duplicate': true,
              'serverId': existing.id,
            });
          }

          // ــ الفئة: تُقبَل كاملةً وتُنشَأ إن غابت ــــــــــــــــــــــ
          //
          // فئةٌ أنشأها العميلُ لا وجودَ لها هنا، ولو اكتفينا بمعرّفها لرُدَّ
          // كلُّ أصلٍ فيها إلى الأبد. وحسابا الأصل والمجمَّع يُشتقّان من
          // الافتراضات لأنّهما محلّيّان لكلّ قاعدة.
          final catRaw = data['category'] as Map<String, dynamic>?;
          final catGid = catRaw?['globalId'] as String?;
          if (catGid == null || catGid.isEmpty) {
            return jsonResponse({
              'success': false,
              'error': 'فئةُ الأصل مفقودةٌ من الطلب',
            }, statusCode: 400);
          }

          var category = await (db.select(db.assetCategories)
                ..where((c) => c.globalId.equals(catGid))
                ..limit(1))
              .getSingleOrNull();
          if (category == null) {
            await db.syncDefaultAccounts();
            // نفسُ افتراضَي الـDAO حرفاً (`_getCategoryAssetAccount` و
            // `_getCategoryDepreciationAccount`): `1211` الأراضي و`1218`
            // مجمّعُ إهلاك المباني. ورمزٌ لا وجودَ له في الشجرة يجعل كلَّ
            // أصلٍ بفئةٍ جديدةٍ مردوداً بـ409 إلى الأبد.
            final assetAcc = await db.getAccountByCode('1211');
            final accumAcc = await db.getAccountByCode('1218');
            if (assetAcc == null || accumAcc == null) {
              return jsonResponse({
                'success': false,
                'error': 'حسابا الأصول والمجمَّع غيرُ مهيَّأين على الخادم',
              }, statusCode: 409);
            }
            final newCatId = await db.createAssetCategory(
              name: catRaw?['name'] as String? ?? 'فئةٌ واردة',
              defaultUsefulLife:
                  parseDouble(catRaw?['defaultUsefulLife'], 5),
              defaultDepreciationMethod: catRaw?['defaultDepreciationMethod']
                      as String? ??
                  'straight_line',
              accountId: assetAcc.id,
              depreciationAccountId: accumAcc.id,
              globalId: catGid,
            );
            category = await (db.select(db.assetCategories)
                  ..where((c) => c.id.equals(newCatId)))
                .getSingle();
          }

          final ccGid = data['costCenterGlobalId'] as String?;
          final costCenter = ccGid == null || ccGid.isEmpty
              ? null
              : await (db.select(db.costCenters)
                    ..where((c) => c.globalId.equals(ccGid))
                    ..limit(1))
                  .getSingleOrNull();

          final serverId = await db.createFixedAsset(
            code: data['code'] as String? ?? '',
            name: data['name'] as String? ?? '',
            categoryId: category.id,
            location: data['location'] as String?,
            purchasePrice: parseDouble(data['purchasePrice']),
            purchaseDate:
                DateTime.tryParse(data['purchaseDate'] as String? ?? '') ??
                    DateTime.now(),
            usefulLifeYears: parseDouble(data['usefulLifeYears'], 1),
            salvageValue: parseDouble(data['salvageValue']),
            depreciationMethod: data['depreciationMethod'] as String? ??
                'straight_line',
            notes: data['notes'] as String?,
            costCenterId: costCenter?.id,
            globalId: gid,
            linkedAccountGlobalId:
                data['linkedAccountGlobalId'] as String?,
          );

          return jsonResponse({'success': true, 'serverId': serverId});
        },
      );
    } catch (e, st) {
      debugPrint('[API] postFixedAsset failed: $e\n$st');
      return ApiErrors.failJson(e, st);
    }
  }

  /// `POST /api/fixed-assets/depreciation/run`
  ///
  /// يُرحّل إهلاكَ الشهر على أصول **الخادم**. ولذلك لا تُرسَل قائمةُ أصولٍ:
  /// قائمةُ العميل قد تنقص ما لم يصله بعد، فترحيلُها يُنتج شهراً ناقصاً.
  ///
  /// وإعادةُ الطلب لا تُضاعف: [runMonthlyDepreciation] يتخطّى أيَّ أصلٍ له
  /// صفُّ إهلاكٍ بنفس `(asset_id, period_date)`.
  Future<Response> postAssetDepreciationRun(Request request) async {
    try {
      final perm = await ApiUserCtx.requirePermission(
          request, db, PermissionCodes.assetsDepreciation);
      if (perm != null) return perm;

      return await ApiHandlerBase.withBroadcast<Response>(
        endpointLabel: 'postAssetDepreciationRun',
        tables: const {
          'asset_depreciations', 'fixed_assets',
          'journal_entries', 'accounting',
        },
        body: () async {
          final data =
              json.decode(await request.readAsString()) as Map<String, dynamic>;
          final periodRaw = data['periodDate'] as String?;
          final period =
              DateTime.tryParse(periodRaw ?? '');
          if (period == null) {
            return jsonResponse({
              'success': false,
              'error': 'periodDate غيرُ صالح',
            }, statusCode: 400);
          }

          final count = await db.runMonthlyDepreciation(
            period,
            costCenterId: parseIntNullable(data['costCenterId']),
          );
          return jsonResponse({'success': true, 'count': count});
        },
      );
    } catch (e, st) {
      debugPrint('[API] postAssetDepreciationRun failed: $e\n$st');
      return ApiErrors.failJson(e, st);
    }
  }

  // ═══════════════════════════════════════════════════════════════════════
  // OPERATIONAL EXPENSES — مصروفٌ تشغيليٌّ واردٌ من عميل (v166 / المرحلة ٢)
  // ═══════════════════════════════════════════════════════════════════════

  /// `POST /api/op-expenses`
  ///
  /// يشغّل [recordAndPostOperationalExpense] على الخادم: صفُّ المصروف
  /// وقيدُه وسندُ صرفه وخصمُ الخزنة — الأربعةُ في معاملةٍ واحدة. والعميلُ
  /// لا يكتب منها شيئاً (‏`operational_expenses_dao.dart`).
  ///
  /// ⚠️ **والخزنةُ تُحَلّ بمعرّفها العالميّ.** رقمُ خزنةٍ محلّيٌّ يصل هنا قد
  ///    يطابق خزنةً أخرى، فيُخصَم المبلغُ من غير مصدره ولا يظهر الخطأُ إلّا
  ///    في جردٍ يدويّ.
  Future<Response> postOperationalExpense(Request request) async {
    try {
      final perm = await ApiUserCtx.requirePermission(
          request, db, PermissionCodes.posExpense);
      if (perm != null) return perm;

      return await ApiHandlerBase.withBroadcast<Response>(
        endpointLabel: 'postOperationalExpense',
        tables: const {
          'op_expenses', 'op_expense_categories', 'safe_transactions',
          'safes', 'journal_entries', 'accounting',
        },
        body: () async {
          final data =
              json.decode(await request.readAsString()) as Map<String, dynamic>;

          final gid = data['globalId'] as String?;
          if (gid == null || gid.isEmpty) {
            return jsonResponse({'success': false, 'error': 'globalId مفقود'},
                statusCode: 400);
          }

          final existing = await (db.select(db.opExpenses)
                ..where((e) => e.globalId.equals(gid))
                ..limit(1))
              .getSingleOrNull();
          if (existing != null) {
            return jsonResponse({
              'success': true,
              'duplicate': true,
              'serverId': existing.id,
            });
          }

          // الفئةُ تُقبَل كاملةً وتُنشَأ إن غابت — فئةٌ سكّها العميلُ لا
          // وجودَ لها هنا، وإرسالُ معرّفها وحدَه يردّ كلَّ مصروفٍ فيها.
          final catRaw = data['category'] as Map<String, dynamic>?;
          final catGid = catRaw?['globalId'] as String?;
          if (catGid == null || catGid.isEmpty) {
            return jsonResponse({
              'success': false,
              'error': 'فئةُ المصروف مفقودةٌ من الطلب',
            }, statusCode: 400);
          }

          var category = await (db.select(db.opExpenseCategories)
                ..where((c) => c.globalId.equals(catGid))
                ..limit(1))
              .getSingleOrNull();
          if (category == null) {
            final newCatId = await db.createExpenseCategory(
              name: catRaw?['name'] as String? ?? 'فئةٌ واردة',
              type: catRaw?['type'] as String? ?? 'indirect',
              isProductionRelated: catRaw?['isProductionRelated'] as bool? ?? true,
              allocationMethod:
                  catRaw?['allocationMethod'] as String? ?? 'fixed_monthly',
              defaultRate: parseDouble(catRaw?['defaultRate']),
              accountCode: catRaw?['accountCode'] as String? ?? '6214',
              globalId: catGid,
            );
            category = await (db.select(db.opExpenseCategories)
                  ..where((c) => c.id.equals(newCatId)))
                .getSingle();
          }

          final safeGid = data['safeGlobalId'] as String?;
          final safe = safeGid == null || safeGid.isEmpty
              ? null
              : await (db.select(db.safes)
                    ..where((s) => s.globalId.equals(safeGid))
                    ..limit(1))
                  .getSingleOrNull();
          if (safeGid != null && safeGid.isNotEmpty && safe == null) {
            // 409 لا خصمٌ من خزنةٍ مخمَّنة: الطابورُ يعيد المحاولةَ حين
            // تصل الخزنة، والتخمينُ يخصم من غير مصدره بلا أثرٍ ظاهر.
            return jsonResponse({
              'success': false,
              'error': 'الخزنةُ المطلوبةُ لم تصل الخادمَ بعد',
              'retry': true,
            }, statusCode: 409);
          }

          final ccGid = data['costCenterGlobalId'] as String?;
          final costCenter = ccGid == null || ccGid.isEmpty
              ? null
              : await (db.select(db.costCenters)
                    ..where((c) => c.globalId.equals(ccGid))
                    ..limit(1))
                  .getSingleOrNull();

          final serverId = await db.recordAndPostOperationalExpense(
            categoryId: category.id,
            amount: parseDouble(data['amount']),
            expenseDate:
                DateTime.tryParse(data['expenseDate'] as String? ?? '') ??
                    DateTime.now(),
            description: data['description'] as String? ?? '',
            expenseAccountCode: data['expenseAccountCode'] as String? ??
                category.accountCode,
            period: data['period'] as String? ?? 'monthly',
            reference: data['reference'] as String?,
            notes: data['notes'] as String?,
            userId: parseInt(data['userId'], 1),
            branchId: parseIntNullable(data['branchId']),
            costCenterId: costCenter?.id,
            paymentMethod: data['paymentMethod'] as String?,
            safeId: safe?.id,
            globalId: gid,
          );

          return jsonResponse({'success': true, 'serverId': serverId});
        },
      );
    } catch (e, st) {
      debugPrint('[API] postOperationalExpense failed: $e\n$st');
      return ApiErrors.failJson(e, st);
    }
  }
}
