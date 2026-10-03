part of '../database.dart';

/// J4 (الجزء ٣) — عمولاتُ المندوبين: خططٌ (افتراضيّةٌ أو لمندوب) بنسبةٍ من
/// صافي المبيعات بعد المرتجعات ونسبةٍ من التحصيلات، وشرائحَ بنسبة تحقيق
/// الهدف الشهريّ (‏`sales_rep_targets`) ونسبٍ اختياريّةٍ لفئات المنتجات.
/// الكشفُ يُحسب من المستندات **المختومة** بالمندوب (‏`rep_employee_id`)
/// عبر [repTransactionDetail] نفسِها التي يقرؤها تقريرُ أداء المندوبين.
extension HrCommissionDao on AppDatabase {
  CommissionPlan _hrpPlanOf(Map<String, Object?> d) => CommissionPlan(
        id: (d['id'] as num).toInt(),
        name: d['name'] as String,
        employeeId: _dmInt(d['employee_id']),
        employeeName: d['employee_name'] as String?,
        salesRatePct: _hrpD(d['sales_rate']),
        collectionsRatePct: _hrpD(d['collections_rate']),
        tiers: CommissionPlan.decodeTiers(d['tiers'] as String?),
        categoryRates:
            CommissionPlan.decodeCategoryRates(d['category_rates'] as String?),
        isActive: _dmBool(d['is_active']),
      );

  Future<List<CommissionPlan>> listCommissionPlans(
      {bool activeOnly = false}) async {
    final rows = await customSelect(
      'SELECT p.*, e.name AS employee_name FROM hr_commission_plans p '
      'LEFT JOIN employees e ON e.id = p.employee_id '
      'WHERE p.deleted_at IS NULL ${activeOnly ? 'AND p.is_active = 1 ' : ''}'
      'ORDER BY p.employee_id IS NOT NULL, p.id',
    ).get();
    return [for (final r in rows) _hrpPlanOf(r.data)];
  }

  /// خطّةٌ فعّالةٌ واحدةٌ للافتراضيّ ولكلّ مندوب.
  Future<int> saveCommissionPlan(CommissionPlan p, {int? userId}) async {
    await _hrpRequire(userId, PermissionCodes.hrCommissionsManage);
    if (p.name.trim().isEmpty) throw HrException('اسم الخطة مطلوب.');
    bool bad(double v) => v < 0 || v > 100;
    if (bad(p.salesRatePct) ||
        bad(p.collectionsRatePct) ||
        p.tiers.any((t) => bad(t.salesRatePct) || t.minAchievementPct < 0) ||
        p.categoryRates.values.any(bad)) {
      throw HrException('النسبة يجب أن تكون بين 0 و100.');
    }
    if (p.isActive) {
      final clash = (await listCommissionPlans(activeOnly: true)).any(
          (o) => o.id != p.id && o.employeeId == p.employeeId);
      if (clash) {
        throw HrException(p.employeeId == null
            ? 'توجد خطة افتراضية فعالة بالفعل.'
            : 'لهذا المندوب خطة فعالة بالفعل.');
      }
    }
    final values = <String, Object?>{
      'name': p.name.trim(),
      'employee_id': p.employeeId,
      'sales_rate': p.salesRatePct,
      'collections_rate': p.collectionsRatePct,
      'tiers': p.encodeTiers(),
      'category_rates': p.encodeCategoryRates(),
      'is_active': p.isActive ? 1 : 0,
    };
    if (p.id == null) return _dmInsert('hr_commission_plans', values);
    await _hrpUpdate('hr_commission_plans', p.id!, values);
    return p.id!;
  }

  Future<void> deleteCommissionPlan(int id, {int? userId}) async {
    await _hrpRequire(userId, PermissionCodes.hrCommissionsManage);
    await _hrpSoftDelete('hr_commission_plans', 'id = ?', [id]);
  }

  /// خطّةُ المندوب الخاصّة، وإلّا الافتراضيّة.
  Future<CommissionPlan?> commissionPlanFor(int employeeId) async {
    final plans = await listCommissionPlans(activeOnly: true);
    return plans.where((p) => p.employeeId == employeeId).firstOrNull ??
        plans.where((p) => p.employeeId == null).firstOrNull;
  }

  /// هدفُ المندوب الشهريّ (‏null ⇒ لا هدف).
  Future<double?> repMonthlyTarget(int employeeId, int year, int month) async {
    final t = await (select(salesRepTargets)
          ..where((t) =>
              t.salesRepId.equals(employeeId) &
              t.year.equals(year) &
              t.month.equals(month) &
              t.deletedAt.isNull()))
        .get();
    if (t.isEmpty) return null;
    final v = t.first.targetAmount;
    return v > 0 ? v : null;
  }

