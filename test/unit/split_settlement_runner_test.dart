// حلقةُ تسوية التقسيم — تُقاد بمنفذٍ وهميّ، بلا قاعدةٍ ولا واجهة.
//
// هذه هي الحلقةُ التي تمسّ الدفاتر: تُصدر فواتيرَ حقيقيّةً وتسجّل دفعات.
// وكانت تعيش في دوالَّ خاصّةٍ داخل حالةِ ودجت فلم يمسّها اختبارٌ واحد —
// وشاشاتُ هذا المستودع لا تُركَّب أصلاً في اختبارات الويدجت (`db.close()`
// ينتظر مؤقّت drift في المنطقة الوهميّة). المنفذُ الوهميُّ هنا يسجّل كلَّ
// نداءٍ فيُثبَت **ما لم يقع** بقدر ما يُثبَت ما وقع: أن الفاتورة لم تُرحَّل.
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/domain/models/split_plan.dart';
import 'package:picpos_erp/services/split_settlement_runner.dart';

class _FakePort implements SplitSettlementPort {
  _FakePort({
    required this.plan,
    required this.unsettled,
    this.existingInvoiceId,
    this.cartTotal,
    this.cancelPayment = false,
    this.settleThrowsOnLabel,
  });

  final SplitPlan plan;
  final List<SplitPart> unsettled;
  final int? existingInvoiceId;

  /// إجماليُّ السلّة الذي يعود من الملء. `null` = يطابق المتوقَّع تماماً.
  final double? cartTotal;

  /// رقمُ الفاتورة التي «تصدر» عن أيّ ترحيلٍ في هذا المنفذ.
  final int invoiceId = 900;
  bool cancelPayment;
  String? settleThrowsOnLabel;

  final List<Map<int, double>?> fills = [];
  final List<double> charges = [];
  final List<({String label, int invoiceId})> settled = [];
  final List<String> progress = [];

  @override
  Future<SplitPlan> buildPlan() async => plan;

  @override
  Future<List<SplitPart>> unsettledParts(SplitPlan plan) async => unsettled;

  @override
  Future<int?> settledInvoiceId() async => existingInvoiceId;

  /// الحجوزُ المُنشأةُ في هذه الجولة: رقمُ الحجز → الحصّة.
  final Map<int, SplitPart> reserved = {};
  final List<int> released = [];
  int _nextReservationId = 1;

  /// تسميةٌ يرفضها الحجزُ **قبل** الترحيل (حارسٌ يرمي).
  String? reserveThrowsOnLabel;

  @override
  Future<int> reservePart(SplitPart part) async {
    if (part.label == reserveThrowsOnLabel) {
      throw StateError('الدفعةُ تتجاوز المتبقّي');
    }
    final id = _nextReservationId++;
    reserved[id] = part;
    return id;
  }

  @override
  Future<void> confirmPart(int reservationId, int invoiceId) async {
    final part = reserved[reservationId];
    if (part == null) throw StateError('لا حجزَ #$reservationId');
    if (part.label == settleThrowsOnLabel) {
      throw StateError('تعذّر الربط');
    }
    settled.add((label: part.label, invoiceId: invoiceId));
  }

  @override
  Future<void> releaseReservations(List<int> reservationIds) async {
    released.addAll(reservationIds);
    for (final id in reservationIds) {
      reserved.remove(id);
    }
  }

  @override
  Future<double> fillCart(Map<int, double>? itemQuantities) async {
    fills.add(itemQuantities);
    if (cartTotal != null) return cartTotal!;
    // السلوكُ السليم: السلّةُ تساوي ما ستُسجَّله الحصصُ الباقية.
    if (itemQuantities == null) {
      return unsettled.fold<double>(0, (s, p) => s + p.amount);
    }
    return unsettled
        .firstWhere((p) => p.itemQuantities.keys.toSet().containsAll(
              itemQuantities.keys,
            ))
        .amount;
  }

