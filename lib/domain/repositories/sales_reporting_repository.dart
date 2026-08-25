import '../../data/database/database.dart';

/// Sales-specific reporting interface
/// P2-03: Return types updated to typed objects (ISS-16).
abstract class ISalesReportingRepository {
  Future<List<DailySalesSummaryRow>> getDailySalesForRange({
    required DateTime from,
    required DateTime to,
    int? costCenterId,
    List<int>? warehouseIds,
    Set<int>? allowedBranchIds,
  });

  Future<List<TopSellingProductRow>> getTopSellingProducts({
    required int limit,
    required DateTime from,
    required DateTime to,
    int? costCenterId,
    List<int>? warehouseIds,
    Set<int>? allowedBranchIds,
  });

  Future<List<PaymentMethodStatRow>> getPaymentMethodStats({
    int? costCenterId,
    DateTime? from,
    DateTime? to,
    Set<int>? allowedBranchIds,
  });

  Future<double> getTotalSales({required DateTime from, required DateTime to});

  Future<int> getSalesCount({required DateTime from, required DateTime to});

  Future<int> getNewCustomersCount({
    required DateTime from,
    required DateTime to,
    int? costCenterId,
    Set<int>? allowedBranchIds,
  });

  Future<SalesAnalytics> getSalesAnalytics(
    DateTime from,
    DateTime to, {
    int? userId,
    int? costCenterId,
    List<int>? warehouseIds,
    String? paymentMethod,
    String? saleType,
    Set<int>? allowedBranchIds,
  });

  /// [revenueOnly] يستثني اللي مش إيراد (مستندات المرتجع والملغي والمُرجَع)
  /// عشان جمع عمود الجدول يطابق بطاقة «إجمالي المبيعات». اختياري لأن مسار
  /// المرتجعات وقائمة الضريبة محتاجين المجموعة الكاملة.
  Future<List<SalesInvoiceData>> getSalesByDateRange(
    DateTime start,
    DateTime end, {
    int? userId,
    List<int>? warehouseIds,
    int? costCenterId,
    Set<int>? allowedBranchIds,
    bool revenueOnly = false,

    /// H8 · يستبعد الملغى/المعدوم **فقط** ويُبقي المرتجعَ ليُطرح — اقرا
    /// `SalesDao.getSalesByDateRange`.
    bool excludeVoided = false,
  });

  /// `{معرّفُ الفاتورة الأصلية: مجموعُ ما رُدّ}` — **نفسُ** الدالّة التي
  /// تغذّي «المتبقي» و«إجمالي المرتجعات» في شاشة الفواتير.
  ///
  /// موجودةٌ هنا كي يتّفق تقريرُ المبيعات مع شاشة الفواتير **بالبناء**: كانت
  /// الشاشتان تقرآن نفسَ القاعدة وتجيبان جوابين، لأن التقريرَ لم يكن ينده
  /// المرتجعاتِ ولا مرّةً واحدة (فاتورةُ ١٨ بمرتجعِ ٤ تقول ١٨ هناك و١٤ هنا).
  ///
  /// تجمع شكلَي المرتجع معاً: حركةَ خزينةٍ `reference_type='sales_return'`
  /// (‏التنصيبُ المستقلّ) ومستندَ `sale_type='return'` المربوطَ بالأصل
  /// (‏مسارُ السيرفر).
  Future<Map<int, double>> getReturnedAmountsForInvoices(List<int> invoiceIds);

  Future<List<SalesInvoiceItem>> getSalesInvoiceItems(int invoiceId);

  Future<List<Map<String, dynamic>>> getDeliveryReport({
    required DateTime from,
    required DateTime to,
    List<int>? warehouseIds,
    Set<int>? allowedBranchIds,
  });

  Future<List<TopProductRow>> getTopProductsReport({
    required DateTime from,
    required DateTime to,
    int limit = 10,
    bool orderByValue = true,
    List<int>? warehouseIds,
    Set<int>? allowedBranchIds,
  });

  Future<Map<String, dynamic>> getTaxReport(
    DateTime from,
    DateTime to, {
    int? costCenterId,
    List<int>? warehouseIds,
    int? branchId,
    Set<int>? allowedBranchIds,
  });

  /// البند 8 — per-item sales-tax detail (each line's own rate + taxable base).
  Future<List<Map<String, dynamic>>> getSalesTaxDetailByItem(
    DateTime from,
    DateTime to, {
    int? costCenterId,
    List<int>? warehouseIds,
    int? branchId,
    Set<int>? allowedBranchIds,
  });

  /// البند 8 — taxable base + tax subtotalled per distinct rate.
  Future<List<Map<String, dynamic>>> getSalesTaxByRate(
    DateTime from,
    DateTime to, {
    int? costCenterId,
    List<int>? warehouseIds,
    int? branchId,
    Set<int>? allowedBranchIds,
  });

  Future<List<ShiftReportDto>> getShiftsReportPaginated({
    int limit = 50,
    int offset = 0,
    DateTime? startDate,
    DateTime? endDate,
    int? userId,
    Set<int>? allowedBranchIds,
    /// اختيارُ المستخدم للفرع/الإقليم — يُطبَّق في SQL قبل `limit`.
    int? branchId,
    Set<int>? regionBranchIds,
  });

  Future<List<CategoryProfitRow>> getCategoryProfitReport({
    required DateTime from,
    required DateTime to,
    List<int>? warehouseIds,
    Set<int>? allowedBranchIds,
    int? costCenterId,
  });

  Future<List<SalesByCategoryRow>> getSalesByCategory({
    required DateTime from,
    required DateTime to,
    List<int>? warehouseIds,
    Set<int>? allowedBranchIds,
  });

  Future<List<SalesBySaleTypeRow>> getSalesBySaleType({
    required DateTime from,
    required DateTime to,
    List<int>? warehouseIds,
    Set<int>? allowedBranchIds,
  });

  Future<List<SalesInvoiceSummaryRow>> getSalesInvoicesBySaleType({
    required String saleType,
    required DateTime from,
    required DateTime to,
    Set<int>? allowedBranchIds,
  });

  Future<ReturnsAnalyticsSummary> getSalesReturnsAnalytics({
    required DateTime from,
    required DateTime to,
    int? costCenterId,
    List<int>? warehouseIds,
    Set<int>? allowedBranchIds,
  });

  Future<ReturnsAnalyticsSummary> getPurchaseReturnsAnalytics({
    required DateTime from,
    required DateTime to,
    int? costCenterId,
    List<int>? warehouseIds,
    Set<int>? allowedBranchIds,
  });

  /// تجميعُ مبيعاتِ الفترة لكلّ عميل — «تحليل سلوك العملاء» و«تقسيم RFM».
  Future<List<PartyPeriodAggregateRow>> getCustomerPeriodAggregates({
    DateTime? from,
    DateTime? to,
    int limit,
    List<int>? warehouseIds,
    Set<int>? allowedBranchIds,
  });
}
