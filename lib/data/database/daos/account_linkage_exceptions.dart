// ═══════════════════════════════════════════════════════════════════════════
// ACCOUNT LINKAGE EXCEPTIONS — Feature 004 (Multi-Branch Governance, US1)
// ═══════════════════════════════════════════════════════════════════════════
//
// Exception types thrown by the atomic safe-and-fixed-asset auto-account
// creation paths in [TreasuryDao.createSafeWithLinkedAccount] and
// [FixedAssetsDao.createFixedAsset]. They surface configuration problems
// (missing parent account, missing category account) so the dialog layer
// can render a clear Arabic error to the user without leaking the partial
// transaction state — both methods roll back atomically before throwing.
// ═══════════════════════════════════════════════════════════════════════════

/// Thrown when the parent account expected for safe linkage (typically
/// code `1110` — "النقدية فى الصناديق") is absent from the deployed Chart
/// of Accounts. The save is aborted and no partial rows are persisted.
class MissingParentAccountException implements Exception {
  /// The code of the parent account that should exist (e.g. '1110').
  final String parentCode;

  /// A short Arabic hint describing what the user can do to recover (e.g.
  /// "يرجى إنشاء الحساب من شاشة دليل الحسابات قبل إعادة المحاولة.").
  final String hint;

  const MissingParentAccountException(this.parentCode, this.hint);

  @override
  String toString() => 'الحساب الأب غير موجود: $parentCode. $hint';
}

/// Thrown when a fixed-asset category exists but its `accountId` field
/// (the asset acquisition account) is null. Without this linkage the
/// per-asset sub-account has no parent under which to be created.
class MissingCategoryAccountException implements Exception {
  /// The local id of the category whose `accountId` is missing.
  final int categoryId;

  /// The category's display name, copied for the error message so the
  /// user can locate it on the categories screen.
  final String categoryName;

  const MissingCategoryAccountException(this.categoryId, this.categoryName);

  @override
  String toString() =>
      'فئة الأصل "$categoryName" غير مرتبطة بحساب فى دليل الحسابات. '
      'يرجى ربطها قبل إنشاء أصول جديدة.';
}
