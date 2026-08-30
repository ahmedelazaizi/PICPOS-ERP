import '../../core/constants/payment_methods.dart';
// ═══════════════════════════════════════════════════════════════════════════
// تقسيمُ مرتجعِ المبيعات: كم يعود ذمّةً، وكم يخرج نقداً، وكم يخرج بنكاً
// ═══════════════════════════════════════════════════════════════════════════
//
// حسابٌ خالصٌ واحدٌ يُجيب سؤالاً واحداً: مرتجعٌ بقيمة [totalReturn] على فاتورةٍ
// معلومةٍ — كيف ينقسم؟
//
// ولماذا خرج من `returns_repository_impl` إلى هنا:
//
// حارسُ «لا صرفَ نقديٍّ بلا ورديّةٍ مفتوحة» لا بدّ أن يعرف **قبل** فتحِ
// المعاملة هل سيخرج نقدٌ أصلاً. وكان الحسابُ مدفوناً **داخل** المعاملة، فلو
// نُسخ للحارس لصار في المستودع نسختان تُجيبان سؤالاً واحداً — وتنحرفان يوماً.
// وانحرافُ الحارسِ عن السلوك هو بعينُه شكلُ العطبِ الذي جاء الحارسُ ليمنعه:
// حارسٌ يقول «لا نقدَ هنا» ومسارٌ يُخرِج نقداً.
//
// فالدالّةُ تُستدعى مرّتين بنفس الدخل — مرّةً للحارس ومرّةً للتنفيذ — ويستحيل
// أن يتنبّأ الحارسُ بغير ما يقع.
//
// موضعُه `domain/models` لا `data/`: حسابٌ خالصٌ بلا قاعدةِ بيانات، وقاعدةُ
// البيت أن الحسابَ الخالص يعيش هنا (‏Constitution §IV، وحارسُ
// `presentation_db_import_guard`). ولا يستورد هذا الملفُّ شيئاً إطلاقاً.

/// نتيجةُ تقسيمِ مرتجعٍ واحد.
///
/// الحاصلاتُ الثلاثةُ ([arRefund] و[cashRefund] و[bankRefund]) مجموعُها
/// [totalReturn] دائماً (في حدود دقّةِ العشريّات) — **ما لم يُمرَّر
/// `invoiceRoundingAdjustment` غيرَ صفرٍ على مرتجعٍ كامل**، فيكون المجموعُ
/// حينها `totalReturn - invoiceRoundingAdjustment`، والفرقُ يقابله سطرُ
/// `4319 فروق تقريب` في قيد المرتجع.
class SalesReturnRefundSplit {
  /// ما قوصص من ذمّةِ العميل بدل أن يُدفع — لا يمسّ درجاً.
  final double arRefund;

  /// ما يخرج نقداً من الدرج. **هذا وحدَه ما يشترط ورديّةً مفتوحة.**
  final double cashRefund;

  /// ما يخرج من خزنةٍ بنكيّة — لا يدخل `expectedCash` أصلاً، فلا ورديّةَ له.
  final double bankRefund;

  /// ما بقي بعد مقاصّةِ الذمّة، أي `cashRefund + bankRefund`.
  final double actualRefundToPay;

  const SalesReturnRefundSplit({
    required this.arRefund,
    required this.cashRefund,
    required this.bankRefund,
    required this.actualRefundToPay,
  });

  /// طرقُ الدفع التي تُعَدّ «بنكيّة» في مسار المرتجع.
  ///
  /// كانت هنا قائمةٌ ضيّقةٌ خاصّةٌ بالمرتجع (`transfer, card, bank` فقط)
  /// تخالف نظيرتَها في مسار البيع. فبيعةُ `visa` تدخل الخزنةَ البنكيّة
  /// ومرتجعُها يخرج نقداً من الدرج — عجزٌ في درجٍ ورصيدٌ بنكيٌّ وهميّ، ولا
  /// يتقاصّان أبداً. صارت تشير إلى المصدر المشترك.
  static const bankMethods = kBankPaymentMethods;

