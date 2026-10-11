// ApiHandler - table-bill page/API and guest order requests.
part of '../api_handler.dart';

/// table-bill page/API and guest order requests (see [ApiHandler]).
extension ApiHandlerTableGuestRoutes on ApiHandler {
  // ═══════════════════════════════════════════════════════════════
  // حسابُ الطاولة على هاتف الزبون — البندُ الأوّل (2026-09-12)
  // ═══════════════════════════════════════════════════════════════
  //
  // ⚠️ **ثلاثةُ حرّاسٍ متعاقبةٍ على كلّ مسار، بهذا الترتيب:**
  //    ١. الرايةُ مُشعَلة — والافتراضُ مُطفأ، فتنصيبةٌ لم تطلب الميزةَ لا
  //       تفتح مساراً بلا مصادقةٍ لمجرّد أنها رقّت.
  //    ٢. التوقيعُ صحيح — يمنع تخمينَ أرقام الطاولات وتبديلَها.
  //    ٣. الطاولةُ لها طلبٌ مفتوح — ولا يُكشَف الفرقُ بين «لا طاولة» و«لا
  //       طلب»، فالجوابُ واحدٌ في الحالتين.
  //
  // ⚠️ **ولا `_error` بنصٍّ تشخيصيّ**: هذه المسارات يقرؤها غريبٌ على شبكة
  //    المحلّ، ورسالةٌ تقول «الطاولة ٧ غير موجودة» تُحوِّل التخمينَ إلى مسح.

  /// هل ميزةُ رمز حساب الطاولة مُشعَلة؟ مُطفأةٌ ما لم تُكتَب `true` صراحةً.
  Future<bool> _tableBillEnabled() async =>
      (await _db.getSettingValue(kTableBillQrEnabledKey)) == 'true';

  /// هل الخادمُ منشورٌ على دومينٍ عامّ؟
  ///
  /// ⚠️ **وهذا السؤالُ أمنيٌّ لا عرضيّ.** جوابُه `true` يعني أن حاجزَ الشبكة
  /// المحلّيّة سقط، فيُشترَط الرقمُ القصير على كلّ كتابة. واشتقاقُه من
  /// **وجود العنوان** لا من إعدادٍ ثالثٍ مستقلٍّ مقصود: إعدادان يصفان نفسَ
  /// الحقيقة يفترقان، ومن ينشر على دومينٍ وينسى الثانيَ يفتح الكتابةَ للعالم.
  Future<bool> _tableBillIsPublic() async =>
      normalizeTableBillBaseUrl(
        await _db.getSettingValue(kTableBillPublicBaseUrlKey),
      ) !=
      null;

  /// يفحص الرقمَ القصير حين يكون الخادمُ عامّاً. `null` = مسموح.
  Future<Response?> _requireSessionPin(
    Map<String, dynamic> body,
    TableOrder order,
  ) async {
    if (!await _tableBillIsPublic()) return null;
    final ok = TableBillToken.verifySessionPin(
      body['pin'] as String?,
      orderId: order.id,
      openedAt: order.openedAt,
    );
    if (ok) return null;
    return _json({
      'success': false,
      'pinRequired': true,
      'error': 'اطلب رقمَ الطاولة من النادل',
    });
  }

  /// الطلبُ المفتوحُ على الطاولة الموقَّعة في [token]، أو `null`.
  ///
  /// ⚠️ و«مفتوح» تشمل `bill_requested`: الضيفُ طلب الحساب ثمّ فتح الصفحةَ
  /// ثانيةً ليراجع — وإخفاؤه عنه حينَها يبدو كأنّ حسابَه ضاع.
  Future<TableOrder?> _openOrderForToken(String token) async {
    final tableId = TableBillToken.verifyTable(token);
    if (tableId == null) return null;
    final rows = await (_db.select(_db.tableOrders)
          ..where((o) => o.tableId.equals(tableId))
          ..where((o) => o.status.isIn(['open', 'bill_requested']))
          ..orderBy([(o) => OrderingTerm.desc(o.openedAt)])
          ..limit(1))
        .get();
    return rows.isEmpty ? null : rows.first;
  }

