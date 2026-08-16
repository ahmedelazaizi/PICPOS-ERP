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

  /// الحصصُ التي لم تُسوَّ بعد.
  ///
  /// إعادةُ المحاولة بعد فشلٍ في منتصف التسوية يجب أن تُكمل لا أن تبدأ من
  /// الصفر: صفُّ الدفع يحمل `splitLabel`، فما وُجد له صفٌّ فقد سُوّي.
  Future<List<SplitPart>> unsettledParts({
    required int orderId,
    required SplitPlan plan,
  }) async {
    final labels = plan.parts.map((p) => p.label).toList();
    if (labels.toSet().length != labels.length) {
      throw StateError(
          'تسمياتُ الحصص متكرّرةٌ في الخطّة — لا يمكن تمييزُ المسوَّى من الباقي');
    }
    final settled = (await _session.paymentsFor(orderId))
        .map((p) => p.splitLabel)
        .whereType<String>()
        .toSet();
    return plan.parts.where((p) => !settled.contains(p.label)).toList();
  }

  /// رقمُ الفاتورة الذي سُوِّيت عليه حصصُ هذا الطلب فعلاً — `null` إن لم تُسوَّ
  /// حصّةٌ بعد.
  ///
  /// بالتساوي وبمبلغ فاتورةٌ واحدةٌ تُغطّي كلَّ الحصص؛ فإعادةُ المحاولة بعد
  /// فشلٍ جزئيٍّ يجب أن تُكمل التسويةَ على نفس الفاتورة، لا أن تُصدر فاتورةً
  /// ثانيةً لنفس الأصناف (بيعٌ مضاعَفٌ حقيقيّ — مخزونٌ وقيودٌ محاسبيّةٌ مكرّرة).
  Future<int?> settledInvoiceId(int orderId) async {
    final payments = await _session.paymentsFor(orderId);
    return payments.isEmpty ? null : payments.first.invoiceId;
  }
}
