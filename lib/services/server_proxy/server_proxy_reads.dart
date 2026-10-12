// ServerProxy - guest-order queue, delta pull, server time and admin verification.
part of '../server_proxy.dart';

/// Read-side calls of [ServerProxy]: guest-order requests, delta pull, branch-scope
/// query param, server clock and mirror-mode admin verification.
extension ServerProxyReads on ServerProxy {
  // ═══════════════════════════════════════════════════════════════
  // طلباتُ الضيوف — الطابورُ يعيش في ذاكرة الخادم وحدَه
  // ═══════════════════════════════════════════════════════════════
  //
  // ⚠️ **ولا مِرآةَ له في القاعدة**، فلا تصل هذه الطلباتُ بالمزامنة كما يصل
  // كلُّ شيءٍ آخرَ تعرضه شاشةُ الطاولات. جهازُ العميل لا سبيلَ له إليها إلّا
  // بهذه النداءات، وبدونها كانت الشاشةُ تعرض «لا طلبات» على كلِّ جهازٍ ليس
  // هو الخادم — وهو أسوأُ من عدمها: نفيٌ يبدو يقيناً.

  /// ما ينتظر اعتمادَ النادل كما يراه الخادم. `null` = تعذّر السؤال.
  Future<List<Map<String, dynamic>>?> fetchGuestOrderRequests() async {
    try {
      final url = Uri.parse('$_baseUrl/api/table-requests');
      final response = await TlsTrust.httpClient()
          .get(url, headers: _authHeaders)
          .timeout(const Duration(seconds: 5));
      if (!_isSuccessStatusCode(response.statusCode)) return null;
      final body = json.decode(response.body) as Map<String, dynamic>;
      if (body['success'] != true) return null;
      return (body['requests'] as List).cast<Map<String, dynamic>>();
    } catch (e) {
      debugPrint('[ServerProxy] fetchGuestOrderRequests error: $e');
      return null;
    }
  }

  /// يعتمد طلبَ ضيفٍ على الخادم. والخطأُ يعود نصّاً ليُعرَض كما هو.
  Future<String?> approveGuestOrderRequest(int id) =>
      _guestRequestAction('/api/table-requests/$id/approve');

  Future<String?> rejectGuestOrderRequest(int id) =>
      _guestRequestAction('/api/table-requests/$id/reject');

  /// `null` عند النجاح، ونصُّ الخطأ عند الرفض.
  Future<String?> _guestRequestAction(String endpoint) async {
    try {
      final result = await post(endpoint, const {});
      if (result['success'] == true) return null;
      return (result['error'] as String?) ?? 'تعذّر التنفيذ';
    } catch (e) {
      debugPrint('[ServerProxy] $endpoint error: $e');
      return 'تعذّر الاتصال بالخادم';
    }
  }

  Future<int?> createProduct(Map<String, dynamic> productData, {String? idempotencyKey}) async {
    final result = await post('/api/products', productData, idempotencyKey: idempotencyKey);
    return result['serverId'] as int?;
  }

  Future<void> updateProduct(int id, Map<String, dynamic> productData, {String? idempotencyKey}) async {
    await put('/api/products/$id', productData, idempotencyKey: idempotencyKey);
  }

  Future<void> deleteProduct(int id, {String? idempotencyKey}) async {
    await delete('/api/products/$id', idempotencyKey: idempotencyKey);
  }

  // ─── P3.1: Delta Pull ────────────────────────────────────────────────────

  /// Fetch records from [table] that changed since [since] (epoch seconds).
  /// Returns `{ "rows": [...], "serverTime": <int epoch> }` or null on error.
  /// When [since] is null the server performs a full table dump.
  ///
  /// Phase 5A.3 (Issue 5) / المرحلة ١ G2: النداء يحمل `&branch_id=<id>` فيقصّ
  /// الخادمُ الجداولَ المحصورة قبل الإرسال. الإعفاء الوحيد من الحصر هو **مدير
  /// النظام** (وجهاز المرآة) — لا «المدير أو المدير المالي» كما كان هنا:
  /// تفصيل القرار في [_branchScopeQueryParam].
  /// Fetch one PAGE of a table's delta.
  ///
  /// [limit] bounds the rows the server materialises for this request; the
  /// response carries `hasMore`. [cursorTs]/[cursorId] are the keyset cursor
  /// for pages 2..N — the `(last_modified_at, id)` pair of the last row the
  /// caller applied. Callers must loop until `hasMore == false` before
  /// advancing their watermark (see `DeltaPullService.pullTable`).
  Future<Map<String, dynamic>?> fetchDelta(
    String table, {
    DateTime? since,
    int? limit,
    int? cursorTs,
    int? cursorId,
  }) async {
    try {
      final sinceParam = since != null
          ? '&since=${since.millisecondsSinceEpoch ~/ 1000}'
          : '';
      final limitParam = limit != null ? '&limit=$limit' : '';
      final cursorParam = (cursorTs != null && cursorId != null)
          ? '&cursorTs=$cursorTs&cursorId=$cursorId'
          : '';
      final branchParam = await _branchScopeQueryParam();
      final url = Uri.parse('$_baseUrl/api/sync/pull?table=$table'
          '$sinceParam$limitParam$cursorParam$branchParam');
      final response = await TlsTrust.httpClient()
          .get(url, headers: _authHeaders)
          .timeout(const Duration(seconds: 30));
      if (!_isSuccessStatusCode(response.statusCode)) {
        debugPrint('[ServerProxy] fetchDelta $table HTTP ${response.statusCode}');
        return null;
      }
      return json.decode(response.body) as Map<String, dynamic>;
    } catch (e) {
      debugPrint('[ServerProxy] fetchDelta $table: $e');
      return null;
    }
  }

