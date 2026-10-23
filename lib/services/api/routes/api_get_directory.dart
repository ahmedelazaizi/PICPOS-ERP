// ApiHandler - parties, branches, regions, cost centers, accounts, warehouses, follow-ups (GET).
part of '../api_handler.dart';

/// parties, branches, regions, cost centers, accounts, warehouses, follow-ups (GET) (see [ApiHandler]).
extension ApiHandlerDirectoryGets on ApiHandler {
  // ═══════════════════════════════════════════════════════════════
  // Sync Endpoints (Parties, Warehouses, Users — GET)
  // ═══════════════════════════════════════════════════════════════

  Future<Response> _getParties(Request request) async {
    try {
      // SEC-008: branch scope + no balances without a verified identity.
      final hasIdentity = ApiUserCtx.userIdOf(request) != null;
      final scope = await _resolveBranchScope(request);
      final parties = (await _db.select(_db.parties).get())
          .where((p) =>
              scope == null ||
              PartyVisibility.visible(
                  isGlobal: p.isGlobal, branchIds: p.branchIds, scope: scope))
          .toList();
      // Include `code`, `globalId`, `accountId`, `groupId` so the client's
      // sync strategy can dedupe by `globalId` and reflect the authoritative
      // code that the server generated (e.g. CUST-00001). Dropping these
      // fields was the source of the party-duplication bug on client nodes.
      final jsonList = parties
          .map(
            (p) => <String, dynamic>{
              'id': p.id,
              'globalId': p.globalId,
              'code': p.code,
              'name': p.name,
              'phone': p.phone,
              'address': p.address,
              'taxId': p.taxId,
              'isCustomer': p.isCustomer,
              'isSupplier': p.isSupplier,
              'isDeliveryCompany': p.isDeliveryCompany,
              'isFavorite': p.isFavorite,
              if (hasIdentity) 'balance': p.balance,
              if (hasIdentity) 'creditLimit': p.creditLimit,
              'paymentTermsDays': p.paymentTermsDays,
              'fixedDiscount': p.fixedDiscount,
              'priceLevel': p.priceLevel,
              'isActive': p.isActive,
              'accountId': p.accountId,
               'currencyId': p.currencyId,
              'groupId': p.groupId,
            },
          )
          .toList();
      return _json({'parties': jsonList, 'count': jsonList.length});
    } catch (e) {
      return ApiErrors.fail(e, 'Failed to fetch parties');
    }
  }

  Future<Response> _getBranches(Request request) async {
    try {
      final branchId = await _extractBranchId(request);
      final query = _db.select(_db.branches);
      if (branchId != null) {
        query.where((b) => b.id.equals(branchId));
      }
      final branches = await query.get();
      final jsonList = branches
          .map(
            (b) => <String, dynamic>{
              'id': b.id,
              'name': b.name,
              'code': b.code,
              'address': b.address,
              'phone': b.phone,
              'isActive': b.isActive,
              'costCenterId': b.costCenterId,
              // Cluster 023 / Issue 4 — regionId was missing from this
              // payload, so every pull-sync wiped the branch↔region link
              // a mirror admin had just saved (the put endpoint persisted
              // it correctly, but the next GET dropped it on the floor).
              // globalId is added alongside so BranchSyncStrategy can match
              // on the deterministic key instead of falling back to the
              // name-only tier (R8 SYNC-WARN). Same reasoning for code.
              'regionId': b.regionId,
              'globalId': b.globalId,
            },
          )
          .toList();
      return _json({'branches': jsonList, 'count': jsonList.length});
    } catch (e) {
      return ApiErrors.fail(e, 'Failed to fetch branches');
    }
  }

  Future<Response> _getRegions(Request request) async {
    try {
      final regionsList = await _db.select(_db.regions).get();
      final jsonList = regionsList
          .map(
            (r) => <String, dynamic>{
              'id': r.id,
              'name': r.name,
              'address': r.address,
              'phone': r.phone,
              'isActive': r.isActive,
              'costCenterId': r.costCenterId,
              'globalId': r.globalId,
            },
          )
          .toList();
      return _json({'regions': jsonList, 'count': jsonList.length});
    } catch (e) {
      return ApiErrors.fail(e, 'Failed to fetch regions');
    }
  }

