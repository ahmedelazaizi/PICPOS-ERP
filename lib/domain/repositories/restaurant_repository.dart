import '../../data/database/database.dart';
import '../models/floor_plan_layout.dart';
import '../models/tables_report_row.dart';

abstract class IRestaurantRepository {
  Stream<List<TableSection>> watchAllSections();
  Future<List<TableSection>> getAllSections();
  Future<int> createSection(String name);
  Future<bool> updateSection(int id, String name);
  Future<void> deleteSection(int id);

  Stream<List<RestaurantTable>> watchTablesInSection(int sectionId);

  /// كلُّ الطاولات **بثّاً**.
  ///
  /// 🔴 مصمّمُ القاعة كان يقرؤها لقطةً (`getAllTables`)، فطاولةٌ تُنشأ
  /// والمصمّمُ مفتوحٌ لا تصله أبداً — راجع `watchAllSections` أعلاه.
  Stream<List<RestaurantTable>> watchAllTables();
  Future<List<RestaurantTable>> getAllTables();
  Future<int> createTable({
    required String name,
    required int capacity,
    required int sectionId,
  });
  Future<bool> updateTable({
    required int id,
    required String name,
    required int capacity,
    required int sectionId,
  });
  Future<void> deleteTable(int id);
  Future<void> updateTableStatus(int id, String status);
  Future<void> updateTablePosition(int id, double x, double y);

  // ─── مصمّمُ القاعة (قسمُ ٧) ─────────────────────────────
  //
  // ⚠️ **وليس لها نظيرٌ يحفظ معلَماً واحداً.** المخطَّطُ وحدةُ الحفظ
  //    لأنّ `تراجع` لا يعني شيئاً فوق كتابةٍ تقع مع كلّ سحبة، ولأنّ
  //    الكتابةَ في هذا المستودع **مستندٌ صريح**.
  Future<FloorPlanSectionLayout?> getFloorPlanLayout(int sectionId);
  Future<List<FloorPlanSectionBox>> getFloorPlanSectionBoxes();
  Future<void> saveFloorPlanLayout(FloorPlanSectionLayout layout);

  Future<TableReservation?> getActiveReservationForTable(int tableId);
  Future<void> createReservation({
    required int tableId,
    required String customerName,
    String? customerPhone,
    required DateTime reservationTime,
    required int partySize,
    String? notes,
  });
  Future<void> cancelReservation(int id);
  /// [taxRate] كسريّةٌ — حضورُ الحجز يفتح طلباً، فيلزمه ما يلزم الفتح.
  Future<void> seatReservation(int id, {int? userId, double taxRate = 0});

  Future<void> transferTableOrder(int sourceTableId, int targetTableId);
  Future<void> partialTransferTableOrder({
    required int sourceTableId,
    required int targetTableId,
    required Map<int, double> itemQuantities,
  });

  Future<TableOrder?> getActiveOrderForTable(int tableId);
  Future<List<TableOrderItem>> getTableOrderItems(int orderId);

  /// [taxRate] نسبةُ الضريبة كسريّةً (0.16) لقطةً من `pos_default_tax_rate`.
  /// المستدعي يقرأ الإعدادَ ويمرّره — طلبٌ بلا نسبةٍ لا يقبل تفعيلَ الضريبة.
  Future<int> createTableOrder(int tableId, {int? userId, double taxRate = 0});
  Future<void> mergeTableOrders(int sourceTableId, int targetTableId);

  // Table order item operations (used by TablePosScreen)
  /// [taxRate] نسبةُ ضريبة الصنف مئويّةً (16) منسوخةً عن `Products.taxRate`.
  Future<void> addOrUpdateTableOrderItem({
    required int orderId,
    required int productId,
    required double quantity,
    required double unitPrice,
    double taxRate = 0,
  });
  Future<void> clearTableOrderItems(int orderId);

  /// طلباتُ الطاولات في مدىً زمنيّ، جاهزةً لـ[aggregateTablesReport].
  ///
  /// [allowedBranchIds] سقفُ صلاحية المستخدم، ويُحقَن في **الاستعلام** —
  /// `null` لا حدّ، و`{}` لا صفوف، و`{ids}` تلك الفروعُ وما لا فرعَ له.
  /// و[branchIds] اختيارُه هو (فرعٌ أو فروعُ منطقة). التفاصيل عند
  /// `TablesDao.getTableOrdersForReport`.
  Future<List<TableOrderInput>> getTableOrdersForReport({
    required DateTime from,
    required DateTime to,
    int? sectionId,
    int? tableId,
    int? userId,
    Set<int>? branchIds,
    Set<int>? allowedBranchIds,
  });
}
