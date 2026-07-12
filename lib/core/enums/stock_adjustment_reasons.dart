// ═══════════════════════════════════════════════════════════════════════════
// Stock Adjustment Reason Codes (I-04)
// Structured reason codes for inventory adjustments — enables analytics
// ═══════════════════════════════════════════════════════════════════════════

/// Mandatory reason selection for stock adjustments.
/// Stored as a structured prefix in the movement notes field:
/// `[REASON:damage] optional user notes`
enum StockAdjustmentReason {
  damage('damage', 'تلف', 'البضاعة تالفة أو معيبة'),
  theft('theft', 'سرقة', 'نقص ناتج عن سرقة'),
  countVariance('count_variance', 'فروقات جرد', 'فرق بين الجرد الفعلي والنظام'),
  systemError('system_error', 'خطأ نظام', 'تصحيح خطأ في النظام'),
  expired('expired', 'انتهاء صلاحية', 'بضاعة منتهية الصلاحية'),
  returnToSupplier('return_to_supplier', 'مرتجع مورد', 'إرجاع بضاعة للمورد'),
  initialBalance('initial_balance', 'رصيد افتتاحي', 'تعديل الرصيد الافتتاحي'),
  other('other', 'أخرى', 'سبب آخر (يرجى التوضيح)');

  const StockAdjustmentReason(this.code, this.label, this.description);

  /// Machine-readable code stored in notes prefix
  final String code;

  /// Arabic display label
  final String label;

  /// Arabic tooltip/description
  final String description;

  /// Format the reason + optional user notes into a structured string
  String formatWithNotes(String? userNotes) {
    final notes = userNotes?.trim() ?? '';
    if (notes.isEmpty) return '[REASON:$code]';
    return '[REASON:$code] $notes';
  }

  /// Parse a reason code from a structured notes string.
  /// Returns null if no reason prefix is found.
  static StockAdjustmentReason? fromNotes(String? notes) {
    if (notes == null || notes.isEmpty) return null;
    final match = RegExp(r'\[REASON:(\w+)\]').firstMatch(notes);
    if (match == null) return null;
    final code = match.group(1);
    return StockAdjustmentReason.values.cast<StockAdjustmentReason?>().firstWhere(
      (r) => r?.code == code,
      orElse: () => null,
    );
  }

  /// Extract user notes (without the reason prefix) from a structured string
  static String extractUserNotes(String? notes) {
    if (notes == null || notes.isEmpty) return '';
    return notes.replaceFirst(RegExp(r'\[REASON:\w+\]\s*'), '').trim();
  }
}
