part of '../database.dart';

/// v185 — عمليّاتُ المندوب وتقاريرُه (المرحلة و).
///
/// • التحميل = تحويلُ مخزونٍ من المخزن الرئيس إلى مخزن السيارة، والتفريغ
///   عكسُه — كلاهما عبر [transferStock] نفسِه (حركتا مخزونٍ + قيدا التحويل).
/// • التسليم = تحويلٌ بين الخزائن من خزنة العهدة إلى الخزينة الرئيسة: صفّا
///   `safe_transactions` (صرفٌ من العهدة وقبضٌ في الرئيسة — نفسُ شكل
///   `postSafeTransfer` على الخادم) وقيدٌ بين حسابَي الخزنتين حين يختلفان.
/// • التقاريرُ تقرأ الختمَ (`rep_employee_id` / `route_id`) لا المسارَ
///   الحاليّ، فإعادةُ التوزيع لا تغيّر أرقامَ الماضي.
extension DistributionRepOpsDao on AppDatabase {
  /// LOAD — main warehouse → the rep's van. Returns the transfer bond id.
  Future<int> repLoadVan({
    required int repEmployeeId,
    required int fromWarehouseId,
    required List<Map<String, dynamic>> items,
    int? userId,
  }) async {
    final van = await _repVanWarehouse(repEmployeeId);
    if (van == fromWarehouseId) {
      throw DistributionException('المخزن المصدر هو مخزن السيارة نفسه.');
    }
    return transferStock(
      fromWarehouseId: fromWarehouseId,
      toWarehouseId: van,
      items: items,
      notes: 'تحميل سيارة المندوب #$repEmployeeId',
      userId: userId,
      globalId: UuidV7.generate(),
    );
  }

  /// UNLOAD — the rep's van → main warehouse. Returns the transfer bond id.
  Future<int> repUnloadVan({
    required int repEmployeeId,
    required int toWarehouseId,
    required List<Map<String, dynamic>> items,
    int? userId,
  }) async {
    final van = await _repVanWarehouse(repEmployeeId);
    if (van == toWarehouseId) {
      throw DistributionException('المخزن الوجهة هو مخزن السيارة نفسه.');
    }
    return transferStock(
      fromWarehouseId: van,
      toWarehouseId: toWarehouseId,
      items: items,
      notes: 'تفريغ سيارة المندوب #$repEmployeeId',
      userId: userId,
      globalId: UuidV7.generate(),
    );
  }

  Future<int> _repVanWarehouse(int repEmployeeId) async {
    final res = await getRepResources(repEmployeeId);
    final van = res?.vanWarehouseId;
    if (van == null) {
      throw DistributionException('لم يُحدَّد مخزن سيارة لهذا المندوب.');
    }
    return van;
  }

