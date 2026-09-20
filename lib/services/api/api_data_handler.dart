// ═══════════════════════════════════════════════════════════════════════════
// API DATA HANDLER — CRUD for Expenses, Receipts, Shifts, Parties,
// Products, Purchases, Inventory, Treasury, Settings, Categories,
// Users, Warehouses, Backup
// ═══════════════════════════════════════════════════════════════════════════
//
// Extracted from ApiHandler for maintainability (PIR C-01).

import 'dart:async';
import 'dart:convert';
import 'dart:io' show Directory, File, Platform;
import 'package:flutter/foundation.dart';
import 'package:shelf/shelf.dart';
import 'package:drift/drift.dart';
import '../../core/auth/bootstrap_admin.dart';
import '../../core/logging/diagnostic_logger.dart';
import '../../core/permissions/permission_codes.dart';
import '../../core/utils/uuid_v7.dart';
import '../../data/database/database.dart';
import '../../domain/models/floor_plan_layout.dart';
import '../cheque_receipt_jes.dart';
import '../sync/strategies/setting_sync_strategy.dart'
    show isDeviceLocalSettingKey, isServerSecretSettingKey;
import 'api_user_context.dart';
import '../../domain/entities/accounting_entities.dart';
import 'api_handler_base.dart';
import '../../core/config/brand.dart';

/// Handles all data CRUD API endpoints (non-sales, non-display).
class ApiDataHandler extends ApiHandlerBase {
  ApiDataHandler(super.db, super.wsClients);

  // ═══════════════════════════════════════════════════════════════
  // FK Resolution Helpers (Client SQLite IDs → Server PostgreSQL IDs)
  // ═══════════════════════════════════════════════════════════════

  /// Resolve a client-provided warehouseId to a valid server warehouseId.
  Future<int> _resolveWarehouseId(int clientWarehouseId,
      {int? branchId, String? warehouseGlobalId}) async {
    // Spec 136 ISS-26 (#2 hardening / Spec 132) — resolve by globalId FIRST
    // when the caller threads it, so a mirror/client whose local warehouse ids
    // diverge from the server still routes the stock movement to the CORRECT
    // server warehouse (instead of a "Strict Mapping Violation" or landing in
    // the wrong warehouse). Falls back to the raw-id lookup for legacy callers.
    Warehouse? existing;
    if (warehouseGlobalId != null && warehouseGlobalId.isNotEmpty) {
      existing = await (db.select(db.warehouses)
            ..where((w) => w.globalId.equals(warehouseGlobalId))
            ..limit(1))
          .getSingleOrNull();
    }
    existing ??= await (db.select(db.warehouses)
          ..where((w) => w.id.equals(clientWarehouseId)))
        .getSingleOrNull();
    if (existing == null) {
      throw Exception(
          'Strict Mapping Violation: Warehouse ID $clientWarehouseId '
          '(globalId=$warehouseGlobalId) not found on server.');
    }
    // L4 (2026-04-28): Authorization check — when client declares its branch,
    // ensure the warehouse belongs to that branch (prevents cross-branch ops).
    if (branchId != null && existing.branchId != null && existing.branchId != branchId) {
      throw Exception(
        'Authorization Error: warehouse ${existing.id} belongs to branch '
        '${existing.branchId} but client declared branch $branchId. '
        'Cross-branch operation denied.',
      );
    }
    return existing.id;
  }

  /// Resolve a client-provided userId to a valid server userId.
  /// Primary: exact ID match. Fallback: username lookup (handles client/server
  /// auto-increment divergence when user was created in client mode).
  /// Resolve client-provided user ID to server-side ID with admin fallback.
  /// See `api_sales_handler.dart::_resolveUserId` for the full rationale —
  /// the short version: NEVER throw, always preserve the incoming record by
  /// attributing to admin as a last resort.
  Future<int> _resolveUserId(int clientUserId, {String? fallbackUsername}) async {
    final existing = await (db.select(db.users)
          ..where((u) => u.id.equals(clientUserId)))
        .getSingleOrNull();
    if (existing != null) return clientUserId;

    if (fallbackUsername != null && fallbackUsername.isNotEmpty) {
      final byUsername = await (db.select(db.users)
            ..where((u) => u.username.equals(fallbackUsername)))
          .getSingleOrNull();
      if (byUsername != null) {
        debugPrint('[API] _resolveUserId: ID $clientUserId not found — '
            'fell back to username "$fallbackUsername" → server ID ${byUsername.id}');
        return byUsername.id;
      }
    }

    final admin = await (db.select(db.users)
          ..where((u) => u.username.equals('admin') & u.isActive.equals(true))
          ..limit(1))
        .getSingleOrNull();
    if (admin != null) {
      debugPrint('[API] ⚠ _resolveUserId: clientUserId=$clientUserId '
          '(username="$fallbackUsername") not found — attributing to admin '
          '(id=${admin.id}) to preserve data');
      // ⚠️ أثرٌ **باقٍ** لا `debugPrint` وحدَه: هذا السطرُ يجعل سجلّاً يُنسب
      // إلى مديرِ النظام بدل صاحبِه، فيصير رقمٌ في «المبيعات حسب الكاشير»
      // كاذباً بلا أن يعلم أحد. و`debugPrint` يختفي في الإصدار — فبلاغُ
      // المالك «التقريرُ غيرُ دقيق» كان بلا أيّ أثرٍ يُقاس عليه.
      // (‏مقيسٌ في `test/unit/user_attribution_fallback_visible_test.dart`.)
      unawaited(DiagnosticLogger.log(
          'USER-ATTRIBUTION',
          '⚠ سجلٌّ أُسنِد إلى admin(id=${admin.id}) لأن '
          'clientUserId=$clientUserId username="$fallbackUsername" '
          'غيرُ موجودٍ على السيرفر — تقاريرُ «حسب المستخدم» ستنسبه للمدير'));
      return admin.id;
    }

    throw Exception('No valid user on server — cannot persist record. '
        'clientUserId=$clientUserId fallbackUsername=$fallbackUsername');
  }

