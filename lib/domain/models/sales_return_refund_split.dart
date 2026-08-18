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
/// [totalReturn] دائماً (في حدود دقّةِ العشريّات).
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
  /// ⚠️ هذه القائمةُ **أضيقُ** من نظيرتها في مسار البيع
  /// (`_recordSalesReceipt`: bank, card, transfer, visa, mastercard, amex,
  /// mada, stcpay). فمرتجعُ فاتورةٍ دُفعت بـ`visa` يخرج اليومَ **نقداً** من
  /// الدرج لا من الخزنة البنكيّة.
  ///
  /// نُقلت كما هي عن قصد: هذه المواصفةُ تنقل الحسابَ ولا تغيّره، وتوسيعُ
  /// القائمة تغييرُ سلوكٍ ماليٍّ يستحقّ قرارَه ومواصفتَه. مسجَّلٌ ولم يُعالَج.
  static const bankMethods = {'transfer', 'card', 'bank'};

  /// يعيد إنتاجَ منطقِ `returns_repository_impl` حرفيّاً (تقسيمُ المرتجع
  /// المدمجُ سابقاً داخل معاملةِ `processSalesReturn`).
  ///
  /// [hasCustomer] — الفاتورةُ مرتبطةٌ بعميل. بدونه لا مقاصّةَ ذمّةٍ إطلاقاً
  /// ويخرج المرتجعُ كلُّه دفعاً، وهو سلوكُ المسار الأصليّ
  /// (`if (invoice.customerId != null)`).
  factory SalesReturnRefundSplit.from({
    required double invoiceTotal,
    required double invoicePaid,
    required String? paymentMethod,
    required double cashPaid,
    required double bankPaid,
    required double totalReturn,
    required bool hasCustomer,
  }) {
    // ١) ما زال على العميل؟ يُقاصّ أوّلاً — فلا نعيد نقداً لمن لم يدفعه بعد.
    //    والقصُّ عند [totalReturn] يمنع مقاصّةً أكبرَ من المرتجع نفسه.
    var actualRefundToPay = totalReturn;
    var arRefund = 0.0;

    if (hasCustomer) {
      final oldRemaining =
          (invoiceTotal - invoicePaid).clamp(0.0, double.infinity);
      if (oldRemaining > 0) {
        final balanceCorrection = totalReturn.clamp(0.0, oldRemaining);
        arRefund = balanceCorrection;
        actualRefundToPay = totalReturn - balanceCorrection;
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

  /// كم نقداً يخرج من الدرج في مرتجعٍ يُنشَأ كـ**فاتورةٍ سالبة**
  /// (`createSalesInvoice(saleType:'return')`) — مسارُ «المرتجع السريع» في
  /// نقطة البيع، ومسارُ الخادم لمرتجعِ العميل.
  ///
  /// هذا المسارُ لا يقاصّ ذمّةً هنا (الـDAO يعالج `remaining` على حدة)، فلا
  /// يصلح له [SalesReturnRefundSplit.from]. الحسابُ يحاكي ما سيفعله
  /// `_recordSalesReceipt` بالضبط:
  ///   * مختلطٌ (`multiple`/`mixed`) بمبلغَين صريحَين ⇒ الشقُّ النقديُّ وحدَه.
  ///   * وإلا ⇒ `paid` كلُّه، ما لم تكن الطريقةُ بنكيّةً أو `click`.
  ///
  /// ⚠️ متى تغيّر توزيعُ `_recordSalesReceipt` فغيّر هذا معه: حارسٌ يقول «لا
  /// نقدَ هنا» ومسارٌ يُخرِج نقداً هو العطبُ الذي بُني الحارسُ لمنعه.
  static double cashOutForNegativeInvoice({
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
