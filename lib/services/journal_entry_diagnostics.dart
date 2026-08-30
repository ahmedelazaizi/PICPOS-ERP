/// Cluster 025 / Issue 1 (revised by Spec 139) — surface the last rounding
/// residual from `createJournalEntry` so callers (POS checkout, voucher
/// dialogs) can show a brief "تمت تسوية فروقات تقريب 0.00X" toast without
/// changing the DAO's `int` return type. Last-write-wins; the value is reset
/// to 0 at the start of each `createJournalEntry` invocation.
class JournalEntryDiagnostics {
  JournalEntryDiagnostics._();

  /// The signed difference (debit − credit) that Spec 139 booked to the
  /// dedicated «فروق تقريب» (rounding_difference) account during the most
  /// recent `createJournalEntry` call — NOT absorbed into a business leg.
  /// Zero when the JE was already balanced (the common case for credit sales /
  /// manual entries). Always within ±`FinancialUtils.balanceTolerance` (0.01)
  /// by construction; larger diffs are rejected with the
  /// "المدين لا يساوي الدائن" exception (dead-lettered by the sync worker).
  static double lastRoundingAdjustment = 0;

  /// فرقُ تقريب **سياسةِ البيع** (`pos_total_rounding`) في آخر بيعةٍ رُحِّلت
  /// — `total - roundedTotal`، مُرحَّلاً بسطرٍ صريحٍ على `4319`.
  ///
  /// ⚠️ **حقلٌ مستقلٌّ عن [lastRoundingAdjustment] عمداً — ولا يُدمَجان.**
  /// ذاك فتاتُ عائمٍ دون ٠٫٠١ لا يراه أحدٌ ولا يملك المشغّلُ حياله شيئاً؛
  /// وهذا **قرارُ سعرٍ رآه العميلُ على الإيصال** ويبلغ نصفَ جنيهٍ عند خيار
  /// «لأقرب جنيه». وخلطُهما في رسالةٍ واحدةٍ يجعل الكاشيرَ يقرأ تسويةً
  /// حسابيّةً حيث وقع تقريبُ ثمن، أو يتجاهل الاثنين معاً.
  ///
  /// يُصفَّر في مطلع `autoPostCashSale` لا في `createJournalEntry`: قيمتُه
  /// تُكتَب **قبل** بناء القيد، فتصفيرُها هناك كان سيمحوها قبل أن تُقرأ.
  static double lastPolicyRounding = 0;
}