  Future<Response> _getUserRegionAccess(Request request) async {
    try {
      final accessData = await _db.select(_db.userRegionAccess).get();
      final jsonList = accessData
          .map((a) => <String, dynamic>{
                'userId': a.userId,
                'regionId': a.regionId,
              })
          .toList();
      return _json({'user_region_access': jsonList, 'count': jsonList.length});
    } catch (e) {
      debugPrint('[API] Error fetching user region access: $e');
      return ApiErrors.fail(e, 'Failed to fetch user region access');
    }
  }

  Future<Response> _getCostCenters(Request request) async {
    try {
      final branchId = await _extractBranchId(request);
      final query = _db.select(_db.costCenters);

      if (branchId == _kNoBranchAccess) {
        // Spec 151 residual #2 (D-06 fail-open): a mis-provisioned user resolves
        // to the -1 sentinel. Without this branch, the lookup below returns null,
        // the filter is skipped, and the ENTIRE cost-center table leaks. Fail CLOSED.
        query.where((c) => c.id.equals(_kNoBranchAccess));
      } else if (branchId != null) {
        // Resolve the branch to get its costCenterId
        final branch = await (_db.select(_db.branches)
              ..where((b) => b.id.equals(branchId)))
            .getSingleOrNull();

        if (branch != null && branch.costCenterId != null) {
          // Return the branch's cost center and potentially its children
          // For now, let's just return the primary cost center assigned to the branch
          query.where((c) => c.id.equals(branch.costCenterId!));
        }
      }

      final centers = await query.get();
      final jsonList = centers
          .map(
            (c) => <String, dynamic>{
              'id': c.id,
              'code': c.code,
              'name': c.name,
              'parentId': c.parentId,
              'isActive': c.isActive,
              'createdAt': c.createdAt.toIso8601String(),
            },
          )
          .toList();
      return _json({'cost_centers': jsonList, 'count': jsonList.length});
    } catch (e) {
      return ApiErrors.fail(e, 'Failed to fetch cost centers');
    }
  }

  Future<Response> _getAccounts(Request request) async {
    try {
      final accounts = await _db.select(_db.accounts).get();
      final jsonList = accounts
          .map(
            (a) => <String, dynamic>{
              'id': a.id,
              'code': a.code,
              'name': a.name,
              'accountType': a.accountType,
              'accountNature': a.accountNature,
              'normalBalance': a.normalBalance,
              'level': a.level,
              'parentId': a.parentId,
              'balance': a.balance,
              'isSystem': a.isSystem,
              'isActive': a.isActive,
              'isHiddenFromEntries': a.isHiddenFromEntries,
            },
          )
          .toList();
      return _json({'accounts': jsonList, 'count': jsonList.length});
    } catch (e) {
      return ApiErrors.fail(e, 'Failed to fetch accounts');
    }
  }

  Future<Response> _getWarehouses(Request request) async {
    try {
      final branchId = await _extractBranchId(request);
      final query = _db.select(_db.warehouses);
      if (branchId != null) {
        // قرار المالك §٢-ب — الصف بلا فرع يبقى مرئياً. `Warehouses.branchId`
        // nullable، والحصر الصارم هنا كان يُخفي مخازن مشروعة عن جهاز يعمل
        // عليها ⇒ «جهاز بلا مخزن يعمل عليه». نفس ذراع `_getSafes` والمسار
        // المحصور في `/api/sync/pull`.
        query.where((w) => w.branchId.equals(branchId) | w.branchId.isNull());
      }
      final warehouses = await query.get();
      final jsonList = warehouses
          .map(
            (w) => <String, dynamic>{
              'id': w.id,
              'name': w.name,
              'branchId': w.branchId,
              'isDefault': w.isDefault,
              'isActive': w.isActive,
            },
          )
          .toList();
      return _json({'warehouses': jsonList, 'count': jsonList.length});
    } catch (e) {
      return ApiErrors.fail(e, 'Failed to fetch warehouses');
    }
  }