  Future<Response> _getTableBillPage(Request request, String token) async {
    if (!await _tableBillEnabled()) return _notFound(request);
    return Response.ok(
      tableBillHtmlTemplate,
      headers: {'Content-Type': 'text/html; charset=utf-8'},
    );
  }

  Future<Response> _getTableBill(Request request, String token) async {
    if (!await _tableBillEnabled()) return _notFound(request);
    try {
      final order = await _openOrderForToken(token);
      if (order == null) return _json({'success': true, 'open': false});

      final items = await (_db.select(_db.tableOrderItems)
            ..where((i) => i.tableOrderId.equals(order.id))
            ..orderBy([(i) => OrderingTerm.asc(i.addedAt)]))
          .get();

      // ⚠️ **المحرّكُ الواحدُ لا حسابٌ رابع.** `TableOrderTotals.compute` هو
      // ما تحسب به الشاشةُ والطباعةُ والتحصيل، وجمعُ `quantity × unitPrice`
      // هنا كان يعرض على هاتف الضيف رقماً يخالف ما يُطبَع في يده كلّما كان
      // على الطلب خصمٌ أو ضريبة.
      final totals = await TableSessionService(_db).totalsFor(order.id);

      final table = await (_db.select(_db.restaurantTables)
            ..where((t) => t.id.equals(order.tableId)))
          .getSingleOrNull();

      final products = {
        for (final p in await (_db.select(_db.products)
              ..where((p) => p.id.isIn(items.map((i) => i.productId).toSet())))
            .get())
          p.id: p.name,
      };

      final shopName =
          await _db.getSettingValue('company_name') ?? AppConfig.appNameAr;
      final remaining = totals.total - order.paidAmount;

      return _json({
        'success': true,
        'open': true,
        'shopName': shopName,
        'tableName': table?.name ?? '—',
        'guestCount': order.guestCount,
        'billRequested': order.status == 'bill_requested',
        // ⚠️ **تُقرأ من الخادم لا تُفترَض في الصفحة**: زرٌّ يظهر وميزتُه
        // مطفأةٌ يعطي الضيفَ وعداً يُرَدُّ عليه بخطأٍ بعد أن يختار.
        'guestOrder': await _guestOrderEnabled(),
        // ⚠️ **ولا يُرسَل الرقمُ نفسُه بحال.** الصفحةُ تعرف أنه مطلوبٌ فقط،
        // والرقمُ يُقال شفاهاً من النادل. وإرسالُه مع القراءة كان يُلغيه
        // تماماً: من يقرأ عن بُعدٍ يأخذه ويكتب.
        'pinRequired': await _tableBillIsPublic(),
        'pendingRequests':
            GuestOrderRequests.instance.forOrder(order.id).length,
        // رمزُ الجلسة — الكتابةُ لا تُقبَل بدونه، ويموت بإغلاق الطلب.
        'session':
            TableBillToken.mintSession(orderId: order.id, openedAt: order.openedAt),
        'items': [
          for (var i = 0; i < items.length; i++)
            {
              'name': products[items[i].productId] ?? '—',
              'qty': items[i].quantity,
              'unitPrice': items[i].unitPrice,
              // حصّةُ البند من المستحقّ — نصيبُه من الخصم وضريبتُه فوقه،
              // فمجموعُ ما يقرؤه الضيفُ يساوي المستحقَّ بالضبط.
              'total': i < totals.lineTotals.length
                  ? totals.lineTotals[i]
                  : items[i].total,
              'notes': items[i].notes,
            },
        ],
        'subtotal': totals.subtotal,
        'discount': totals.discount,
        'taxAmount': totals.taxAmount,
        'total': totals.total,
        'paidAmount': order.paidAmount,
        'remaining': remaining < 0 ? 0 : remaining,
      });
    } catch (e) {
      debugPrint('[TABLE-BILL] read failed: $e');
      return _json({'success': false, 'error': 'تعذّر عرض الحساب'});
    }
  }


  // ═══════════════════════════════════════════════════════════════
  // طلباتُ الضيوف — من الهاتف إلى طابورٍ ينتظر اعتمادَ النادل
  // ═══════════════════════════════════════════════════════════════