  /// Resolve a nullable userId — returns null if input is null.
  Future<int?> _resolveUserIdNullable(int? clientUserId, {String? fallbackUsername}) async {
    if (clientUserId == null) return null;
    return _resolveUserId(clientUserId, fallbackUsername: fallbackUsername);
  }

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
      return errorResponse('Failed to record expense: $e');
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
      return errorResponse('Failed to delete expense: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════════════════
  // LANDED COST — تطبيقُ ورقة تحميلٍ واردةٍ من عميل (v166 / المرحلة ٢)
  // ═══════════════════════════════════════════════════════════════════════

  /// `POST /api/landed-costs/apply`
  ///
  /// يستقبل المستندَ كاملاً — الورقةَ وبنودَها وتوزيعاتِها — ثمّ يشغّل
  /// [applyLandedCost] **على الخادم**. فالحسابُ يقع مرّةً واحدةً وفي مكانٍ
  /// واحد، ويعود إلى الأجهزة بسحب الدلتا.
  ///
  /// ⚠️ **والمفاتيحُ تُقرأ بمعرّفاتها العالميّة لا بأرقامٍ محلّيّة.** رقمُ
  ///    العميل ورقمُ الخادم يتباعدان بالتصميم، ورقمٌ محلّيٌّ يصل هنا قد
  ///    يطابق صفّاً آخرَ تماماً فيُعاد بناءُ مستندٍ ليس هو. وهو عينُ العطب
  ///    الذي أُلغيت لأجله بوّابةُ تعديل المشتريات (‏ح-٦).
  ///
  /// ⚠️ **ولا يُرحَّل قيدٌ من العميل لهذا الحدث.** الطرفُ المُرحِّل واحدٌ
  ///    هو الخادم — عبر [applyLandedCost] أدناه. والعميلُ ممتنعٌ صراحةً
  ///    في `landed_cost_dao.dart`، لأنّ إزالةَ تكرار القيد مفتاحُها
  ///    `(referenceType, referenceId)` ورقمُ الورقة يختلف بين الطرفين.
  Future<Response> postLandedCostApply(Request request) async {
    try {
      final perm = await ApiUserCtx.requirePermission(
          request, db, PermissionCodes.purchasesEdit);
      if (perm != null) return perm;

      return await ApiHandlerBase.withBroadcast<Response>(
        endpointLabel: 'postLandedCostApply',
        // التطبيقُ يمسّ التكلفةَ والمخزونَ والأستاذ معاً.
        tables: const {
          'landed_cost_sheets', 'landed_cost_items', 'landed_cost_allocations',
          'products', 'inventory_balances', 'journal_entries', 'accounting',
        },
        body: () async {
          final data =
              json.decode(await request.readAsString()) as Map<String, dynamic>;

          final sheetGid = data['globalId'] as String?;
          if (sheetGid == null || sheetGid.isEmpty) {
            return jsonResponse({'success': false, 'error': 'globalId مفقود'},
                statusCode: 400);
          }

          // إزالةُ التكرار: إعادةُ إرسالٍ بعد انقطاعٍ لا تُطبّق مرّتين.
          final existing = await (db.select(db.landedCostSheets)
                ..where((s) => s.globalId.equals(sheetGid))
                ..limit(1))
              .getSingleOrNull();
          if (existing != null && existing.status == 'applied') {
            return jsonResponse({
              'success': true,
              'duplicate': true,
              'serverId': existing.id,
            });
          }

          // ــ حلُّ المفاتيح بالمعرّفات العالميّة ــــــــــــــــــــــــــ
          final invoiceGid = data['purchaseInvoiceGlobalId'] as String?;
          final invoice = invoiceGid == null || invoiceGid.isEmpty
              ? null
              : await (db.select(db.purchaseInvoices)
                    ..where((i) => i.globalId.equals(invoiceGid))
                    ..limit(1))
                  .getSingleOrNull();
          if (invoice == null) {
            // 409 لا 400: الطلبُ سليمٌ والفاتورةُ لم تصل بعد. الطابورُ
            // يعيد المحاولةَ، ولو ابتلعناه صامتين لضاع التطبيقُ نهائيّاً.
            return jsonResponse({
              'success': false,
              'error': 'فاتورةُ المشتريات الأمّ لم تصل الخادمَ بعد',
              'retry': true,
            }, statusCode: 409);
          }

          final sheetId = existing?.id ??
              await db.into(db.landedCostSheets).insert(
                    LandedCostSheetsCompanion.insert(
                      purchaseInvoiceId: invoice.id,
                      sheetNumber: data['sheetNumber'] as String? ?? '',
                      allocationMethod: Value(
                          data['allocationMethod'] as String? ?? 'by_value'),
                      notes: Value(data['notes'] as String?),
                      globalId: Value(sheetGid),
                    ),
                  );

          // البنودُ والتوزيعاتُ تُكتَب مرّةً واحدةً: صفٌّ بمعرّفٍ موجودٍ
          // يُتخطّى، فإعادةُ الإرسال لا تضاعف الإجماليّ.
          for (final raw in (data['items'] as List? ?? const [])) {
            final it = raw as Map<String, dynamic>;
            final gid = it['globalId'] as String?;
            if (gid == null || gid.isEmpty) continue;
            final dup = await (db.select(db.landedCostItems)
                  ..where((t) => t.globalId.equals(gid))
                  ..limit(1))
                .getSingleOrNull();
            if (dup != null) continue;

            final supGid = it['supplierPartyGlobalId'] as String?;
            final supplier = supGid == null || supGid.isEmpty
                ? null
                : await (db.select(db.parties)
                      ..where((t) => t.globalId.equals(supGid))
                      ..limit(1))
                    .getSingleOrNull();

            await db.into(db.landedCostItems).insert(
                  LandedCostItemsCompanion.insert(
                    sheetId: sheetId,
                    costType: Value(it['costType'] as String? ?? 'shipping'),
                    description: it['description'] as String? ?? '',
                    amount: parseDouble(it['amount']),
                    supplierPartyId: Value(supplier?.id),
                    globalId: Value(gid),
                  ),
                );
          }

          for (final raw in (data['allocations'] as List? ?? const [])) {
            final al = raw as Map<String, dynamic>;
            final gid = al['globalId'] as String?;
            if (gid == null || gid.isEmpty) continue;
            final dup = await (db.select(db.landedCostAllocations)
                  ..where((t) => t.globalId.equals(gid))
                  ..limit(1))
                .getSingleOrNull();
            if (dup != null) continue;

            final prodGid = al['productGlobalId'] as String?;
            final product = prodGid == null || prodGid.isEmpty
                ? null
                : await (db.select(db.products)
                      ..where((t) => t.globalId.equals(prodGid))
                      ..limit(1))
                    .getSingleOrNull();
            final piGid = al['purchaseItemGlobalId'] as String?;
            final purchaseItem = piGid == null || piGid.isEmpty
                ? null
                : await (db.select(db.purchaseInvoiceItems)
                      ..where((t) => t.globalId.equals(piGid))
                      ..limit(1))
                    .getSingleOrNull();

            if (product == null || purchaseItem == null) {
              // توزيعٌ بلا صنفٍ أو بلا بندِ فاتورةٍ لا يُكتَب بمفتاحٍ مخمَّن:
              // مزجُ التكلفة سيقع على الصنف الخطأ ولا يظهر خطؤه في أيّ رصيد.
              return jsonResponse({
                'success': false,
                'error': 'صنفٌ أو بندُ فاتورةٍ في التوزيع لم يصل الخادمَ بعد',
                'retry': true,
              }, statusCode: 409);
            }

            await db.into(db.landedCostAllocations).insert(
                  LandedCostAllocationsCompanion.insert(
                    sheetId: sheetId,
                    productId: product.id,
                    purchaseItemId: purchaseItem.id,
                    originalCost: parseDouble(al['originalCost']),
                    allocatedAmount: parseDouble(al['allocatedAmount']),
                    newUnitCost: parseDouble(al['newUnitCost']),
                    quantity: parseDouble(al['quantity']),
                    globalId: Value(gid),
                  ),
                );
          }

          // التطبيقُ نفسُه — نفسُ الدالّة التي يشغّلها وضعُ الخادم المستقلّ،
          // فلا منطقَ ماليٌّ مكرَّرٌ هنا يمكن أن ينحرف عنها.
          await db.applyLandedCost(sheetId);

          return jsonResponse({
            'success': true,
            'serverId': sheetId,
          });
        },
      );
    } catch (e, st) {
      debugPrint('[API] postLandedCostApply failed: $e\n$st');
      return jsonResponse({'success': false, 'error': e.toString()},
          statusCode: 500);
    }
  }

  // ═══════════════════════════════════════════════════════════════════════
  // FLOOR PLAN — مخطَّطُ قاعةٍ واردٌ من عميل (v174 / قسمُ ٧)
  // ═══════════════════════════════════════════════════════════════════════

  /// `POST /api/floor-plan`
  ///
  /// يطبّق **نفسَ** `saveFloorPlanLayout` التي يشغّلها التشغيلُ المنفرد،
  /// فلا منطقَ ثانٍ هنا ينحرف عنها.
  ///
  /// 🔴 **والطاولاتُ تُحلَّ من طاولاتِ هذا القسم وحدَها.** معرِّفٌ
  ///    عالميٌّ لطاولةٍ في قسمٍ آخرَ يُسقَط بدل أن يُنقلَ إلى إحداثيّاتِ
  ///    لوحةٍ لا تخصُّه — فتختفي من قسمِها ولم يلمسها أحد.
  Future<Response> postFloorPlan(Request request) async {
    try {
      final perm = await ApiUserCtx.requirePermission(
          request, db, PermissionCodes.tablesManage);
      if (perm != null) return perm;

      return await ApiHandlerBase.withBroadcast<Response>(
        endpointLabel: 'postFloorPlan',
        tables: const {
          'floor_plan_items',
          'table_sections',
          'restaurant_tables',
        },
        body: () async {
          final data =
              json.decode(await request.readAsString()) as Map<String, dynamic>;

          final sectionGid = data['sectionGlobalId'] as String?;
          if (sectionGid == null || sectionGid.isEmpty) {
            return jsonResponse(
                {'success': false, 'error': 'sectionGlobalId مفقود'},
                statusCode: 400);
          }

          final section = await (db.select(db.tableSections)
                ..where((s) => s.globalId.equals(sectionGid))
                ..limit(1))
              .getSingleOrNull();
          if (section == null) {
            // 409 لا 400: الطلبُ سليمٌ والقسمُ لم يصل بعد، والطابورُ
            // يعيد المحاولة. وابتلاعُه صامتاً يُضيّع ترتيبَ القاعة
            // نهائيّاً والمستخدمُ يظنُّ أنّه حفظ.
            return jsonResponse({
              'success': false,
              'error': 'قسمُ الطاولات لم يصل الخادمَ بعد',
              'retry': true,
            }, statusCode: 409);
          }

          final tablesInSection = await (db.select(db.restaurantTables)
                ..where((t) => t.sectionId.equals(section.id)))
              .get();
          final idByGlobalId = <String, int>{
            for (final t in tablesInSection)
              if (t.globalId != null) t.globalId!: t.id,
          };

          final layout = floorPlanLayoutFromJson(
            data,
            sectionId: section.id,
            resolveTableId: (gid) => gid == null ? null : idByGlobalId[gid],
          );

          await db.saveFloorPlanLayout(layout);

          return jsonResponse({
            'success': true,
            'sectionId': section.id,
            'items': layout.items.length,
          });
        },
      );
    } catch (e, st) {
      debugPrint('[API] postFloorPlan failed: $e\n$st');
      return jsonResponse({'success': false, 'error': e.toString()},
          statusCode: 500);
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
      return jsonResponse({'success': false, 'error': e.toString()},
          statusCode: 500);
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
      return jsonResponse({'success': false, 'error': e.toString()},
          statusCode: 500);
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
      return jsonResponse({'success': false, 'error': e.toString()},
          statusCode: 500);
    }
  }

  // ═══════════════════════════════════════════════════════════════════════
  // MANUFACTURING — حدثٌ على أمرِ إنتاجٍ واردٌ من عميل (v166 / المرحلة ٢)
  // ═══════════════════════════════════════════════════════════════════════

  /// `POST /api/manufacturing/action`
  ///
  /// أربعةُ أحداثٍ في نقطةٍ واحدة: `start` · `complete` · `reverse` ·
  /// `add_cost`. وكلُّها تُنفَّذ بدوالِّ الـDAO نفسِها التي يشغّلها الوضعُ
  /// المستقلّ، فلا منطقَ ماليٌّ مكرَّرٌ هنا يمكن أن ينحرف عنها.
  ///
  /// ⚠️ **والأمرُ يُحَلّ بهويّته العالميّة.** رقمٌ محلّيٌّ يصل هنا قد يطابق
  ///    أمراً آخرَ تماماً، فتُستهلك خاماتُ غيره — واستهلاكٌ خطأٌ لا يُعكَس
  ///    بقيدٍ كما يُعكَس ترحيلٌ خطأ.
  ///
  /// وإعادةُ الإرسال لا تُنفّذ مرّتين: كلُّ دالّةٍ تفحص حالةَ الأمر أوّلاً
  /// (‏`draft` للبدء و`in_progress` للإنجاز) وترمي إن خالفت.
  Future<Response> postManufacturingAction(Request request) async {
    try {
      final perm = await ApiUserCtx.requirePermission(
          request, db, PermissionCodes.manufacturingManage);
      if (perm != null) return perm;

      return await ApiHandlerBase.withBroadcast<Response>(
        endpointLabel: 'postManufacturingAction',
        tables: const {
          'manufacturing_orders', 'mfg_order_costs', 'stock_movements',
          'products', 'inventory_balances', 'journal_entries', 'accounting',
        },
        body: () async {
          final data =
              json.decode(await request.readAsString()) as Map<String, dynamic>;

          final orderGid = data['orderGlobalId'] as String?;
          final action = data['action'] as String?;
          if (orderGid == null || orderGid.isEmpty || action == null) {
            return jsonResponse({
              'success': false,
              'error': 'orderGlobalId أو action مفقود',
            }, statusCode: 400);
          }

          final order = await (db.select(db.manufacturingOrders)
                ..where((o) => o.globalId.equals(orderGid))
                ..limit(1))
              .getSingleOrNull();
          if (order == null) {
            // 409 لا 404: الأمرُ سيصل بالمزامنة، والطابورُ يعيد المحاولة.
            return jsonResponse({
              'success': false,
              'error': 'أمرُ الإنتاج لم يصل الخادمَ بعد',
              'retry': true,
            }, statusCode: 409);
          }

          switch (action) {
            case 'start':
              await db.startProduction(order.id);
              break;
            case 'complete':
              await db.completeProduction(
                order.id,
                actualProducedQty:
                    parseDoubleNullable(data['actualProducedQty']),
                costCenterId: parseIntNullable(data['costCenterId']),
              );
              break;
            case 'reverse':
              await db.reverseManufacturingOrder(order.id);
              break;
            case 'add_cost':
              await db.addMfgOrderCost(
                orderId: order.id,
                costType: data['costType'] as String? ?? 'other',
                description: data['description'] as String? ?? '',
                amount: parseDouble(data['amount']),
                globalId: data['globalId'] as String?,
              );
              break;
            default:
              return jsonResponse({
                'success': false,
                'error': 'حدثٌ غيرُ معروف: $action',
              }, statusCode: 400);
          }

          return jsonResponse({'success': true, 'serverId': order.id});
        },
      );
    } catch (e, st) {
      debugPrint('[API] postManufacturingAction failed: $e\n$st');
      return jsonResponse({'success': false, 'error': e.toString()},
          statusCode: 500);
    }
  }

  /// POST /api/bookings/apply-deposit · v167 / المرحلة ٣
  ///
  /// إطفاءُ التزامِ عربونٍ على فاتورة، واردٌ من عميل. الحدثُ الماليُّ
  /// الوحيدُ في الفئةِ التشغيليّة.
  ///
  /// 🔴 **والخادمُ وحدَه يُرحّل.** مفتاحُ إزالة تكرار القيد
  /// `(referenceType, referenceId)` لا يمسك ترحيلاً مزدوجاً هنا:
  /// `referenceId` رقمُ الحجز **المحلّيّ** على العميل وهو يخالف رقمَه
  /// هنا. فلو حسب الطرفان لصار قيدان يبدوان مختلفَين، ورصيدُ العميل
  /// منقوصاً ضِعفَ العربون.
  ///
  /// والحجزُ يُدعى بهويّته العالميّة: رقمٌ محلّيٌّ قد يُطفئ عربونَ حجزِ
  /// عميلٍ آخر على فاتورةِ عميلٍ آخر.
  ///
  /// ⚠️ و`applyBookingDepositToInvoice` نفسُها هي المنفّذ — لا منطقَ
  /// ماليٌّ مكرَّرٌ في المعالج يمكن أن ينحرف عنها. وحارسُها
  /// (`booking.invoiceId != null`) هو ما يجعل إعادةَ إرسالِ الطابور بعد
  /// انقطاعٍ تُردّ بدل أن تُطفئ الالتزامَ مرّتين.
  Future<Response> postBookingApplyDeposit(Request request) async {
    try {
      final perm = await ApiUserCtx.requirePermission(
          request, db, PermissionCodes.bookingsDeposit);
      if (perm != null) return perm;

      return await ApiHandlerBase.withBroadcast<Response>(
        endpointLabel: 'postBookingApplyDeposit',
        tables: const {
          'bookings', 'sales_invoices', 'parties', 'journal_entries',
          'accounting',
        },
        body: () async {
          final data =
              json.decode(await request.readAsString()) as Map<String, dynamic>;

          final bookingGid = data['bookingGlobalId'] as String?;
          final invoiceGid = data['invoiceGlobalId'] as String?;
          if (bookingGid == null ||
              bookingGid.isEmpty ||
              invoiceGid == null ||
              invoiceGid.isEmpty) {
            return jsonResponse({
              'success': false,
              'error': 'bookingGlobalId أو invoiceGlobalId مفقود',
            }, statusCode: 400);
          }

          final booking = await (db.select(db.bookings)
                ..where((b) => b.globalId.equals(bookingGid))
                ..limit(1))
              .getSingleOrNull();
          final invoice = await (db.select(db.salesInvoices)
                ..where((i) => i.globalId.equals(invoiceGid))
                ..limit(1))
              .getSingleOrNull();

          // 409 لا 404: الطرفُ الغائبُ سيصل بالمزامنة، والطابورُ يعيد
          // المحاولة. و404 يعني «لن يصل أبداً» فيُسقِط الحدثَ نهائيّاً.
          if (booking == null || invoice == null) {
            return jsonResponse({
              'success': false,
              'error': booking == null
                  ? 'الحجزُ لم يصل الخادمَ بعد'
                  : 'الفاتورةُ لم تصل الخادمَ بعد',
              'retry': true,
            }, statusCode: 409);
          }

          await db.applyBookingDepositToInvoice(
            bookingId: booking.id,
            invoiceId: invoice.id,
            userId: parseIntNullable(data['userId']),
          );

          return jsonResponse({'success': true, 'serverId': booking.id});
        },
      );
    } catch (e, st) {
      debugPrint('[API] postBookingApplyDeposit failed: $e\n$st');
      return jsonResponse({'success': false, 'error': e.toString()},
          statusCode: 500);
    }
  }

  Future<Response> postReceipt(Request request) async {
    try {
      // Spec 077 Batch 5 (Spec 060 Phase 2): per-user permission gate.
      final perm = await ApiUserCtx.requirePermission(
          request, db, PermissionCodes.treasuryReceiptsCreate);
      if (perm != null) return perm;
      return await ApiHandlerBase.withBroadcast<Response>(
        endpointLabel: 'postReceipt',
        tables: const {
          'safe_transactions', 'accounting', 'journal_entries',
          'commercial_papers',
        },
        body: () async {
      final data =
          json.decode(await request.readAsString()) as Map<String, dynamic>;

      // Issue 12 — globalId-based idempotency. Mirrors the postExpense
      // pattern: a retry from the outbox with the same globalId returns
      // the existing serverId instead of inserting a phantom duplicate.
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

      // Issue 12 — resolve `safeId` to a server-side id. Client and server
      // each seed the chart of safes independently, so the same logical
      // safe (e.g. "صندوق نقد المعان") commonly has different numeric ids
      // on each side. SafeSyncStrategy keeps the local id when matching
      // by name, so the client's `safeId` is its OWN id — useless on the
      // server. Prefer match by `safeGlobalId`, fall back to raw safeId.
      int? resolvedSafeId = parseIntNullable(data['safeId']);
      final clientSafeGlobalId = (data['safeGlobalId'] as String?)?.trim();
      if (clientSafeGlobalId != null && clientSafeGlobalId.isNotEmpty) {
        final byGlobal = await (db.select(db.safes)
              ..where((s) => s.globalId.equals(clientSafeGlobalId))
              ..limit(1))
            .getSingleOrNull();
        if (byGlobal != null) {
          if (byGlobal.id != resolvedSafeId) {
            debugPrint('[API] postReceipt: remapped safeId '
                '$resolvedSafeId → ${byGlobal.id} via globalId');
          }
          resolvedSafeId = byGlobal.id;
        }
      }

      // Resolve costCenterId — prefer explicit value, otherwise derive
      // from the branchId the client sent so the journal entry lands on
      // the right cost center even when the client didn't compute one.
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

      // Feature 044 — remap partyId via globalId, same as postExpense.
      // Without this the receipt's safe_transactions row hit the FK on
      // party_id when the mirror's local autoincrement diverged from
      // the server.
      final clientRcpPartyId = parseIntNullable(data['partyId']);
      final rcpPartyGid = (data['partyGlobalId'] as String?)?.trim();
      final rcpPartyName = (data['partyName'] as String?)?.trim();
      int? resolvedRcpPartyId;
      if (clientRcpPartyId != null && clientRcpPartyId > 0) {
        resolvedRcpPartyId = await resolvePartyId(
          clientPartyId: clientRcpPartyId,
          partyGlobalId: rcpPartyGid == null || rcpPartyGid.isEmpty ? null : rcpPartyGid,
          fallbackName: rcpPartyName == null || rcpPartyName.isEmpty ? null : rcpPartyName,
        );
      }

      // Spec 133 — when the client sends paperType='cheque', skip the
      // cash-leg JE and the safe transaction on the server side too,
      // so the server's pull doesn't re-introduce the duplicate JE that
      // mirror/client installs would otherwise inherit on next sync.
      // Symmetric with postExpense's Spec 081 fix (this file, postExpense
      // around line 118-119).
      final receiptPaperType = data['paperType'] as String?;
      final receiptIsCheque =
          receiptPaperType == 'cheque' || receiptPaperType == 'check';

      final id = await db.createReceiptVoucher(
        amount: parseDouble(data['amount']),
        category: data['category'] as String,
        discount: parseDouble(data['discount']),
        description: data['description'] as String?,
        partyId: resolvedRcpPartyId,
        safeId: resolvedSafeId,
        userId: await _resolveUserIdNullable(parseIntNullable(data['userId']),
            fallbackUsername: data['createdByUsername'] as String?),
        costCenterId: costCenterId,
        // Issue 3 (Feature 020): honor the operator's CoA account pick from
        // the client. Without this, the server's JE credit leg falls back to
        // the category-default account and diverges from what the local JE
        // posted on the client. Null means "no override" — the existing
        // category-derived behavior runs unchanged.
        linkedAccountId: parseIntNullable(data['linkedAccountId']),
        globalId: incomingGlobalId,
        skipJournalEntry: receiptIsCheque,
        skipSafeTransaction: receiptIsCheque,
        // Spec 135 BUG-C — attribute the JE to the operator's branch (the
        // client sent it) instead of the target safe's branch.
        operatingBranchId: clientBranchId,
      );

      // Spec 133 (FR-010) — discount-only JE for cheque receipts with a
      // settlement discount. Same helper the repo path uses (mirrors
      // treasury_repository_impl.dart::createReceiptVoucher). The
      // commercial-papers `pending` autopost handles the cheque amount;
      // this handles ONLY the discount portion so the customer's
      // outstanding balance lands at the correct net.
      if (receiptIsCheque) {
        final discountAmount = parseDouble(data['discount']);
        if (discountAmount > 0 && resolvedRcpPartyId != null) {
          await ChequeReceiptJEs.postDiscountAllowedJournalEntry(
            db: db,
            partyId: resolvedRcpPartyId,
            discountAmount: discountAmount,
            costCenterId: costCenterId,
            branchId: clientBranchId,
          );
        }
      }

      return jsonResponse({'success': true, 'serverId': id});
        },
      );
    } catch (e) {
      debugPrint('[API] postReceipt error: $e');
      return errorResponse('Failed to record receipt: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // Shifts
  // ═══════════════════════════════════════════════════════════════

  Future<Response> postOpenShift(Request request) async {
    try {
      // Spec 077 Batch 5 (Spec 060 Phase 2): per-user permission gate.
      final perm = await ApiUserCtx.requirePermission(
          request, db, PermissionCodes.posShiftOpen);
      if (perm != null) return perm;
      return await ApiHandlerBase.withBroadcast<Response>(
        endpointLabel: 'postOpenShift',
        // openShift writes a shifts row + an opening safe_transaction; an
        // opening-balance JE is not auto-posted by the current path, but
        // declaring the accounting tables is the safe maximum if a future
        // wiring lands.
        tables: const {
          'shifts', 'safe_transactions', 'accounting', 'journal_entries',
        },
        body: () async {
      final data =
          json.decode(await request.readAsString()) as Map<String, dynamic>;
      final resolvedUserId = await _resolveUserId(parseInt(data['userId']),
          fallbackUsername: data['createdByUsername'] as String?);
      // Spec 008 / FR-006: honour the client's branchId so the close-time
      // logic on this side (and on every paired client) can pull the right
      // branch's safes for shift-close zero-out.
      final branchId = parseIntNullable(data['branchId'] ?? data['branch_id']);
      // R9 idempotency: if the client sent a globalId and we already have a
      // shift for it, return that id instead of opening a duplicate. This
      // covers outbox replays + retries that previously created phantom
      // server shifts every time.
      final clientGlobalId = data['globalId'] as String?;
      if (clientGlobalId != null && clientGlobalId.isNotEmpty) {
        final existing = await (db.select(db.shifts)
              ..where((s) => s.globalId.equals(clientGlobalId))
              ..limit(1))
            .getSingleOrNull();
        if (existing != null) {
          debugPrint('[API] postOpenShift: dedup by globalId=$clientGlobalId '
              '→ existing shiftId=${existing.id}');
          return jsonResponse({'success': true, 'shiftId': existing.id});
        }
      }

      // Feature 048 (v130) — duplicate-open guard. Field log
      // (2026-05-13) showed admin user accumulated 4 simultaneously
      // open shifts on the server (ids 1, 2, 3, 5) because every mirror
      // open call created a NEW row without checking the user's state.
      // Symptoms cascaded: `getCurrentOpenShift(userId)` returned
      // different ids on different reads, shift-close calls disappeared
      // (they targeted a different open shift than the cashier saw),
      // and the closing report aggregated the wrong window.
      //
      // Fix: before INSERT, look up the user's existing open shift on
      // THIS server. If one exists, return its id (idempotent open).
      // The client still treats the response as "shift opened" because
      // the response shape is identical — but the server no longer
      // creates phantoms. Combined with v129's reverse carve-out
      // (Feature 036), the system now self-heals: stale opens stop
      // accumulating AND existing recently-closed shifts are protected
      // from flip-back.
      final existingOpen = await (db.select(db.shifts)
            ..where((s) =>
                s.userId.equals(resolvedUserId) &
                s.status.equals('open'))
            ..orderBy([(s) => OrderingTerm.desc(s.id)])
            ..limit(1))
          .getSingleOrNull();
      if (existingOpen != null) {
        debugPrint('[API] postOpenShift: user $resolvedUserId already has '
            'an open shift (id=${existingOpen.id}, globalId='
            '${existingOpen.globalId ?? "null"}) — returning that instead '
            'of creating a duplicate. Feature 048 v130 guard.');
        return jsonResponse({
          'success': true,
          'shiftId': existingOpen.id,
          'duplicate': true,
          'reason': 'user_has_open_shift',
        });
      }

      final shiftId = await db.openShift(
        resolvedUserId,
        parseDoubleNullable(data['openingBalance']) ?? 0,
        branchId: branchId,
        globalId: clientGlobalId,
      );
      return jsonResponse({'success': true, 'shiftId': shiftId});
        },
      );
    } catch (e) {
      debugPrint('[API] postOpenShift error: $e');
      return errorResponse('Failed to open shift: $e');
    }
  }

  Future<Response> postCloseShift(Request request) async {
    try {
      // Spec 077 Batch 5 (Spec 060 Phase 2): per-user permission gate.
      final perm = await ApiUserCtx.requirePermission(
          request, db, PermissionCodes.posShiftClose);
      if (perm != null) return perm;
      return await ApiHandlerBase.withBroadcast<Response>(
        endpointLabel: 'postCloseShift',
        // Close path writes variance JE + ZRO safe_transactions per safe +
        // safes.balance updates.
        tables: const {
          'shifts', 'safes', 'safe_transactions',
          'accounting', 'journal_entries',
        },
        body: () async {
      final data =
          json.decode(await request.readAsString()) as Map<String, dynamic>;

      int shiftId = parseInt(data['shiftId']);

      // R9 (2026-05-12 fix): prefer globalId-based resolution. The client's
      // local SQLite shiftId rarely matches the server's auto-increment id
      // because the original /api/shifts/open response wasn't mapped back
      // (online opens bypass the outbox where mappedIds is populated). The
      // result was a recurring "Shift not found" 500 → DEAD-LETTER on every
      // shift close. Looking up by globalId fixes the root cause without
      // requiring a separate id-mapping table on the client.
      final shiftGlobalId = data['shiftGlobalId'] as String?;
      if (shiftGlobalId != null && shiftGlobalId.isNotEmpty) {
        final byGlobalId = await (db.select(db.shifts)
              ..where((s) => s.globalId.equals(shiftGlobalId))
              ..limit(1))
            .getSingleOrNull();
        if (byGlobalId != null) {
          // Idempotency: a retried close on an already-closed shift is a
          // no-op success — never throw.
          if (byGlobalId.status == 'closed') {
            debugPrint('[API] postCloseShift: globalId=$shiftGlobalId already '
                'closed (id=${byGlobalId.id}) — returning success');
            return jsonResponse(
                {'success': true, 'shiftId': byGlobalId.id, 'alreadyClosed': true});
          }
          shiftId = byGlobalId.id;
        }
      }

      // Defense in depth: if the client sent a shiftId that doesn't exist on
      // this server, reset to 0 so the userId-based fallback / reconstruction
      // path kicks in (instead of throwing "Shift not found"). Only triggers
      // when the globalId lookup above didn't already resolve a row.
      if (shiftId != 0) {
        final exists = await (db.select(db.shifts)
              ..where((s) => s.id.equals(shiftId))
              ..limit(1))
            .getSingleOrNull();
        if (exists == null) {
          debugPrint('[API] postCloseShift: shiftId=$shiftId not found on '
              'server — falling back to userId lookup / reconstruction');
          shiftId = 0;
        }
      }

      // Client mode sends shiftId=0 when the local DB doesn't have the shift yet.
      // Fall back to looking up the user's currently open shift by userId.
      // Supports two payload formats:
      //   • New (post-fix): payload contains explicit 'userId' field
      //   • Old (pre-fix):  userId is encoded in 'notes' as "userId=X,actualCard=Y"
      if (shiftId == 0) {
        // Try explicit userId field first (new format)
        int? userId = parseIntNullable(data['userId']);

        // Fall back to parsing from notes string (old format queued before fix)
        if (userId == null) {
          final notes = (data['notes'] as String?) ?? '';
          final match = RegExp(r'userId=(\d+)').firstMatch(notes);
          userId = match != null ? int.tryParse(match.group(1) ?? '') : null;
        }

        if (userId != null) {
          final openShift = await db.getCurrentOpenShift(userId);
          if (openShift != null) shiftId = openShift.id;
        }
      }

      // Phase 5A.7 (Issue 2) — when no server shift exists, RECONSTRUCT
      // it from the close payload's reconstruction hints (openingBalance,
      // openedAt, userId) before closing. Previously this branch returned
      // {clientAuthoritative: true} and never wrote anything, leaving the
      // server's reports forever inconsistent with the client's books
      // (the user's exact complaint: "إقفال الوردية لا يُرحَّل بشكل سليم").
      //
      // The client now ships these hints in the close payload (cwi_catalog
      // closeShift). Outbox rows queued before this change won't have
      // them; in that legacy case we fall back to opening with a zero
      // balance + a backfill flag so the server still has SOMETHING to
      // close — better than a silent acknowledge.
      if (shiftId == 0) {
        final reconstructUserId = parseIntNullable(data['userId']);
        if (reconstructUserId == null) {
          debugPrint('[API] postCloseShift: cannot reconstruct shift — '
              'no userId in payload. Rejecting.');
          return errorResponse('Cannot reconstruct shift: userId required');
        }
        final openingBalance =
            parseDoubleNullable(data['openingBalance']) ?? 0.0;
        final openedAtRaw = data['openedAt'] as String?;
        debugPrint('[API] postCloseShift: reconstructing missing shift for '
            'userId=$reconstructUserId, openingBalance=$openingBalance');
        final resolvedUserId = await _resolveUserId(reconstructUserId,
            fallbackUsername: data['createdByUsername'] as String?);
        // Spec 008 / FR-006: best-effort branchId for the reconstructed
        // shift. The close payload may carry it (when the open queued
        // offline + close arrives first); if not, we leave it null and the
        // close logic falls back to getUserBranchId — same as legacy rows.
        final reconstructBranchId =
            parseIntNullable(data['branchId'] ?? data['branch_id']);
        shiftId = await db.openShift(
          resolvedUserId,
          openingBalance,
          branchId: reconstructBranchId,
          // R9: thread the client's shiftGlobalId into the reconstructed
          // server row so future retries dedup by globalId (instead of
          // reconstructing a fresh phantom shift on every replay).
          globalId: shiftGlobalId,
        );
        // Backdate startTime if the client told us when the shift opened
        // — keeps shift duration analytics honest. Best-effort: ignore
        // failures so a malformed timestamp doesn't break the close.
        if (openedAtRaw != null) {
          final parsed = DateTime.tryParse(openedAtRaw);
          if (parsed != null) {
            try {
              await (db.update(db.shifts)
                    ..where((s) => s.id.equals(shiftId)))
                  .write(ShiftsCompanion(startTime: Value(parsed)));
            } catch (_) {}
          }
        }
      }

      await db.closeShiftWithAudit(
        shiftId,
        parseDouble(data['actualCash']),
        notes: data['notes'] as String?,
        closingMethod: (data['closingMethod'] as String?) ?? 'normal',
        // v151 — persist the client's closing figures on the server too;
        // otherwise a shift closed from a client terminal has no snapshot to
        // reprint from anywhere but that one machine.
        closingSnapshot: data['closingSnapshot'] as String?,
      );
      return jsonResponse({'success': true, 'shiftId': shiftId});
        },
      );
    } catch (e) {
      debugPrint('[API] postCloseShift error: $e');
      return errorResponse('Failed to close shift: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // Inventory
  // ═══════════════════════════════════════════════════════════════

  Future<Response> postStockAdjust(Request request) async {
    try {
      // Spec 077 Batch 5 (Spec 060 Phase 2): per-user permission gate.
      final perm = await ApiUserCtx.requirePermission(
          request, db, PermissionCodes.inventoryEdit);
      if (perm != null) return perm;
      return await ApiHandlerBase.withBroadcast<Response>(
        endpointLabel: 'postStockAdjust',
        // adjustStock writes a stock_movement, updates inventory_balances +
        // products.currentStock, and autoposts a JE for cycle_count /
        // adjustment / write_off / loss types.
        tables: const {
          'products', 'inventory', 'stock_movements',
          'accounting', 'journal_entries',
        },
        body: () async {
      final data =
          json.decode(await request.readAsString()) as Map<String, dynamic>;

      // Resolve productId — prefer globalId when the client sends one so a
      // client↔server id drift (different auto-increment sequences, outbox
      // replay after the row was created under a different server id) heals
      // transparently instead of failing silently and leaving `inventory_balances`
      // unpopulated. Mirrors the `categoryGlobalId` reconciliation already used
      // in postProduct.
      int productIdResolved = parseInt(data['productId']);
      final productGlobalId = data['productGlobalId'] as String?;
      if (productGlobalId != null && productGlobalId.isNotEmpty) {
        final existingByUuid = await (db.select(db.products)
              ..where((p) => p.globalId.equals(productGlobalId))
              ..limit(1))
            .getSingleOrNull();
        if (existingByUuid != null) {
          productIdResolved = existingByUuid.id;
        }
      }
      if (productIdResolved <= 0) {
        throw Exception(
          'Validation Error: productId or productGlobalId is required.',
        );
      }

      final clientWhIdAdj = parseInt(data['warehouseId']);
      if (clientWhIdAdj == 0) throw Exception('Validation Error: warehouseId is required.');
      final resolvedWhIdAdj = await _resolveWarehouseId(
        clientWhIdAdj,
        branchId: parseIntNullable(data['branchId']),
        warehouseGlobalId: data['warehouseGlobalId'] as String?,
      );

      final type = data['type'] as String?;

      // Idempotency for opening_stock: if this (product, warehouse) already
      // has an opening_stock movement recorded, a repeat call (from outbox
      // retry OR the client startup reconcile) must NOT stack a second
      // opening balance on top — that would silently double the stock.
      // Treated as success so the caller / outbox stops retrying.
      if (type == 'opening_stock') {
        final existingMv = await (db.select(db.stockMovements)
              ..where((m) =>
                  m.productId.equals(productIdResolved) &
                  m.warehouseId.equals(resolvedWhIdAdj) &
                  m.movementType.equals('opening_stock'))
              ..limit(1))
            .getSingleOrNull();
        if (existingMv != null) {
          debugPrint('[API] postStockAdjust: opening_stock already recorded '
              'for product=$productIdResolved warehouse=$resolvedWhIdAdj '
              '— skipping (idempotent).');
          return jsonResponse({
            'success': true,
            'skipped': 'opening_stock_already_applied',
          });
        }
      }

      await db.adjustStock(
        productId: productIdResolved,
        warehouseId: resolvedWhIdAdj,
        quantity: parseDouble(data['quantity']),
        type: type,
        notes: data['notes'] as String?,
        // Spec 135 BUG-A: honour the client-minted event gid so the server's
        // autoposted JE converges on the SAME deterministic globalId as the
        // client's, and the UNIQUE constraint dedups a replay instead of the
        // server re-deriving a colliding ...ref0... id.
        adjustmentEventGid: data['adjustmentEventGid'] as String?,
      );
      return jsonResponse({'success': true});
        },
      );
    } catch (e) {
      debugPrint('[API] postStockAdjust error: $e');
      return errorResponse('Failed to adjust stock: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // Treasury — Safe Close
  // ═══════════════════════════════════════════════════════════════

  Future<Response> postCloseSafe(Request request) async {
    try {
      // Spec 077 Batch 5 (Spec 060 Phase 2): per-user permission gate.
      final perm = await ApiUserCtx.requirePermission(
          request, db, PermissionCodes.treasuryManage);
      if (perm != null) return perm;
      return await ApiHandlerBase.withBroadcast<Response>(
        endpointLabel: 'postCloseSafe',
        // closeSafe writes a closing safe_transaction, updates safes.balance,
        // and may post a closing JE.
        tables: const {
          'safes', 'safe_transactions',
          'accounting', 'journal_entries',
        },
        body: () async {
      final data =
          json.decode(await request.readAsString()) as Map<String, dynamic>;
      // Spec 135: honour the client's amounts + closeEventGid so the server
      // posts the IDENTICAL closing JE with the SAME deterministic globalId
      // (dedup against the client's local row on DeltaPull).
      await db.closeSafe(
        parseInt(data['safeId']),
        userId: parseIntNullable(data['userId']),
        cashAmount: (data['cashAmount'] as num?)?.toDouble(),
        bankAmount: (data['bankAmount'] as num?)?.toDouble(),
        notes: data['notes'] as String?,
        closeEventGid: data['closeEventGid'] as String?,
      );
      return jsonResponse({'success': true});
        },
      );
    } catch (e) {
      debugPrint('[API] postCloseSafe error: $e');
      return errorResponse('Failed to close safe: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // Settings
  // ═══════════════════════════════════════════════════════════════

  Future<Response> postSettings(Request request) async {
    try {
      // Spec 077 Batch 5 (Spec 060 Phase 2): per-user permission gate.
      final perm = await ApiUserCtx.requirePermission(
          request, db, PermissionCodes.settingsEdit);
      if (perm != null) return perm;
      final data =
          json.decode(await request.readAsString()) as Map<String, dynamic>;
      final incoming = data.map<String, String>(
        (k, v) => MapEntry(k, v.toString()),
      );

      // ── قائمةُ منعٍ على الخادم، لا على العميل وحدَه ─────────────────────
      //
      // 🔴 كانت هذه النقطةُ تكتب **أيَّ** مفتاحٍ يرسله العميل. وهي الطرفُ
      // الثالثُ لنفس الثغرة: العميلُ يمنع الدفعَ الصاعد، والاستراتيجيّةُ
      // تمنع الكتابةَ الهابطة — والخادمُ كان مفتوحاً. فعميلٌ واحدٌ (‏أو
      // حاملُ توكن LAN) يكتب `network_mode='client'` على الخادم فيقلع
      // الخادمُ عميلاً وتعمى كلُّ الأجهزة، أو يكتب `_watermark__<table>`
      // فيفتح فجوةَ سحبٍ دائمةً صامتة.
      //
      // ولا يُرفَض الطلبُ كلُّه: حمولةٌ مشروعةٌ قد تحمل مفتاحاً واحداً
      // ممنوعاً بين عشرة صحيحة، ورفضُ الكلِّ يُسقط إعداداتٍ سليمة. فتُكتَب
      // المسموحةُ ويُبلَّغ عن المحجوبة.
      // ⚠️ **محوران، لا واحد.** `isDeviceLocalSettingKey` تمنع ما يخصُّ
      // الجهاز، و`isServerSecretSettingKey` تمنع ما يحمل سرّاً. وكلمةُ مرور
      // المدير ليست «إعداداً محلّيّاً» فلم تكن القائمةُ الأولى تغطّيها —
      // فمن يملك `settings_edit` (‏أو المستخدمُ رقم ١) كان **يستبدلها عن
      // بُعد** ويصير له تجاوزُ الصلاحيّات كلِّه. تصعيدُ امتيازٍ كامل عبر
      // نقطةِ حفظِ إعدادات.
      final blocked = <String>[];
      final allowed = <String, String>{};
      incoming.forEach((k, v) {
        if (isDeviceLocalSettingKey(k) || isServerSecretSettingKey(k)) {
          blocked.add(k);
        } else {
          allowed[k] = v;
        }
      });
      if (blocked.isNotEmpty) {
        unawaited(DiagnosticLogger.log(
          'API-SETTINGS',
          '⛔ رُفض ${blocked.length} مفتاحاً يخصُّ الجهاز: '
              '${blocked.join(", ")}',
        ));
      }

      await db.saveSettings(allowed);
      broadcast('settings');
      return jsonResponse({
        'success': true,
        'saved': allowed.length,
        if (blocked.isNotEmpty) 'blocked': blocked,
      });
    } catch (e) {
      debugPrint('[API] postSettings error: $e');
      return errorResponse('Failed to save settings: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // Categories
  // ═══════════════════════════════════════════════════════════════

  Future<Response> postCategory(Request request) async {
    try {
      // Spec 077 Batch 5 (Spec 060 Phase 2): per-user permission gate.
      final perm = await ApiUserCtx.requirePermission(
          request, db, PermissionCodes.categoriesAdd);
      if (perm != null) return perm;
      final data =
          json.decode(await request.readAsString()) as Map<String, dynamic>;
      final isGlobal = parseBool(data['isGlobal'], true);
      final clientGlobalId = (data['globalId'] as String?)?.trim();
      final name = data['name'] as String;

      // Issue 1 — dedup-by-globalId so a retried create from the client outbox
      // (or a duplicate POST from a different device that already received the
      // record via WebSocket pull) doesn't end up as a second row on the
      // server. The strategy already dedups by globalId on the read side; we
      // need the same guarantee on the write side because not all clients
      // pull before posting.
      if (clientGlobalId != null && clientGlobalId.isNotEmpty) {
        final existing = await (db.select(db.categories)
              ..where((c) => c.globalId.equals(clientGlobalId))
              ..limit(1))
            .getSingleOrNull();
        if (existing != null) {
          debugPrint('[API] postCategory dedup: globalId=$clientGlobalId '
              'already exists as id=${existing.id}; returning that id.');
          return jsonResponse({'success': true, 'id': existing.id, 'deduped': true});
        }
      }

      final id = await db.insertCategoryWithPrinter(
        name: name,
        color: data['color'] as String? ?? '#2563EB',
        printerId: parseIntNullable(data['printerId']),
        iconName: data['iconName'] as String?,
      );

      // Now update the global flag, branch links, and globalId stamp using
      // raw updates since insertCategoryWithPrinter doesn't expose them.
      await (db.update(db.categories)..where((c) => c.id.equals(id))).write(
        CategoriesCompanion(
          isGlobal: Value(isGlobal),
          isLocked: Value(parseBool(data['isLocked'], false)),
          isExcluded: Value(parseBool(data['isExcluded'], false)),
          showInPos: Value(parseBool(data['showInPos'], true)),
          globalId: (clientGlobalId != null && clientGlobalId.isNotEmpty)
              ? Value(clientGlobalId)
              : const Value.absent(),
        )
      );

      final branchIdsList = data['branchIds'] as List?;
      if (branchIdsList != null) {
        final intBranchIds = branchIdsList.map((e) => parseInt(e)).toList();
        await db.setCategoryBranches(id, intBranchIds);
      }

      broadcast('categories');
      return jsonResponse({'success': true, 'id': id});
    } catch (e) {
      debugPrint('[API] postCategory error: $e');
      return errorResponse('Failed to create category: $e');
    }
  }

  Future<Response> putCategory(Request request, String id) async {
    try {
      // Spec 077 Batch 5 (Spec 060 Phase 2): per-user permission gate.
      final perm = await ApiUserCtx.requirePermission(
          request, db, PermissionCodes.categoriesEdit);
      if (perm != null) return perm;
      final categoryId = int.parse(id);
      final data =
          json.decode(await request.readAsString()) as Map<String, dynamic>;
      
      final isGlobal = parseBool(data['isGlobal'], true);

      await db.updateCategoryWithPrinter(
        id: categoryId,
        name: data['name'] as String,
        color: data['color'] as String? ?? '#2563EB',
        printerId: parseIntNullable(data['printerId']),
        iconName: data['iconName'] as String?,
      );

      // Same as above, update extra flags
      await (db.update(db.categories)..where((c) => c.id.equals(categoryId))).write(
        CategoriesCompanion(
          isGlobal: Value(isGlobal),
          isLocked: Value(parseBool(data['isLocked'], false)),
          isExcluded: Value(parseBool(data['isExcluded'], false)),
          showInPos: Value(parseBool(data['showInPos'], true)),
        )
      );

      final branchIdsList = data['branchIds'] as List?;
      if (branchIdsList != null) {
        final intBranchIds = branchIdsList.map((e) => parseInt(e)).toList();
        await db.setCategoryBranches(categoryId, intBranchIds);
      }

      broadcast('categories');
      return jsonResponse({'success': true});
    } catch (e) {
      debugPrint('[API] putCategory error: $e');
      return errorResponse('Failed to update category: $e');
    }
  }

  Future<Response> deleteCategory(Request request, String id) async {
    try {
      // Spec 077 Batch 5 (Spec 060 Phase 2): per-user permission gate.
      final perm = await ApiUserCtx.requirePermission(
          request, db, PermissionCodes.categoriesDelete);
      if (perm != null) return perm;
      final catId = int.parse(id);
      // Feature 045 — accept `moveToCategoryId` from either the query
      // string (the way server_proxy.deleteCategory ships it) or the
      // request body (defensive — older replays might use either).
      // A literal NULL value means "leave products uncategorized";
      // `Products.categoryId` is nullable so that's a valid resting
      // state. The DAO runs the move + soft-delete atomically.
      int? moveToCategoryId;
      final qpRaw = request.requestedUri.queryParameters['moveToCategoryId'];
      if (qpRaw != null && qpRaw.isNotEmpty) {
        moveToCategoryId = int.tryParse(qpRaw);
      }
      if (moveToCategoryId == null) {
        try {
          final body = await request.readAsString();
          if (body.isNotEmpty) {
            final data = json.decode(body);
            if (data is Map && data['moveToCategoryId'] != null) {
              moveToCategoryId = parseIntNullable(data['moveToCategoryId']);
            }
          }
        } catch (_) {/* DELETE bodies are optional; silent ignore */}
      }

      await db.deleteCategory(catId, moveToCategoryId: moveToCategoryId);
      broadcast('categories');
      // Soft-delete still broadcasts a delete event to clients so any
      // open UI refresh. The local row is now `isActive=false` rather
      // than physically gone; sync strategies UPDATE it on pull.
      broadcastRecordDeleted('categories', catId);
      return jsonResponse({'success': true});
    } catch (e) {
      return errorResponse('Failed to delete category: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // Users (Admin CRUD)
  // ═══════════════════════════════════════════════════════════════

  Future<Response> postUser(Request request) async {
    try {
      // Spec 077 Batch 5 (Spec 060 Phase 2): per-user permission gate.
      final perm = await ApiUserCtx.requirePermission(
          request, db, PermissionCodes.usersManage);
      if (perm != null) return perm;
      final data =
          json.decode(await request.readAsString()) as Map<String, dynamic>;

      // UUID-First (Phase 1): idempotent lookup by globalId.
      final incomingGlobalId = data['globalId'] as String?;
      if (incomingGlobalId != null && incomingGlobalId.isNotEmpty) {
        final existing = await (db.select(db.users)
              ..where((u) => u.globalId.equals(incomingGlobalId))
              ..limit(1))
            .getSingleOrNull();
        if (existing != null) {
          return jsonResponse(
              {'success': true, 'id': existing.id, 'duplicate': true});
        }
      }

      final id = await db.createUser(
        username: data['username'] as String,
        password: data['password'] as String,
        displayName: data['displayName'] as String,
        roleId: parseIntNullable(data['roleId']),
        maxDiscountPercent: parseDoubleNullable(data['maxDiscountPercent']),
        discountLimitIsPercent: parseBool(data['discountLimitIsPercent'], true),
        cardCode: data['cardCode'] as String?,
        defaultScreen: data['defaultScreen'] as String?,
        forcePasswordChange: parseBool(data['forcePasswordChange'], false),
        globalId: incomingGlobalId,
      );
      
      final dynamic branchIdsList = data['branchIds'];
      if (branchIdsList is List && branchIdsList.isNotEmpty) {
        await db.setUserBranchAccess(id, branchIdsList.cast<int>());
        broadcast('user_branch_access'); // Notify clients to pull access table
      }

      final dynamic warehouseIdsList = data['warehouseIds'];
      if (warehouseIdsList is List && warehouseIdsList.isNotEmpty) {
        await db.setUserWarehouseAccess(id, warehouseIdsList.cast<int>());
        broadcast('user_warehouse_access'); // Notify clients to pull access table
      }

      broadcast('users');
      return jsonResponse({'success': true, 'id': id});
    } catch (e) {
      debugPrint('[API] postUser error: $e');
      return errorResponse('Failed to create user: $e');
    }
  }

  Future<Response> putUser(Request request, String id) async {
    try {
      // 060 (D1-001): per-user permission gate.
      final perm = await ApiUserCtx.requirePermission(
          request, db, PermissionCodes.usersManage);
      if (perm != null) return perm;

      final data =
          json.decode(await request.readAsString()) as Map<String, dynamic>;
      final userId = int.parse(id);

      // Spec 061 (D1-002): guard the bootstrap admin row from demotion /
      // deactivation / lock. Other fields (displayName, username, cardCode,
      // maxDiscount, branchIds, warehouseIds) stay editable.
      final existing = await (db.select(db.users)
            ..where((u) => u.id.equals(userId)))
          .getSingleOrNull();
      if (existing != null &&
          isBootstrapAdmin(userId, username: existing.username)) {
        final caller =
            request.headers['x-forwarded-for'] ?? request.headers['host'] ?? 'unknown';
        if (data.containsKey('roleId')) {
          final newRoleId = parseIntNullable(data['roleId']);
          if (newRoleId != null && newRoleId != existing.roleId) {
            unawaited(DiagnosticLogger.log('ADMIN-GUARD',
                'reason=role-change caller=$caller userId=$userId newRoleId=$newRoleId'));
            return errorResponse(bootstrapAdminRoleGuardMessage,
                statusCode: 403);
          }
        }
        if (data.containsKey('isActive') && parseBool(data['isActive']) == false) {
          unawaited(DiagnosticLogger.log('ADMIN-GUARD',
              'reason=disable caller=$caller userId=$userId'));
          return errorResponse(bootstrapAdminGuardMessage, statusCode: 403);
        }
        if (data.containsKey('isLocked') && parseBool(data['isLocked']) == true) {
          unawaited(DiagnosticLogger.log('ADMIN-GUARD',
              'reason=lock caller=$caller userId=$userId'));
          return errorResponse(bootstrapAdminGuardMessage, statusCode: 403);
        }
      }

      final companion = UsersCompanion(
        roleId: data.containsKey('roleId')
            ? Value(parseIntNullable(data['roleId']))
            : const Value.absent(),
        defaultScreen: data.containsKey('defaultScreen')
            ? Value(data['defaultScreen'] as String)
            : const Value.absent(),
        maxDiscountPercent: data.containsKey('maxDiscountPercent')
            ? Value(parseDoubleNullable(data['maxDiscountPercent']))
            : const Value.absent(),
        isActive: data.containsKey('isActive')
            ? Value(parseBool(data['isActive']))
            : const Value.absent(),
        isLocked: data.containsKey('isLocked')
            ? Value(parseBool(data['isLocked']))
            : const Value.absent(),
        displayName: data.containsKey('displayName')
            ? Value(data['displayName'] as String)
            : const Value.absent(),
        // Issue 7 (Feature 018): admins can rename a user (display_name +
        // username) and reassign their MSR card from the edit dialog.
        username: data.containsKey('username')
            ? Value(data['username'] as String)
            : const Value.absent(),
        cardCode: data.containsKey('cardCode')
            ? Value(data['cardCode'] as String?)
            : const Value.absent(),
      );
      await (db.update(db.users)..where((u) => u.id.equals(userId)))
          .write(companion);

      if (data.containsKey('branchIds')) {
        final dynamic branchIdsList = data['branchIds'];
        if (branchIdsList is List) {
          await db.setUserBranchAccess(userId, branchIdsList.cast<int>());
          broadcast('user_branch_access'); // Notify clients to pull access table
        }
      }

      if (data.containsKey('warehouseIds')) {
        final dynamic warehouseIdsList = data['warehouseIds'];
        if (warehouseIdsList is List) {
          await db.setUserWarehouseAccess(userId, warehouseIdsList.cast<int>());
          broadcast('user_warehouse_access'); // Notify clients to pull access table
        }
      }

      broadcast('users');
      return jsonResponse({'success': true});
    } catch (e) {
      debugPrint('[API] putUser error: $e');
      return errorResponse('Failed to update user: $e');
    }
  }

  /// DELETE /api/users/`<id>` — soft-delete a user account.
  ///
  /// We don't hard-delete because users are referenced from many places
  /// (invoices, journal entries, activity logs). A hard DELETE would
  /// cascade-delete those records or fail on FK constraints. Instead we
  /// mark the user as `isActive=false` and `isLocked=true`, which has the
  /// same end-user effect: they can't log in, they're hidden from pickers,
  /// and existing transactions still reference them by ID.
  ///
  /// The client should refresh its user list after this call to hide the
  /// deleted user from the management UI.
  Future<Response> deleteUser(Request request, String id) async {
    try {
      // 060 (D1-001): per-user permission gate.
      final perm = await ApiUserCtx.requirePermission(
          request, db, PermissionCodes.usersManage);
      if (perm != null) return perm;

      final userId = int.parse(id);
      // Protect the super admin from accidental deletion.
      final existing = await (db.select(db.users)
            ..where((u) => u.id.equals(userId)))
          .getSingleOrNull();
      if (existing == null) {
        return errorResponse('User not found', statusCode: 404);
      }
      // Spec 061 (D1-002): refuse to delete the bootstrap admin row. The
      // predicate covers BOTH id==1 AND username=='admin' so a renamed
      // username (or shifted id, if a future migration changed seeding)
      // can't bypass the protection.
      if (isBootstrapAdmin(userId, username: existing.username)) {
        final caller =
            request.headers['x-forwarded-for'] ?? request.headers['host'] ?? 'unknown';
        unawaited(DiagnosticLogger.log('ADMIN-GUARD',
            'reason=delete caller=$caller userId=$userId'));
        return errorResponse(bootstrapAdminGuardMessage, statusCode: 403);
      }
      await (db.update(db.users)..where((u) => u.id.equals(userId))).write(
        const UsersCompanion(
          isActive: Value(false),
          isLocked: Value(true),
        ),
      );
      broadcast('users');
      broadcastRecordDeleted('users', userId);
      return jsonResponse({'success': true, 'soft_deleted': userId});
    } catch (e) {
      debugPrint('[API] deleteUser error: $e');
      return errorResponse('Failed to delete user: $e');
    }
  }

  Future<Response> postUserPassword(Request request, String id) async {
    try {
      // Spec 077 Batch 5 (Spec 060 Phase 2): per-user permission gate.
      final perm = await ApiUserCtx.requirePermission(
          request, db, PermissionCodes.usersManage);
      if (perm != null) return perm;
      final data =
          json.decode(await request.readAsString()) as Map<String, dynamic>;
      await db.updateUserPassword(
        userId: int.parse(id),
        newPassword: data['password'] as String,
      );
      broadcast('users');
      return jsonResponse({'success': true});
    } catch (e) {
      debugPrint('[API] postUserPassword error: $e');
      return errorResponse('Failed to update password: $e');
    }
  }

  Future<Response> postUserPin(Request request, String id) async {
    try {
      // Spec 077 Batch 5 (Spec 060 Phase 2): per-user permission gate.
      final perm = await ApiUserCtx.requirePermission(
          request, db, PermissionCodes.usersManage);
      if (perm != null) return perm;
      final data =
          json.decode(await request.readAsString()) as Map<String, dynamic>;
      await db.updateUserPin(int.parse(id), data['pin'] as String?);
      broadcast('users');
      return jsonResponse({'success': true});
    } catch (e) {
      debugPrint('[API] postUserPin error: $e');
      return errorResponse('Failed to update PIN: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // Warehouses (Admin CRUD)
  // ═══════════════════════════════════════════════════════════════

  Future<Response> postWarehouse(Request request) async {
    try {
      // Spec 077 Batch 5 (Spec 060 Phase 2): per-user permission gate.
      final perm = await ApiUserCtx.requirePermission(
          request, db, PermissionCodes.warehousesManage);
      if (perm != null) return perm;
      final data =
          json.decode(await request.readAsString()) as Map<String, dynamic>;

      // UUID-First (Phase 1): idempotent lookup by globalId.
      final incomingGlobalId = data['globalId'] as String?;
      if (incomingGlobalId != null && incomingGlobalId.isNotEmpty) {
        final existing = await (db.select(db.warehouses)
              ..where((w) => w.globalId.equals(incomingGlobalId))
              ..limit(1))
            .getSingleOrNull();
        if (existing != null) {
          return jsonResponse(
              {'success': true, 'id': existing.id, 'duplicate': true});
        }
      }

      final id = await db
          .into(db.warehouses)
          .insert(
            WarehousesCompanion.insert(
              name: data['name'] as String,
              branchId: Value(parseIntNullable(data['branchId'])),
              costCenterId: Value(parseIntNullable(data['costCenterId'])),
              globalId: Value(incomingGlobalId),
            ),
          );
      broadcast('warehouses');
      return jsonResponse({'success': true, 'id': id});
    } catch (e) {
      debugPrint('[API] postWarehouse error: $e');
      return errorResponse('Failed to create warehouse: $e');
    }
  }

  Future<Response> putWarehouse(Request request, String id) async {
    try {
      // Spec 077 Batch 5 (Spec 060 Phase 2): per-user permission gate.
      final perm = await ApiUserCtx.requirePermission(
          request, db, PermissionCodes.warehousesManage);
      if (perm != null) return perm;
      final data =
          json.decode(await request.readAsString()) as Map<String, dynamic>;
      final warehouseId = int.parse(id);
      if (data['setDefault'] == true) {
        // Per-branch: only reset defaults within the same branch
        final wh = await (db.select(db.warehouses)..where((w) => w.id.equals(warehouseId))).getSingleOrNull();
        if (wh != null) {
          await (db.update(db.warehouses)..where((w) => w.branchId.equalsNullable(wh.branchId)))
              .write(const WarehousesCompanion(isDefault: Value(false)));
        }
        await (db.update(db.warehouses)
              ..where((w) => w.id.equals(warehouseId)))
            .write(const WarehousesCompanion(isDefault: Value(true)));
      } else if (data['unsetDefault'] == true) {
        await (db.update(db.warehouses)
              ..where((w) => w.id.equals(warehouseId)))
            .write(const WarehousesCompanion(isDefault: Value(false)));
      } else {
        await (db.update(db.warehouses)
              ..where((w) => w.id.equals(warehouseId)))
            .write(
          WarehousesCompanion(
            name: data.containsKey('name')
                ? Value(data['name'] as String)
                : const Value.absent(),
            branchId: data.containsKey('branchId')
                ? Value(parseIntNullable(data['branchId']))
                : const Value.absent(),
            costCenterId: data.containsKey('costCenterId')
                ? Value(parseIntNullable(data['costCenterId']))
                : const Value.absent(),
          ),
        );
      }
      broadcast('warehouses');
      return jsonResponse({'success': true});
    } catch (e) {
      debugPrint('[API] putWarehouse error: $e');
      return errorResponse('Failed to update warehouse: $e');
    }
  }

  Future<Response> deleteWarehouse(Request request, String id) async {
    try {
      // Spec 077 Batch 5 (Spec 060 Phase 2): per-user permission gate.
      final perm = await ApiUserCtx.requirePermission(
          request, db, PermissionCodes.warehousesManage);
      if (perm != null) return perm;
      final whId = int.parse(id);
      await (db.delete(db.warehouses)..where((w) => w.id.equals(whId))).go();
      broadcast('warehouses');
      broadcastRecordDeleted('warehouses', whId);
      return jsonResponse({'success': true});
    } catch (e) {
      return errorResponse('Failed to delete warehouse: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // Cost Centers (Admin CRUD) — Feature 006 / MM.C
  // ═══════════════════════════════════════════════════════════════

  Future<Response> postCostCenter(Request request) async {
    try {
      // Spec 077 Batch 5 (Spec 060 Phase 2): per-user permission gate.
      final perm = await ApiUserCtx.requirePermission(
          request, db, PermissionCodes.accountingManage);
      if (perm != null) return perm;
      final data =
          json.decode(await request.readAsString()) as Map<String, dynamic>;

      final incomingGlobalId = data['globalId'] as String?;
      if (incomingGlobalId != null && incomingGlobalId.isNotEmpty) {
        final existing = await (db.select(db.costCenters)
              ..where((c) => c.globalId.equals(incomingGlobalId))
              ..limit(1))
            .getSingleOrNull();
        if (existing != null) {
          return jsonResponse(
              {'success': true, 'id': existing.id, 'duplicate': true});
        }
      }

      final id = await db.createCostCenter(
        code: data['code'] as String,
        name: data['name'] as String,
        parentId: parseIntNullable(data['parentId']),
      );
      if (incomingGlobalId != null && incomingGlobalId.isNotEmpty) {
        await (db.update(db.costCenters)..where((c) => c.id.equals(id)))
            .write(CostCentersCompanion(globalId: Value(incomingGlobalId)));
      }
      broadcast('cost_centers');
      return jsonResponse({'success': true, 'id': id});
    } catch (e) {
      debugPrint('[API] postCostCenter error: $e');
      return errorResponse('Failed to create cost center: $e');
    }
  }

  Future<Response> putCostCenter(Request request, String id) async {
    try {
      // Spec 077 Batch 5 (Spec 060 Phase 2): per-user permission gate.
      final perm = await ApiUserCtx.requirePermission(
          request, db, PermissionCodes.accountingManage);
      if (perm != null) return perm;
      final data =
          json.decode(await request.readAsString()) as Map<String, dynamic>;
      final ccId = int.parse(id);
      await db.updateCostCenter(
        ccId,
        code: data.containsKey('code') ? data['code'] as String? : null,
        name: data.containsKey('name') ? data['name'] as String? : null,
        parentId: data.containsKey('parentId')
            ? parseIntNullable(data['parentId'])
            : null,
        isActive: data.containsKey('isActive')
            ? parseBool(data['isActive'], true)
            : null,
      );
      broadcast('cost_centers');
      return jsonResponse({'success': true});
    } catch (e) {
      debugPrint('[API] putCostCenter error: $e');
      return errorResponse('Failed to update cost center: $e');
    }
  }

  Future<Response> deleteCostCenter(Request request, String id) async {
    try {
      // Spec 077 Batch 5 (Spec 060 Phase 2): per-user permission gate.
      final perm = await ApiUserCtx.requirePermission(
          request, db, PermissionCodes.accountingManage);
      if (perm != null) return perm;
      final ccId = int.parse(id);
      await db.deactivateCostCenter(ccId);
      broadcast('cost_centers');
      broadcastRecordDeleted('cost_centers', ccId);
      return jsonResponse({'success': true});
    } catch (e) {
      return errorResponse('Failed to delete cost center: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // Accounts (CoA Admin CRUD) — Feature 006 / MM.C
  //
  // Lets a mirror admin add / rename / soft-delete chart-of-accounts
  // rows from a remote laptop. Uses the same DAO methods the server's
  // own UI uses (createAccount / updateAccount / deleteAccount), so
  // the system-account / non-zero-balance guards fire identically.
  // ═══════════════════════════════════════════════════════════════

  Future<Response> postAccount(Request request) async {
    try {
      // Spec 077 Batch 5 (Spec 060 Phase 2): per-user permission gate.
      final perm = await ApiUserCtx.requirePermission(
          request, db, PermissionCodes.accountingManage);
      if (perm != null) return perm;
      final data =
          json.decode(await request.readAsString()) as Map<String, dynamic>;

      final incomingGlobalId = data['globalId'] as String?;
      if (incomingGlobalId != null && incomingGlobalId.isNotEmpty) {
        final existing = await (db.select(db.accounts)
              ..where((a) => a.globalId.equals(incomingGlobalId))
              ..limit(1))
            .getSingleOrNull();
        if (existing != null) {
          return jsonResponse(
              {'success': true, 'id': existing.id, 'duplicate': true});
        }
      }

      final id = await db.createAccount(
        code: data['code'] as String,
        name: data['name'] as String,
        accountType: data['accountType'] as String,
        parentId: parseIntNullable(data['parentId']),
      );
      // Stamp caller-provided globalId so the next DeltaPull on the
      // mirror device re-attaches its local cache to this exact row.
      if (incomingGlobalId != null && incomingGlobalId.isNotEmpty) {
        await (db.update(db.accounts)..where((a) => a.id.equals(id)))
            .write(AccountsCompanion(globalId: Value(incomingGlobalId)));
      }
      broadcast('accounts');
      return jsonResponse({'success': true, 'id': id});
    } catch (e) {
      debugPrint('[API] postAccount error: $e');
      return errorResponse('Failed to create account: $e');
    }
  }

  Future<Response> putAccount(Request request, String id) async {
    try {
      // Spec 077 Batch 5 (Spec 060 Phase 2): per-user permission gate.
      final perm = await ApiUserCtx.requirePermission(
          request, db, PermissionCodes.accountingManage);
      if (perm != null) return perm;
      final data =
          json.decode(await request.readAsString()) as Map<String, dynamic>;
      final accountId = int.parse(id);
      await db.updateAccount(
        accountId,
        name: data.containsKey('name') ? data['name'] as String? : null,
        code: data.containsKey('code') ? data['code'] as String? : null,
        isActive: data.containsKey('isActive')
            ? parseBool(data['isActive'], true)
            : null,
        isHiddenFromEntries: data.containsKey('isHiddenFromEntries')
            ? parseBool(data['isHiddenFromEntries'], false)
            : null,
      );
      broadcast('accounts');
      return jsonResponse({'success': true});
    } catch (e) {
      debugPrint('[API] putAccount error: $e');
      return errorResponse('Failed to update account: $e');
    }
  }

  Future<Response> deleteAccount(Request request, String id) async {
    try {
      // Spec 077 Batch 5 (Spec 060 Phase 2): per-user permission gate.
      final perm = await ApiUserCtx.requirePermission(
          request, db, PermissionCodes.accountingManage);
      if (perm != null) return perm;
      final accountId = int.parse(id);
      await db.deleteAccount(accountId);
      broadcast('accounts');
      broadcastRecordDeleted('accounts', accountId);
      return jsonResponse({'success': true});
    } catch (e) {
      return errorResponse('Failed to delete account: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // Account Mappings (purpose → account) — Feature 006 / MM.C
  //
  // setAccountMapping is upsert semantics (the DAO does delete+insert
  // inside one transaction, keyed on purpose+costCenterId). DELETE
  // accepts an optional ?cost_center_id query param so the mirror admin
  // can clear a global default OR a per-cost-center override.
  // ═══════════════════════════════════════════════════════════════

  Future<Response> postAccountMapping(Request request) async {
    try {
      // Spec 077 Batch 5 (Spec 060 Phase 2): per-user permission gate.
      final perm = await ApiUserCtx.requirePermission(
          request, db, PermissionCodes.accountingManage);
      if (perm != null) return perm;
      final data =
          json.decode(await request.readAsString()) as Map<String, dynamic>;
      final purpose = data['purpose'] as String?;
      final accountId = parseIntNullable(data['accountId']);
      if (purpose == null || purpose.isEmpty || accountId == null) {
        return errorResponse('purpose + accountId required', statusCode: 400);
      }
      await db.setAccountMapping(
        purpose,
        accountId,
        costCenterId: parseIntNullable(data['costCenterId']),
      );
      broadcast('account_mappings');
      return jsonResponse({'success': true});
    } catch (e) {
      debugPrint('[API] postAccountMapping error: $e');
      return errorResponse('Failed to set account mapping: $e');
    }
  }

  Future<Response> deleteAccountMapping(Request request) async {
    try {
      // Spec 077 Batch 5 (Spec 060 Phase 2): per-user permission gate.
      final perm = await ApiUserCtx.requirePermission(
          request, db, PermissionCodes.accountingManage);
      if (perm != null) return perm;
      final purpose = request.url.queryParameters['purpose'];
      if (purpose == null || purpose.isEmpty) {
        return errorResponse('purpose query param required', statusCode: 400);
      }
      final ccRaw = request.url.queryParameters['cost_center_id'];
      final costCenterId = ccRaw != null && ccRaw.isNotEmpty
          ? int.tryParse(ccRaw)
          : null;
      if (costCenterId != null) {
        await (db.delete(db.accountMappings)
              ..where((m) =>
                  m.purpose.equals(purpose) &
                  m.costCenterId.equals(costCenterId)))
            .go();
      } else {
        await (db.delete(db.accountMappings)
              ..where(
                  (m) => m.purpose.equals(purpose) & m.costCenterId.isNull()))
            .go();
      }
      broadcast('account_mappings');
      return jsonResponse({'success': true});
    } catch (e) {
      return errorResponse('Failed to delete account mapping: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // Safes (Admin CRUD) — Feature 006 / MM.C
  //
  // Creation goes through createSafeWithLinkedAccount so the safe is
  // atomically paired with a CoA sub-account (Feature 004 / FR-006).
  // The dedicated postCloseSafe / postSafeTransaction / postSafeTransfer
  // / postSetDefaultSafe endpoints are unchanged — those handle
  // operational moves; this group handles structural CRUD.
  // ═══════════════════════════════════════════════════════════════

  Future<Response> postSafe(Request request) async {
    try {
      // Spec 077 Batch 5 (Spec 060 Phase 2): per-user permission gate.
      final perm = await ApiUserCtx.requirePermission(
          request, db, PermissionCodes.treasuryManage);
      if (perm != null) return perm;
      final data =
          json.decode(await request.readAsString()) as Map<String, dynamic>;

      final incomingGlobalId = data['globalId'] as String?;
      if (incomingGlobalId != null && incomingGlobalId.isNotEmpty) {
        final existing = await (db.select(db.safes)
              ..where((s) => s.globalId.equals(incomingGlobalId))
              ..limit(1))
            .getSingleOrNull();
        if (existing != null) {
          return jsonResponse(
              {'success': true, 'id': existing.id, 'duplicate': true});
        }
      }

      final id = await db.createSafeWithLinkedAccount(
        name: data['name'] as String,
        safeType: (data['safeType'] as String?) ?? 'cash',
        bankName: data['bankName'] as String?,
        accountNumber: data['accountNumber'] as String?,
        costCenterId: parseIntNullable(data['costCenterId']),
        branchId: parseIntNullable(data['branchId']),
      );

      // Stamp the caller-provided globalId so the next DeltaPull on the
      // mirror device re-attaches its local cache to this exact row.
      if (incomingGlobalId != null && incomingGlobalId.isNotEmpty) {
        await (db.update(db.safes)..where((s) => s.id.equals(id)))
            .write(SafesCompanion(globalId: Value(incomingGlobalId)));
      }
      broadcast('safes');
      broadcast('accounts'); // linked CoA sub-account also created
      return jsonResponse({'success': true, 'id': id});
    } catch (e) {
      debugPrint('[API] postSafe error: $e');
      return errorResponse('Failed to create safe: $e');
    }
  }

  Future<Response> putSafe(Request request, String id) async {
    try {
      // Spec 077 Batch 5 (Spec 060 Phase 2): per-user permission gate.
      final perm = await ApiUserCtx.requirePermission(
          request, db, PermissionCodes.treasuryManage);
      if (perm != null) return perm;
      final data =
          json.decode(await request.readAsString()) as Map<String, dynamic>;
      final safeId = int.parse(id);
      // Mirror the rename to the linked CoA account in a single
      // transaction so a reader never sees a half-renamed pair.
      await db.transaction(() async {
        final existing = await (db.select(db.safes)
              ..where((s) => s.id.equals(safeId))
              ..limit(1))
            .getSingleOrNull();
        await (db.update(db.safes)..where((s) => s.id.equals(safeId)))
            .write(
          SafesCompanion(
            name: data.containsKey('name')
                ? Value(data['name'] as String)
                : const Value.absent(),
            bankName: data.containsKey('bankName')
                ? Value(data['bankName'] as String?)
                : const Value.absent(),
            accountNumber: data.containsKey('accountNumber')
                ? Value(data['accountNumber'] as String?)
                : const Value.absent(),
            costCenterId: data.containsKey('costCenterId')
                ? Value(parseIntNullable(data['costCenterId']))
                : const Value.absent(),
            branchId: data.containsKey('branchId')
                ? Value(parseIntNullable(data['branchId']))
                : const Value.absent(),
            isActive: data.containsKey('isActive')
                ? Value(parseBool(data['isActive'], true))
                : const Value.absent(),
          ),
        );
        if (existing != null &&
            existing.linkedAccountId != null &&
            data.containsKey('name') &&
            (data['name'] as String) != existing.name) {
          await (db.update(db.accounts)
                ..where((a) => a.id.equals(existing.linkedAccountId!)))
              .write(AccountsCompanion(name: Value(data['name'] as String)));
        }
      });
      broadcast('safes');
      broadcast('accounts');
      return jsonResponse({'success': true});
    } catch (e) {
      debugPrint('[API] putSafe error: $e');
      return errorResponse('Failed to update safe: $e');
    }
  }

  Future<Response> deleteSafe(Request request, String id) async {
    try {
      // Spec 077 Batch 5 (Spec 060 Phase 2): per-user permission gate.
      final perm = await ApiUserCtx.requirePermission(
          request, db, PermissionCodes.treasuryManage);
      if (perm != null) return perm;
      final safeId = int.parse(id);
      await db.deleteSafeById(safeId);
      broadcast('safes');
      broadcastRecordDeleted('safes', safeId);
      return jsonResponse({'success': true});
    } catch (e) {
      return errorResponse('Failed to delete safe: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // Branches (Admin CRUD) — Feature 006 / MM.C
  //
  // Mirror-mode admin can create / rename / soft-deactivate branches
  // from a remote laptop. Endpoints stay UUID-First (idempotent on
  // globalId) so a retry after a network blip cannot duplicate a branch
  // on HQ.
  // ═══════════════════════════════════════════════════════════════

  Future<Response> postBranch(Request request) async {
    try {
      // Spec 077 Batch 5 (Spec 060 Phase 2): per-user permission gate.
      final perm = await ApiUserCtx.requirePermission(
          request, db, PermissionCodes.branchesManage);
      if (perm != null) return perm;
      return await ApiHandlerBase.withBroadcast<Response>(
        endpointLabel: 'postBranch',
        tables: const {'branches'},
        body: () async {
      final data =
          json.decode(await request.readAsString()) as Map<String, dynamic>;

      // Tier 1 — globalId dedup (UUID-First contract). The historical
      // dedup path: a retried POST with the same globalId returns the
      // existing row instead of creating a duplicate.
      final incomingGlobalId = data['globalId'] as String?;
      if (incomingGlobalId != null && incomingGlobalId.isNotEmpty) {
        final existing = await (db.select(db.branches)
              ..where((b) => b.globalId.equals(incomingGlobalId))
              ..limit(1))
            .getSingleOrNull();
        if (existing != null) {
          return jsonResponse(
              {'success': true, 'id': existing.id, 'duplicate': true});
        }
      }

      // Feature 011 / Issue 7+8 — name+isActive dedup.
      // Diagnostic logs from a beta restaurant showed 9 rows on the server
      // all named "الفرع الرئيسي", all with globalId=null. Root cause:
      // the legacy path skipped the globalId-dedup branch above when the
      // caller didn't supply a globalId, then inserted blindly with no
      // name check. Every client/mirror that POSTed a branch without a
      // globalId — e.g. a client first-sync echo, a default-branch
      // placeholder write — created a NEW row.
      //
      // Fix: when no incoming globalId, check by (name, is_active=true)
      // before inserting. If an active row with the same name exists,
      // return it AND backfill the globalId on the matched row so future
      // syncs hit the Tier 1 path instead of falling here repeatedly.
      final name = data['name'] as String?;
      if (name == null || name.trim().isEmpty) {
        return errorResponse('Branch name is required');
      }
      final trimmedName = name.trim();

      // Spec 136 ISS-1 — name-collision dedup. This runs whenever the Tier-1
      // globalId lookup above did NOT return early: either no gid was sent, OR
      // a gid was sent but matched no server row. Pre-fix this check was gated
      // on `incomingGlobalId == null`, so a client posting an EXISTING branch
      // name with its OWN divergent (non-null) gid skipped the check entirely
      // and fell through to the blind insert below — creating a DUPLICATE
      // "الفرع الرئيسي" row. That is the field ISS-1 root cause (the server
      // accumulating multiple main branches, then sync skipping the duplicate
      // to stay stable). Now any active row with the same name short-circuits
      // the insert regardless of the incoming gid.
      final byName = await (db.select(db.branches)
            ..where((b) =>
                b.name.equals(trimmedName) & b.isActive.equals(true))
            ..orderBy([(b) => OrderingTerm.asc(b.id)])
            ..limit(1))
          .getSingleOrNull();
      if (byName != null) {
        // Converge the matched row's gid ONLY when it is currently NULL
        // (Spec 132 FR-011 — never overwrite an existing gid; a divergent
        // non-null gid converges via the sync push-down, not here). Prefer
        // the client's incoming gid so that client's future syncs hit Tier-1;
        // otherwise mint one so the row stops falling here on every POST.
        if (byName.globalId == null || byName.globalId!.isEmpty) {
          final backfillGid =
              (incomingGlobalId != null && incomingGlobalId.isNotEmpty)
                  ? incomingGlobalId
                  : UuidV7.generate();
          await (db.update(db.branches)..where((b) => b.id.equals(byName.id)))
              .write(BranchesCompanion(globalId: Value(backfillGid)));
          debugPrint('[API] postBranch: name dedup + globalId backfill — '
              'name="$trimmedName" id=${byName.id} gid=$backfillGid '
              'incoming=$incomingGlobalId');
        } else {
          debugPrint('[API] postBranch: name dedup (no overwrite) — '
              'name="$trimmedName" id=${byName.id} '
              'existingGlobalId=${byName.globalId} incoming=$incomingGlobalId');
        }
        return jsonResponse(
            {'success': true, 'id': byName.id, 'duplicate': true});
      }

      // No dedup hit — create a new branch. Always mint a globalId
      // server-side if the caller didn't send one, so the row never lands
      // with null globalId (the pre-fix state that caused the duplicate
      // pile-up — null globalIds are not unique against each other in
      // SQLite/PG, so the unique constraint allowed unlimited NULL rows).
      final globalIdToPersist =
          (incomingGlobalId != null && incomingGlobalId.isNotEmpty)
              ? incomingGlobalId
              : UuidV7.generate();

      final id = await db.into(db.branches).insert(
            BranchesCompanion.insert(
              name: trimmedName,
              code: Value(data['code'] as String?),
              address: Value(data['address'] as String?),
              phone: Value(data['phone'] as String?),
              costCenterId: Value(parseIntNullable(data['costCenterId'])),
              regionId: Value(parseIntNullable(data['regionId'])),
              globalId: Value(globalIdToPersist),
            ),
          );
      return jsonResponse(
          {'success': true, 'id': id, 'globalId': globalIdToPersist});
        },
      );
    } catch (e) {
      debugPrint('[API] postBranch error: $e');
      return errorResponse('Failed to create branch: $e');
    }
  }

  Future<Response> putBranch(Request request, String id) async {
    try {
      // Spec 077 Batch 5 (Spec 060 Phase 2): per-user permission gate.
      final perm = await ApiUserCtx.requirePermission(
          request, db, PermissionCodes.branchesManage);
      if (perm != null) return perm;
      final data =
          json.decode(await request.readAsString()) as Map<String, dynamic>;
      final branchId = int.parse(id);
      await (db.update(db.branches)..where((b) => b.id.equals(branchId)))
          .write(
        BranchesCompanion(
          name: data.containsKey('name')
              ? Value(data['name'] as String)
              : const Value.absent(),
          code: data.containsKey('code')
              ? Value(data['code'] as String?)
              : const Value.absent(),
          address: data.containsKey('address')
              ? Value(data['address'] as String?)
              : const Value.absent(),
          phone: data.containsKey('phone')
              ? Value(data['phone'] as String?)
              : const Value.absent(),
          costCenterId: data.containsKey('costCenterId')
              ? Value(parseIntNullable(data['costCenterId']))
              : const Value.absent(),
          regionId: data.containsKey('regionId')
              ? Value(parseIntNullable(data['regionId']))
              : const Value.absent(),
          isActive: data.containsKey('isActive')
              ? Value(parseBool(data['isActive'], true))
              : const Value.absent(),
        ),
      );
      broadcast('branches');
      return jsonResponse({'success': true});
    } catch (e) {
      debugPrint('[API] putBranch error: $e');
      return errorResponse('Failed to update branch: $e');
    }
  }

  Future<Response> deleteBranch(Request request, String id) async {
    try {
      // Spec 077 Batch 5 (Spec 060 Phase 2): per-user permission gate.
      final perm = await ApiUserCtx.requirePermission(
          request, db, PermissionCodes.branchesManage);
      if (perm != null) return perm;
      final branchId = int.parse(id);

      // Feature 049 (v131) — accept `reassignUsersToBranchId` from the
      // query string (server_proxy ships it that way) or the body.
      // Routes through the new DAO `deleteBranch` which soft-deletes +
      // reassigns user_branch_access rows inside a single transaction.
      // Without this v131 wiring, the mirror's dedup-duplicate-branch
      // workflow throws the same FK violation 23503 the server's own
      // admin hit on 2026-05-13.
      int? reassignTo;
      final qpRaw =
          request.requestedUri.queryParameters['reassignUsersToBranchId'];
      if (qpRaw != null && qpRaw.isNotEmpty) {
        reassignTo = int.tryParse(qpRaw);
      }
      if (reassignTo == null) {
        try {
          final body = await request.readAsString();
          if (body.isNotEmpty) {
            final data = json.decode(body);
            if (data is Map && data['reassignUsersToBranchId'] != null) {
              reassignTo =
                  parseIntNullable(data['reassignUsersToBranchId']);
            }
          }
        } catch (_) {/* DELETE bodies optional; silent ignore */}
      }

      await db.deleteBranch(branchId, reassignUsersToBranchId: reassignTo);
      broadcast('branches');
      broadcastRecordDeleted('branches', branchId);
      return jsonResponse({'success': true});
    } catch (e) {
      return errorResponse('Failed to delete branch: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // Commercial Papers
  // ═══════════════════════════════════════════════════════════════

  Future<Response> postCommercialPaper(Request request) async {
    try {
      // Spec 077 Batch 5 (Spec 060 Phase 2): per-user permission gate.
      final perm = await ApiUserCtx.requirePermission(
          request, db, PermissionCodes.commercialPapersManage);
      if (perm != null) return perm;
      final data =
          json.decode(await request.readAsString()) as Map<String, dynamic>;
      // Cluster 030 / Bug D: honour the client's locally-minted globalId
      // so mirror + server share identity. If absent, fall back to the
      // DAO's auto-mint (legacy clients pre-Cluster 030). On a globalId
      // collision (retry from a queued mirror outbox), short-circuit and
      // return the existing serverId so the operator's downstream
      // status updates resolve correctly.
      final incomingGlobalId =
          (data['globalId'] as String?)?.trim().isEmpty ?? true
              ? null
              : (data['globalId'] as String).trim();
      if (incomingGlobalId != null) {
        final existing = await (db.select(db.commercialPapers)
              ..where((p) => p.globalId.equals(incomingGlobalId))
              ..limit(1))
            .getSingleOrNull();
        if (existing != null) {
          debugPrint('[API] postCommercialPaper: globalId '
              '"$incomingGlobalId" already exists → idempotent return '
              '(serverId=${existing.id})');
          return jsonResponse({
            'success': true,
            'serverId': existing.id,
            'duplicate': true,
          });
        }
      }
      // Feature 044 — remap the client's local `partyId` via globalId.
      // Field log:
      //   commercial_papers_party_id_fkey: Key (party_id)=(1000000006) is
      //   not present in table "parties"
      // `resolvePartyId` covers: existing-globalId match → use that id,
      // existing-local-id match → use it, globalId+name supplied →
      // auto-create placeholder party so the FK lands cleanly. The
      // commercial-paper insert requires a non-null party so we throw
      // on a fully unresolvable input instead of letting the DAO crash
      // with a less informative FK error.
      final cpClientPartyId = parseIntNullable(data['partyId']);
      final cpPartyGid = (data['partyGlobalId'] as String?)?.trim();
      final cpPartyName = (data['partyName'] as String?)?.trim();
      final resolvedCpPartyId = await resolvePartyId(
        clientPartyId: cpClientPartyId,
        partyGlobalId: cpPartyGid == null || cpPartyGid.isEmpty ? null : cpPartyGid,
        fallbackName: cpPartyName == null || cpPartyName.isEmpty ? null : cpPartyName,
      );
      if (resolvedCpPartyId == null) {
        throw Exception('Validation Error: commercial_paper.partyId could '
            'not be resolved (clientPartyId=$cpClientPartyId, '
            'partyGlobalId="$cpPartyGid", partyName="$cpPartyName").');
      }

      final id = await db.createCommercialPaper(
        paperNumber: data['paperNumber'] as String,
        type: data['type'] as String,
        direction: data['direction'] as String,
        partyId: resolvedCpPartyId,
        amount: parseDouble(data['amount']),
        issueDate: DateTime.parse(data['issueDate'] as String),
        dueDate: DateTime.parse(data['dueDate'] as String),
        bankName: data['bankName'] as String?,
        safeId: parseIntNullable(data['safeId']),
        accountNumber: data['accountNumber'] as String?,
        notes: data['notes'] as String?,
        globalId: incomingGlobalId,
      );
      broadcast('commercial_papers');
      return jsonResponse({'success': true, 'serverId': id});
    } catch (e) {
      debugPrint('[API] postCommercialPaper error: $e');
      return errorResponse('Failed to create commercial paper: $e');
    }
  }

  Future<Response> putCommercialPaperStatus(
      Request request, String id) async {
    try {
      // Spec 077 Batch 5 (Spec 060 Phase 2): per-user permission gate.
      final perm = await ApiUserCtx.requirePermission(
          request, db, PermissionCodes.commercialPapersManage);
      if (perm != null) return perm;
      return await ApiHandlerBase.withBroadcast<Response>(
        endpointLabel: 'putCommercialPaperStatus',
        tables: const {
          'commercial_papers',
          'journal_entries', 'accounting',
          'safe_transactions',
        },
        body: () async {
      final data =
          json.decode(await request.readAsString()) as Map<String, dynamic>;
      // Feature 014 / Issue 3 — accept an optional `globalId` from the
      // body. Mirror/client devices send it because their LOCAL paper id
      // does NOT match the server's auto-increment; the server resolves
      // globalId → its own paperId here. The path `id` is treated as a
      // hint and is only used when no globalId is provided (single-tier
      // / standalone deployments unchanged).
      final incomingGlobalId = data['globalId'] as String?;
      var resolvedPaperId = int.parse(id);
      if (incomingGlobalId != null && incomingGlobalId.isNotEmpty) {
        final paper = await (db.select(db.commercialPapers)
              ..where((p) => p.globalId.equals(incomingGlobalId))
              ..limit(1))
            .getSingleOrNull();
        if (paper != null) {
          resolvedPaperId = paper.id;
        } else {
          debugPrint('[API] putCommercialPaperStatus: globalId '
              '"$incomingGlobalId" not found on server; falling back to '
              'path id $id (likely 404).');
        }
      }
      // Feature 042 (Bug 5) — remap the client's local user_id to the
      // server's. The client mirror previously sent its LOCAL `changedBy`
      // straight through (commonly id=1 for the cashier on the mirror's
      // SQLite), but the server's `users` table autoincrements
      // independently and admin can land on a different id (id=2 was the
      // field repro). `paper_status_history.changed_by` is FK to
      // `users(id)` with a NOT NULL constraint, so the insert raised
      // 23503 and every status change on the mirror failed with HTTP 500.
      // Mirrors the same `_resolveUserIdNullable(... fallbackUsername:
      // data['createdByUsername'])` pattern used at postExpense (l.185),
      // postSafeTransaction (l.1833), and postReceipt — username is the
      // cross-instance-stable identifier (admin == admin), local id
      // isn't.
      final resolvedChangedBy = await _resolveUserIdNullable(
        parseIntNullable(data['changedBy']),
        fallbackUsername: data['changedByUsername'] as String?,
      );

      // Feature 048 (v130) — resolve the user-chosen contra-leg account
      // by globalId first (cross-instance stable), falling back to the
      // raw integer id (works when client + server happen to share the
      // same accounts.id, e.g. a freshly-seeded standalone install).
      // Null = no override; DAO falls back to purposes-map defaults.
      //
      // Spec 082b — surface the remap (or the failure to remap) via
      // DiagnosticLogger. Without this, if the client's globalId
      // doesn't exist on the server (sync gap, account deleted on
      // server before client refreshed), the resolver silently keeps
      // the client's raw id, the DAO's `select where id=X` either
      // finds the WRONG account or null, and the JE lands on a
      // default — invisible to support. CP-AUTOPOST-GLOBALID-MISS
      // shows the failure trail.
      int? resolvedCounterAccountId = parseIntNullable(data['counterAccountId']);
      final counterAccountGlobalId =
          (data['counterAccountGlobalId'] as String?)?.trim();
      if (counterAccountGlobalId != null && counterAccountGlobalId.isNotEmpty) {
        final byGid = await (db.select(db.accounts)
              ..where((a) => a.globalId.equals(counterAccountGlobalId))
              ..limit(1))
            .getSingleOrNull();
        if (byGid != null) {
          if (resolvedCounterAccountId != null &&
              byGid.id != resolvedCounterAccountId) {
            await DiagnosticLogger.log(
              'CP-AUTOPOST-GLOBALID-REMAP',
              'counterAccountId remapped client=$resolvedCounterAccountId → '
                  'server=${byGid.id} via globalId=$counterAccountGlobalId',
            );
          }
          resolvedCounterAccountId = byGid.id;
        } else {
          await DiagnosticLogger.log(
            'CP-AUTOPOST-GLOBALID-MISS',
            'counterAccountGlobalId=$counterAccountGlobalId NOT FOUND on '
                'server (client sent rawId=$resolvedCounterAccountId). '
                'Falling back to rawId — if it does not exist on server '
                'either, JE will land on purposes-map default or be '
                'skipped (see subsequent CP-AUTOPOST-OVERRIDE-FALLBACK / '
                'CP-AUTOPOST-WARN lines).',
          );
        }
      }

      await db.changePaperStatus(
        paperId: resolvedPaperId,
        newStatus: data['status'] as String,
        changedBy: resolvedChangedBy ?? 0,
        notes: data['notes'] as String?,
        endorsedToPartyId: parseIntNullable(data['endorsedToPartyId']),
        counterAccountId: resolvedCounterAccountId,
      );
      return jsonResponse({'success': true});
        },
      );
    } catch (e) {
      debugPrint('[API] putCommercialPaperStatus error: $e');
      return errorResponse('Failed to update paper status: $e');
    }
  }

  Future<Response> postRenewPaper(Request request, String id) async {
    try {
      // Spec 077 Batch 5 (Spec 060 Phase 2): per-user permission gate.
      final perm = await ApiUserCtx.requirePermission(
          request, db, PermissionCodes.commercialPapersManage);
      if (perm != null) return perm;
      final data =
          json.decode(await request.readAsString()) as Map<String, dynamic>;
      await db.renewPaper(
        paperId: int.parse(id),
        newDueDate: DateTime.parse(data['newDueDate'] as String),
        changedBy: parseIntNullable(data['changedBy']) ?? 0,
        notes: data['notes'] as String?,
      );
      broadcast('commercial_papers');
      return jsonResponse({'success': true});
    } catch (e) {
      debugPrint('[API] postRenewPaper error: $e');
      return errorResponse('Failed to renew paper: $e');
    }
  }

  Future<Response> postPartialCollection(
      Request request, String id) async {
    try {
      // Spec 077 Batch 5 (Spec 060 Phase 2): per-user permission gate.
      final perm = await ApiUserCtx.requirePermission(
          request, db, PermissionCodes.commercialPapersManage);
      if (perm != null) return perm;
      return await ApiHandlerBase.withBroadcast<Response>(
        endpointLabel: 'postPartialCollection',
        tables: const {
          'commercial_papers', 'safe_transactions',
          'accounting', 'journal_entries',
        },
        body: () async {
          final data = json.decode(await request.readAsString())
              as Map<String, dynamic>;
          await db.partialCollection(
            paperId: int.parse(id),
            collectedAmount: parseDouble(data['amount']),
            changedBy: parseIntNullable(data['changedBy']) ?? 0,
            notes: data['notes'] as String?,
          );
          return jsonResponse({'success': true});
        },
      );
    } catch (e) {
      debugPrint('[API] postPartialCollection error: $e');
      return errorResponse('Failed to partially collect paper: $e');
    }
  }

  Future<Response> postDepositForCollection(
      Request request, String id) async {
    try {
      // Spec 077 Batch 5 (Spec 060 Phase 2): per-user permission gate.
      final perm = await ApiUserCtx.requirePermission(
          request, db, PermissionCodes.commercialPapersManage);
      if (perm != null) return perm;
      return await ApiHandlerBase.withBroadcast<Response>(
        endpointLabel: 'postDepositForCollection',
        tables: const {'commercial_papers', 'safe_transactions'},
        body: () async {
          final data = json.decode(await request.readAsString())
              as Map<String, dynamic>;
          await db.depositForCollection(
            paperId: int.parse(id),
            bankSafeId: parseInt(data['bankSafeId']),
            changedBy: parseIntNullable(data['changedBy']) ?? 0,
            notes: data['notes'] as String?,
          );
          return jsonResponse({'success': true});
        },
      );
    } catch (e) {
      debugPrint('[API] postDepositForCollection error: $e');
      return errorResponse('Failed to deposit paper for collection: $e');
    }
  }

  Future<Response> postReissuePaper(Request request, String id) async {
    try {
      // Spec 077 Batch 5 (Spec 060 Phase 2): per-user permission gate.
      final perm = await ApiUserCtx.requirePermission(
          request, db, PermissionCodes.commercialPapersManage);
      if (perm != null) return perm;
      return await ApiHandlerBase.withBroadcast<Response>(
        endpointLabel: 'postReissuePaper',
        tables: const {
          'commercial_papers', 'journal_entries', 'accounting',
        },
        body: () async {
          final data = json.decode(await request.readAsString())
              as Map<String, dynamic>;
          await db.reissueToParty(
            paperId: int.parse(id),
            newPartyId: parseInt(data['newPartyId']),
            changedBy: parseIntNullable(data['changedBy']) ?? 0,
            notes: data['notes'] as String?,
          );
          return jsonResponse({'success': true});
        },
      );
    } catch (e) {
      debugPrint('[API] postReissuePaper error: $e');
      return errorResponse('Failed to reissue paper: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // Journal Entries (Client → Server sync)
  // ═══════════════════════════════════════════════════════════════

  Future<Response> postJournalEntry(Request request) async {
    try {
      // 060 (D1-001): per-user permission gate. Manual journal entries
      // are the GL escape hatch — restricted to accounting-journal perm.
      final perm = await ApiUserCtx.requirePermission(
          request, db, PermissionCodes.accountingJournal);
      if (perm != null) return perm;

      // Feature 054 (v134): stale-cache invalidation. See
      // api_handler_base.dart::checkIdempotency.
      final idempotencyKey = request.headers['x-idempotency-key'] ?? request.headers['X-Idempotency-Key'];
      if (idempotencyKey != null) {
        final cached = await checkIdempotency(idempotencyKey,
            verifyExists: idempotencyVerifierFor('postJournalEntry'));
        if (cached != null) {
          await DiagnosticLogger.log('API-JE',
              '⚠ idempotency-hit: returning cached response key=$idempotencyKey '
              'cached_serverId=${cached['serverId']}');
          return jsonResponse(cached);
        }
      }

      final data =
          json.decode(await request.readAsString()) as Map<String, dynamic>;
      final description = (data['description'] ?? data['notes']) as String? ?? '';
      final dateStr = (data['date'] ?? data['entryDate'] ?? data['entry_date']) as String?;
      final date = dateStr != null ? DateTime.tryParse(dateStr) ?? DateTime.now() : DateTime.now();
      final costCenterId = parseIntNullable(data['costCenterId'] ?? data['cost_center_id']);
      final branchId = parseIntNullable(data['branchId'] ?? data['branch_id']);
      final referenceType = (data['referenceType'] ?? data['reference_type']) as String?;
      final referenceId = parseIntNullable(data['referenceId'] ?? data['reference_id']);
      final isAutoPosted = parseBool(data['isAutoPosted'] ?? data['is_auto_posted']) ?? true;
      // Spec 007 / FR-008: honour the client's locally-minted globalId so
      // both sides converge on the same UUID. Without this the server minted
      // a fresh UUID, DeltaPull then re-inserted the server's row as a
      // duplicate on the originating client/mirror. Empty/whitespace-only
      // strings are treated as absent (DAO will mint).
      final incomingGlobalId =
          (data['globalId'] as String?)?.trim().isEmpty ?? true
              ? null
              : (data['globalId'] as String).trim();
      // globalId-based idempotency: if a JE with this globalId already
      // exists (retry from a client outbox / mirror reconnect), return the
      // existing serverId instead of creating a duplicate. Mirrors the
      // postSafeTransaction pattern shipped in Phase 5B.4.
      if (incomingGlobalId != null) {
        final existing = await (db.select(db.journalEntries)
              ..where((j) => j.globalId.equals(incomingGlobalId))
              ..limit(1))
            .getSingleOrNull();
        if (existing != null) {
          final responseBody = {
            'success': true,
            'duplicate': true,
            'serverId': existing.id,
            'globalId': incomingGlobalId,
          };
          if (idempotencyKey != null) {
            await storeIdempotency(idempotencyKey, responseBody, actionType: 'postJournalEntry');
          }
          return jsonResponse(responseBody);
        }
      }

      final linesList = (data['lines'] as List? ?? []);
      final lines = linesList.map<JournalLine>((item) {
        final m = item as Map<String, dynamic>;
        return JournalLine(
          accountId: parseInt(m['accountId'] ?? m['account_id']),
          debit: parseDoubleNullable(m['debit']) ?? 0,
          credit: parseDoubleNullable(m['credit']) ?? 0,
          description: (m['description'] ?? m['notes']) as String?,
          costCenterId: parseIntNullable(m['costCenterId'] ?? m['cost_center_id']) ?? costCenterId,
        );
      }).toList();

      final entryId = await db.createJournalEntry(
        description: description,
        date: date,
        lines: lines,
        referenceType: referenceType,
        referenceId: referenceId,
        isAutoPosted: isAutoPosted,
        costCenterId: costCenterId,
        branchId: branchId,
        globalId: incomingGlobalId,
      );

      broadcast('journals');
      broadcast('accounting');
      db.markTablesUpdated({db.journalEntries, db.journalEntryLines});

      final responseBody = {
        'success': true,
        'serverId': entryId,
        'globalId': incomingGlobalId,
        'idempotencyKey': idempotencyKey,
      };
      if (idempotencyKey != null) {
        await storeIdempotency(idempotencyKey, responseBody, actionType: 'postJournalEntry');
      }
      return jsonResponse(responseBody);
    } catch (e) {
      debugPrint('[API] postJournalEntry error: $e');
      return errorResponse('Failed to create journal entry: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // Safe Transactions (Client → Server sync)
  // ═══════════════════════════════════════════════════════════════

  Future<Response> postSafeTransaction(Request request) async {
    try {
      // Spec 077 Batch 5 (Spec 060 Phase 2): per-user permission gate.
      final perm = await ApiUserCtx.requirePermission(
          request, db, PermissionCodes.treasuryManage);
      if (perm != null) return perm;
      return await ApiHandlerBase.withBroadcast<Response>(
        endpointLabel: 'postSafeTransaction',
        // No JE is posted by this endpoint today; accounting/journal_entries
        // are declared as the safe maximum in case a future wiring lands.
        tables: const {
          'safe_transactions', 'safes',
          'accounting', 'journal_entries',
        },
        body: () async {
      final data =
          json.decode(await request.readAsString()) as Map<String, dynamic>;

      // Phase 5B.4 (Issue 7) — globalId-based idempotency. Mirrors the
      // postReceipt pattern: a retry from the outbox with the same
      // globalId returns the existing serverId instead of inserting a
      // phantom duplicate. Also lets the JE on this side dedup against
      // the client's local JE via deterministic globalId derivation
      // when 5B.1 is wired through (currently this endpoint doesn't
      // post a JE, but its globalId still anchors the safe_transactions
      // identity for SafeTransactionSyncStrategy).
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

      // Phase 5B.4 (Issue 7) — resolve `safeId` via `safeGlobalId` when
      // the client supplied one. Same divergence problem as postReceipt:
      // each side seeds the chart of safes independently and keeps its
      // own autoincrement, so trusting the client's `safeId` blindly
      // posts the transaction (and any downstream JE) to the wrong
      // safe's linked GL account on the server. globalId is the only
      // stable identifier across both sides.
      int resolvedSafeId = parseInt(data['safeId'] ?? data['safe_id']);
      final clientSafeGlobalId = (data['safeGlobalId'] as String?)?.trim();
      if (clientSafeGlobalId != null && clientSafeGlobalId.isNotEmpty) {
        final byGlobal = await (db.select(db.safes)
              ..where((s) => s.globalId.equals(clientSafeGlobalId))
              ..limit(1))
            .getSingleOrNull();
        if (byGlobal != null) {
          if (byGlobal.id != resolvedSafeId) {
            debugPrint('[API] postSafeTransaction: remapped safeId '
                '$resolvedSafeId → ${byGlobal.id} via globalId');
          }
          resolvedSafeId = byGlobal.id;
        }
      }
      final transactionType = (data['transactionType'] ?? data['transaction_type']) as String; // receipt, payment
      final category = data['category'] as String? ?? 'general';
      final amount = parseDouble(data['amount']);
      final description = (data['description'] ?? data['notes']) as String?;
      final userId = await _resolveUserIdNullable(parseIntNullable(data['userId'] ?? data['user_id']),
          fallbackUsername: data['createdByUsername'] as String?);
      final referenceType = (data['referenceType'] ?? data['reference_type']) as String?;
      final referenceId = parseIntNullable(data['referenceId'] ?? data['reference_id']);
      final costCenterId = parseIntNullable(data['costCenterId'] ?? data['cost_center_id']);

      // Spec 087 (F2) — resolve partyId on the server side so the
      // safe-transaction row carries the right party link. Previously
      // this endpoint silently dropped partyId; vouchers replayed
      // through here (outbox retries, non-receipt-dialog code paths)
      // landed with partyId=null on the server and the voucher was
      // missing from the customer/supplier statement on every client
      // that later pulled the row. Mirrors the resolution pattern
      // already used in postReceipt (cl.338-348).
      final clientStPartyId = parseIntNullable(data['partyId'] ?? data['party_id']);
      final stPartyGid = (data['partyGlobalId'] as String?)?.trim();
      final stPartyName = (data['partyName'] as String?)?.trim();
      int? resolvedStPartyId;
      if (clientStPartyId != null && clientStPartyId > 0) {
        resolvedStPartyId = await resolvePartyId(
          clientPartyId: clientStPartyId,
          partyGlobalId: stPartyGid == null || stPartyGid.isEmpty ? null : stPartyGid,
          fallbackName: stPartyName == null || stPartyName.isEmpty ? null : stPartyName,
        );
      }

      // Get current safe balance
      final safe = await (db.select(db.safes)
            ..where((s) => s.id.equals(resolvedSafeId)))
          .getSingleOrNull();
      if (safe == null) {
        return errorResponse('Safe not found: $resolvedSafeId');
      }

      final balanceChange = transactionType == 'receipt' ? amount : -amount;

      // Feature 005 Phase 8 — atomic safe-balance update to prevent the
      // Lost-Update race when two clients post safe transactions to the
      // same safe concurrently. Pre-005 this read `safe.balance` outside
      // a transaction, computed `newBalance = safe.balance + change`, then
      // wrote the absolute value via `updateSafeBalance` — under PostgreSQL's
      // default Read-Committed isolation two concurrent requests both saw
      // the same starting balance and the second write silently clobbered
      // the first. Now both the insert and the increment run inside a
      // single transaction with SQL-level arithmetic (`balance = balance + ?`)
      // and the recorded `balanceAfter` is read AFTER the increment so it
      // reflects the actual post-state.
      // 066 (D5-001): generateInvoiceNumber moved inside the txn so the
      // RV/PV counter rolls back if the safe-update or insert fails.
      final newBalance = await db.transaction(() async {
        final voucherNumber = await db.generateInvoiceNumber(
          transactionType == 'receipt' ? 'RV' : 'PV',
        );
        await db.customStatement(
          'UPDATE safes SET balance = balance + ? WHERE id = ?',
          [balanceChange, resolvedSafeId],
        );
        final updated = await (db.select(db.safes)
              ..where((s) => s.id.equals(resolvedSafeId))
              ..limit(1))
            .getSingle();
        await db.into(db.safeTransactions).insert(
          SafeTransactionsCompanion.insert(
            voucherNumber: voucherNumber,
            safeId: resolvedSafeId,
            transactionType: transactionType,
            category: category,
            amount: amount,
            balanceAfter: updated.balance,
            description: Value(description),
            referenceType: Value(referenceType),
            referenceId: Value(referenceId),
            userId: Value(userId),
            // Phase 5B.4 — persist the cost center the dialog selected.
            costCenterId: Value(costCenterId),
            // Spec 087 (F2) — persist the resolved partyId so the
            // voucher appears in the right customer/supplier statement.
            partyId: Value(resolvedStPartyId),
            // Phase 5B.4 — share identity with the client row so
            // SafeTransactionSyncStrategy dedupes on the next pull.
            globalId: incomingGlobalId != null && incomingGlobalId.isNotEmpty
                ? Value(incomingGlobalId)
                : const Value.absent(),
          ),
        );
        return updated.balance;
      });

      return jsonResponse({'success': true});
        },
      );
    } catch (e) {
      debugPrint('[API] postSafeTransaction error: $e');
      return errorResponse('Failed to record safe transaction: $e');
    }
  }

  Future<Response> postSafeTransfer(Request request) async {
    try {
      // Spec 077 Batch 5 (Spec 060 Phase 2): per-user permission gate.
      final perm = await ApiUserCtx.requirePermission(
          request, db, PermissionCodes.treasuryTransfer);
      if (perm != null) return perm;
      return await ApiHandlerBase.withBroadcast<Response>(
        endpointLabel: 'postSafeTransfer',
        tables: const {
          'safe_transactions', 'safes',
          'accounting', 'journal_entries',
        },
        body: () async {
      final data =
          json.decode(await request.readAsString()) as Map<String, dynamic>;
      final fromSafeId = parseInt(data['fromSafeId']);
      final toSafeId = parseInt(data['toSafeId']);
      final amount = parseDouble(data['amount']);
      final userId = await _resolveUserIdNullable(parseIntNullable(data['userId']),
          fallbackUsername: data['createdByUsername'] as String?);
      final description = data['description'] as String? ?? 'تحويل بين صناديق';

      // ── dedup بالـglobalId قبل أي حركة ────────────────────────────────────
      // ده كان الـendpoint الوحيد في مجموعة الخزينة بلا أي فحص تكرار — على
      // عكس postSafeTransaction وpostExpense. فطلب اتنفّذ وضاع رده كان
      // بيتعاد من طابور العميل ويتنفّذ تاني: تحويل ١٠,٠٠٠ يبقى ٢٠,٠٠٠ و٤
      // سندات بدل ٢. والهيدر x-idempotency-key مش مقروء هنا فما كانش بيحمي.
      //
      // التحويل مالوش جدول رأس، بيتسجّل كسطرين في safe_transactions، فالختم
      // على سطر الصرف (الخزنة المصدر) وهو هدف الفحص.
      final incomingGlobalId = (data['globalId'] as String?)?.trim();
      if (incomingGlobalId != null && incomingGlobalId.isNotEmpty) {
        final existing = await (db.select(db.safeTransactions)
              ..where((t) => t.globalId.equals(incomingGlobalId))
              ..limit(1))
            .getSingleOrNull();
        if (existing != null) {
          debugPrint('[API] postSafeTransfer: duplicate globalId='
              '$incomingGlobalId — skipping (voucher=${existing.voucherNumber})');
          return jsonResponse({'success': true, 'dedup': true});
        }
      }

      // Validate both safes exist before opening the transaction.
      final fromSafe = await (db.select(db.safes)
            ..where((s) => s.id.equals(fromSafeId)))
          .getSingleOrNull();
      final toSafe = await (db.select(db.safes)
            ..where((s) => s.id.equals(toSafeId)))
          .getSingleOrNull();
      if (fromSafe == null || toSafe == null) {
        return errorResponse('One or both safes not found');
      }

      // Feature 005 Phase 8 — atomic transfer: both balance updates and
      // both safe_transactions inserts run inside a single transaction
      // using SQL-level arithmetic, preventing the Lost-Update race when
      // concurrent transfers touch the same source or destination safe.
      // balanceAfter on each row is read AFTER the corresponding UPDATE
      // so it reflects the actual post-state.
      // 066 (D5-001): generateInvoiceNumber moved inside the txn so PV/RV
      // counters roll back if either UPDATE or insert fails.
      await db.transaction(() async {
        final pvNumber = await db.generateInvoiceNumber('PV');
        final rvNumber = await db.generateInvoiceNumber('RV');
        await db.customStatement(
          'UPDATE safes SET balance = balance - ? WHERE id = ?',
          [amount, fromSafeId],
        );
        final fromUpdated = await (db.select(db.safes)
              ..where((s) => s.id.equals(fromSafeId))
              ..limit(1))
            .getSingle();
        await db.into(db.safeTransactions).insert(
          SafeTransactionsCompanion.insert(
            voucherNumber: pvNumber,
            safeId: fromSafeId,
            transactionType: 'payment',
            category: 'transfer',
            amount: amount,
            balanceAfter: fromUpdated.balance,
            description: Value('$description → ${toSafe.name}'),
            userId: Value(userId),
            // هدف الـdedup فوق — سطر الصرف هو هوية التحويل.
            globalId: Value(incomingGlobalId),
          ),
        );

        await db.customStatement(
          'UPDATE safes SET balance = balance + ? WHERE id = ?',
          [amount, toSafeId],
        );
        final toUpdated = await (db.select(db.safes)
              ..where((s) => s.id.equals(toSafeId))
              ..limit(1))
            .getSingle();
        await db.into(db.safeTransactions).insert(
          SafeTransactionsCompanion.insert(
            voucherNumber: rvNumber,
            safeId: toSafeId,
            transactionType: 'receipt',
            category: 'transfer',
            amount: amount,
            balanceAfter: toUpdated.balance,
            description: Value('$description ← ${fromSafe.name}'),
            userId: Value(userId),
          ),
        );
      });

      return jsonResponse({'success': true});
        },
      );
    } catch (e) {
      debugPrint('[API] postSafeTransfer error: $e');
      return errorResponse('Failed to transfer between safes: $e');
    }
  }

  Future<Response> postSetDefaultSafe(Request request) async {
    try {
      // Spec 077 Batch 5 (Spec 060 Phase 2): per-user permission gate.
      final perm = await ApiUserCtx.requirePermission(
          request, db, PermissionCodes.treasuryManage);
      if (perm != null) return perm;
      return await ApiHandlerBase.withBroadcast<Response>(
        endpointLabel: 'postSetDefaultSafe',
        tables: const {'safes'},
        body: () async {
          final data = json.decode(await request.readAsString())
              as Map<String, dynamic>;
          final safeId = parseInt(data['safeId']);
          // When setting a safe as default from branch, we only set it for
          // that branch. The db method handles per-branch scoping itself.
          await db.setDefaultSafe(safeId);
          return jsonResponse({'success': true});
        },
      );
    } catch (e) {
      debugPrint('[API] postSetDefaultSafe error: $e');
      return errorResponse('Failed to set default safe: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // Stock Transfers (Client → Server sync)
  // ═══════════════════════════════════════════════════════════════

  Future<Response> postStockTransfer(Request request) async {
    try {
      // Spec 077 Batch 5 (Spec 060 Phase 2): per-user permission gate.
      final perm = await ApiUserCtx.requirePermission(
          request, db, PermissionCodes.inventoryTransfer);
      if (perm != null) return perm;
      final data =
          json.decode(await request.readAsString()) as Map<String, dynamic>;
      final fromWarehouseId = await _resolveWarehouseId(parseInt(data['fromWarehouseId']));
      final toWarehouseId = await _resolveWarehouseId(parseInt(data['toWarehouseId']));
      final userId = await _resolveUserIdNullable(parseIntNullable(data['userId']),
          fallbackUsername: data['createdByUsername'] as String?);
      final notes = data['notes'] as String? ?? 'تحويل مخزني من عميل';
      // Spec 129 F4 — caller-minted globalId stamped on the inventory_bonds
      // row created below. Dedup against it before doing the stock moves so a
      // retried request can't double-deduct from the source warehouse.
      final incomingGlobalId = (data['globalId'] as String?)?.trim();
      if (incomingGlobalId != null && incomingGlobalId.isNotEmpty) {
        final existing = await (db.select(db.inventoryBonds)
              ..where((b) => b.globalId.equals(incomingGlobalId))
              ..limit(1))
            .getSingleOrNull();
        if (existing != null) {
          debugPrint('[API] postStockTransfer: duplicate globalId=$incomingGlobalId — skipping (serverBondId=${existing.id})');
          return jsonResponse({'success': true, 'dedup': true});
        }
      }

      // Record the transfer header row server-side so a globalId dedup target
      // exists symmetrically with the mirror's local DAO (Spec 129 F4).
      final transferBondId = await db.into(db.inventoryBonds).insert(
            InventoryBondsCompanion.insert(
              bondNumber: 'TRF-${DateTime.now().millisecondsSinceEpoch}',
              type: const Value('transfer'),
              warehouseId: fromWarehouseId,
              toWarehouseId: Value(toWarehouseId),
              notes: Value(notes),
              createdBy: Value(userId),
              bondDate: Value(DateTime.now()),
              globalId: Value(incomingGlobalId),
            ),
          );

      final itemsList = (data['items'] as List? ?? []);
      for (final item in itemsList) {
        final m = item as Map<String, dynamic>;
        final resolvedPid = await resolveProductId(
          clientProductId: parseIntNullable(m['productId']),
          productGlobalId: m['productGlobalId'] as String?,
          fallbackCode: m['productCode'] as String?,
          fallbackName: m['productName'] as String?,
        );
        if (resolvedPid == null) {
          throw Exception('Validation Error: stock transfer item missing productId/productGlobalId');
        }
        final productId = resolvedPid;
        final quantity = parseDouble(m['quantity']);

        // Deduct from source warehouse
        await db.adjustStock(
          productId: productId,
          warehouseId: fromWarehouseId,
          quantity: -quantity,
          type: 'transfer_out',
          referenceType: 'stock_transfer',
          referenceId: transferBondId,
          notes: '$notes → مخزن $toWarehouseId',
        );

        // Add to destination warehouse
        await db.adjustStock(
          productId: productId,
          warehouseId: toWarehouseId,
          quantity: quantity,
          type: 'transfer_in',
          referenceType: 'stock_transfer',
          referenceId: transferBondId,
          notes: '$notes ← مخزن $fromWarehouseId',
        );
      }

      broadcast('products');
      broadcast('inventory');
      return jsonResponse({'success': true});
    } catch (e) {
      debugPrint('[API] postStockTransfer error: $e');
      return errorResponse('Failed to process stock transfer: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // Inventory Bonds — Spec 109
  // ═══════════════════════════════════════════════════════════════
  //
  // Server-side handler for inventory_bond inserts originating on client/
  // mirror. Mirrors the local-only `InventoryService.createAddingBond`
  // flow so the server stays the source of truth (Constitution R3):
  //   1. Insert bond header
  //   2. For each item: insert bond_item + adjustStock (creates a
  //      stock_movement row) + recompute weighted-average cost
  //   3. Post the inventory JE (Dr inventory / Cr capital|surplus|shrinkage)
  //
  // The whole flow runs inside a single transaction so a failed item
  // never leaves a half-applied bond.

  Future<Response> postInventoryBond(Request request) async {
    try {
      // Permission gate: bond creation is an inventory edit.
      final perm = await ApiUserCtx.requirePermission(
          request, db, PermissionCodes.inventoryEdit);
      if (perm != null) return perm;

      final data =
          json.decode(await request.readAsString()) as Map<String, dynamic>;

      final type = (data['type'] as String?) ?? 'in';
      final warehouseId =
          await _resolveWarehouseId(parseInt(data['warehouseId']));
      final notes = data['notes'] as String?;
      final userId = await _resolveUserIdNullable(
          parseIntNullable(data['userId']),
          fallbackUsername: data['createdByUsername'] as String?);
      final dateStr = data['date'] as String?;
      final bondDate =
          dateStr != null ? DateTime.tryParse(dateStr) : DateTime.now();
      final itemsList = (data['items'] as List? ?? []);
      // Spec 129 F4 — caller-minted globalId. If present, dedup against
      // any existing inventory_bonds row before re-running the whole flow.
      final incomingGlobalId = (data['globalId'] as String?)?.trim();

      if (itemsList.isEmpty) {
        return errorResponse('Validation Error: bond items list is empty');
      }

      if (incomingGlobalId != null && incomingGlobalId.isNotEmpty) {
        final existing = await (db.select(db.inventoryBonds)
              ..where((b) => b.globalId.equals(incomingGlobalId))
              ..limit(1))
            .getSingleOrNull();
        if (existing != null) {
          debugPrint('[API] postInventoryBond: duplicate globalId=$incomingGlobalId — returning success (serverId=${existing.id})');
          return jsonResponse({'success': true, 'serverId': existing.id, 'dedup': true});
        }
      }

      final warehouse =
          await (db.select(db.warehouses)..where((w) => w.id.equals(warehouseId)))
              .getSingleOrNull();
      final branchId = warehouse?.branchId;

      final serverBondId = await db.transaction(() async {
        final bondNumber = 'BND-${DateTime.now().millisecondsSinceEpoch}';
        final bondId = await db.createInventoryBond(
          InventoryBondsCompanion.insert(
            bondNumber: bondNumber,
            type: Value(type),
            warehouseId: warehouseId,
            notes: Value(notes),
            createdBy: Value(userId),
            bondDate: Value(bondDate ?? DateTime.now()),
            globalId: Value(incomingGlobalId),
          ),
        );

        double totalValue = 0;

        for (final item in itemsList) {
          final m = item as Map<String, dynamic>;
          final resolvedPid = await resolveProductId(
            clientProductId: parseIntNullable(m['productId']),
            productGlobalId: m['productGlobalId'] as String?,
            fallbackCode: m['productCode'] as String?,
            fallbackName: m['productName'] as String?,
          );
          if (resolvedPid == null) {
            throw Exception(
                'Validation Error: inventory bond item missing productId/productGlobalId');
          }
          final productId = resolvedPid;
          final qty = parseDouble(m['quantity']);
          final unitCost = parseDouble(m['unitCost']);
          totalValue += qty * unitCost;

          await db.into(db.inventoryBondItems).insert(
                InventoryBondItemsCompanion.insert(
                  bondId: bondId,
                  productId: productId,
                  quantity: qty,
                  unitCost: Value(unitCost),
                ),
              );

          // Update stock and audit movement (same path used by every
          // other write so reports stay consistent).
          await db.adjustStock(
            productId: productId,
            warehouseId: warehouseId,
            quantity: qty,
            type: 'bond_${type == 'opening' ? 'opening' : 'in'}',
            notes: 'Bond #$bondId',
            branchId: branchId,
          );

          // Weighted-average cost update (mirrors the default path in
          // CostingMethodService).
          final product = await (db.select(db.products)
                ..where((p) => p.id.equals(productId)))
              .getSingleOrNull();
          if (product != null && qty > 0) {
            final stockBefore = product.currentStock - qty;
            final newCost = stockBefore + qty <= 0
                ? unitCost
                : ((stockBefore * product.costPrice) + (qty * unitCost)) /
                    (stockBefore + qty);
            if (newCost > 0 && (newCost - product.costPrice).abs() > 0.0001) {
              await db.updateProduct(
                product.copyWith(costPrice: newCost),
              );
            }
          }
        }

        // Generate the inventory JE — same pattern as InventoryService.
        if (totalValue > 0) {
          try {
            final String purpose = (type == 'opening')
                ? 'capital'
                : 'inventory_surplus';
            final invAccount = await db.getAccountByPurpose('inventory');
            final targetAccount = await db.getAccountByPurpose(purpose);
            if (invAccount != null && targetAccount != null) {
              await db.createJournalEntry(
                description: 'إثبات قيد سند مخزني #$bondId (${notes ?? ''})',
                date: bondDate ?? DateTime.now(),
                branchId: branchId,
                isAutoPosted: true,
                referenceType: 'inventory_bond',
                referenceId: bondId,
                lines: [
                  JournalLine(
                    accountId: invAccount.id,
                    debit: totalValue.abs(),
                    credit: 0,
                    description: 'تعديل قيمة المخزون',
                  ),
                  JournalLine(
                    accountId: targetAccount.id,
                    debit: 0,
                    credit: totalValue.abs(),
                    description: type == 'opening'
                        ? 'رصيد أول المدة'
                        : 'تسوية فروقات مخزنية',
                  ),
                ],
              );
            } else {
              debugPrint('[API] postInventoryBond: COA not configured — '
                  'JE skipped (bondId=$bondId)');
            }
          } catch (e) {
            debugPrint('[API] postInventoryBond JE failed (non-fatal): $e');
          }
        }

        return bondId;
      });

      broadcast('products');
      broadcast('inventory');
      return jsonResponse({'success': true, 'serverId': serverBondId});
    } catch (e) {
      debugPrint('[API] postInventoryBond error: $e');
      return errorResponse('Failed to create inventory bond: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // Regions (Admin CRUD)
  // ═══════════════════════════════════════════════════════════════

  Future<Response> postRegion(Request request) async {
    try {
      // Spec 077 Batch 5 (Spec 060 Phase 2): per-user permission gate.
      final perm = await ApiUserCtx.requirePermission(
          request, db, PermissionCodes.branchesManage);
      if (perm != null) return perm;
      final data =
          json.decode(await request.readAsString()) as Map<String, dynamic>;
      final id = await db.createRegion(
        name: data['name'] as String,
        address: data['address'] as String?,
        phone: data['phone'] as String?,
        costCenterId: parseIntNullable(data['costCenterId']),
      );
      broadcast('regions');
      return jsonResponse({'success': true, 'id': id});
    } catch (e) {
      debugPrint('[API] postRegion error: $e');
      return errorResponse('Failed to create region: $e');
    }
  }

  Future<Response> putRegion(Request request, String id) async {
    try {
      // Spec 077 Batch 5 (Spec 060 Phase 2): per-user permission gate.
      final perm = await ApiUserCtx.requirePermission(
          request, db, PermissionCodes.branchesManage);
      if (perm != null) return perm;
      final regionId = int.parse(id);
      final data =
          json.decode(await request.readAsString()) as Map<String, dynamic>;
      final existing = await db.getRegionById(regionId);
      if (existing == null) {
        return Response.notFound(
          json.encode({'error': 'Region not found'}),
          headers: {'Content-Type': 'application/json'},
        );
      }
      await db.updateRegion(existing.copyWith(
        name: data['name'] as String? ?? existing.name,
        address: Value(data['address'] as String?),
        phone: Value(data['phone'] as String?),
        costCenterId: Value(parseIntNullable(data['costCenterId'])),
      ));
      broadcast('regions');
      return jsonResponse({'success': true});
    } catch (e) {
      debugPrint('[API] putRegion error: $e');
      return errorResponse('Failed to update region: $e');
    }
  }

  Future<Response> deleteRegion(Request request, String id) async {
    try {
      // Spec 077 Batch 5 (Spec 060 Phase 2): per-user permission gate.
      final perm = await ApiUserCtx.requirePermission(
          request, db, PermissionCodes.branchesManage);
      if (perm != null) return perm;
      final regionId = int.parse(id);
      await db.deactivateRegion(regionId);
      broadcast('regions');
      broadcastRecordDeleted('regions', regionId);
      return jsonResponse({'success': true});
    } catch (e) {
      debugPrint('[API] deleteRegion error: $e');
      return errorResponse('Failed to deactivate region: $e', statusCode: 400);
    }
  }

  Future<Response> postUserRegionAccess(Request request) async {
    try {
      // Spec 077 Batch 5 (Spec 060 Phase 2): per-user permission gate.
      final perm = await ApiUserCtx.requirePermission(
          request, db, PermissionCodes.usersManage);
      if (perm != null) return perm;
      final data =
          json.decode(await request.readAsString()) as Map<String, dynamic>;
      final userId = parseInt(data['userId']);
      final regionIds = (data['regionIds'] as List).cast<int>();
      await db.setUserRegionAccess(userId, regionIds);
      broadcast('user_region_access');
      return jsonResponse({'success': true});
    } catch (e) {
      debugPrint('[API] postUserRegionAccess error: $e');
      return errorResponse('Failed to set user region access: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // Roles (Admin CRUD)
  // ═══════════════════════════════════════════════════════════════

  Future<Response> createRole(Request request) async {
    try {
      // Spec 077 Batch 5 (Spec 060 Phase 2): per-user permission gate.
      final perm = await ApiUserCtx.requirePermission(
          request, db, PermissionCodes.rolesManage);
      if (perm != null) return perm;
      final data = json.decode(await request.readAsString()) as Map<String, dynamic>;
      final name = (data['name'] as String?)?.trim();
      if (name == null || name.isEmpty) {
        return errorResponse('اسم الدور مطلوب', statusCode: 400);
      }
      final id = await db.insertRole(
        name: name,
        description: data['description'] as String?,
        isSystemRole: parseBool(data['isSystemRole'], false),
      );
      broadcast('roles');
      return jsonResponse({'id': id, 'success': true});
    } catch (e) {
      debugPrint('[API] createRole error: $e');
      return errorResponse('Failed to create role: $e');
    }
  }

  /// Set permissions for a role (called by client nodes).
  Future<Response> setRolePermissions(Request request, String id) async {
    try {
      // 060 (D1-001): per-user permission gate. Highest-risk write —
      // setting role permissions is the privilege-escalation path.
      final perm = await ApiUserCtx.requirePermission(
          request, db, PermissionCodes.rolesManage);
      if (perm != null) return perm;

      final roleId = int.parse(id);
      final data = json.decode(await request.readAsString()) as Map<String, dynamic>;
      final codes = (data['permissionCodes'] as List).cast<String>();

      // Spec 136 ISS-15: resolve the role by globalId first. A role created on
      // a mirror/client lives only in that node's local db (insertRole never
      // pushes), so the server may know it by neither the drifted local id nor
      // its globalId — without this, db.setRolePermissions throws FK 23503
      // (role_permissions_role_id_fkey). resolveRoleId creates a placeholder
      // preserving the UUID so the link resolves and DeltaPull reconciles later.
      final resolvedRoleId = await resolveRoleId(
            clientRoleId: roleId,
            roleGlobalId: data['roleGlobalId'] as String?,
            fallbackName: data['roleName'] as String?,
          ) ??
          roleId;

      // Spec 061 (D1-002): if the target role is the bootstrap admin's role,
      // refuse any payload that does NOT include the two minimal recovery
      // codes (rolesManage + usersManage). Otherwise a paired client with the
      // API token could POST `[]` and brick the system.
      final admin = await (db.select(db.users)..where((u) => u.id.equals(1)))
          .getSingleOrNull();
      if (admin != null && admin.roleId == resolvedRoleId) {
        if (!codes.contains('rolesManage') || !codes.contains('usersManage')) {
          final caller =
              request.headers['x-forwarded-for'] ?? request.headers['host'] ?? 'unknown';
          unawaited(DiagnosticLogger.log('ADMIN-GUARD',
              'reason=strip-permissions caller=$caller roleId=$roleId codes=${codes.length}'));
          return errorResponse(
              bootstrapAdminRolePermissionsGuardMessage,
              statusCode: 403);
        }
      }

      // Resolve permission codes → IDs
      final allPerms = await db.getAllPermissions();
      final codeToId = <String, int>{
        for (final p in allPerms) p.code: p.id,
      };
      final permIds = <int>[];
      for (final code in codes) {
        final pid = codeToId[code];
        if (pid != null) permIds.add(pid);
      }

      await db.setRolePermissions(resolvedRoleId, permIds);
      broadcast('role_permissions');
      return jsonResponse({'success': true});
    } catch (e) {
      debugPrint('[API] setRolePermissions error: $e');
      return errorResponse('Failed to set role permissions: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // S4.2: Party Groups
  // ═══════════════════════════════════════════════════════════════

  Future<Response> postPartyGroup(Request request) async {
    try {
      // Spec 077 Batch 5 (Spec 060 Phase 2): per-user permission gate.
      final perm = await ApiUserCtx.requirePermission(
          request, db, PermissionCodes.customersEdit);
      if (perm != null) return perm;
      final data = json.decode(await request.readAsString()) as Map<String, dynamic>;
      final incomingGid = data['globalId'] as String?;

      if (incomingGid != null && incomingGid.isNotEmpty) {
        final existing = await (db.select(db.partyGroups)
              ..where((g) => g.globalId.equals(incomingGid))
              ..limit(1))
            .getSingleOrNull();
        if (existing != null) {
          await (db.update(db.partyGroups)..where((g) => g.id.equals(existing.id))).write(
            PartyGroupsCompanion(
              name: Value(data['name'] as String? ?? existing.name),
              type: Value(data['type'] as String? ?? existing.type),
              description: Value(data['description'] as String? ?? existing.description),
              defaultDiscount: Value(parseDouble(data['defaultDiscount'], existing.defaultDiscount)),
              defaultPaymentTerms: Value(data['defaultPaymentTerms'] as String? ?? existing.defaultPaymentTerms),
              priceLevel: Value(data['priceLevel'] as String? ?? existing.priceLevel),
              notes: Value(data['notes'] as String? ?? existing.notes),
            ),
          );
          broadcast('party_groups');
          return jsonResponse({'success': true, 'id': existing.id, 'global_id': incomingGid});
        }
      }

      final gid = (incomingGid != null && incomingGid.isNotEmpty) ? incomingGid : UuidV7.generate();
      final id = await db.into(db.partyGroups).insert(
        PartyGroupsCompanion.insert(
          name: data['name'] as String,
          type: Value(data['type'] as String? ?? 'both'),
          description: Value(data['description'] as String?),
          defaultDiscount: Value(parseDouble(data['defaultDiscount'])),
          defaultPaymentTerms: Value(data['defaultPaymentTerms'] as String?),
          priceLevel: Value(data['priceLevel'] as String?),
          notes: Value(data['notes'] as String?),
          parentGroupId: Value(parseIntNullable(data['parentGroupId'])),
          globalId: Value(gid),
        ),
      );
      broadcast('party_groups');
      return jsonResponse({'success': true, 'id': id, 'global_id': gid});
    } catch (e) {
      debugPrint('[API] postPartyGroup error: $e');
      return errorResponse('Failed to create party group: $e');
    }
  }

  Future<Response> putPartyGroup(Request request, String id) async {
    try {
      // Spec 077 Batch 5 (Spec 060 Phase 2): per-user permission gate.
      final perm = await ApiUserCtx.requirePermission(
          request, db, PermissionCodes.customersEdit);
      if (perm != null) return perm;
      final data = json.decode(await request.readAsString()) as Map<String, dynamic>;
      final group = await (db.select(db.partyGroups)..where((g) => g.id.equals(int.parse(id)))).getSingleOrNull();
      if (group == null) return errorResponse('Party group not found', statusCode: 404);
      await (db.update(db.partyGroups)..where((g) => g.id.equals(int.parse(id)))).write(
        PartyGroupsCompanion(
          name: data.containsKey('name') ? Value(data['name'] as String) : const Value.absent(),
          type: data.containsKey('type') ? Value(data['type'] as String) : const Value.absent(),
          description: data.containsKey('description') ? Value(data['description'] as String?) : const Value.absent(),
          defaultDiscount: data.containsKey('defaultDiscount') ? Value(parseDouble(data['defaultDiscount'])) : const Value.absent(),
          isActive: data.containsKey('isActive') ? Value(parseBool(data['isActive'], true)) : const Value.absent(),
        ),
      );
      broadcast('party_groups');
      return jsonResponse({'success': true});
    } catch (e) {
      return errorResponse('Failed to update party group: $e');
    }
  }

  Future<Response> deletePartyGroup(Request request, String id) async {
    try {
      // Spec 077 Batch 5 (Spec 060 Phase 2): per-user permission gate.
      final perm = await ApiUserCtx.requirePermission(
          request, db, PermissionCodes.customersEdit);
      if (perm != null) return perm;
      final gid = int.parse(id);
      await (db.delete(db.partyGroups)..where((g) => g.id.equals(gid))).go();
      broadcast('party_groups');
      broadcastRecordDeleted('party_groups', gid);
      return jsonResponse({'success': true});
    } catch (e) {
      return errorResponse('Failed to delete party group: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // S4.2: Purchase Orders
  // ═══════════════════════════════════════════════════════════════

  Future<Response> postPurchaseOrder(Request request) async {
    try {
      // Spec 077 Batch 5 (Spec 060 Phase 2): per-user permission gate.
      final perm = await ApiUserCtx.requirePermission(
          request, db, PermissionCodes.purchasesCreate);
      if (perm != null) return perm;
      final data = json.decode(await request.readAsString()) as Map<String, dynamic>;
      final incomingGid = data['globalId'] as String?;

      if (incomingGid != null && incomingGid.isNotEmpty) {
        final existing = await (db.select(db.purchaseOrders)
              ..where((o) => o.globalId.equals(incomingGid))
              ..limit(1))
            .getSingleOrNull();
        if (existing != null) {
          broadcast('purchase_orders');
          return jsonResponse({'success': true, 'id': existing.id, 'global_id': incomingGid});
        }
      }

      final gid = (incomingGid != null && incomingGid.isNotEmpty) ? incomingGid : UuidV7.generate();
      final supplierId = await _resolveWarehouseId(parseInt(data['supplierId']));
      final warehouseId = await _resolveWarehouseId(
        parseInt(data['warehouseId']),
        branchId: parseIntNullable(data['branchId']),
      );
      final orderDate = DateTime.tryParse(data['orderDate'] as String? ?? '') ?? DateTime.now();

      final orderId = await db.transaction(() async {
        final id = await db.into(db.purchaseOrders).insert(
          PurchaseOrdersCompanion.insert(
            orderNumber: data['orderNumber'] as String? ?? 'PO-SYNC',
            supplierId: supplierId,
            warehouseId: warehouseId,
            orderDate: orderDate,
            expectedDate: Value(DateTime.tryParse(data['expectedDate'] as String? ?? '')),
            subtotal: Value(parseDouble(data['subtotal'])),
            total: Value(parseDouble(data['total'])),
            notes: Value(data['notes'] as String?),
            costCenterId: Value(parseIntNullable(data['costCenterId'])),
            globalId: Value(gid),
          ),
        );
        final items = data['items'] as List? ?? [];
        for (final item in items) {
          final itemMap = item as Map<String, dynamic>;
          final itemGid = itemMap['globalId'] as String?;
          final resolvedPid = await resolveProductId(
            clientProductId: parseIntNullable(itemMap['productId']),
            productGlobalId: itemMap['productGlobalId'] as String?,
            fallbackCode: itemMap['productCode'] as String?,
            fallbackName: itemMap['productName'] as String?,
          );
          if (resolvedPid == null) {
            throw Exception('Validation Error: purchase order item missing productId/productGlobalId');
          }
          await db.into(db.purchaseOrderItems).insert(
            PurchaseOrderItemsCompanion.insert(
              orderId: id,
              productId: resolvedPid,
              quantity: parseDouble(itemMap['quantity']),
              unitCost: parseDouble(itemMap['unitCost']),
              total: parseDouble(itemMap['total']),
              notes: Value(itemMap['notes'] as String?),
              globalId: Value(itemGid != null && itemGid.isNotEmpty ? itemGid : UuidV7.generate()),
            ),
            onConflict: DoNothing(target: []),
          );
        }
        return id;
      });

      broadcast('purchase_orders');
      return jsonResponse({'success': true, 'id': orderId, 'global_id': gid});
    } catch (e) {
      debugPrint('[API] postPurchaseOrder error: $e');
      return errorResponse('Failed to create purchase order: $e');
    }
  }

  Future<Response> putPurchaseOrderStatus(Request request, String id) async {
    try {
      // Spec 077 Batch 5 (Spec 060 Phase 2): per-user permission gate.
      final perm = await ApiUserCtx.requirePermission(
          request, db, PermissionCodes.purchasesEdit);
      if (perm != null) return perm;
      final data = json.decode(await request.readAsString()) as Map<String, dynamic>;
      await (db.update(db.purchaseOrders)..where((o) => o.id.equals(int.parse(id)))).write(
        PurchaseOrdersCompanion(status: Value(data['status'] as String)),
      );
      broadcast('purchase_orders');
      return jsonResponse({'success': true});
    } catch (e) {
      return errorResponse('Failed to update purchase order status: $e');
    }
  }

  Future<Response> deletePurchaseOrder(Request request, String id) async {
    try {
      // Spec 077 Batch 5 (Spec 060 Phase 2): per-user permission gate.
      final perm = await ApiUserCtx.requirePermission(
          request, db, PermissionCodes.purchasesDelete);
      if (perm != null) return perm;
      final oid = int.parse(id);
      await db.transaction(() async {
        await (db.delete(db.purchaseOrderItems)..where((i) => i.orderId.equals(oid))).go();
        await (db.delete(db.purchaseOrders)..where((o) => o.id.equals(oid))).go();
      });
      broadcast('purchase_orders');
      broadcastRecordDeleted('purchase_orders', oid);
      return jsonResponse({'success': true});
    } catch (e) {
      return errorResponse('Failed to delete purchase order: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // S4.2: Sales Orders
  // ═══════════════════════════════════════════════════════════════

  Future<Response> postSalesOrder(Request request) async {
    try {
      // Spec 077 Batch 5 (Spec 060 Phase 2): per-user permission gate.
      final perm = await ApiUserCtx.requirePermission(
          request, db, PermissionCodes.salesCreate);
      if (perm != null) return perm;
      final data = json.decode(await request.readAsString()) as Map<String, dynamic>;
      final incomingGid = data['globalId'] as String?;

      if (incomingGid != null && incomingGid.isNotEmpty) {
        final existing = await (db.select(db.salesOrders)
              ..where((o) => o.globalId.equals(incomingGid))
              ..limit(1))
            .getSingleOrNull();
        if (existing != null) {
          broadcast('sales_orders');
          return jsonResponse({'success': true, 'id': existing.id, 'global_id': incomingGid});
        }
      }

      final gid = (incomingGid != null && incomingGid.isNotEmpty) ? incomingGid : UuidV7.generate();
      final warehouseId = await _resolveWarehouseId(
        parseInt(data['warehouseId']),
        branchId: parseIntNullable(data['branchId']),
      );
      final orderDate = DateTime.tryParse(data['orderDate'] as String? ?? '') ?? DateTime.now();

      final orderId = await db.transaction(() async {
        final id = await db.into(db.salesOrders).insert(
          SalesOrdersCompanion.insert(
            orderNumber: data['orderNumber'] as String? ?? 'SO-SYNC',
            customerId: Value(parseIntNullable(data['customerId'])),
            warehouseId: warehouseId,
            orderDate: orderDate,
            expectedDate: Value(DateTime.tryParse(data['expectedDate'] as String? ?? '')),
            subtotal: Value(parseDouble(data['subtotal'])),
            total: Value(parseDouble(data['total'])),
            notes: Value(data['notes'] as String?),
            costCenterId: Value(parseIntNullable(data['costCenterId'])),
            globalId: Value(gid),
          ),
        );
        final items = data['items'] as List? ?? [];
        for (final item in items) {
          final itemMap = item as Map<String, dynamic>;
          final itemGid = itemMap['globalId'] as String?;
          final resolvedPid = await resolveProductId(
            clientProductId: parseIntNullable(itemMap['productId']),
            productGlobalId: itemMap['productGlobalId'] as String?,
            fallbackCode: itemMap['productCode'] as String?,
            fallbackName: itemMap['productName'] as String?,
          );
          if (resolvedPid == null) {
            throw Exception('Validation Error: sales order item missing productId/productGlobalId');
          }
          await db.into(db.salesOrderItems).insert(
            SalesOrderItemsCompanion.insert(
              orderId: id,
              productId: resolvedPid,
              quantity: parseDouble(itemMap['quantity']),
              unitPrice: parseDouble(itemMap['unitPrice']),
              total: parseDouble(itemMap['total']),
              notes: Value(itemMap['notes'] as String?),
              globalId: Value(itemGid != null && itemGid.isNotEmpty ? itemGid : UuidV7.generate()),
            ),
            onConflict: DoNothing(target: []),
          );
        }
        return id;
      });

      broadcast('sales_orders');
      return jsonResponse({'success': true, 'id': orderId, 'global_id': gid});
    } catch (e) {
      debugPrint('[API] postSalesOrder error: $e');
      return errorResponse('Failed to create sales order: $e');
    }
  }

  Future<Response> putSalesOrderStatus(Request request, String id) async {
    try {
      // Spec 077 Batch 5 (Spec 060 Phase 2): per-user permission gate.
      final perm = await ApiUserCtx.requirePermission(
          request, db, PermissionCodes.salesEdit);
      if (perm != null) return perm;
      final data = json.decode(await request.readAsString()) as Map<String, dynamic>;
      await (db.update(db.salesOrders)..where((o) => o.id.equals(int.parse(id)))).write(
        SalesOrdersCompanion(status: Value(data['status'] as String)),
      );
      broadcast('sales_orders');
      return jsonResponse({'success': true});
    } catch (e) {
      return errorResponse('Failed to update sales order status: $e');
    }
  }

  Future<Response> deleteSalesOrder(Request request, String id) async {
    try {
      // Spec 077 Batch 5 (Spec 060 Phase 2): per-user permission gate.
      final perm = await ApiUserCtx.requirePermission(
          request, db, PermissionCodes.salesDelete);
      if (perm != null) return perm;
      final oid = int.parse(id);
      await db.transaction(() async {
        await (db.delete(db.salesOrderItems)..where((i) => i.orderId.equals(oid))).go();
        await (db.delete(db.salesOrders)..where((o) => o.id.equals(oid))).go();
      });
      broadcast('sales_orders');
      broadcastRecordDeleted('sales_orders', oid);
      return jsonResponse({'success': true});
    } catch (e) {
      return errorResponse('Failed to delete sales order: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // S4.2: Quotations
  // ═══════════════════════════════════════════════════════════════

  Future<Response> postQuotation(Request request) async {
    try {
      // Spec 077 Batch 5 (Spec 060 Phase 2): per-user permission gate.
      final perm = await ApiUserCtx.requirePermission(
          request, db, PermissionCodes.salesCreate);
      if (perm != null) return perm;
      final data = json.decode(await request.readAsString()) as Map<String, dynamic>;
      final incomingGid = data['globalId'] as String?;

      if (incomingGid != null && incomingGid.isNotEmpty) {
        final existing = await (db.select(db.quotations)
              ..where((q) => q.globalId.equals(incomingGid))
              ..limit(1))
            .getSingleOrNull();
        if (existing != null) {
          broadcast('quotations');
          return jsonResponse({'success': true, 'id': existing.id, 'global_id': incomingGid});
        }
      }

      final gid = (incomingGid != null && incomingGid.isNotEmpty) ? incomingGid : UuidV7.generate();
      final userId = await _resolveUserId(parseInt(data['userId'], 1));
      final warehouseId = await _resolveWarehouseId(
        parseInt(data['warehouseId']),
        branchId: parseIntNullable(data['branchId']),
      );
      final quotationDate = DateTime.tryParse(data['quotationDate'] as String? ?? '') ?? DateTime.now();

      final resolvedQuotationCustomerId = await resolvePartyId(
        clientPartyId: parseIntNullable(data['customerId']),
        partyGlobalId: data['customerGlobalId'] as String?,
        isCustomer: true,
      );

      final quotationId = await db.transaction(() async {
        final id = await db.into(db.quotations).insert(
          QuotationsCompanion.insert(
            quotationNumber: data['quotationNumber'] as String? ?? 'QT-SYNC',
            customerId: Value(resolvedQuotationCustomerId),
            warehouseId: warehouseId,
            userId: userId,
            quotationDate: quotationDate,
            validityDate: Value(DateTime.tryParse(data['validityDate'] as String? ?? '')),
            subtotal: Value(parseDouble(data['subtotal'])),
            discount: Value(parseDouble(data['discount'])),
            tax: Value(parseDouble(data['tax'])),
            total: Value(parseDouble(data['total'])),
            notes: Value(data['notes'] as String?),
            status: Value(data['status'] as String? ?? 'draft'),
            globalId: Value(gid),
          ),
        );
        final items = data['items'] as List? ?? [];
        for (final item in items) {
          final itemMap = item as Map<String, dynamic>;
          final itemGid = itemMap['globalId'] as String?;
          final resolvedPid = await resolveProductId(
            clientProductId: parseIntNullable(itemMap['productId']),
            productGlobalId: itemMap['productGlobalId'] as String?,
            fallbackCode: itemMap['productCode'] as String?,
            fallbackName: itemMap['productName'] as String?,
          );
          if (resolvedPid == null) {
            throw Exception('Validation Error: quotation item missing productId/productGlobalId');
          }
          await db.into(db.quotationItems).insert(
            QuotationItemsCompanion.insert(
              quotationId: id,
              productId: resolvedPid,
              quantity: parseDouble(itemMap['quantity']),
              unitPrice: parseDouble(itemMap['unitPrice']),
              discount: Value(parseDouble(itemMap['discount'])),
              total: parseDouble(itemMap['total']),
              globalId: Value(itemGid != null && itemGid.isNotEmpty ? itemGid : UuidV7.generate()),
            ),
            onConflict: DoNothing(target: []),
          );
        }
        return id;
      });

      broadcast('quotations');
      return jsonResponse({'success': true, 'id': quotationId, 'global_id': gid});
    } catch (e) {
      debugPrint('[API] postQuotation error: $e');
      return errorResponse('Failed to create quotation: $e');
    }
  }

  Future<Response> putQuotationStatus(Request request, String id) async {
    try {
      // Spec 077 Batch 5 (Spec 060 Phase 2): per-user permission gate.
      final perm = await ApiUserCtx.requirePermission(
          request, db, PermissionCodes.salesEdit);
      if (perm != null) return perm;
      final data = json.decode(await request.readAsString()) as Map<String, dynamic>;
      await (db.update(db.quotations)..where((q) => q.id.equals(int.parse(id)))).write(
        QuotationsCompanion(
          status: Value(data['status'] as String),
          convertedToInvoiceId: data.containsKey('convertedToInvoiceId')
              ? Value(parseIntNullable(data['convertedToInvoiceId']))
              : const Value.absent(),
        ),
      );
      broadcast('quotations');
      return jsonResponse({'success': true});
    } catch (e) {
      return errorResponse('Failed to update quotation status: $e');
    }
  }

  Future<Response> putQuotation(Request request, String id) async {
    try {
      // Spec 077 Batch 5 (Spec 060 Phase 2): per-user permission gate.
      final perm = await ApiUserCtx.requirePermission(
          request, db, PermissionCodes.salesEdit);
      if (perm != null) return perm;
      final qid = int.parse(id);
      final data = json.decode(await request.readAsString()) as Map<String, dynamic>;
      final quotationDate = DateTime.tryParse(data['quotationDate'] as String? ?? '');
      final validityDate = DateTime.tryParse(data['validityDate'] as String? ?? '');

      await db.transaction(() async {
        await (db.update(db.quotations)..where((q) => q.id.equals(qid))).write(
          QuotationsCompanion(
            customerId: data.containsKey('customerId')
                ? Value(parseIntNullable(data['customerId']))
                : const Value.absent(),
            warehouseId: data.containsKey('warehouseId')
                ? Value(parseInt(data['warehouseId']))
                : const Value.absent(),
            userId: data.containsKey('userId')
                ? Value(parseInt(data['userId']))
                : const Value.absent(),
            quotationDate: quotationDate != null
                ? Value(quotationDate)
                : const Value.absent(),
            validityDate: validityDate != null
                ? Value(validityDate)
                : const Value.absent(),
            subtotal: data.containsKey('subtotal')
                ? Value(parseDouble(data['subtotal']))
                : const Value.absent(),
            discount: data.containsKey('discount')
                ? Value(parseDouble(data['discount']))
                : const Value.absent(),
            tax: data.containsKey('tax')
                ? Value(parseDouble(data['tax']))
                : const Value.absent(),
            total: data.containsKey('total')
                ? Value(parseDouble(data['total']))
                : const Value.absent(),
            notes: data.containsKey('notes')
                ? Value(data['notes'] as String?)
                : const Value.absent(),
            status: data.containsKey('status')
                ? Value(data['status'] as String)
                : const Value.absent(),
          ),
        );

        final items = data['items'] as List?;
        if (items != null) {
          await (db.delete(db.quotationItems)..where((i) => i.quotationId.equals(qid))).go();
          for (final item in items) {
            final itemMap = item as Map<String, dynamic>;
            final itemGid = itemMap['globalId'] as String?;
            final resolvedPid = await resolveProductId(
              clientProductId: parseIntNullable(itemMap['productId']),
              productGlobalId: itemMap['productGlobalId'] as String?,
              fallbackCode: itemMap['productCode'] as String?,
              fallbackName: itemMap['productName'] as String?,
            );
            if (resolvedPid == null) {
              throw Exception('Validation Error: quotation item missing productId/productGlobalId');
            }
            await db.into(db.quotationItems).insert(
              QuotationItemsCompanion.insert(
                quotationId: qid,
                productId: resolvedPid,
                quantity: parseDouble(itemMap['quantity']),
                unitPrice: parseDouble(itemMap['unitPrice']),
                discount: Value(parseDouble(itemMap['discount'])),
                total: parseDouble(itemMap['total']),
                globalId: Value(itemGid != null && itemGid.isNotEmpty ? itemGid : UuidV7.generate()),
              ),
              onConflict: DoNothing(target: []),
            );
          }
        }
      });

      broadcast('quotations');
      return jsonResponse({'success': true, 'id': qid});
    } catch (e) {
      debugPrint('[API] putQuotation error: $e');
      return errorResponse('Failed to update quotation: $e');
    }
  }

  Future<Response> deleteQuotation(Request request, String id) async {
    try {
      // Spec 077 Batch 5 (Spec 060 Phase 2): per-user permission gate.
      final perm = await ApiUserCtx.requirePermission(
          request, db, PermissionCodes.salesDelete);
      if (perm != null) return perm;
      final qid = int.parse(id);
      await db.transaction(() async {
        await (db.delete(db.quotationItems)..where((i) => i.quotationId.equals(qid))).go();
        await (db.delete(db.quotations)..where((q) => q.id.equals(qid))).go();
      });
      broadcast('quotations');
      broadcastRecordDeleted('quotations', qid);
      return jsonResponse({'success': true});
    } catch (e) {
      return errorResponse('Failed to delete quotation: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // S4.2: Price Lists
  // ═══════════════════════════════════════════════════════════════

  Future<Response> postPriceList(Request request) async {
    try {
      // Spec 077 Batch 5 (Spec 060 Phase 2): per-user permission gate.
      final perm = await ApiUserCtx.requirePermission(
          request, db, PermissionCodes.priceListsManage);
      if (perm != null) return perm;
      final data = json.decode(await request.readAsString()) as Map<String, dynamic>;
      final incomingGid = data['globalId'] as String?;

      if (incomingGid != null && incomingGid.isNotEmpty) {
        final existing = await (db.select(db.priceLists)
              ..where((p) => p.globalId.equals(incomingGid))
              ..limit(1))
            .getSingleOrNull();
        if (existing != null) {
          broadcast('price_lists');
          return jsonResponse({'success': true, 'id': existing.id, 'global_id': incomingGid});
        }
      }

      final gid = (incomingGid != null && incomingGid.isNotEmpty) ? incomingGid : UuidV7.generate();
      final isDefault = parseBool(data['isDefault'], false);
      if (isDefault) {
        await db.update(db.priceLists).write(const PriceListsCompanion(isDefault: Value(false)));
      }
      final id = await db.into(db.priceLists).insert(
        PriceListsCompanion.insert(
          name: data['name'] as String,
          code: data['code'] as String? ?? gid.substring(0, 8),
          isDefault: Value(isDefault),
          currencyId: Value(parseIntNullable(data['currencyId'])),
          startDate: Value(DateTime.tryParse(data['startDate'] as String? ?? '')),
          endDate: Value(DateTime.tryParse(data['endDate'] as String? ?? '')),
          globalId: Value(gid),
        ),
      );
      broadcast('price_lists');
      return jsonResponse({'success': true, 'id': id, 'global_id': gid});
    } catch (e) {
      debugPrint('[API] postPriceList error: $e');
      return errorResponse('Failed to create price list: $e');
    }
  }

  Future<Response> putPriceList(Request request, String id) async {
    try {
      // Spec 077 Batch 5 (Spec 060 Phase 2): per-user permission gate.
      final perm = await ApiUserCtx.requirePermission(
          request, db, PermissionCodes.priceListsManage);
      if (perm != null) return perm;
      final data = json.decode(await request.readAsString()) as Map<String, dynamic>;
      await (db.update(db.priceLists)..where((p) => p.id.equals(int.parse(id)))).write(
        PriceListsCompanion(
          name: data.containsKey('name') ? Value(data['name'] as String) : const Value.absent(),
          isActive: data.containsKey('isActive') ? Value(parseBool(data['isActive'], true)) : const Value.absent(),
        ),
      );
      broadcast('price_lists');
      return jsonResponse({'success': true});
    } catch (e) {
      return errorResponse('Failed to update price list: $e');
    }
  }

  Future<Response> postPriceListItem(Request request) async {
    try {
      // Spec 077 Batch 5 (Spec 060 Phase 2): per-user permission gate.
      final perm = await ApiUserCtx.requirePermission(
          request, db, PermissionCodes.priceListsManage);
      if (perm != null) return perm;
      final data = json.decode(await request.readAsString()) as Map<String, dynamic>;
      final incomingGid = data['globalId'] as String?;
      final priceListId = parseInt(data['priceListId']);
      final productId = parseInt(data['productId']);

      await (db.delete(db.priceListItems)
            ..where((i) => i.priceListId.equals(priceListId) & i.productId.equals(productId)))
          .go();
      await db.into(db.priceListItems).insert(
        PriceListItemsCompanion.insert(
          priceListId: priceListId,
          productId: productId,
          price: parseDouble(data['price']),
          minQuantity: Value(parseDouble(data['minQuantity'], 1.0)),
          maxDiscount: Value(parseDouble(data['maxDiscount'])),
          globalId: Value(incomingGid != null && incomingGid.isNotEmpty ? incomingGid : UuidV7.generate()),
        ),
      );
      broadcast('price_list_items');
      return jsonResponse({'success': true});
    } catch (e) {
      return errorResponse('Failed to set price list item: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // S4.2: Printers
  // ═══════════════════════════════════════════════════════════════

  Future<Response> postPrinter(Request request) async {
    try {
      // Spec 077 Batch 5 (Spec 060 Phase 2): per-user permission gate.
      final perm = await ApiUserCtx.requirePermission(
          request, db, PermissionCodes.settingsPrinter);
      if (perm != null) return perm;
      final data = json.decode(await request.readAsString()) as Map<String, dynamic>;
      final incomingGid = data['globalId'] as String?;

      if (incomingGid != null && incomingGid.isNotEmpty) {
        final existing = await (db.select(db.printers)
              ..where((p) => p.globalId.equals(incomingGid))
              ..limit(1))
            .getSingleOrNull();
        if (existing != null) {
          broadcast('printers');
          return jsonResponse({'success': true, 'id': existing.id, 'global_id': incomingGid});
        }
      }

      final gid = (incomingGid != null && incomingGid.isNotEmpty) ? incomingGid : UuidV7.generate();
      final id = await db.into(db.printers).insert(
        PrintersCompanion.insert(
          name: data['name'] as String,
          port: Value(data['port'] as String?),
          ipAddress: Value(data['ipAddress'] as String?),
          portNumber: Value(parseIntNullable(data['portNumber'])),
          printerType: Value(data['printerType'] as String? ?? 'thermal'),
          purpose: Value(data['purpose'] as String? ?? 'pos_receipt'),
          description: Value(data['description'] as String?),
          globalId: Value(gid),
        ),
      );
      broadcast('printers');
      return jsonResponse({'success': true, 'id': id, 'global_id': gid});
    } catch (e) {
      debugPrint('[API] postPrinter error: $e');
      return errorResponse('Failed to create printer: $e');
    }
  }

  Future<Response> putPrinter(Request request, String id) async {
    try {
      // Spec 077 Batch 5 (Spec 060 Phase 2): per-user permission gate.
      final perm = await ApiUserCtx.requirePermission(
          request, db, PermissionCodes.settingsPrinter);
      if (perm != null) return perm;
      final data = json.decode(await request.readAsString()) as Map<String, dynamic>;
      await (db.update(db.printers)..where((p) => p.id.equals(int.parse(id)))).write(
        PrintersCompanion(
          name: data.containsKey('name') ? Value(data['name'] as String) : const Value.absent(),
          port: data.containsKey('port') ? Value(data['port'] as String?) : const Value.absent(),
          ipAddress: data.containsKey('ipAddress') ? Value(data['ipAddress'] as String?) : const Value.absent(),
          portNumber: data.containsKey('portNumber') ? Value(parseIntNullable(data['portNumber'])) : const Value.absent(),
          printerType: data.containsKey('printerType') ? Value(data['printerType'] as String) : const Value.absent(),
          purpose: data.containsKey('purpose') ? Value(data['purpose'] as String) : const Value.absent(),
          description: data.containsKey('description') ? Value(data['description'] as String?) : const Value.absent(),
          isActive: data.containsKey('isActive') ? Value(parseBool(data['isActive'], true)) : const Value.absent(),
        ),
      );
      broadcast('printers');
      return jsonResponse({'success': true});
    } catch (e) {
      return errorResponse('Failed to update printer: $e');
    }
  }

  Future<Response> deletePrinter(Request request, String id) async {
    try {
      // Spec 077 Batch 5 (Spec 060 Phase 2): per-user permission gate.
      final perm = await ApiUserCtx.requirePermission(
          request, db, PermissionCodes.settingsPrinter);
      if (perm != null) return perm;
      final pid = int.parse(id);
      await (db.delete(db.printers)..where((p) => p.id.equals(pid))).go();
      broadcast('printers');
      broadcastRecordDeleted('printers', pid);
      return jsonResponse({'success': true});
    } catch (e) {
      return errorResponse('Failed to delete printer: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // Backup (client uploads its DB to the server)
  // ═══════════════════════════════════════════════════════════════

  Future<Response> postBackup(Request request) async {
    try {
      // Spec 077 Batch 5 (Spec 060 Phase 2): per-user permission gate.
      final perm = await ApiUserCtx.requirePermission(
          request, db, PermissionCodes.settingsBackup);
      if (perm != null) return perm;
      final data =
          json.decode(await request.readAsString()) as Map<String, dynamic>;
      final clientName = data['clientName'] as String? ?? 'unknown';
      final dbBase64 = data['dbData'] as String;
      final dbBytes = base64Decode(dbBase64);

      final timestamp = DateTime.now()
          .toIso8601String()
          .replaceAll(':', '-')
          .split('.')
          .first;
      final backupDir =
          '${Platform.environment['APPDATA'] ?? '.'}/${Brand.backupFolderName}/clients';
      final dir = Directory(backupDir);
      if (!await dir.exists()) await dir.create(recursive: true);

      final backupPath = '$backupDir/backup_${clientName}_$timestamp.sqlite';
      await File(backupPath).writeAsBytes(dbBytes);

      debugPrint(
        '[API] Client backup saved: $backupPath (${dbBytes.length} bytes)',
      );
      return jsonResponse({'success': true, 'path': backupPath});
    } catch (e) {
      debugPrint('[API] postBackup error: $e');
      return errorResponse('Failed to save backup: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // Activity Log Push — Central Audit Trail (Multi-Client Sync)
  // ═══════════════════════════════════════════════════════════════

  /// POST /api/activity-logs/push
  ///
  /// Receives a single activity log entry pushed from a client device and
  /// persists it in the server's activity_logs table.  Uses globalId for
  /// idempotency so that offline-queued entries replayed from the outbox
  /// cannot produce duplicate rows.
  // EXEMPT-PER-USER: forensic ingest, not a user-initiated action.
  // Gating would create a perm-loop (cashier denied → push deny-log
  // → log push denied). Bearer-token auth is sufficient.
  // (Spec 077 Batch 5 allow-list — see §5.27 of endpoint-permission-map.md)
  Future<Response> pushActivityLog(Request request) async {
    try {
      final body = json.decode(await request.readAsString()) as Map<String, dynamic>;

      final globalId = body['globalId'] as String?;
      if (globalId == null || globalId.isEmpty) {
        return errorResponse('Missing required field: globalId', statusCode: 400);
      }

      // Idempotency: skip silently if we already have this log entry.
      final existing = await (db.select(db.activityLogs)
            ..where((l) => l.globalId.equals(globalId))
            ..limit(1))
          .getSingleOrNull();
      if (existing != null) {
        return jsonResponse({'success': true, 'skipped': true});
      }

      // Resolve userId: prefer exact server ID, fall back to admin.
      final clientUserId = body['userId'] as int?;
      final userName = (body['userName'] as String?) ?? '';
      final resolvedUserId = await _resolveUserIdNullable(
        clientUserId,
        fallbackUsername: userName,
      );

      final createdAtRaw = body['createdAt'] as String?;
      final createdAt = createdAtRaw != null
          ? DateTime.tryParse(createdAtRaw) ?? DateTime.now()
          : DateTime.now();
      final now = DateTime.now();

      await db.into(db.activityLogs).insert(
        ActivityLogsCompanion.insert(
          userId: Value(resolvedUserId),
          userName: userName,
          action: (body['action'] as String?) ?? '',
          entityType: (body['entityType'] as String?) ?? '',
          entityId: Value(body['entityId'] as int?),
          description: (body['description'] as String?) ?? '',
          oldValue: Value(body['oldValue'] as String?),
          newValue: Value(body['newValue'] as String?),
          amount: Value((body['amount'] as num?)?.toDouble()),
          deviceInfo: Value(body['deviceInfo'] as String?),
          createdAt: Value(createdAt),
          globalId: Value(globalId),
          originClientId: Value(body['originClientId'] as String?),
          lastModifiedAt: Value(now),
        ),
      );

      return jsonResponse({'success': true});
    } catch (e) {
      debugPrint('[API] pushActivityLog error: $e');
      return errorResponse('Failed to store activity log: $e');
    }
  }
}