  /// فئاتُ المنتجات (معرّف، اسم) لنسب الفئات.
  Future<List<(int, String)>> commissionCategoryOptions() async => [
        for (final c in await select(categories).get()) (c.id, c.name),
      ];

  /// كشفُ عمولة مندوبٍ للفترة [from]..[to] (شاملة) بالمستندات.
  Future<CommissionStatement> commissionStatement(
      int employeeId, DateTime from, DateTime to) async {
    final plan = await commissionPlanFor(employeeId);
    final start = DateTime(from.year, from.month, from.day);
    final end = DateTime(to.year, to.month, to.day + 1);
    if (plan == null) {
      return CommissionStatement(employeeId: employeeId, from: start, to: to);
    }
    final rows = await repTransactionDetail(
        from: start, to: end, repEmployeeId: employeeId);
    double sum(Set<String> kinds) => rows
        .where((r) => kinds.contains(r.kind))
        .fold<double>(0, (a, r) => a + r.amount.abs());
    final sales = sum({'invoice'});
    final returns = sum({'return'});
    final collections = sum({'receipt', 'collection'});
    final target = await repMonthlyTarget(employeeId, from.year, from.month);
    final achievement =
        target == null ? null : (sales - returns) / target * 100;
    final rate = plan.salesRateFor(achievement);

    // نسبُ الفئات: عمولةُ كلّ فاتورةٍ من بنودها (مقيّسةً بإجمالي الفاتورة
    // بعد خصمها)، والفئةُ بلا نسبةٍ خاصّةٍ بالنسبة المطبَّقة.
    final perInvoice = <String, double>{};
    if (plan.categoryRates.isNotEmpty) {
      final stamps = await _repStamps('sales_invoices');
      final invoices = [
        for (final inv in await (select(salesInvoices)
              ..where((s) =>
                  s.invoiceDate.isBiggerOrEqualValue(start) &
                  s.invoiceDate.isSmallerThanValue(end) &
                  s.isDeleted.equals(false)))
            .get())
          if (stamps[inv.id]?.repEmployeeId == employeeId &&
              inv.saleType != 'return' &&
              inv.status != 'cancelled')
            inv,
      ];
      if (invoices.isNotEmpty) {
        final productCategory = {
          for (final p in await select(products).get()) p.id: p.categoryId,
        };
        final ids = [for (final i in invoices) i.id];
        final items = await (select(salesInvoiceItems)
              ..where((i) => i.invoiceId.isIn(ids)))
            .get();
        for (final inv in invoices) {
          final mine = items.where((i) => i.invoiceId == inv.id).toList();
          final base = mine.fold<double>(0, (a, i) => a + i.total);
          if (base <= 0) {
            perInvoice[inv.invoiceNumber] = inv.total * rate / 100;
            continue;
          }
          final scale = inv.total / base;
          var c = 0.0;
          for (final i in mine) {
            final cat = productCategory[i.productId];
            final r = (cat == null ? null : plan.categoryRates[cat]) ?? rate;
            c += i.total * scale * r / 100;
          }
          perInvoice[inv.invoiceNumber] = c;
        }
      }
    }
    const round = FinancialUtils.round;
    final docs = <CommissionDoc>[];
    var salesCommission = 0.0;
    var collectionsCommission = 0.0;
    for (final r in rows) {
      double c;
      switch (r.kind) {
        case 'invoice':
          c = perInvoice[r.number] ?? r.amount * rate / 100;
          salesCommission += c;
        case 'return':
          c = -r.amount.abs() * rate / 100;
          salesCommission += c;
        case 'receipt' || 'collection':
          c = r.amount.abs() * plan.collectionsRatePct / 100;
          collectionsCommission += c;
        default:
          continue;
      }
      docs.add(CommissionDoc(
        date: r.date,
        kind: r.kind,
        number: r.number,
        amount: r.kind == 'return' ? -r.amount.abs() : r.amount,
        commission: round(c),
        customerName: r.customerName,
      ));
    }
    return CommissionStatement(
      employeeId: employeeId,
      from: start,
      to: to,
      plan: plan,
      sales: round(sales),
      returns: round(returns),
      collections: round(collections),
      target: target,
      achievementPct: achievement,
      appliedSalesRatePct: rate,
      salesCommission: round(salesCommission < 0 ? 0 : salesCommission),
      collectionsCommission: round(collectionsCommission),
      docs: docs,
    );
  }
}