  /// هل يُسمَح للضيف بطلبِ أصنافٍ من هاتفه؟ رايةٌ ثانيةٌ مطفأةٌ افتراضاً.
  Future<bool> _guestOrderEnabled() async =>
      (await _db.getSettingValue(kTableBillGuestOrderEnabledKey)) == 'true';

  /// الضيفُ يطلب أصنافاً — تدخل **الطابورَ** لا الحساب.
  ///
  /// ⚠️ **ولا سعرَ يُقرأ من الجسم.** المصدرُ هاتفٌ غيرُ مصادَق؛ وسعرٌ يأتي
  /// منه سعرٌ يكتبه الزبون. المقبولُ معرِّفُ صنفٍ وكمّيّةٌ وملاحظة، والتسعيرُ
  /// يقع عند الاعتماد من `Products.salePrice` كما لو أدخله النادلُ بيده.
  // EXEMPT-PER-USER: مسارُ **ضيفٍ** لا مستخدم — لا جلسةَ له ولا صلاحيّة، فـ
  // `ApiUserCtx.requirePermission` ترفضه 401 دائماً. وبديلُها ثلاثةُ حرّاسٍ
  // مقيسةٌ في `guest_order_request_api_test`: رايتان مطفأتان افتراضاً،
  // وتوقيعُ الطاولة، ورمزُ الجلسة. ولا يكتب هذا المعالجُ في القاعدة أصلاً —
  // يُدرج في طابورٍ في الذاكرة لا يبلغ الحسابَ إلّا باعتمادِ مستخدمٍ
  // **مصادَقٍ** عبر `/api/table-requests/<id>/approve` المحروسِ بـ
  // `tables_view`.
  Future<Response> _addGuestOrderRequest(Request request, String token) async {
    if (!await _tableBillEnabled()) return _notFound(request);
    if (!await _guestOrderEnabled()) {
      return _json({'success': false, 'error': 'الطلبُ من الهاتف غيرُ مفعَّل'});
    }
    try {
      final order = await _openOrderForToken(token);
      if (order == null) {
        return _json({'success': false, 'error': 'لا حساب مفتوحاً'});
      }

      final body = await request.readAsString();
      if (body.isEmpty) {
        return _json({'success': false, 'error': 'طلبٌ فارغ'});
      }
      final map = json.decode(body) as Map<String, dynamic>;
      if (!TableBillToken.verifySession(
        map['session'] as String?,
        orderId: order.id,
        openedAt: order.openedAt,
      )) {
        return _json({'success': false, 'error': 'انتهت الجلسة — حدِّث الصفحة'});
      }
      if (await _requireSessionPin(map, order) case final blocked?) {
        return blocked;
      }

      final raw = map['items'];
      if (raw is! List || raw.isEmpty) {
        return _json({'success': false, 'error': 'لم تختر أصنافاً'});
      }

      final lines = <GuestOrderLine>[];
      for (final entry in raw) {
        if (entry is! Map) continue;
        final pid = (entry['productId'] as num?)?.toInt() ?? 0;
        final qty = (entry['qty'] as num?)?.toDouble() ?? 0;
        final note = entry['note'] as String?;
        lines.add(GuestOrderLine(
          productId: pid,
          quantity: qty,
          // ملاحظةُ الضيف تصل المطبخَ وتُطبع، فتُقَصّ عند حدٍّ معقول.
          note: (note == null || note.trim().isEmpty)
              ? null
              : note.trim().substring(0, note.trim().length.clamp(0, 120)),
        ));
      }

      // ⚠️ **وجودُ الصنف يُتحقَّق هنا لا عند الاعتماد**: معرِّفٌ ملفَّقٌ كان
      // يدخل الطابورَ فيرى النادلُ سطراً بلا اسمٍ لا يستطيع اعتمادَه ولا
      // يفهم من أين جاء.
      final ids = {for (final l in lines) l.productId};
      final known = {
        for (final p in await (_db.select(_db.products)
              ..where((p) => p.id.isIn(ids))
              ..where((p) => p.isActive.equals(true)))
            .get())
          p.id,
      };
      if (lines.any((l) => !known.contains(l.productId))) {
        return _json({'success': false, 'error': 'صنفٌ غيرُ متاح'});
      }

      final table = await (_db.select(_db.restaurantTables)
            ..where((t) => t.id.equals(order.tableId)))
          .getSingleOrNull();

      final id = GuestOrderRequests.instance.enqueue(
        tableId: order.tableId,
        orderId: order.id,
        tableName: table?.name ?? '—',
        lines: lines,
      );
      if (id == null) {
        return _json({
          'success': false,
          'error': 'طلباتُك المعلَّقةُ كثيرة — انتظر النادل',
        });
      }

      // الشاشاتُ تُنبَّه بجدولٍ قائمٍ: لا جدولَ لهذا الطابور، و`table_orders`
      // هو ما تشترك فيه شاشةُ الطاولات أصلاً.
      await ApiHandlerBase.withBroadcast(
        endpointLabel: 'POST /api/table-bill/<token>/add',
        tables: {'table_orders'},
        body: () async {},
      );
      return _json({'success': true});
    } catch (e) {
      debugPrint('[TABLE-BILL] guest add failed: $e');
      return _json({'success': false, 'error': 'تعذّر إرسال الطلب'});
    }
  }