  // ═══════════════════════════════════════════════════════════════
  // v165 — متابعةُ التحصيل ومطالبةُ المورد
  // ═══════════════════════════════════════════════════════════════
  //
  // ⚠️ **بلا حصرِ فرعٍ — كأصلهما.** الجدولان يتعلّقان بـ`parties`، ولا عمودَ
  // فرعٍ فيهما. والعميلُ يُرسل `branch_id` (‏المساران في `_scopedEndpoints`)
  // لكنّ `_getParties` نفسَه لا يقرؤه ويعيد الأطرافَ كلَّها. فحصرُ التابعِ
  // بفرعٍ لا يُحصَر به أصلُه كان يُنتج فرعاً يرى الطرفَ ولا يرى متابعاتِه —
  // وهو أسوأُ من الحالتين. ويومَ يُحصَر مسارُ الأطراف يُحصَر هذان معه.
  //
  // ⚠️ **والمحذوفُ ناعماً يُرسَل** ولا يُرشَّح هنا: المزامنةُ تحتاج الصفَّ
  // بعمود `deletedAt` لتحذفه عند الطرف الآخر، وإخفاؤه يُبقيه حيّاً هناك
  // إلى الأبد.

  Future<Response> _getPartyFollowUps(Request request) async {
    try {
      final rows = await _db.select(_db.partyFollowUps).get();
      final jsonList = rows
          .map((f) => <String, dynamic>{
                'id': f.id,
                'globalId': f.globalId,
                'partyId': f.partyId,
                'invoiceId': f.invoiceId,
                'invoiceNumber': f.invoiceNumber,
                'amountDue': f.amountDue,
                'contactedAt': f.contactedAt.toIso8601String(),
                'outcome': f.outcome,
                'promisedDate': f.promisedDate?.toIso8601String(),
                'promisedAmount': f.promisedAmount,
                'contactPerson': f.contactPerson,
                'nextActionAt': f.nextActionAt?.toIso8601String(),
                'notes': f.notes,
                'createdBy': f.createdBy,
                'createdAt': f.createdAt.toIso8601String(),
                'lastModifiedAt': f.lastModifiedAt?.toIso8601String(),
                'deletedAt': f.deletedAt?.toIso8601String(),
                'rowVersion': f.rowVersion,
              })
          .toList();
      return _json({'party_follow_ups': jsonList, 'count': jsonList.length});
    } catch (e) {
      return ApiErrors.fail(e, 'Failed to fetch party follow-ups');
    }
  }

  Future<Response> _getSupplierClaims(Request request) async {
    try {
      final rows = await _db.select(_db.supplierClaims).get();
      final jsonList = rows
          .map((c) => <String, dynamic>{
                'id': c.id,
                'globalId': c.globalId,
                'supplierId': c.supplierId,
                'claimDate': c.claimDate.toIso8601String(),
                'ledgerBalance': c.ledgerBalance,
                'settlementKind': c.settlementKind,
                'status': c.status,
                'netAmount': c.netAmount,
                'linesJson': c.linesJson,
                'lineCount': c.lineCount,
                'replyDueAt': c.replyDueAt?.toIso8601String(),
                'notes': c.notes,
                'createdBy': c.createdBy,
                'createdAt': c.createdAt.toIso8601String(),
                'lastModifiedAt': c.lastModifiedAt?.toIso8601String(),
                'deletedAt': c.deletedAt?.toIso8601String(),
                'rowVersion': c.rowVersion,
              })
          .toList();
      return _json({'supplier_claims': jsonList, 'count': jsonList.length});
    } catch (e) {
      return ApiErrors.fail(e, 'Failed to fetch supplier claims');
    }
  }

}