  /// HANDOVER — custody safe → main treasury [toSafeId]. Returns the id of
  /// the payment row on the custody safe.
  Future<int> handoverCustodyCash({
    required int repEmployeeId,
    required int toSafeId,
    required double amount,
    int? userId,
  }) {
    return transaction(() async {
      await accountingDao.validateFinancialPeriod(DateTime.now(),
          operation: 'تسليم عهدة');
      if (amount <= 0) throw DistributionException('المبلغ غير صالح.');
      final custodyId = (await getRepResources(repEmployeeId))?.custodySafeId;
      if (custodyId == null) {
        throw DistributionException('لم تُحدَّد خزنة عهدة لهذا المندوب.');
      }
      if (custodyId == toSafeId) {
        throw DistributionException('الخزينة الوجهة هي خزنة العهدة نفسها.');
      }
      final from = await (select(safes)..where((s) => s.id.equals(custodyId)))
          .getSingleOrNull();
      final to = await (select(safes)..where((s) => s.id.equals(toSafeId)))
          .getSingleOrNull();
      if (from == null || to == null) {
        throw DistributionException('الخزنة غير موجودة.');
      }
      if (from.balance + 0.0001 < amount) {
        throw DistributionException('رصيد العهدة لا يكفي.');
      }
      final gid = UuidV7.generate();
      final pv = await generateInvoiceNumber('PV');
      final rv = await generateInvoiceNumber('RV');
      final stamp = RepStamp(repEmployeeId: repEmployeeId);

      await adjustSafeBalance(from.id, -amount);
      final outId = await into(safeTransactions).insert(
        SafeTransactionsCompanion.insert(
          voucherNumber: pv,
          safeId: from.id,
          transactionType: 'payment',
          category: kRepHandoverCategory,
          amount: amount,
          balanceAfter: from.balance - amount,
          description: Value('تسليم عهدة المندوب → ${to.name}'),
          userId: Value(userId),
          employeeId: Value(repEmployeeId),
          globalId: Value(gid),
        ),
      );
      await adjustSafeBalance(to.id, amount);
      final inId = await into(safeTransactions).insert(
        SafeTransactionsCompanion.insert(
          voucherNumber: rv,
          safeId: to.id,
          transactionType: 'receipt',
          category: kRepHandoverCategory,
          amount: amount,
          balanceAfter: to.balance + amount,
          description: Value('تسليم عهدة المندوب ← ${from.name}'),
          userId: Value(userId),
          employeeId: Value(repEmployeeId),
          globalId: Value('$gid-in'),
        ),
      );
      await stampDocumentRep('safe_transactions', outId, null, explicit: stamp);
      await stampDocumentRep('safe_transactions', inId, null, explicit: stamp);

      final fromAccount = await _repSafeAccount(from);
      final toAccount = await _repSafeAccount(to);
      if (fromAccount == null || toAccount == null) {
        throw DistributionException('حساب الخزنة غير مربوط بدليل الحسابات.');
      }
      if (fromAccount != toAccount) {
        await accountingDao.createJournalEntry(
          description: 'تسليم عهدة المندوب ($pv)',
          date: DateTime.now(),
          lines: [
            JournalLine(
                accountId: toAccount,
                debit: amount,
                description: 'استلام عهدة من ${from.name}'),
            JournalLine(
                accountId: fromAccount,
                credit: amount,
                description: 'تسليم عهدة إلى ${to.name}'),
          ],
          referenceType: kRepHandoverCategory,
          referenceId: outId,
          isAutoPosted: true,
          branchId: to.branchId ?? from.branchId,
          globalId: 'je-handover-$gid',
        );
      }
      return outId;
    });
  }

  Future<int?> _repSafeAccount(Safe safe) async {
    if (safe.linkedAccountId != null) return safe.linkedAccountId;
    final code = kSafeTypeAccountCode[safe.safeType];
    if (code == null) return null;
    return (await accountingDao.getAccountByCode(code))?.id;
  }

  // ═══════════════════════════════════════════════════════════════════════
  // Reports (item 12) — all from the STAMPED columns
  // ═══════════════════════════════════════════════════════════════════════

  Future<Map<int, RepStamp>> _repStamps(String table) async {
    final rows = await customSelect(
      'SELECT id, rep_employee_id, route_id FROM $table '
      'WHERE rep_employee_id IS NOT NULL OR route_id IS NOT NULL',
    ).get();
    return {
      for (final r in rows)
        (r.data['id'] as num).toInt(): RepStamp(
          repEmployeeId: _dmInt(r.data['rep_employee_id']),
          routeId: _dmInt(r.data['route_id']),
        ),
    };
  }

