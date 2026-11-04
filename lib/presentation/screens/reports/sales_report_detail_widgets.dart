// FS-16: moved verbatim out of sales_report_screen.dart to keep that file under
// its size-ratchet ceiling (no behaviour change). Imports live in the library.
part of 'sales_report_screen.dart';

/// Small label-over-value block used in the invoice details header.
class _MetaField extends StatelessWidget {
  final String label;
  final String value;

  const _MetaField({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(fontSize: 11, color: context.picposMuted),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}

/// One line of the totals stack in the invoice details dialog.
class _TotalRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? color;
  final bool emphasize;

  const _TotalRow({
    required this.label,
    required this.value,
    this.color,
    this.emphasize = false,
  });

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontSize: emphasize ? 15 : 13,
      fontWeight: emphasize ? FontWeight.bold : FontWeight.w500,
      color: color,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: style),
          Text(value, style: style),
        ],
      ),
    );
  }
}

/// Status chip in the invoice details title. A posted (locked) invoice is
/// called out explicitly because it cannot be edited — the cashier asking
/// "why can't I change this?" should be able to see the answer.
class _StatusPill extends StatelessWidget {
  final String status;
  final bool isLocked;

  const _StatusPill({required this.status, required this.isLocked});

  @override
  Widget build(BuildContext context) {
    final (String label, Color color) = switch (status) {
      'cancelled' || 'canceled' => (tr('ملغاة'), AppColors.error),
      'returned' => (tr('مرتجعة'), AppColors.warning),
      'draft' => (tr('مسودة'), context.picposMuted),
      _ => isLocked
          ? (tr('مُرحّلة'), AppColors.success)
          : (tr('مكتملة'), AppColors.success),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: color,
        ),
      ),
    );
  }
}
