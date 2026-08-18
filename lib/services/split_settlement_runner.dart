import '../domain/models/split_plan.dart';
import '../domain/models/table_charge_check.dart';

/// نتيجةُ محاولة تسوية.
enum SplitRunStatus {
  /// سُوِّيت كلُّ الحصص الباقية.
  success,

  /// لا حصّةَ باقية — التقسيمُ كان مكتملاً قبل هذه المحاولة.
  alreadyComplete,

  /// رُفضت المتابعةُ **قبل** ترحيل أيّ فاتورة. لا شيءَ يحتاج تسوية.
  aborted,

  /// فاتورةٌ رُحِّلت (محاسبةً ومخزوناً) ثم تعذّر تسجيلُ دفعتها على الطلب.
  /// هذه وحدَها تستحقّ سطراً دائماً في السجل.
  reconcileNeeded,
}

class SplitRunResult {
  const SplitRunResult({
    required this.status,
    required this.settledCount,
    this.message,
    this.orphanInvoiceId,
    this.orphanAmount,
  });

  final SplitRunStatus status;

  /// كم حصّةً سُوِّيت فعلاً في هذه الجولة.
  final int settledCount;

  /// رسالةٌ تُعرَض كما هي — تحمل الرقمين والفرقَ حين يكون الرفضُ لفرقٍ نقديّ.
  final String? message;

  final int? orphanInvoiceId;
  final double? orphanAmount;
}

/// ما تحتاجه [SplitSettlementRunner] من العالم الخارجيّ.
///
/// حلقةُ التسوية هي الموضعُ الذي يمسّ الدفاتر: تُصدر فواتيرَ حقيقيّةً
/// وتسجّل دفعات. وكانت تعيش في دوالَّ خاصّةٍ داخل حالةِ ودجت، فلم يكن
/// لها اختبارٌ واحد — وشاشاتُ هذا المستودع لا تُركَّب في اختبارات الويدجت
/// أصلاً (`db.close()` ينتظر مؤقّت drift في المنطقة الوهميّة). فُصلت
/// خلفَ هذا المنفذ لتُقاد بمنفذٍ وهميٍّ بلا قاعدةٍ ولا واجهة.
abstract class SplitSettlementPort {
  /// الخطّةُ الرسميّةُ مبنيّةً من حالة الطلب في القاعدة.
  Future<SplitPlan> buildPlan();

  /// الحصصُ التي لم تُسوَّ بعد. ترمي إن تغيّرت تركيبةُ التقسيم عمّا سُوّي.
  Future<List<SplitPart>> unsettledParts(SplitPlan plan);

  /// رقمُ الفاتورة التي سُوِّيت عليها الحصصُ السابقة، أو `null`.
  Future<int?> settledInvoiceId();

  /// يحجز حصّةً على الطلب — **كلُّ الحراس هنا، وقبل أيِّ ترحيل**. يعيد رقمَ
  /// الحجز. يرمي إن رفض حارس، ولا شيءَ يكون قد رُحِّل.
  Future<int> reservePart(SplitPart part);

  /// يربط حجزاً بفاتورةٍ صدرت. لا حسابَ مالٍ فيه فلا تردّه قاعدةُ عمل.
  Future<void> confirmPart(int reservationId, int invoiceId);

  /// يُحرِّر حجوزاً لم تصدر فاتورتُها — تراجُعٌ أو فشلُ ترحيل.
  Future<void> releaseReservations(List<int> reservationIds);

  /// يملأ السلّةَ بالأصناف المطلوبة ويعيد إجماليَّها **كما سيُشحَن** —
  /// بلا أيّ ترحيل. `null` تعني كلَّ أصناف الطلب.
  Future<double> fillCart(Map<int, double>? itemQuantities);

  /// يأخذ طريقةَ الدفع من الكاشير ويُرحّل الفاتورة، ويعيد رقمَها.
  /// `null` = تراجَع الكاشيرُ قبل أيّ ترحيل.
  Future<int?> payFilledCart(double chargeTotal);