  /// Every stamped document in [from, to), oldest first. [repEmployeeId]
  /// narrows to one rep.
  Future<List<RepTransactionRow>> repTransactionDetail({
    required DateTime from,
    required DateTime to,
    int? repEmployeeId,
  }) async {
    final invoiceStamps = await _repStamps('sales_invoices');
    final txnStamps = await _repStamps('safe_transactions');
    final collectionStamps = await _repStamps('sales_rep_collections');
    final invoiceGeo = await fieldGeoMapsUrls('sales_invoices');
    final txnGeo = await fieldGeoMapsUrls('safe_transactions');
    final partyNames = {
      for (final p in await select(parties).get()) p.id: p.name,
    };
    final routeNames = {
      for (final r in await select(salesRoutes).get()) r.id: r.name,
    };
    bool keep(RepStamp? s) =>
        s != null &&
        s.repEmployeeId != null &&
        (repEmployeeId == null || s.repEmployeeId == repEmployeeId);
    final out = <RepTransactionRow>[];

    final invoices = await (select(salesInvoices)
          ..where((s) =>
              s.invoiceDate.isBiggerOrEqualValue(from) &
              s.invoiceDate.isSmallerThanValue(to) &
              s.isDeleted.equals(false)))
        .get();
    final echoedReturns = _echoedReturnKeys(invoices);
    for (final inv in invoices) {
      final s = invoiceStamps[inv.id];
      if (!keep(s) || inv.status == 'cancelled') continue;
      if (_isClientReturnCache(inv)) {
        // E-fix ٤أ — صفُّ ذاكرة العميل يُعَدّ مرّةً واحدة: إن وصل نظيرُه من
        // الخادم استُهلك به، وإلّا فهو المرتجعُ الوحيد بعد.
        final key = _returnKey(inv);
        final left = echoedReturns[key] ?? 0;
        if (left > 0) {
          echoedReturns[key] = left - 1;
          continue;
        }
      }
      out.add(RepTransactionRow(
        date: inv.invoiceDate,
        kind: inv.saleType == 'return' ? 'return' : 'invoice',
        number: inv.invoiceNumber,
        amount: inv.total,
        paid: inv.saleType == 'return' ? 0 : inv.paid,
        repEmployeeId: s!.repEmployeeId,
        customerName: partyNames[inv.customerId],
        routeName: routeNames[s.routeId],
        mapsUrl: invoiceGeo[inv.id],
      ));
    }

    final txns = await (select(safeTransactions)
          ..where((t) =>
              t.createdAt.isBiggerOrEqualValue(from) &
              t.createdAt.isSmallerThanValue(to)))
        .get();
    for (final t in txns) {
      final s = txnStamps[t.id];
      if (!keep(s)) continue;
      final kind = _repTxnKind(t);
      if (kind == null) continue;
      out.add(RepTransactionRow(
        date: t.createdAt,
        kind: kind,
        number: t.voucherNumber,
        amount: t.amount,
        paid: kind == 'receipt' ? t.amount : 0,
        repEmployeeId: s!.repEmployeeId,
        customerName: partyNames[t.partyId],
        routeName: routeNames[s.routeId],
        mapsUrl: txnGeo[t.id],
      ));
    }

    final collections = await (select(salesRepCollections)
          ..where((c) =>
              c.createdAt.isBiggerOrEqualValue(from) &
              c.createdAt.isSmallerThanValue(to)))
        .get();
    for (final c in collections) {
      final s = collectionStamps[c.id] ??
          RepStamp(repEmployeeId: c.salesRepId);
      if (!keep(s) || c.deletedAt != null) continue;
      out.add(RepTransactionRow(
        date: c.createdAt,
        kind: 'collection',
        number: c.referenceNumber ?? '#${c.id}',
        amount: c.amount,
        paid: c.amount,
        repEmployeeId: s.repEmployeeId,
        customerName: partyNames[c.customerId],
        routeName: routeNames[s.routeId],
      ));
    }
    out.sort((a, b) => a.date.compareTo(b.date));
    return out;
  }

  /// E-fix ٤أ — مرتجعُ جهاز العميل يُكتَب **صفَّين** على ذلك الجهاز:
  ///
  ///   ‏١) صفُّ ذاكرةٍ محلّيٌّ (`returns_repository_impl`): رقمه `SRET-<gid>`،
  ///      يحمل المعرّفَ العامَّ للمرتجع ورابطَ الأصل `|gid:<أصل>` في الملاحظة؛
  ///   ‏٢) نظيرُه من الخادم حين تعود لقطةُ `/api/sales`: `SalesSyncStrategy`
  ///      تُدرجه **بلا** `globalId` وبرقم الخادم، فلا يلتقيان بالمعرّف
  ///      ولا بالرقم، ومطابقةُ «الإجماليّ+اليوم+العميل» تفشل حين يختلف
  ///      معرّفُ العميل — وكلاهما مختومٌ بالمندوب ⇒ المرتجعُ يُعَدّ مرّتين.
  ///
  /// فالمفتاحُ: معرّفُ الأصل العامُّ + الإجماليّ. وكلُّ نظيرٍ من الخادم
  /// يستهلك صفَّ ذاكرةٍ واحداً لا أكثر.
  static bool _isClientReturnCache(SalesInvoiceData inv) =>
      inv.saleType == 'return' &&
      inv.invoiceNumber.startsWith('SRET-') &&
      (inv.globalId ?? '').isNotEmpty;

  static String? _returnKey(SalesInvoiceData inv) {
    final original = returnOriginalGidFromNote(inv.notes);
    if (original == null) return null;
    return '$original|${inv.total.toStringAsFixed(2)}';
  }

  Map<String?, int> _echoedReturnKeys(List<SalesInvoiceData> invoices) {
    final out = <String?, int>{};
    for (final inv in invoices) {
      if (inv.saleType != 'return' ||
          inv.status == 'cancelled' ||
          _isClientReturnCache(inv)) {
        continue;
      }
      final key = _returnKey(inv);
      if (key != null) out[key] = (out[key] ?? 0) + 1;
    }
    return out;
  }