  /// يعيد إنتاجَ منطقِ `returns_repository_impl` حرفيّاً (تقسيمُ المرتجع
  /// المدمجُ سابقاً داخل معاملةِ `processSalesReturn`).
  ///
  /// [hasCustomer] — الفاتورةُ مرتبطةٌ بعميل. بدونه لا مقاصّةَ ذمّةٍ إطلاقاً
  /// ويخرج المرتجعُ كلُّه دفعاً، وهو سلوكُ المسار الأصليّ
  /// (`if (invoice.customerId != null)`).
  /// [invoiceRoundingAdjustment] — فرقُ تقريب الإجماليّ على الفاتورة الأصليّة
  /// (`total - roundedTotal`). **افتراضُه صفرٌ فيبقى السلوكُ السابقُ حرفاً
  /// بحرف** لكلِّ منادٍ لا يمرّرُه.
  ///
  /// بدونه يقع عطبان على مرتجعِ بيعةٍ قُرِّبت:
  ///   • `oldRemaining` تُقرأ ٠٫٠٢ فيُقاصّ مبلغٌ من ذمّةٍ **لم تُفتح أصلاً**
  ///     (‏قيدُ البيع لم يَعُد يُثبت مديناً بفرق التقريب) ⇒ رصيدٌ دائنٌ وهميٌّ
  ///     على حساب المراقبة.
  ///   • والمرتجعُ الكاملُ يردّ ١١٤٫٠٧ بينما المقبوضُ كان ١١٤٫٠٥ ⇒ قرشان
  ///     يخرجان من الدرج لم يدخلاه قطّ.
  factory SalesReturnRefundSplit.from({
    required double invoiceTotal,
    required double invoicePaid,
    required String? paymentMethod,
    required double cashPaid,
    required double bankPaid,
    required double totalReturn,
    required bool hasCustomer,
    double invoiceRoundingAdjustment = 0,
  }) {
    // ٠) عكسُ التقريب — **على المرتجع الكامل وحدَه.**
    //
    // التقريبُ وقع على تسويةِ الفاتورة كلِّها لا على سطرٍ بعينه، فلا معنى
    // لتوزيعه على مرتجعٍ جزئيّ: نصفُ الأصناف لا يحمل نصفَ قرشِ التقريب.
    // والمرتجعُ الجزئيُّ يترك الفاتورةَ قائمةً بتقريبها كما هو.
    final isFullReturn = invoiceRoundingAdjustment != 0 &&
        totalReturn >= invoiceTotal - 0.01;
    final roundingReversal = isFullReturn ? invoiceRoundingAdjustment : 0.0;

    // ١) ما زال على العميل؟ يُقاصّ أوّلاً — فلا نعيد نقداً لمن لم يدفعه بعد.
    //    والقصُّ عند [totalReturn] يمنع مقاصّةً أكبرَ من المرتجع نفسه.
    var actualRefundToPay = totalReturn - roundingReversal;
    var arRefund = 0.0;

    if (hasCustomer) {
      // ⚠️ **وفرقُ التقريب يُطرَح — فهو ليس ديناً باقياً على العميل.**
      final oldRemaining =
          (invoiceTotal - invoicePaid - invoiceRoundingAdjustment)
              .clamp(0.0, double.infinity);
      if (oldRemaining > 0) {
        final balanceCorrection =
            actualRefundToPay.clamp(0.0, oldRemaining);
        arRefund = balanceCorrection;
        actualRefundToPay -= balanceCorrection;
      }
    }

    // ٢) الباقي يُدفع — بنفس الطريقةِ التي قُبض بها.
    var cashRefund = 0.0;
    var bankRefund = 0.0;

    if (actualRefundToPay > 0) {
      if (paymentMethod == 'multiple' || paymentMethod == 'mixed') {
        // تناسبٌ بما قُبض فعلاً. و`totalPaid == 0` على فاتورةٍ مختلطةٍ حالةٌ
        // شاذّةٌ (مختلطةٌ ولم يُقبض منها شيء) — تُعامَل نقداً كما كانت.
        final totalPaid = cashPaid + bankPaid;
        if (totalPaid > 0) {
          cashRefund = actualRefundToPay * (cashPaid / totalPaid);
          bankRefund = actualRefundToPay * (bankPaid / totalPaid);
        } else {
          cashRefund = actualRefundToPay;
        }
      } else if (bankMethods.contains(paymentMethod)) {
        bankRefund = actualRefundToPay;
      } else {
        // نقدٌ، وآجلٌ سُدِّد، وكلُّ ما عداه — بما فيه `paymentMethod == null`.
        cashRefund = actualRefundToPay;
      }
    }

    return SalesReturnRefundSplit(
      arRefund: arRefund,
      cashRefund: cashRefund,
      bankRefund: bankRefund,
      actualRefundToPay: actualRefundToPay,
    );
  }

  /// هل يستلزم هذا المرتجعُ فتحَ درج؟ (‏ح‑١ في المواصفة)
  bool get requiresOpenShift => cashRefund > 0;

  /// كم نقداً **يمسّ الدرج** في فاتورةٍ تمرّ بـ`createSalesInvoice` — بيعةً
  /// كانت (نقدٌ يدخل) أو مرتجعاً سريعاً (نقدٌ يخرج). القيمةُ مطلقةٌ في
  /// الحالتين: السؤالُ «هل يتحرّك الدرج؟» لا «في أيّ اتجاه».
  ///
  /// هذا المسارُ لا يقاصّ ذمّةً في موضعه (الـDAO يعالج `remaining` على حدة)،
  /// فلا يصلح له [SalesReturnRefundSplit.from]. الحسابُ يحاكي ما سيفعله
  /// `_recordSalesReceipt` بالضبط:
  ///   * مختلطٌ (`multiple`/`mixed`) بمبلغَين صريحَين ⇒ الشقُّ النقديُّ وحدَه.
  ///   * وإلا ⇒ `paid` كلُّه، ما لم تكن الطريقةُ بنكيّةً أو `click`.
  ///
  /// ⚠️ متى تغيّر توزيعُ `_recordSalesReceipt` فغيّر هذا معه: حارسٌ يقول «لا
  /// نقدَ هنا» ومسارٌ يحرّك الدرجَ هو العطبُ الذي بُني الحارسُ لمنعه.
  static double cashTouchingDrawer({
    required double paid,
    required String paymentMethod,
    double? cashAmount,
    double? bankAmount,
  }) {
    if ((paymentMethod == 'multiple' || paymentMethod == 'mixed') &&
        cashAmount != null &&
        bankAmount != null) {
      return cashAmount.abs();
    }
    if (bankMethods.contains(paymentMethod) || paymentMethod == 'click') {
      return 0;
    }
    return paid.abs();
  }

  @override
  String toString() => 'SalesReturnRefundSplit(ar: $arRefund, '
      'cash: $cashRefund, bank: $bankRefund, pay: $actualRefundToPay)';
}
