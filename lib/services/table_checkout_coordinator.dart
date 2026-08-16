import '../data/database/database.dart';
import '../domain/models/split_plan.dart';
import 'table_session_service.dart';

/// يحوّل طلبَ طاولةٍ إلى خطّةِ تقسيمٍ، ويُسوّي حصّةً بعد صدور فاتورتها.
///
/// إنشاءُ الفاتورة نفسُه يبقى في `checkoutController.processPayment` لأنه
/// يقرأ السلّة من Riverpod. هذا المنسّقُ يملك ما يمكن اختبارُه بلا واجهة:
/// بناءُ الخطّة من حالة الطلب، وتسجيلُ الدفعة بعدها.
class TableCheckoutCoordinator {
  TableCheckoutCoordinator({
    required AppDatabase db,
    required TableSessionService session,
  })  : _db = db,
        _session = session;

  final AppDatabase _db;
  final TableSessionService _session;

  /// يبني خطّةَ تقسيمٍ من حالة الطلب.
  ///
  /// [ways] و[assignment] لازمان في `byItems` فقط. وفي `equal` يكون المقام
  /// `ways` إن مُرّر، وإلّا `guestCount` — فعددُ الأشخاص المسؤولُ سُئل عنه
  /// عند فتح الطاولة لهذا الغرض بالذات.
  Future<SplitPlan> buildSplitPlan({
    required int orderId,
    required SplitMode mode,
    int? ways,
    Map<int, int>? assignment,
    List<double>? amounts,
  }) async {
    final order = await (_db.select(_db.tableOrders)
          ..where((o) => o.id.equals(orderId)))
        .getSingle();
    final total = await _session.effectiveTotal(orderId);

    switch (mode) {
      case SplitMode.equal:
        return SplitPlan.equal(
            total: total, ways: ways ?? order.guestCount);
      case SplitMode.byAmounts:
        return SplitPlan.byAmounts(total: total, amounts: amounts ?? const []);
      case SplitMode.byItems:
        final items = await _db.getTableOrderItems(orderId);
        return SplitPlan.byItems(
          items: [
            for (final i in items)
              SplitItem(
                  itemId: i.id, quantity: i.quantity, lineTotal: i.total),
          ],
          assignment: assignment ?? const {},
          ways: ways ?? order.guestCount,
        );
    }
  }

  /// تسجيلُ حصّةٍ بعد صدور فاتورتها.
  Future<void> settlePart({
    required int orderId,
    required SplitPart part,
    required int invoiceId,
  }) =>
      _session.recordPayment(
        orderId: orderId,
        invoiceId: invoiceId,
        amount: part.amount,
        splitLabel: part.label,
      );
}
