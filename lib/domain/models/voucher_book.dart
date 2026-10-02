import '../../core/i18n/tr.dart';

// دفاترُ سندات القبض والصرف — المرحلة هـ / E3.
//
// يعيش النموذجُ هنا لا في الـDAO: شاشاتُ العرض الجديدة ممنوعةٌ من استيراد
// `data/database` (‏`presentation_db_import_guard`)، فيقرؤه الـDAO والشاشةُ معاً.

/// A rejected leaf / book operation. [key] is the Arabic catalog key (with
/// `{p0}`-style placeholders) so the message follows the UI language.
class VoucherBookException implements Exception {
  VoucherBookException(this.key, [this.params = const {}]);
  final String key;
  final Map<String, Object?> params;

  String get message => tr(key, params);

  @override
  String toString() => message;
}

/// A burnt (damaged / void) leaf.
class VoucherBookCancelledLeaf {
  const VoucherBookCancelledLeaf({
    required this.number,
    required this.reason,
    required this.cancelledAt,
  });
  final int number;
  final String reason;
  final DateTime cancelledAt;
}

/// One row of `voucher_books`.
class VoucherBook {
  const VoucherBook({
    required this.id,
    required this.type,
    required this.rangeFrom,
    required this.rangeTo,
    required this.nextNumber,
    required this.status,
    this.prefix,
    this.label,
    this.holderEmployeeId,
    this.holderUserId,
    this.branchId,
    this.notes,
    this.usedCount = 0,
  });

  final int id;

  /// `receipt` | `payment`.
  final String type;
  final int rangeFrom;
  final int rangeTo;
  final int nextNumber;

  /// `active` | `closed` | `cancelled`.
  final String status;
  final String? prefix;
  final String? label;
  final int? holderEmployeeId;
  final int? holderUserId;
  final int? branchId;
  final String? notes;

  /// Leaves consumed (used by a voucher or cancelled).
  final int usedCount;

  int get size => rangeTo - rangeFrom + 1;
  int get remaining => (size - usedCount).clamp(0, size);

  String get displayName => (label != null && label!.trim().isNotEmpty)
      ? label!
      : '${prefix ?? ''}$rangeFrom–${prefix ?? ''}$rangeTo';

  /// The leaf as printed: prefix + number.
  String leafLabel(int number) => '${prefix ?? ''}$number';
}
