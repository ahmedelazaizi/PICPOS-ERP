/// Status of a stock requisition — canonical 4-value vocabulary (Spec 148).
///
/// One source of truth used across creation, storage, reading, badge display
/// and filtering. Use [statusToDb] / [parseStatus] to cross the enum ↔ DB-string
/// boundary; never compare a [RequisitionStatus] to a raw string (the old
/// `enum == String` defect silently always evaluated to false).
enum RequisitionStatus {
  /// Created, awaiting an approve/reject decision. Default for new rows.
  pending,

  /// Reserved: approval recorded but the fulfilling transfer not yet
  /// materialized (future two-step flow). Not persisted on the happy path —
  /// a successful approval goes straight to [fulfilled].
  approved,

  /// Declined by an authorized user. Terminal; no inventory/GL effect.
  rejected,

  /// Goods issued via a warehouse transfer. Terminal; carries the transfer id.
  fulfilled,
}

/// Canonical DB string for a [RequisitionStatus] (exhaustive).
String statusToDb(RequisitionStatus s) {
  switch (s) {
    case RequisitionStatus.pending:
      return 'pending';
    case RequisitionStatus.approved:
      return 'approved';
    case RequisitionStatus.rejected:
      return 'rejected';
    case RequisitionStatus.fulfilled:
      return 'fulfilled';
  }
}

/// Parse a stored status string. Any unrecognized/legacy value (e.g. old
/// `draft`/`submitted`) maps to [RequisitionStatus.pending] so legacy rows
/// still render and filter safely.
RequisitionStatus parseStatus(String s) {
  switch (s) {
    case 'approved':
      return RequisitionStatus.approved;
    case 'rejected':
      return RequisitionStatus.rejected;
    case 'fulfilled':
      return RequisitionStatus.fulfilled;
    case 'pending':
    default:
      return RequisitionStatus.pending;
  }
}