  /// تقدُّمٌ للعرض بعد كلّ حصّةٍ سُوِّيت.
  void onPartSettled(SplitPart part);
}

/// حلقةُ تسوية التقسيم — استئنافٌ لا إعادةُ بدء، ورفضٌ قبل الترحيل لا بعده.
class SplitSettlementRunner {
  const SplitSettlementRunner(this._port);

  final SplitSettlementPort _port;

  /// [previewSum] إجماليُّ الخطّة كما رآه الكاشيرُ في المعاينة. اختلافُه عن
  /// الخطّة الطازجة يعني أن الطلبَ تغيّر والشاشةُ مفتوحة.
  Future<SplitRunResult> run({required double previewSum}) async {
    final plan = await _port.buildPlan();
    final freshSum = plan.parts.fold<double>(0, (s, p) => s + p.amount);
    if (tableMoneyUnits(freshSum) != tableMoneyUnits(previewSum)) {
      return const SplitRunResult(
        status: SplitRunStatus.aborted,
        settledCount: 0,
        message: 'تغيّر الطلبُ منذ فتح شاشة التقسيم — أعِد فتحها وحاول من '
            'جديد',
      );
    }

    final unsettled = await _port.unsettledParts(plan);
    if (unsettled.isEmpty) {
      return const SplitRunResult(
        status: SplitRunStatus.alreadyComplete,
        settledCount: 0,
      );
    }

    return plan.producesSeparateInvoices
        ? _runPerPartInvoices(unsettled)
        : _runSingleInvoice(plan, unsettled);
  }

  /// بالأصناف: لكلّ حصّةٍ فاتورتُها الخاصّة بأصنافها هي.
  Future<SplitRunResult> _runPerPartInvoices(List<SplitPart> unsettled) async {
    var settledCount = 0;
    for (final part in unsettled) {
      final cartTotal = await _port.fillCart(part.itemQuantities);
      final mismatch =
          checkTableCharge(charged: cartTotal, expected: part.amount);
      if (mismatch != null) {
        return SplitRunResult(
          status: SplitRunStatus.aborted,
          settledCount: settledCount,
          message: 'حصّةُ ${part.label}: ${mismatch.message}',
        );
      }

      // الحجزُ قبل الترحيل: كلُّ الحراس تعمل الآن، فإن رفضت لم تصدر فاتورة.
      final int reservationId;
      try {
        reservationId = await _port.reservePart(part);
      } catch (e) {
        return SplitRunResult(
          status: SplitRunStatus.aborted,
          settledCount: settledCount,
          message: 'حصّةُ ${part.label} رُفضت قبل الترحيل: $e',
        );
      }

      final invoiceId = await _port.payFilledCart(part.amount);
      if (invoiceId == null) {
        await _port.releaseReservations([reservationId]);
        return SplitRunResult(
          status: SplitRunStatus.aborted,
          settledCount: settledCount,
          message: 'أُلغيت طريقةُ الدفع عند حصّة ${part.label} — لم تُصدَر '
              'فاتورة',
        );
      }

      try {
        await _port.confirmPart(reservationId, invoiceId);
      } catch (e) {
        // لا يُحرَّر الحجز: فاتورتُه صدرت، وتحريرُه يمحو دفعةً حقيقيّة.
        return SplitRunResult(
          status: SplitRunStatus.reconcileNeeded,
          settledCount: settledCount,
          orphanInvoiceId: invoiceId,
          orphanAmount: part.amount,
          message: 'فاتورةُ حصّة ${part.label} صدرت والمبلغُ محجوزٌ، وتعذّر '
              'ربطُهما: $e',
        );
      }
      settledCount++;
      _port.onPartSettled(part);
    }
    return SplitRunResult(
      status: SplitRunStatus.success,
      settledCount: settledCount,
    );
  }

