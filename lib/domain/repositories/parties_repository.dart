import '../../data/database/database.dart';
import '../models/party_balance_mismatch.dart' as domain_models;

/// Parties repository interface
///
/// Defines the contract for customer/supplier operations.
abstract class IPartiesRepository {
  /// Watch all customers
  Stream<List<Party>> watchCustomers();

  /// Watch every party flagged as a customer regardless of `isActive`.
  /// Use for invoice-list name-lookup maps where every FK must resolve.
  Stream<List<Party>> watchAllCustomersForLookup();

  /// Watch all suppliers
  Stream<List<Party>> watchSuppliers();

  /// Watch all delivery companies
  Stream<List<Party>> watchDeliveryParties();

  /// Watch all parties
  Stream<List<Party>> watchAllParties();

  /// Branch-scoped variants — pass `null` for full access (admin), or
  /// the set returned by [branchScopeProvider] to hide rows tagged for
  /// branches the current user can't see. See PartyDao for the
  /// is_global / branch_ids CSV semantics.
  Stream<List<Party>> watchAllPartiesForBranches(Set<int>? allowedBranchIds);
  Stream<List<Party>> watchCustomersForBranches(Set<int>? allowedBranchIds);
  Stream<List<Party>> watchSuppliersForBranches(Set<int>? allowedBranchIds);

  /// Get suppliers list
  Future<List<Party>> getSuppliers();

  /// Get party by ID
  Future<Party?> getPartyById(int id);

  /// Search parties by query
  Stream<List<Party>> searchParties(String query);

  /// Insert a new party
  Future<int> insertParty(PartiesCompanion party);

  /// Update a party
  Future<bool> updateParty(Party party);

  /// Soft delete a party
  Future<void> deleteParty(int partyId);

  /// Hard delete a party (only without transactions)
  Future<int> hardDeleteParty(int partyId);

  /// Adjust party balance
  Future<void> adjustPartyBalance(int partyId, double amount);

  /// Check if party has transactions
  Future<bool> partyHasTransactions(int partyId);

  /// Get parties with outstanding balances
  Future<List<Party>> getPartiesWithBalance({bool? isCustomer});

  /// Get total receivables
  Future<double> getTotalReceivables();

  /// Get total payables
  Future<double> getTotalPayables();

  /// Get party summary with totals
  Future<PartySummary> getPartySummary(int partyId);

  /// Get party by name
  Future<Party?> getPartyByName(String name, bool isSupplier);

  /// Get party statement
  Future<List<PartyStatementEntry>> getPartyStatement(
    int partyId, {
    DateTime? fromDate,
    DateTime? toDate,
    int? branchId,
  });

  /// Get party transactions
  Future<List<SafeTransactionData>> getPartyTransactions(int partyId);

  /// Search customer by phone number
  Future<List<Party>> searchCustomerByPhone(String phone);

  /// Get all parties (generic)
  Future<List<Party>> getAllPartiesList();

  /// Get calculated balance from movements (PIR Integrity)
  Future<double> getCalculatedPartyBalance(int partyId);

  /// Find stored party balances that differ from the posted ledger.
  Future<List<domain_models.PartyBalanceMismatch>> getPartyBalanceMismatches();

  /// Recalculate stored party balances from the posted ledger.
  Future<int> recalculatePartyBalancesFromLedger(int userId);

  /// Update party balance directly (Manual adjustment or reconciliation)
  Future<void> updatePartyBalance(int partyId, double balance);

  /// Get parties with optional filters
  Future<List<Party>> getParties({bool? isCustomer, bool? isSupplier});

  // ═══════════════════════════════════════════════════════════════════════
  // كشفُ حساب الطرف — تبويباتُ ما بعد «الحركة والرصيد»
  // ═══════════════════════════════════════════════════════════════════════
  //
  // الخمسةُ كانت تعيش في `PartyDao` بلا منفذٍ إلى طبقة العرض، فتبويبةُ
  // «الحركة والرصيد» وحدَها كانت قابلةً للبناء. وكشفُهنّ هنا هو الشرطُ
  // الذي يجعل التبويباتِ الأربعَ الباقيةَ ممكنةً بلا كسر طبقيّة:
  // `lib/presentation` ممنوعٌ عليه استيرادُ `data/database` مباشرةً
  // (‏حارسُ D4-001)، فالطريقُ الوحيدُ المشروع هو مستودعٌ يُحقَن بمزوِّد.