  /// ما ينتظر اعتمادَ النادل — يقرؤه جهازٌ **مقترنٌ** لا هاتفُ ضيف.
  Future<Response> _listGuestOrderRequests(Request request) async {
    final perm = await ApiUserCtx.requirePermission(
        request, _db, PermissionCodes.tablesView);
    if (perm != null) return perm;

    return _json({
      'success': true,
      'requests': [
        for (final r in GuestOrderRequests.instance.pending)
          {
            'id': r.id,
            'tableId': r.tableId,
            'orderId': r.orderId,
            'tableName': r.tableName,
            'at': r.at.toIso8601String(),
            'lines': [
              for (final l in r.lines)
                {
                  'productId': l.productId,
                  'qty': l.quantity,
                  'note': l.note,
                },
            ],
          },
      ],
    });
  }

  /// اعتمادُ طلبِ ضيفٍ — يدخل الحسابَ عبر مسار الإضافة القائم.
  ///
  /// ⚠️ **والسعرُ يُقرأ الآن من المنتج، ولقطةُ الضريبة معه.** المرورُ بـ
  /// `addOrUpdateTableOrderItem` هو ما يجعل صنفَ الضيف مطابقاً لما يُدخِله
  /// النادلُ بيده: نفسُ الدمج مع بندٍ قائم، ونفسُ قاعدةِ «لا تُطمَس نسبةٌ
  /// محفوظة»، ونفسُ تحديثِ إجماليّ الطلب.
  Future<Response> _approveGuestOrderRequest(Request request, String id) async {
    final perm = await ApiUserCtx.requirePermission(
        request, _db, PermissionCodes.tablesView);
    if (perm != null) return perm;

    final requestId = int.tryParse(id);
    if (requestId == null) return _json({'success': false, 'error': 'معرّفٌ غيرُ صالح'});

    // ⚠️ المنطقُ في [GuestOrderApproval] لا هنا: جهازُ الخادم يعتمد من شاشته
    // **مباشرةً** بلا مرورٍ بـHTTP، فنسخةٌ ثانيةٌ هنا تعني بنداً يدخل الحسابَ
    // بسعرٍ أو ضريبةٍ مختلفةٍ بحسب الجهاز الذي ضُغط عليه الزرّ.
    final outcome = await ApiHandlerBase.withBroadcast(
      endpointLabel: 'POST /api/table-requests/<id>/approve',
      tables: {'table_orders', 'restaurant_tables'},
      body: () => GuestOrderApproval(_db).approve(requestId),
    );

    return switch (outcome) {
      GuestApprovalOutcome.approved => _json({'success': true}),
      GuestApprovalOutcome.notPending =>
        _json({'success': false, 'error': 'الطلبُ لم يعد معلَّقاً'}),
      GuestApprovalOutcome.orderClosed =>
        _json({'success': false, 'error': 'الطاولةُ أُغلقت'}),
      GuestApprovalOutcome.failed =>
        _json({'success': false, 'error': 'تعذّر الاعتماد'}),
    };
  }