  /// بالتساوي وبمبلغ: فاتورةٌ واحدةٌ لكلّ الأصناف، وإيصالُ حصّةٍ لكلّ دافع.
  /// وعند الاستئناف تُعاد الفاتورةُ الأصليّةُ نفسُها — لا فاتورةٌ ثانيةٌ
  /// بالأصناف نفسِها (بيعٌ مضاعَفٌ حقيقيّ: مخزونٌ وقيودٌ مكرّرة).
  Future<SplitRunResult> _runSingleInvoice(
    SplitPlan plan,
    List<SplitPart> unsettled,
  ) async {
    final resuming = unsettled.length < plan.parts.length;
    final expected = unsettled.fold<double>(0, (s, p) => s + p.amount);

    // ── تُحجَز **كلُّ** الحصص الباقية أوّلاً ─────────────────────────────
    // فتعمل حراسُها جميعاً قبل أن تُرحَّل فاتورةٌ واحدة. ولو رفض حارسُ الحصّة
    // الأخيرة، حُرِّر ما قبله ولم يصدر شيء — بدل أن تُرحَّل الفاتورةُ ثم
    // يُكتشَف الرفضُ وقد فات الأوان.
    final reservationIds = <int>[];
    for (final part in unsettled) {
      try {
        reservationIds.add(await _port.reservePart(part));
      } catch (e) {
        await _port.releaseReservations(reservationIds);
        return SplitRunResult(
          status: SplitRunStatus.aborted,
          settledCount: 0,
          message: 'حصّةُ ${part.label} رُفضت قبل الترحيل: $e',
        );
      }
    }

    final int invoiceId;
    if (resuming) {
      final existing = await _port.settledInvoiceId();
      if (existing == null) {
        return const SplitRunResult(
          status: SplitRunStatus.aborted,
          settledCount: 0,
          message: 'تعذّر العثور على رقم الفاتورة الأصليّة للاستئناف',
        );
      }
      invoiceId = existing;
    } else {
      final cartTotal = await _port.fillCart(null);
      final mismatch =
          checkTableCharge(charged: cartTotal, expected: expected);
      if (mismatch != null) {
        await _port.releaseReservations(reservationIds);
        return SplitRunResult(
          status: SplitRunStatus.aborted,
          settledCount: 0,
          message: mismatch.message,
        );
      }
      final posted = await _port.payFilledCart(expected);
      if (posted == null) {
        await _port.releaseReservations(reservationIds);
        return const SplitRunResult(
          status: SplitRunStatus.aborted,
          settledCount: 0,
          message: 'أُلغيت طريقةُ الدفع — لم تُصدَر فاتورة',
        );
      }
      invoiceId = posted;
    }

    var settledCount = 0;
    var recorded = 0.0;
    for (var i = 0; i < unsettled.length; i++) {
      final part = unsettled[i];
      try {
        await _port.confirmPart(reservationIds[i], invoiceId);
      } catch (e) {
        // استئنافٌ ⇒ لا فاتورةَ صدرت في هذه الجولة، فلا شيءَ يتيم.
        if (resuming) {
          return SplitRunResult(
            status: SplitRunStatus.aborted,
            settledCount: settledCount,
            message: 'تعذّر ربطُ حصّة ${part.label}: $e',
          );
        }
        return SplitRunResult(
          status: SplitRunStatus.reconcileNeeded,
          settledCount: settledCount,
          orphanInvoiceId: invoiceId,
          orphanAmount: expected - recorded,
          message: 'الفاتورةُ صدرت والمبالغُ محجوزةٌ، وتعذّر ربطُ حصّة '
              '${part.label}: $e',
        );
      }
      recorded += part.amount;
      settledCount++;
      _port.onPartSettled(part);
    }
    return SplitRunResult(
      status: SplitRunStatus.success,
      settledCount: settledCount,
    );
  }
}
