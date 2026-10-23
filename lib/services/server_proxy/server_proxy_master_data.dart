// ServerProxy - parties, products, categories, units and structure writes.
part of '../server_proxy.dart';

/// Parties, products, categories, units/barcodes, regions, party groups, printers,
/// warehouses, branches, floor plan and attachments of [ServerProxy].
extension ServerProxyMasterDataWrites on ServerProxy {
  // ═══════════════════════════════════════════════════════════════
  // Parties
  // ═══════════════════════════════════════════════════════════════

  Future<int?> createParty(Map<String, dynamic> partyData, {String? idempotencyKey}) async {
    final result = await post('/api/parties', partyData, idempotencyKey: idempotencyKey);
    return result['serverId'] as int?;
  }

  Future<void> updateParty(int id, Map<String, dynamic> partyData, {String? idempotencyKey}) async {
    await put('/api/parties/$id', partyData, idempotencyKey: idempotencyKey);
  }

  Future<void> deleteParty(int id, {String? idempotencyKey}) async {
    await delete('/api/parties/$id', idempotencyKey: idempotencyKey);
  }

  // ═══════════════════════════════════════════════════════════════
  // Products
  // ═══════════════════════════════════════════════════════════════

  /// Lookup a product by barcode on the server — used as CLIENT-mode fallback
  /// when the barcode isn't found in the local cache (e.g. product assigned to
  /// a different warehouse and therefore not included in the branch sync).
  /// Returns the raw JSON map from the server, or null if not found / offline.
  Future<Map<String, dynamic>?> fetchProductByBarcode(String barcode, {int? branchId}) async {
    try {
      final encodedBarcode = Uri.encodeComponent(barcode);
      final branchParam = branchId != null ? '&branch_id=$branchId' : '';
      final url = Uri.parse('$_baseUrl/api/products/barcode?barcode=$encodedBarcode$branchParam');
      debugPrint('[ServerProxy] GET /api/products/barcode?barcode=$barcode$branchParam');
      final response = await TlsTrust.httpClient()
          .get(url, headers: _authHeaders)
          .timeout(const Duration(seconds: 5));
      if (_isSuccessStatusCode(response.statusCode)) {
        final body = json.decode(response.body) as Map<String, dynamic>;
        if (body['found'] == true) return body;
      }
      return null;
    } catch (e) {
      debugPrint('[ServerProxy] fetchProductByBarcode error (offline?): $e');
      return null;
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // Categories
  // ═══════════════════════════════════════════════════════════════

  Future<int?> createCategory({
    required String name,
    required String color,
    int? printerId,
    String? iconName,
    bool isGlobal = true,
    List<int>? branchIds,
    String? globalId,
    String? idempotencyKey,
  }) async {
    final response = await post('/api/categories', {
      'globalId': ?globalId,
      'name': name,
      'color': color,
      'printerId': printerId,
      'iconName': iconName,
      'isGlobal': isGlobal,
      'branchIds': ?branchIds,
    }, idempotencyKey: idempotencyKey);
    return response['id'] as int?;
  }

  Future<void> updateCategory({
    required int id,
    required String name,
    required String color,
    int? printerId,
    String? iconName,
    bool isGlobal = true,
    List<int>? branchIds,
    String? idempotencyKey,
  }) async {
    await put('/api/categories/$id', {
      'name': name,
      'color': color,
      'printerId': printerId,
      'iconName': iconName,
      'isGlobal': isGlobal,
      'branchIds': ?branchIds,
    }, idempotencyKey: idempotencyKey);
  }

  /// FIX 3.4: idempotencyKey added so outbox replay prevents double-deletes.
  /// Feature 045: [moveToCategoryId] is forwarded as a query string so the
  /// server's `deleteCategory` handler can run the bulk-move inside its
  /// soft-delete transaction. A literal null on the wire (`?moveTo=` empty
  /// or absent) means "leave products uncategorized".
  Future<void> deleteCategory(
    int id, {
    int? moveToCategoryId,
    String? idempotencyKey,
  }) async {
    final qs = moveToCategoryId != null
        ? '?moveToCategoryId=$moveToCategoryId'
        : '';
    await delete('/api/categories/$id$qs', idempotencyKey: idempotencyKey);
  }

  // ═══════════════════════════════════════════════════════════════
  // Warehouses
  // ═══════════════════════════════════════════════════════════════

  Future<int?> createWarehouse({
    required String name,
    int? branchId,
    String? globalId,
  }) async {
    final response = await post('/api/warehouses', {
      'name': name,
      'branchId': branchId,
      'globalId': ?globalId,
    });
    return response['id'] as int?;
  }

  Future<void> updateWarehouse(int id, Map<String, dynamic> fields, {String? idempotencyKey}) async {
    await put('/api/warehouses/$id', fields, idempotencyKey: idempotencyKey);
  }

  Future<void> setDefaultWarehouse(int id, {String? idempotencyKey}) async {
    await put('/api/warehouses/$id', {'setDefault': true}, idempotencyKey: idempotencyKey);
  }

  Future<void> unsetDefaultWarehouse(int id, {String? idempotencyKey}) async {
    await put('/api/warehouses/$id', {'unsetDefault': true}, idempotencyKey: idempotencyKey);
  }

  Future<void> deleteWarehouse(int id, {String? idempotencyKey}) async {
    await delete('/api/warehouses/$id', idempotencyKey: idempotencyKey);
  }

  // ═══════════════════════════════════════════════════════════════
  // Branches (Feature 006 / MM.C — mirror-mode admin CRUD)
  // ═══════════════════════════════════════════════════════════════

  Future<int?> createBranch(
    Map<String, dynamic> data, {
    String? idempotencyKey,
  }) async {
    final result = await post('/api/branches', data, idempotencyKey: idempotencyKey);
    return result['id'] as int?;
  }

  Future<void> updateBranch(int id, Map<String, dynamic> data, {String? idempotencyKey}) async {
    await put('/api/branches/$id', data, idempotencyKey: idempotencyKey);
  }

  Future<void> deleteBranch(
    int id, {
    int? reassignUsersToBranchId,
    String? idempotencyKey,
  }) async {
    // Feature 049 (v131) — forward `reassignUsersToBranchId` via query
    // string so the server-side handler runs the bulk-reassign +
    // soft-delete inside one transaction. Null means "no reassign";
    // the server then throws the Arabic FK-prevention error.
    final qs = reassignUsersToBranchId != null
        ? '?reassignUsersToBranchId=$reassignUsersToBranchId'
        : '';
    await delete('/api/branches/$id$qs', idempotencyKey: idempotencyKey);
  }

  // ════════════════════════════════════════════════════════════
  // Floor Plan — مخطَّطُ القاعة (Client → Server) · v174 / قسمُ ٧
  // ════════════════════════════════════════════════════════════

  /// المخطَّطُ كلُّه بمعرّفاتٍ **عالميّة** — لا أرقامٍ محلّيّةٍ للقسم
  /// ولا للطاولات ولا للمعالم: رقمٌ محلّيٌّ قد يخصُّ قسماً آخرَ
  /// تماماً على الخادم — فيُعاد ترتيبُ صالةٍ لم يمسّها أحد.
  Future<void> submitFloorPlan(
    Map<String, dynamic> document, {
    String? idempotencyKey,
  }) async {
    await post('/api/floor-plan', document, idempotencyKey: idempotencyKey);
  }

  /// Audit B DATA-001 — full snapshot of a table reservation (global ids).
  Future<void> submitTableReservation(
    Map<String, dynamic> document, {
    String? idempotencyKey,
  }) async {
    await post('/api/table-reservations', document,
        idempotencyKey: idempotencyKey);
  }

  // ════════════════════════════════════════════════════════════
  // Attachments — مرفقاتُ المستندات (Client ↔ Server) · v176 / §٨
  // ════════════════════════════════════════════════════════════

  /// الوصفُ والبايتاتُ معاً — والهُويّةُ العالميّةُ مختومةٌ من فوق،
  /// فإعادةُ الإرسال تُعرَف على الخادم ولا تُنتج مرفقاً ثانياً.
  Future<void> submitAttachment(
    Map<String, dynamic> document, {
    String? idempotencyKey,
  }) async {
    await post('/api/attachments', document, idempotencyKey: idempotencyKey);
  }

  Future<void> submitAttachmentDelete(
    Map<String, dynamic> document, {
    String? idempotencyKey,
  }) async {
    await post('/api/attachments/delete', document,
        idempotencyKey: idempotencyKey);
  }

  /// بايتاتُ مرفقٍ — **جلبٌ كسولٌ عند الفتح لا سحبٌ دوريّ**.
  ///
  /// ومهلتُها أطولُ من سائر النداءات: خمسةُ ميغا على شبكةٍ محلّيّةٍ
  /// بطيئةٍ تتجاوز الخمسَ ثوانٍ بسهولة، وانقطاعٌ هنا يُظهِر المرفقَ
  /// مكسوراً لا «يُحمَّل».
  Future<Uint8List?> fetchAttachmentBytes(String globalId) async {
    try {
      final url = Uri.parse(
          '$_baseUrl/api/attachments/${Uri.encodeComponent(globalId)}');
      final response = await TlsTrust.httpClient()
          .get(url, headers: _authHeaders)
          .timeout(const Duration(seconds: 30));
      if (!_isSuccessStatusCode(response.statusCode)) return null;
      final body = json.decode(response.body) as Map<String, dynamic>;
      if (body['success'] != true) return null;
      final b64 = body['bytesBase64'] as String?;
      if (b64 == null || b64.isEmpty) return null;
      return base64Decode(b64);
    } catch (e) {
      debugPrint('[ServerProxy] fetchAttachmentBytes error: $e');
      return null;
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // Units of Measure (UOM)
  // ═══════════════════════════════════════════════════════════════

  // ═══════════════════════════════════════════════════════════════
  // UNITS & BARCODES
  // ═══════════════════════════════════════════════════════════════

  Future<int?> submitUnit(Map<String, dynamic> data, {String? idempotencyKey}) async {
    final res = await post('/api/units', data, idempotencyKey: idempotencyKey);
    return res['serverId'] as int?;
  }

  Future<bool> updateUnit(int id, Map<String, dynamic> data, {String? idempotencyKey}) async {
    await put('/api/units/$id', data, idempotencyKey: idempotencyKey);
    return true;
  }

  Future<bool> deleteUnit(int id, {String? idempotencyKey}) async {
    await delete('/api/units/$id', idempotencyKey: idempotencyKey);
    return true;
  }

  Future<int?> submitProductUnitMapping(Map<String, dynamic> data, {String? idempotencyKey}) async {
    final res = await post('/api/product-units', data, idempotencyKey: idempotencyKey);
    return res['serverId'] as int?;
  }

  Future<bool> updateProductUnitMapping(int id, Map<String, dynamic> data, {String? idempotencyKey}) async {
    await put('/api/product-units/$id', data, idempotencyKey: idempotencyKey);
    return true;
  }

  Future<bool> deleteProductUnitMapping(int id, {String? idempotencyKey}) async {
    await delete('/api/product-units/$id', idempotencyKey: idempotencyKey);
    return true;
  }

  Future<int?> submitProductBarcode(Map<String, dynamic> data, {String? idempotencyKey}) async {
    final res = await post('/api/product-barcodes', data, idempotencyKey: idempotencyKey);
    return res['serverId'] as int?;
  }

  Future<bool> deleteProductBarcode(int id, {String? idempotencyKey}) async {
    await delete('/api/product-barcodes/$id', idempotencyKey: idempotencyKey);
    return true;
  }

  // ═══════════════════════════════════════════════════════════════
  // Regions
  // ═══════════════════════════════════════════════════════════════

  Future<List<Map<String, dynamic>>?> fetchRegions() async {
    try {
      final url = Uri.parse('$_baseUrl/api/regions');
      debugPrint('[ServerProxy] GET /api/regions');
      final response = await TlsTrust.httpClient()
          .get(url, headers: _authHeaders)
          .timeout(const Duration(seconds: 10));
      if (_isSuccessStatusCode(response.statusCode)) {
        final body = json.decode(response.body) as Map<String, dynamic>;
        final list = body['regions'] as List;
        return list.cast<Map<String, dynamic>>();
      }
    } catch (e) {
      debugPrint('[ServerProxy] fetchRegions error: $e');
    }
    return null;
  }

  Future<int?> createRegion({
    required String name,
    String? address,
    String? phone,
    int? costCenterId,
  }) async {
    final result = await post('/api/regions', {
      'name': name,
      'address': address,
      'phone': phone,
      'costCenterId': costCenterId,
    });
    return result['id'] as int?;
  }

  Future<bool> updateRegion({
    required int id,
    required String name,
    String? address,
    String? phone,
    int? costCenterId,
  }) async {
    await put('/api/regions/$id', {
      'name': name,
      'address': address,
      'phone': phone,
      'costCenterId': costCenterId,
    });
    return true;
  }

  // ═══════════════════════════════════════════════════════════════
  // S4.1: Party Groups
  // ═══════════════════════════════════════════════════════════════

  Future<int?> createPartyGroup(
    Map<String, dynamic> data, {
    String? idempotencyKey,
  }) async {
    final result = await post('/api/party-groups', data, idempotencyKey: idempotencyKey);
    return result['id'] as int?;
  }

  Future<bool> updatePartyGroup(
    int id,
    Map<String, dynamic> data, {
    String? idempotencyKey,
  }) async {
    await put('/api/party-groups/$id', data, idempotencyKey: idempotencyKey);
    return true;
  }

  Future<bool> deletePartyGroup(int id, {String? idempotencyKey}) async {
    await delete('/api/party-groups/$id', idempotencyKey: idempotencyKey);
    return true;
  }

  // ═══════════════════════════════════════════════════════════════
  // S4.1: Printers
  // ═══════════════════════════════════════════════════════════════

  Future<int?> createPrinter(
    Map<String, dynamic> data, {
    String? idempotencyKey,
  }) async {
    final result = await post('/api/printers', data, idempotencyKey: idempotencyKey);
    return result['id'] as int?;
  }

  Future<bool> updatePrinter(
    int id,
    Map<String, dynamic> data, {
    String? idempotencyKey,
  }) async {
    await put('/api/printers/$id', data, idempotencyKey: idempotencyKey);
    return true;
  }

  Future<bool> deletePrinter(int id, {String? idempotencyKey}) async {
    await delete('/api/printers/$id', idempotencyKey: idempotencyKey);
    return true;
  }
}