  @override
  Future<int?> payFilledCart(double chargeTotal) async {
    if (cancelPayment) return null;
    charges.add(chargeTotal);
    return invoiceId;
  }

  @override
  void onPartSettled(SplitPart part) => progress.add(part.label);
}

double _sum(SplitPlan plan) =>
    plan.parts.fold<double>(0, (s, p) => s + p.amount);

void main() {
  group('الفحصُ القبليّ — لا ترحيلَ قبل التطابق', () {
    test('ضريبةٌ تضخّم السلّةَ ⇒ رفضٌ قبل أيّ فاتورة', () async {
      final plan = SplitPlan.equal(total: 100, ways: 2);
      // ١١٦ = ١٠٠ + ضريبة ١٦٪ من مفتاح شاشة الطاولة.
      final port = _FakePort(
          plan: plan, unsettled: plan.parts, cartTotal: 116);

      final result =
          await SplitSettlementRunner(port).run(previewSum: _sum(plan));

      expect(result.status, SplitRunStatus.aborted);
      expect(result.settledCount, 0);
      expect(result.message, contains('116.000'));
      expect(result.message, contains('100.000'));
      expect(port.charges, isEmpty, reason: 'لم تُرحَّل فاتورةٌ أصلاً');
      expect(port.settled, isEmpty);
    });

    test('صنفٌ محذوفٌ ينقص السلّةَ ⇒ رفضٌ قبل أيّ فاتورة', () async {
      final plan = SplitPlan.equal(total: 100, ways: 2);
      final port =
          _FakePort(plan: plan, unsettled: plan.parts, cartTotal: 70);

      final result =
          await SplitSettlementRunner(port).run(previewSum: _sum(plan));

      expect(result.status, SplitRunStatus.aborted);
      expect(port.charges, isEmpty);
      expect(port.settled, isEmpty);
    });

    test('التطابقُ يمضي ⇒ فاتورةٌ واحدةٌ وإيصالٌ لكلّ دافع', () async {
      final plan = SplitPlan.equal(total: 100, ways: 4);
      final port = _FakePort(plan: plan, unsettled: plan.parts);

      final result =
          await SplitSettlementRunner(port).run(previewSum: _sum(plan));

      expect(result.status, SplitRunStatus.success);
      expect(result.settledCount, 4);
      expect(port.charges, [100], reason: 'فاتورةٌ واحدةٌ لكلّ الأصناف');
      expect(port.settled.map((s) => s.invoiceId).toSet(), {900});
      expect(port.progress, plan.parts.map((p) => p.label));
    });

    test('تغيُّرُ الطلب منذ المعاينة ⇒ رفضٌ قبل أيّ فاتورة', () async {
      final plan = SplitPlan.equal(total: 100, ways: 2);
      final port = _FakePort(plan: plan, unsettled: plan.parts);

      final result =
          await SplitSettlementRunner(port).run(previewSum: 120);

      expect(result.status, SplitRunStatus.aborted);
      expect(port.fills, isEmpty);
      expect(port.charges, isEmpty);
    });
  });

  group('الاستئنافُ لا إعادةُ البدء', () {
    test('حصّتان من أربعٍ سُوِّيتا ⇒ لا فاتورةَ ثانيةً بالمرّة', () async {
      final plan = SplitPlan.equal(total: 100, ways: 4);
      final port = _FakePort(
        plan: plan,
        unsettled: [plan.parts[2], plan.parts[3]],
        existingInvoiceId: 77,
      );

      final result =
          await SplitSettlementRunner(port).run(previewSum: _sum(plan));

      expect(result.status, SplitRunStatus.success);
      expect(result.settledCount, 2);
      // الدليلُ الحقيقيّ: لا ملءَ سلّةٍ ولا ترحيل — إعادةُ الإصدار هنا تعني
      // مخزوناً يُخصَم مرّتين وقيداً محاسبيّاً مضاعَفاً.
      expect(port.fills, isEmpty);
      expect(port.charges, isEmpty);
      expect(port.settled, [
        (label: 'ضيف 3', invoiceId: 77),
        (label: 'ضيف 4', invoiceId: 77),
      ]);
    });

    test('استئنافٌ بلا فاتورةٍ أصليّةٍ ⇒ رفضٌ لا فاتورةٌ جديدة', () async {
      final plan = SplitPlan.equal(total: 100, ways: 4);
      final port = _FakePort(
        plan: plan,
        unsettled: [plan.parts[3]],
        existingInvoiceId: null,
      );

      final result =
          await SplitSettlementRunner(port).run(previewSum: _sum(plan));

      expect(result.status, SplitRunStatus.aborted);
      expect(port.charges, isEmpty);
    });

    test('لا حصّةَ باقية ⇒ مكتملٌ بلا أيّ حركة', () async {
      final plan = SplitPlan.equal(total: 100, ways: 2);
      final port = _FakePort(plan: plan, unsettled: const []);

      final result =
          await SplitSettlementRunner(port).run(previewSum: _sum(plan));

      expect(result.status, SplitRunStatus.alreadyComplete);
      expect(port.charges, isEmpty);
      expect(port.settled, isEmpty);
    });
  });

  group('الفجوةُ بين الترحيل والتسجيل', () {
    test('فاتورةٌ صدرت وتعذّر تسجيلُها ⇒ تحتاج تسويةً برقمها ومبلغها',
        () async {
      final plan = SplitPlan.equal(total: 100, ways: 2);
      final port = _FakePort(
        plan: plan,
        unsettled: plan.parts,
        settleThrowsOnLabel: 'ضيف 2',
      );

      final result =
          await SplitSettlementRunner(port).run(previewSum: _sum(plan));

      expect(result.status, SplitRunStatus.reconcileNeeded);
      expect(result.orphanInvoiceId, 900);
      expect(result.settledCount, 1);
      // ٥٠ سُجِّلت و٥٠ لم تُسجَّل من فاتورةٍ قيمتُها ١٠٠.
      expect(result.orphanAmount, 50);
    });

    test('فشلُ التسجيل أثناء استئنافٍ ليس فجوةً — لا فاتورةَ صدرت', () async {
      final plan = SplitPlan.equal(total: 100, ways: 4);
      final port = _FakePort(
        plan: plan,
        unsettled: [plan.parts[2], plan.parts[3]],
        existingInvoiceId: 77,
        settleThrowsOnLabel: 'ضيف 3',
      );

      final result =
          await SplitSettlementRunner(port).run(previewSum: _sum(plan));

      expect(result.status, SplitRunStatus.aborted);
      expect(result.orphanInvoiceId, isNull);
    });

    test('تراجُعُ الكاشير عن ورقة الدفع ⇒ لا فاتورةَ ولا تسجيل', () async {
      final plan = SplitPlan.equal(total: 100, ways: 2);
      final port = _FakePort(
        plan: plan,
        unsettled: plan.parts,
        cancelPayment: true,
      );

      final result =
          await SplitSettlementRunner(port).run(previewSum: _sum(plan));

      expect(result.status, SplitRunStatus.aborted);
      expect(port.settled, isEmpty);
    });
  });

  group('بالأصناف — فاتورةٌ لكلّ دافع', () {
    SplitPlan byItemsPlan() => SplitPlan.byItems(
          items: const [
            SplitItem(itemId: 1, quantity: 1, lineTotal: 60),
            SplitItem(itemId: 2, quantity: 1, lineTotal: 40),
          ],
          assignment: const {1: 0, 2: 1},
          ways: 2,
        );

    test('كلُّ حصّةٍ تُملأ وتُرحَّل وتُسجَّل بفاتورتها', () async {
      final plan = byItemsPlan();
      final port = _FakePort(plan: plan, unsettled: plan.parts);

      final result =
          await SplitSettlementRunner(port).run(previewSum: _sum(plan));

      expect(result.status, SplitRunStatus.success);
      expect(port.fills, hasLength(2));
      expect(port.charges, [60, 40]);
      expect(port.settled.map((s) => s.label), ['ضيف 1', 'ضيف 2']);
    });

    test('فرقٌ في حصّةٍ يوقف الحلقةَ عندها ويُبقي ما قبلها مسجَّلاً',
        () async {
      final plan = byItemsPlan();
      // السلّةُ تعود ٦٠ دوماً: الحصّةُ الأولى تطابق، والثانيةُ (٤٠) لا.
      final port =
          _FakePort(plan: plan, unsettled: plan.parts, cartTotal: 60);

      final result =
          await SplitSettlementRunner(port).run(previewSum: _sum(plan));

      expect(result.status, SplitRunStatus.aborted);
      expect(result.settledCount, 1);
      expect(port.charges, [60], reason: 'الحصّةُ الثانية لم تُرحَّل');
      expect(result.message, contains('ضيف 2'));
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  group('حجزٌ ثم ترحيلٌ ثم تثبيت — النافذةُ مغلقةٌ على مسار التقسيم', () {
    test('حارسُ الحجز يرفض ⇒ لا فاتورةَ تُرحَّل أصلاً', () async {
      final plan = SplitPlan.equal(total: 100, ways: 2);
      final port = _FakePort(plan: plan, unsettled: plan.parts)
        // الحصّةُ الثانيةُ يرفضها حارسٌ عند الحجز.
        ..reserveThrowsOnLabel = plan.parts[1].label;

      final result =
          await SplitSettlementRunner(port).run(previewSum: _sum(plan));

      expect(result.status, SplitRunStatus.aborted);
      // بيتُ القصيد: الرفضُ وقع **قبل** أن تُرحَّل فاتورة.
      expect(port.charges, isEmpty, reason: 'لا فاتورةَ صدرت');
      expect(port.settled, isEmpty);
    });

    test('رفضُ حصّةٍ يُحرِّر ما حُجز قبلها — لا مالَ معلّقٌ بلا سبب', () async {
      final plan = SplitPlan.equal(total: 100, ways: 3);
      final port = _FakePort(plan: plan, unsettled: plan.parts)
        ..reserveThrowsOnLabel = plan.parts[2].label;

      await SplitSettlementRunner(port).run(previewSum: _sum(plan));

      // حُجزت اثنتان قبل الرفض، فوجب تحريرُهما.
      expect(port.released, hasLength(2));
      expect(port.reserved, isEmpty);
    });

    test('تراجُعُ الكاشير بعد الحجز ⇒ تُحرَّر كلُّ الحجوز', () async {
      final plan = SplitPlan.equal(total: 100, ways: 3);
      final port = _FakePort(plan: plan, unsettled: plan.parts)
        ..cancelPayment = true;

      final result =
          await SplitSettlementRunner(port).run(previewSum: _sum(plan));

      expect(result.status, SplitRunStatus.aborted);
      expect(port.released, hasLength(3));
      expect(port.settled, isEmpty);
    });

    test('فشلُ الربط بعد الترحيل ⇒ تسويةٌ مطلوبةٌ ولا يُحرَّر الحجز', () async {
      final plan = SplitPlan.equal(total: 100, ways: 2);
      final port = _FakePort(plan: plan, unsettled: plan.parts)
        ..settleThrowsOnLabel = plan.parts[0].label;

      final result =
          await SplitSettlementRunner(port).run(previewSum: _sum(plan));

      expect(result.status, SplitRunStatus.reconcileNeeded);
      expect(result.orphanInvoiceId, isNotNull);
      // الفاتورةُ صدرت — تحريرُ الحجز هنا يمحو دفعةً حقيقيّة.
      expect(port.released, isEmpty);
    });
  });
}
