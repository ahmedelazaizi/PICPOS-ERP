// ApiDataHandler - landed cost, floor plan, manufacturing and booking deposit endpoints.
part of '../api_data_handler.dart';

/// Landed-cost, floor-plan, manufacturing and booking-deposit endpoints of [ApiDataHandler].
extension ApiDataOperationsRoutes on ApiDataHandler {
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
      return ApiErrors.failJson(e, st);
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
      return ApiErrors.failJson(e, st);
    }
  }

  /// POST /api/table-reservations — audit B DATA-001.
  ///
  /// لقطةٌ كاملةٌ لحجز طاولةٍ من عميل، تُطابَق بـglobalId (idempotent).
  /// طاولةٌ لم تصل بعدُ ⇒ 409 + retry فيعيد طابورُ العميل المحاولة.
  Future<Response> postTableReservation(Request request) async {
    try {
      final perm = await ApiUserCtx.requirePermission(
          request, db, PermissionCodes.tablesReserve);
      if (perm != null) return perm;

      return await ApiHandlerBase.withBroadcast<Response>(
        endpointLabel: 'postTableReservation',
        tables: const {'table_reservations', 'restaurant_tables'},
        body: () async {
          final data =
              json.decode(await request.readAsString()) as Map<String, dynamic>;
          try {
            final id = await applyTableReservationSnapshot(db, data);
            return jsonResponse({'success': true, 'serverId': id});
          } on TableReservationDependencyMissing catch (e) {
            return jsonResponse(
                {'success': false, 'error': e.message, 'retry': true},
                statusCode: 409);
          } on ArgumentError catch (e) {
            return jsonResponse(
                {'success': false, 'error': '${e.message}'},
                statusCode: 400);
          }
        },
      );
    } catch (e, st) {
      debugPrint('[API] postTableReservation failed: $e\n$st');
      return ApiErrors.failJson(e, st);
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
      return ApiErrors.failJson(e, st);
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
      return ApiErrors.failJson(e, st);
    }
  }
}
