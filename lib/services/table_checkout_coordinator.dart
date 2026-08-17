import '../data/database/database.dart';
import '../domain/models/split_plan.dart';
import '../domain/models/table_charge_check.dart';
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
        // حصّةُ البند لا `item.total` الخام: الخام كميّةٌ × سعرٌ بلا خصمٍ ولا
        // ضريبة، فمجموعُ الحصص كان ينقص عن المستحقّ ويبقى على الطلب متبقٍّ
        // لا يُسوّيه أحد.
        final shares = await _session.effectiveLineTotals(orderId);
        return SplitPlan.byItems(
          items: [
            for (final i in items)
              SplitItem(
                  itemId: i.id,
                  quantity: i.quantity,
                  lineTotal: shares[i.id] ?? i.total),
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

  /// ما سُوِّي فعلاً من حصصِ هذا الطلب: `التسمية → مجموعُ ما سُجِّل عليها`.
  ///
  /// الدفعاتُ غيرُ المُسمّاة (تحصيلٌ من شاشة الطاولة لا من التقسيم) لا تظهر
  /// هنا — لا حصّةَ لها تُنسَب إليها.
  ///
  /// تُقرَأ من الشاشة أيضاً: الكاشيرُ الذي يعود إلى تقسيمٍ سُوِّي نصفُه يحتاج
  /// أن يرى ما سُوِّي بالاسم والمبلغ ليُعيد إدخالَ نفسِ التركيبة، لا أن
  /// يخمّنها.
  Future<Map<String, double>> settledShares(int orderId) async {
    final settled = <String, double>{};
    for (final payment in await _session.paymentsFor(orderId)) {
      final label = payment.splitLabel;
      if (label == null) continue;
      settled[label] = (settled[label] ?? 0) + payment.amount;
    }
    return settled;
  }

  /// الحصصُ التي لم تُسوَّ بعد.
  ///
  /// إعادةُ المحاولة بعد فشلٍ في منتصف التسوية يجب أن تُكمل لا أن تبدأ من
  /// الصفر: صفُّ الدفع يحمل `splitLabel`، فما وُجد له صفٌّ فقد سُوّي.
  ///
  /// **والتسميةُ وحدَها لا تكفي.** `TableOrderPayments` يسجّل التسميةَ
  /// والمبلغَ ورقمَ الفاتورة، ولا يسجّل تركيبةَ الخطّة. فلو غُيِّر التقسيمُ
  /// بعد تسويةٍ جزئيّةٍ وقبل إعادة المحاولة — مقامٌ آخر، أو مبالغُ أخرى، أو
  /// صنفٌ نُقل بين ضيفين — لعُدَّت «ضيف ١» المسوّاةُ بالتركيبة القديمة
  /// مسوّاةً بالتركيبة الجديدة، فتضيع أموالٌ أو أصنافٌ بلا خطأٍ يظهر. لذلك
  /// يُقارَن مبلغُ كلّ حصّةٍ سُوِّيت بما تجعله الخطّةُ الحاليّة، ويُرفَض
  /// الاختلافُ صراحةً.
  ///
  /// **والمقارنةُ وحدَها لا تكفي كذلك.** حصّةٌ سُوِّيت ثم اختفت تسميتُها من
  /// الخطّة — مقامٌ نقص من أربعةٍ إلى ثلاثةٍ فذهبت «ضيف ٤» — لا تُقارَن
  /// بشيءٍ فتُهمَل بصمت: تعود الخطّةُ بكلّ حصصها «باقية»، فتُشحَن أصنافُ
  /// الطلب كلُّها من جديدٍ في فاتورةٍ ثانيةٍ (بيعٌ مضاعَفٌ حقيقيّ) ويُحصَّل
  /// ما سبق تحصيلُه. لذلك تُرفَض أيُّ تسميةٍ مسوّاةٍ غائبةٍ عن الخطّة.
  Future<List<SplitPart>> unsettledParts({
    required int orderId,
    required SplitPlan plan,
  }) async {
    final labels = plan.parts.map((p) => p.label).toList();
    if (labels.toSet().length != labels.length) {
      throw StateError(
          'تسمياتُ الحصص متكرّرةٌ في الخطّة — لا يمكن تمييزُ المسوَّى من الباقي');
    }

    final settled = await settledShares(orderId);

    final planLabels = labels.toSet();
    for (final entry in settled.entries) {
      if (planLabels.contains(entry.key)) continue;
      throw StateError(
          'حصّةُ ${entry.key} سُوِّيت بمبلغ ${entry.value} وهي غائبةٌ عن '
          'التقسيم الحاليّ — نقصانُ عدد الحصص يُسقطها من الحساب فتُشحَن '
          'أصنافُها مرّةً ثانية. أعِد عددَ الحصص إلى ما يشمل ${entry.key}.');
    }

    for (final part in plan.parts) {
      final paid = settled[part.label];
      if (paid == null) continue;
      if (tableMoneyUnits(paid) != tableMoneyUnits(part.amount)) {
        throw StateError(
            'حصّةُ ${part.label} سُوِّيت بمبلغ $paid، والتقسيمُ الحاليُّ يجعلها '
            '${part.amount} — تغيّرت تركيبةُ التقسيم بعد تسويةٍ جزئيّة. أعِد '
            'التقسيمَ إلى ما سُوّي عليه، أو أكمِل التحصيلَ من شاشة الطاولة.');
      }
    }

    return plan.parts.where((p) => !settled.containsKey(p.label)).toList();
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