  /// `null` = a stamped safe row that is not a rep document (e.g. the
  /// main-treasury leg of a handover is counted once, on the custody side).
  String? _repTxnKind(SafeTransactionData t) {
    if (t.category == kRepHandoverCategory) {
      return t.transactionType == 'payment' ? 'handover' : null;
    }
    if (t.category == 'sales_return' || t.category == 'sales_return_balance') {
      return 'return';
    }
    if (t.transactionType == 'receipt' ||
        t.transactionType == kAccountTransferReceiptTxnType) {
      return 'receipt';
    }
    return null;
  }

  /// Report 1 — per stamped rep over [from, to).
  Future<List<RepSalesSummaryRow>> repSalesSummary({
    required DateTime from,
    required DateTime to,
  }) async {
    final rows = await repTransactionDetail(from: from, to: to);
    final names = {
      for (final e in await select(employees).get()) e.id: e.name,
    };
    final acc = <int, List<RepTransactionRow>>{};
    for (final r in rows) {
      acc.putIfAbsent(r.repEmployeeId!, () => []).add(r);
    }
    double sum(List<RepTransactionRow> l, String kind) => l
        .where((r) => r.kind == kind)
        .fold(0.0, (s, r) => s + r.amount);
    return [
      for (final e in acc.entries)
        RepSalesSummaryRow(
          repEmployeeId: e.key,
          repName: names[e.key] ?? '#${e.key}',
          invoiceCount: e.value.where((r) => r.kind == 'invoice').length,
          netSales: sum(e.value, 'invoice'),
          returns: sum(e.value, 'return'),
          collections: sum(e.value, 'receipt'),
          fieldCollections: sum(e.value, 'collection'),
          handedOver: sum(e.value, 'handover'),
        ),
    ]..sort((a, b) => a.repName.compareTo(b.repName));
  }

  /// Report 3 — every customer currently on a route, in visit order, with
  /// the last invoice, the last completed visit, and the balance.
  Future<List<RouteCoverageRow>> routeCoverage({int? routeId}) async {
    final routes = await listDistributionRoutes();
    final out = <RouteCoverageRow>[];
    for (final route in routes) {
      if (routeId != null && route.id != routeId) continue;
      for (final c in await listRouteCustomers(route.id)) {
        final lastInvoice = await (selectOnly(salesInvoices)
              ..addColumns([salesInvoices.invoiceDate.max()])
              ..where(salesInvoices.customerId.equals(c.customerId) &
                  salesInvoices.isDeleted.equals(false)))
            .map((r) => r.read(salesInvoices.invoiceDate.max()))
            .getSingleOrNull();
        final lastVisit = await (selectOnly(routeVisits)
              ..addColumns([routeVisits.visitDate.max()])
              ..where(routeVisits.customerId.equals(c.customerId) &
                  routeVisits.status.equals('completed')))
            .map((r) => r.read(routeVisits.visitDate.max()))
            .getSingleOrNull();
        out.add(RouteCoverageRow(
          routeId: route.id,
          routeName: route.name,
          customerId: c.customerId,
          customerName: c.customerName,
          sequence: c.sequence,
          repName: route.repName,
          areaName: route.areaName,
          lastInvoiceDate: lastInvoice,
          lastVisitDate: lastVisit,
          balance: c.balance,
        ));
      }
    }
    return out;
  }

  /// Report 4 — stock in every rep's van warehouse (non-zero lines).
  Future<List<VanStockRow>> vanStock({int? repEmployeeId}) async {
    final names = {
      for (final e in await select(employees).get()) e.id: e.name,
    };
    final out = <VanStockRow>[];
    for (final res in await listRepResources()) {
      final van = res.vanWarehouseId;
      if (van == null) continue;
      if (repEmployeeId != null && res.employeeId != repEmployeeId) continue;
      final warehouse = await getWarehouseById(van);
      final balances = await (select(inventoryBalances)
            ..where((b) => b.warehouseId.equals(van)))
          .get();
      final products = await getProductsByIds(
          [for (final b in balances) b.productId]);
      for (final b in balances) {
        if (b.quantity.abs() < 0.0001) continue;
        out.add(VanStockRow(
          repEmployeeId: res.employeeId,
          repName: names[res.employeeId] ?? '#${res.employeeId}',
          warehouseId: van,
          warehouseName: warehouse?.name ?? '#$van',
          productId: b.productId,
          productName: products[b.productId]?.name ?? '#${b.productId}',
          quantity: b.quantity,
          averageCost: b.averageCost,
        ));
      }
    }
    return out;
  }
}

/// `safe_transactions.category` (and JE reference type) of a custody
/// handover.
const kRepHandoverCategory = 'rep_handover';