  Future<Response> _rejectGuestOrderRequest(Request request, String id) async {
    final perm = await ApiUserCtx.requirePermission(
        request, _db, PermissionCodes.tablesView);
    if (perm != null) return perm;

    final requestId = int.tryParse(id);
    if (requestId == null) {
      return _json({'success': false, 'error': 'معرّفٌ غيرُ صالح'});
    }
    return _json({'success': GuestOrderRequests.instance.reject(requestId)});
  }

  /// «اطلب الحساب» — ينقل الطلبَ إلى `bill_requested` ويُنبّه الشاشات.
  // EXEMPT-PER-USER: مسارُ **ضيفٍ** لا مستخدم — انظر
  // `_addGuestOrderRequest`. وأثرُه الوحيدُ نقلُ الحالة إلى `bill_requested`
  // أي مناداةُ النادل: لا مبلغَ ولا صنفَ ولا سطرَ دفتر. وحارسُه رمزُ الجلسة
  // الذي لا يُنال إلّا بقراءةِ حسابٍ مفتوحٍ الآن على تلك الطاولة.
  Future<Response> _requestTableBill(Request request, String token) async {
    if (!await _tableBillEnabled()) return _notFound(request);
    try {
      final order = await _openOrderForToken(token);
      if (order == null) {
        return _json({'success': false, 'error': 'لا حساب مفتوحاً'});
      }

      // ⚠️ **رمزُ الجلسة شرطُ الكتابة.** رمزُ الطاولة مطبوعٌ وملصوقٌ ولا
      // ينتهي، فمن مسحه مرّةً كان يستطيع مناداةَ النادل لطاولةٍ يجلس عليها
      // غيرُه بعد شهر. ورمزُ الجلسة لا يُنال إلّا بقراءةِ حسابٍ **مفتوحٍ
      // الآن**، ويموت بإغلاقه.
      final raw = await request.readAsString();
      final body = raw.isEmpty
          ? const <String, dynamic>{}
          : json.decode(raw) as Map<String, dynamic>;
      final valid = TableBillToken.verifySession(
        body['session'] as String?,
        orderId: order.id,
        openedAt: order.openedAt,
      );
      if (!valid) {
        return _json({'success': false, 'error': 'انتهت الجلسة — حدِّث الصفحة'});
      }
      // ⚠️ والرقمُ القصير **بعد** رمز الجلسة لا قبله: رمزُ الجلسة يُثبت أن
      // الطلبَ مفتوحٌ الآن، والرقمُ يُثبت أن الطالبَ في المحلّ. وترتيبُهما
      // يجعل رسالةَ «انتهت الجلسة» تسبق «اطلب الرقم» — وهي الأصحُّ للضيف
      // الذي تُركت صفحتُه مفتوحةً من جلسةٍ سابقة.
      if (await _requireSessionPin(body, order) case final blocked?) {
        return blocked;
      }

      // ساكنٌ عند التكرار: ضغطتان لا تُنتجان نداءَين ولا تُرجعان خطأً.
      if (order.status != 'bill_requested') {
        // ⚠️ `withBroadcast` لا `broadcast` مباشرةً — عقدُ مواصفة ١٢٩
        // يحرسه `no_manual_broadcast_test`. والجدولان معاً: شاشةُ الطاولات
        // تقرأ الحالةَ من `restaurant_tables` وقائمةُ الطلبات من
        // `table_orders`، فبثٌّ لأحدهما يترك النصفَ الآخرَ بلا إيقاظ.
        await ApiHandlerBase.withBroadcast(
          endpointLabel: 'POST /api/table-bill/<token>/request',
          tables: {'table_orders', 'restaurant_tables'},
          body: () async =>
              (_db.update(_db.tableOrders)..where((o) => o.id.equals(order.id)))
                  .write(const TableOrdersCompanion(
            status: Value('bill_requested'),
          )),
        );
      }
      return _json({'success': true});
    } catch (e) {
      debugPrint('[TABLE-BILL] request failed: $e');
      return _json({'success': false, 'error': 'تعذّر الإرسال'});
    }
  }

}
