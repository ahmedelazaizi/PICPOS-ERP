part of '../database.dart';

// ═══════════════════════════════════════════════════════════════════════════
// متابعةُ التحصيل ومطالبةُ المورد — قراءةٌ وكتابة (v165)
// ═══════════════════════════════════════════════════════════════════════════
//
// ⚠️ **لا شيءَ هنا يحرّك مالاً.** الجدولان سجلّا تواصلٍ لا قيدَين: لا خزنةَ
// ولا ذمّةَ ولا قيدَ محاسبيّ. والمالُ يتحرّك بسندِ قبضٍ أو صرفٍ — وهما
// مساران قائمان لا يُنسَخان هنا.

extension PartyEngagementDao on AppDatabase {
  // ── متابعةُ التحصيل ──────────────────────────────────────────────────────

  /// متابعاتُ طرفٍ من الأحدث — كلُّها أو ما يخصّ فاتورةً بعينها.
  Future<List<PartyFollowUp>> getPartyFollowUps(
    int partyId, {
    int? invoiceId,
    int limit = 50,
  }) {
    final q = select(partyFollowUps)
      ..where((f) => f.partyId.equals(partyId) & f.deletedAt.isNull())
      ..orderBy([(f) => OrderingTerm.desc(f.contactedAt)])
      ..limit(limit);
    if (invoiceId != null) {
      q.where((f) => f.invoiceId.equals(invoiceId));
    }
    return q.get();
  }

  /// عددُ المحاولات السابقة — «محاولات سابقة» في التصميم، عدٌّ لا عمود.
  Future<int> countPartyFollowUps(int partyId, {int? invoiceId}) async {
    final rows = await getPartyFollowUps(partyId, invoiceId: invoiceId);
    return rows.length;
  }

  /// وعودٌ حلّ موعدُها ولم تُسدَّد — تُقرأ في القائمة، **ولا مؤقّتَ يوقظها**.
  Future<List<PartyFollowUp>> getOverduePromises({DateTime? asOf}) {
    final at = asOf ?? DateTime.now();
    return (select(partyFollowUps)
          ..where((f) =>
              f.deletedAt.isNull() &
              f.outcome.equals('promise') &
              f.promisedDate.isSmallerOrEqualValue(at))
          ..orderBy([(f) => OrderingTerm.asc(f.promisedDate)]))
        .get();
  }

  Future<int> insertPartyFollowUp(PartyFollowUpsCompanion row) =>
      into(partyFollowUps).insert(row);

  /// حذفٌ ناعم — السجلُّ يبقى للتاريخ، والمزامنةُ تحتاج الصفَّ لا غيابَه.
  Future<void> softDeletePartyFollowUp(int id) =>
      (update(partyFollowUps)..where((f) => f.id.equals(id))).write(
        PartyFollowUpsCompanion(deletedAt: Value(DateTime.now())),
      );

  // ── مطالبةُ المورد ───────────────────────────────────────────────────────

  Future<List<SupplierClaim>> getSupplierClaims(
    int supplierId, {
    int limit = 50,
  }) {
    return (select(supplierClaims)
          ..where((c) => c.supplierId.equals(supplierId) & c.deletedAt.isNull())
          ..orderBy([(c) => OrderingTerm.desc(c.claimDate)])
          ..limit(limit))
        .get();
  }

  /// مطالباتٌ ما زالت مفتوحةً — لم تُقبَل ولم تُرفَض ولم تُسوَّ.
  Future<List<SupplierClaim>> getOpenSupplierClaims(int supplierId) {
    return (select(supplierClaims)
          ..where((c) =>
              c.supplierId.equals(supplierId) &
              c.deletedAt.isNull() &
              c.status.isIn(['draft', 'sent']))
          ..orderBy([(c) => OrderingTerm.desc(c.claimDate)]))
        .get();
  }

  Future<int> insertSupplierClaim(SupplierClaimsCompanion row) =>
      into(supplierClaims).insert(row);

  Future<void> updateSupplierClaimStatus(int id, String status) =>
      (update(supplierClaims)..where((c) => c.id.equals(id))).write(
        SupplierClaimsCompanion(
          status: Value(status),
          lastModifiedAt: Value(DateTime.now()),
        ),
      );

  Future<void> softDeleteSupplierClaim(int id) =>
      (update(supplierClaims)..where((c) => c.id.equals(id))).write(
        SupplierClaimsCompanion(deletedAt: Value(DateTime.now())),
      );
}