  /// فواتيرُ طرفٍ **القائمةُ** بأعمارها — «أعمارُ الدين» للعميل و«المستحقُّ
  /// والاستحقاق» للمورد.
  Future<List<PartyOpenInvoiceRow>> getPartyOpenInvoices({
    required int partyId,
    required bool supplier,
    DateTime? asOf,
  });

  /// دفعاتُ طرفٍ ومقدارُ المربوطِ منها بفواتير — «مطابقةُ الدفعات».
  Future<List<PartyPaymentMatchRow>> getPartyPaymentMatches({
    required int partyId,
    DateTime? from,
    DateTime? to,
  });

  /// مطابقةُ أمرِ الشراء بالمستلَم بالمفوتَر — «مطابقةُ الفواتير بالاستلام».
  Future<List<PoMatchRow>> getPurchaseOrderMatches({
    required int supplierId,
    DateTime? from,
    DateTime? to,
  });

  /// أوراقُ طرفٍ التجاريّة — «الأوراقُ والضمانات» / «الأوراقُ والمقايضات».
  Future<List<CommercialPaperData>> getPartyPapers(int partyId);

  /// معدّلاتُ ملفّ الطرف المشتقّةُ من تواريخَ حقيقيّة — «الملفُّ والائتمان».
  Future<PartyProfileMetrics> getPartyProfileMetrics({
    required int partyId,
    required bool supplier,
  });

  /// آخرُ فواتيرِ طرفٍ **صفّاً صفّاً** بتاريخ آخرِ سدادٍ لكلٍّ — تسند رسمَي
  /// «سلوك السداد» و«الخصم النقدي» في تبويبة الملفّ.
  Future<List<PartySettlementRow>> getPartySettlementRows({
    required int partyId,
    required bool supplier,
    int limit,
  });

  // ═══════════════════════════════════════════════════════════════════════
  // متابعةُ التحصيل ومطالبةُ المورد (v165)
  // ═══════════════════════════════════════════════════════════════════════
  //
  // ⚠️ **سجلّا تواصلٍ لا قيدَين ماليَّين**: لا يحرّكان خزنةً ولا ذمّةً ولا
  // يكتبان قيداً. والمالُ يتحرّك بسندِ قبضٍ أو صرفٍ أو بإشعارٍ دائنٍ حين يصل.

  /// متابعاتُ تحصيلِ طرفٍ من الأحدث — كلُّها أو ما يخصّ فاتورةً بعينها.
  Future<List<PartyFollowUp>> getPartyFollowUps(
    int partyId, {
    int? invoiceId,
    int limit,
  });

  /// عددُ المحاولات السابقة — «محاولات سابقة» في حوار المتابعة.
  Future<int> countPartyFollowUps(int partyId, {int? invoiceId});

  /// ⚠️ **وسائطُ عاديّةٌ لا `Companion`**: الـcompanion نوعٌ من drift، وتمريرُه
  /// عبر الواجهة يجعل الحوارَ في طبقة العرض يعرف شكلَ الجدول. والبناءُ يقع في
  /// الطبقة البيانيّة حيث يعيش الجدول.
  Future<int> insertPartyFollowUp({
    required int partyId,
    required DateTime contactedAt,
    required String outcome,
    required double amountDue,
    int? invoiceId,
    String? invoiceNumber,
    DateTime? promisedDate,
    double? promisedAmount,
    String? contactPerson,
    DateTime? nextActionAt,
    String? notes,
    int? createdBy,
  });

  /// مطالباتُ مورّدٍ من الأحدث.
  Future<List<SupplierClaim>> getSupplierClaims(int supplierId, {int limit});

  /// مطالباتٌ لم تُقبَل ولم تُرفَض ولم تُسوَّ بعد.
  Future<List<SupplierClaim>> getOpenSupplierClaims(int supplierId);

  Future<int> insertSupplierClaim({
    required int supplierId,
    required DateTime claimDate,
    required String settlementKind,
    required double ledgerBalance,
    required double netAmount,
    required int lineCount,
    String? linesJson,
    DateTime? replyDueAt,
    String? notes,
    int? createdBy,
  });

  Future<void> updateSupplierClaimStatus(int id, String status);
}
