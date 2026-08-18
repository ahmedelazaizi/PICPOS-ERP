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

  /// تحصيلُ الطلب كاملاً: **حجزٌ → ترحيلٌ → تثبيت**.
  ///
  /// هذه هي الحلقةُ التي تُغلق نافذةَ «الترحيلُ قبل التسجيل». كان الترتيبُ
  /// ترحيلاً ثم حراساً، فإن رمى حارسٌ بقيت فاتورةٌ مُرحَّلةٌ بلا دفعةٍ على
  /// الطاولة. الآن كلُّ الحراس تعمل في [TableSessionService.reservePayment]
  /// **قبل** أن يُنادى [postInvoice] أصلاً.
  ///
  /// [postInvoice] يُرحّل الفاتورةَ ويعيد رقمَها، أو `null` إن تراجع الكاشير.
  /// يبقى دالّةً يمرّرها المستدعي لأن الترحيلَ يقرأ السلّةَ من Riverpod —
  /// وبهذا تُقاد الحلقةُ كلُّها في اختبارٍ بلا واجهة.
  ///
  /// والحجزُ يُؤخَذ **بعد** ورقةِ الدفع (يستدعيها [postInvoice])، فعمرُه زمنُ
  /// آلةٍ لا زمنُ إنسان — وهو ما يُبقي خطرَ الحجز العالق صغيراً.
  Future<TableSettleOutcome> settleFull({
    required int orderId,
    required double amount,
    required Future<int?> Function() postInvoice,
    int? userId,
    String? userName,
  }) async {
    final int reservationId;
    try {
      reservationId = await _session.reservePayment(
        orderId: orderId,
        amount: amount,
        userId: userId,
        userName: userName,
      );
    } on TableTransitionException catch (e) {
      // لا شيءَ رُحِّل — لا تسويةَ تُطلَب، ورسالةٌ واحدةٌ تكفي.
      return TableSettleOutcome(
          status: TableSettleStatus.rejected, message: e.message);
    }

    int? invoiceId;
    try {
      invoiceId = await postInvoice();
    } catch (e) {
      await _releaseQuietly(reservationId, 'فشلَ الترحيل: $e', userId, userName);
      return TableSettleOutcome(
          status: TableSettleStatus.aborted, message: 'فشلَ الترحيل: $e');
    }

    if (invoiceId == null) {
      await _releaseQuietly(
          reservationId, 'أُلغيت طريقةُ الدفع', userId, userName);
      return const TableSettleOutcome(
        status: TableSettleStatus.aborted,
        message: 'أُلغيت طريقةُ الدفع — لم تُصدَر فاتورة',
      );
    }

    try {
      await _session.confirmPayment(
          reservationId: reservationId, invoiceId: invoiceId);
    } catch (e) {
      // الفاتورةُ رُحّلت والمالُ مسجَّلٌ على الطاولة بمبلغه الصحيح — الناقصُ
      // رابطُ الفاتورة وحدَه. لا يُحرَّر الحجزُ هنا: تحريرُه يمحو دفعةً
      // حقيقيّةً رُحّلت فاتورتُها.
      return TableSettleOutcome(
        status: TableSettleStatus.reconcileNeeded,
        invoiceId: invoiceId,
        message: 'فاتورةٌ #$invoiceId صدرت ورُحِّلت، والمبلغُ مسجَّلٌ على '
            'الطاولة، لكن تعذّر ربطُهما (حجز #$reservationId) — يحتاج ربطاً '
            'يدويّاً. الخطأ: $e',
      );
    }

    return TableSettleOutcome(
        status: TableSettleStatus.success, invoiceId: invoiceId);
  }

  Future<void> _releaseQuietly(
      int reservationId, String reason, int? userId, String? userName) async {
    // التحريرُ نفسُه قد يفشل على عطلِ قرص؛ وابتلاعُه هنا مقصود — الفشلُ
    // الأصليُّ هو ما يُبلَّغ، والحجزُ المعلّقُ يظهر في سجلّ الطاولة.
    try {
      await _session.releaseReservation(
        reservationId: reservationId,
        reason: reason,
        userId: userId,
        userName: userName,
      );
    } catch (_) {}
  }

  /// تسجيلُ حصّةٍ على فاتورةٍ **صدرت بالفعل** — حجزٌ وتثبيتٌ في معاملةٍ واحدة.
  ///
  /// يبقى لمن يملك رقمَ فاتورةٍ سلفاً. وحلقةُ التقسيم لا تستعمله: هي تحجز
  /// أوّلاً ثم تُرحّل ثم تثبّت، وذلك هو ما يُغلق النافذة.
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

  /// حجزُ حصّةٍ **قبل** صدور فاتورتها — كلُّ حراسِ الدفع تعمل هنا.
  Future<int> reservePart({
    required int orderId,
    required SplitPart part,
    int? userId,
    String? userName,
  }) =>
      _session.reservePayment(
        orderId: orderId,
        amount: part.amount,
        splitLabel: part.label,
        userId: userId,
        userName: userName,
      );

  /// ربطُ حجزِ حصّةٍ بفاتورةٍ صدرت.
  Future<void> confirmPart({
    required int reservationId,
    required int invoiceId,
  }) =>
      _session.confirmPayment(
          reservationId: reservationId, invoiceId: invoiceId);

  /// تحريرُ حجوزٍ لم تصدر فاتورتُها. لا يرمي — الفشلُ الأصليُّ هو ما يُبلَّغ.
  Future<void> releaseReservations(
    List<int> reservationIds, {
    String reason = 'لم تُصدَر فاتورةٌ للحصّة',
    int? userId,
    String? userName,
  }) async {
    for (final id in reservationIds) {
      try {
        await _session.releaseReservation(
          reservationId: id,
          reason: reason,
          userId: userId,
          userName: userName,
        );
      } catch (_) {}
    }
  }

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

    // ── الحالةُ الثالثة: محجوزةٌ تنتظر رقمَ فاتورة ────────────────────────
    //
    // كانت الحصّةُ إمّا مسوّاةً أو باقية. ومنذ v158 بينهما ثالثة، و
    // `settledShares` لا يراها (يقرأ `paymentsFor` المُرشَّح بـ`settled`).
    //
    // فلو مرّت لَعادت في «الباقية» فحُجزت ثانيةً — أو، لولا حارسُ الحجز
    // المزدوج، لَتضاعف `paidAmount`. وعدُّها «مسوّاة» أسوأ: يبقى رابطُ
    // فاتورتها فارغاً للأبد.
    //
    // ولا تُحسَم تخميناً. صفٌّ معلّقٌ يعني — بحكم ترتيب [settleFull] — أن
    // الفاتورةَ **رُحّلت** وفشل ربطُها وحدَه (فشلُ الترحيل يُحرِّر الحجز
    // فوراً). فالاستئنافُ فوقه يشحن أصنافاً حُصِّلت بالفعل. يُرفَض صراحةً
    // بذكر الرقم والمبلغ ليحسمه إنسان: يربطها أو يحرّرها.
    final pending = await _session.pendingReservations(orderId);
    if (pending.isNotEmpty) {
      final p = pending.first;
      final named = p.splitLabel != null ? ' لحصّة ${p.splitLabel}' : '';
      throw StateError(
          'على هذا الطلب حجزٌ معلّق (#${p.id}$named بمبلغ ${p.amount}): '
          'فاتورتُه صدرت وتعذّر ربطُها بالطاولة. لا يُستأنَف التقسيمُ فوقه — '
          'اربِط الحجزَ بفاتورته أو حرّره، ثم أعِد المحاولة.');
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

/// نتيجةُ محاولة تحصيل — أربعُ حالاتٍ لا لبسَ بينها.
enum TableSettleStatus {
  /// رُحِّلت الفاتورةُ وسُجِّلت الدفعةُ وارتبطتا.
  success,

  /// رفضَ حارسٌ **قبل** أيِّ ترحيل. لا شيءَ يحتاج تسوية.
  rejected,

  /// لم تُرحَّل فاتورةٌ (تراجُعٌ أو فشلُ ترحيل) وحُرِّر الحجز.
  aborted,

  /// رُحِّلت الفاتورةُ والمالُ مسجَّلٌ على الطاولة، والناقصُ ربطُهما.
  reconcileNeeded,
}

class TableSettleOutcome {
  const TableSettleOutcome({
    required this.status,
    this.invoiceId,
    this.message,
  });

  final TableSettleStatus status;
  final int? invoiceId;
  final String? message;
}