  /// المرحلة ١ / G2 — يبني `&branch_id=<id>` لنداءات المزامنة المحصورة.
  ///
  /// **يُرجع `''` (بلا حصر) لمدير النظام وحده**، لأن إعداد البدء يحتاج
  /// قراءة البيانات الأساسية كاملة قبل ربط الجهاز بفرع.
  ///
  /// كان يستعمل [SyncInterceptor.isCurrentUserAdmin] — مطابقة نصّية على
  /// اسم الدور تمنح «مسؤول مبيعات» صلاحية كاملة. وكان يُرجع `''` أيضاً
  /// عندما لا يكون الجهاز مربوطاً بفرع، أي **يفشل مفتوحاً**: جهاز غير
  /// مُعَدّ كان يسحب بيانات الشركة كاملة. كلاهما مُغلق الآن.
  ///
  /// ⚠️ العلَم أدناه هو الاقتران `isSystemRole && name == 'مدير النظام'` كما
  /// ينشره متحكّم المصادقة — **لا** العمود `isSystemRole` وحده، فهو `true`
  /// لخمسة أدوار مزروعة منها الكاشير ومدير مالي.
  Future<String> _branchScopeQueryParam() async {
    if (SyncInterceptor.currentUserIsSystemAdmin == true) return '';

    // جهاز المرآة — بلا تغيير (المواصفة §٢). المرآة لا تكتب
    // `client_branch_id` إطلاقاً (يكتبه معالج الإعداد وشاشة وضع الشبكة
    // فقط)، فكانت هتقع على سنتينل `-1`. وبما أن الاقتران يمنحها توكن جلسة
    // أدمن مُتحقَّق منه، كان الخادم هيرجّع صفر صفوف بينما
    // `DeltaPullService.shouldWithholdWatermark` لا يحجب العلامة المائية
    // إلا للنداء **بلا توكن** ⇒ علامة مائية تتقدّم فوق استجابة فارغة
    // وفجوة دائمة. المرآة ليست جهاز فرع أصلاً: نطاقها الفروع كلها.
    if (SyncInterceptor.isMirrorMode) return '';

    final prefs = await SharedPreferences.getInstance();
    final id = prefs.getInt('client_branch_id');
    if (id == null) {
      // يفشل مقفولاً. السنتينل يطابق `ApiHandler._kNoBranchAccess` فيقصّ
      // الخادمُ الصفوفَ إلى صفر بدل أن يعيدها كلها.
      return '&branch_id=-1';
    }
    return '&branch_id=$id';
  }

  /// منفذ اختبار لـ[_branchScopeQueryParam]. المنطق أعلاه هو حدّ أمني،
  /// واختباره عبر نداء HTTP كامل يخلط فشله بفشل الشبكة.
  @visibleForTesting
  Future<String> debugBranchScopeQueryParam() => _branchScopeQueryParam();

  /// Returns the authoritative server clock (epoch seconds) from
  /// `/api/sync/time`. Falls back to `null` on failure — callers should
  /// then decide whether to retry or use a safe local approximation.
  Future<int?> fetchServerTime() async {
    try {
      final url = Uri.parse('$_baseUrl/api/sync/time');
      final response = await TlsTrust.httpClient()
          .get(url, headers: _authHeaders)
          .timeout(const Duration(seconds: 10));
      if (!_isSuccessStatusCode(response.statusCode)) return null;
      final body = json.decode(response.body) as Map<String, dynamic>;
      return body['serverTime'] as int?;
    } catch (e) {
      debugPrint('[ServerProxy] fetchServerTime: $e');
      return null;
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // Mirror-mode admin verification (Feature 006 / MM.C)
  // ═══════════════════════════════════════════════════════════════

  /// Outcome of a `verifyAdmin` call. Distinguishes wrong-password (401)
  /// from non-admin-role (403) so the wizard can surface a precise
  /// message — both are user-actionable but in different ways.
  Future<MirrorAdminVerification> verifyAdmin({
    required String username,
    required String password,
  }) async {
    try {
      final url = Uri.parse('$_baseUrl/api/auth/verify-admin');
      final response = await TlsTrust.httpClient()
          .post(
            url,
            headers: _authHeaders,
            body: json.encode({'username': username, 'password': password}),
          )
          .timeout(const Duration(seconds: 10));

      if (_isSuccessStatusCode(response.statusCode)) {
        final body = json.decode(response.body) as Map<String, dynamic>;
        final id = body['userId'];
        final userId = id is int
            ? id
            : (id is num ? id.toInt() : int.tryParse('${id ?? ''}'));
        if (userId == null) {
          return MirrorAdminVerification.failed(
            'Server response missing userId',
          );
        }
        return MirrorAdminVerification.success(
          userId: userId,
          displayName: (body['displayName'] as String?) ?? username,
          roleName: (body['roleName'] as String?) ?? '',
        );
      }
      if (response.statusCode == 401) {
        return MirrorAdminVerification.invalidCredentials();
      }
      if (response.statusCode == 403) {
        return MirrorAdminVerification.notAdmin();
      }
      return MirrorAdminVerification.failed(
        'HTTP ${response.statusCode}: ${response.body}',
      );
    } catch (e) {
      return MirrorAdminVerification.failed(e.toString());
    }
  }

  /// Push a single activity log entry from a client to the server.
  /// Uses the standard retry + idempotency-key pattern.
  Future<void> pushActivityLog(
    Map<String, dynamic> data, {
    String? idempotencyKey,
  }) async {
    await _postWithRetry(
      '/api/activity-logs/push',
      data,
      idempotencyKey: idempotencyKey,
    );
  }
}
