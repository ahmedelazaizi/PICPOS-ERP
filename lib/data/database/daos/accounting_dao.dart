part of '../database.dart';

extension AccountingDao on AppDatabase {
  static Map<String, String> get accountPurposes =>
      AccountingDaoReadsExt.accountPurposes;

  /// هل وقع أثرٌ ماليٌّ واحدٌ على الأقلّ في هذه التنصيبة؟
  ///
  /// ── لماذا تُسأل (‏م-٢، قرارُ المالك 2026-08-23) ─────────────────────────
  /// دقّةُ العملة صارت تتبع العملةَ (الدينارُ ٣ والجنيهُ ٢). فتبديلُ العملة
  /// **بعد** أن تُكتب أرقامٌ في الدفاتر يُعيد حسابَ مبلغٍ `12.345` إلى
  /// `12.35`، وقيدٌ اتّزن بثلاث خاناتٍ قد يختلّ بخانتين — والسماحُ نفسُه
  /// يضيق من ١٠ وحداتٍ صغرى إلى **١**. فالعملةُ قرارُ تنصيبٍ لا تفضيلُ
  /// عرض: حرّةٌ في معالج البدء، مقفولةٌ بعد أوّل أثر.
  ///
  /// ── وما يُعَدّ أثراً ─────────────────────────────────────────────────
  /// فاتورةُ بيعٍ أو شراءٍ أو حركةُ خزنة — **غيرُ الملغاة**. والقيودُ لا
  /// تُسأل عنها استقلالاً: كلُّ قيدٍ تلقائيٍّ يتولّد عن أحدِ هذه الثلاثة،
  /// وسؤالُها يفتح بابَ قفلٍ مبكّرٍ لو زُرعت أرصدةٌ افتتاحيّةٌ عند الإقلاع
  /// (فتُقفَل العملةُ قبل أن يصل المستخدمُ إلى المعالج أصلاً).
  Future<bool> hasAnyFinancialMovement() async {
    Future<bool> any(String table) async {
      final row = await customSelect(
        'SELECT 1 FROM $table WHERE is_deleted = ${sqlBool(false)} LIMIT 1',
      ).getSingleOrNull();
      return row != null;
    }

    if (await any('sales_invoices')) return true;
    if (await any('purchase_invoices')) return true;

    // ‏`safe_transactions` تحذف منطقيّاً بـ`deleted_at` لا بـ`is_deleted`.
    final safeRow = await customSelect(
      'SELECT 1 FROM safe_transactions WHERE deleted_at IS NULL LIMIT 1',
    ).getSingleOrNull();
    return safeRow != null;
  }
}
