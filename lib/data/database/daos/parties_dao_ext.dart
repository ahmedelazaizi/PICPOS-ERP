import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import '../../../core/utils/uuid_v7.dart';
import '../database.dart';

/// Parties Data Access Object Extension
///
/// This file contains party-related (customers/suppliers) database operations
/// as an extension on AppDatabase for better organization.
extension PartiesDao on AppDatabase {
  /// Watch all customers
  Stream<List<Party>> watchCustomers() {
    return (select(parties)
          ..where((p) => p.isCustomer.equals(true))
          ..orderBy([(p) => OrderingTerm.asc(p.name)]))
        .watch();
  }

  /// Watch all suppliers
  Stream<List<Party>> watchSuppliers() {
    return (select(parties)
          ..where((p) => p.isSupplier.equals(true))
          ..orderBy([(p) => OrderingTerm.asc(p.name)]))
        .watch();
  }

  /// Get all customers
  Future<List<Party>> getAllCustomers() {
    return (select(parties)
          ..where((p) => p.isCustomer.equals(true))
          ..orderBy([(p) => OrderingTerm.asc(p.name)]))
        .get();
  }

  /// Get all suppliers
  Future<List<Party>> getAllSuppliers() {
    return (select(parties)
          ..where((p) => p.isSupplier.equals(true))
          ..orderBy([(p) => OrderingTerm.asc(p.name)]))
        .get();
  }

  Stream<List<Party>> watchDeliveryCompanies() {
    return (select(parties)
          ..where((p) => p.isDeliveryCompany.equals(true))
          ..orderBy([(p) => OrderingTerm.asc(p.name)]))
        .watch();
  }

  /// Watch parties acting as delivery companies
  Stream<List<Party>> watchDeliveryParties() {
    return (select(parties)
          ..where((p) => p.isDeliveryCompany.equals(true))
          ..orderBy([(p) => OrderingTerm.asc(p.name)]))
        .watch();
  }

  /// Get all delivery companies
  Future<List<Party>> getAllDeliveryCompanies() {
    return (select(parties)
          ..where((p) => p.isDeliveryCompany.equals(true))
          ..orderBy([(p) => OrderingTerm.asc(p.name)]))
        .get();
  }

  /// Get party by ID
  Future<Party?> getPartyById(int id) {
    return (select(parties)..where((p) => p.id.equals(id))).getSingleOrNull();
  }

  /// Insert party with auto-posting to chart of accounts (Item #10)
  /// Customers get a sub-account under 1121 (receivables — ذمم عملاء محليون),
  /// Suppliers get a sub-account under 2111 (payables — ذمم موردون محليون).
  Future<int> insertParty({
    required String name,
    String? phone,
    String? address,
    bool isCustomer = true,
    bool isSupplier = false,
    double creditLimit = 0,
  }) async {
    final partyId = await into(parties).insert(
      PartiesCompanion(
        name: Value(name),
        phone: Value(phone),
        address: Value(address),
        isCustomer: Value(isCustomer),
        isSupplier: Value(isSupplier),
        creditLimit: Value(creditLimit),
        balance: const Value(0),
        // UUID-First (Phase 1): auto-mint so the COA-autopost variant keeps
        // parity with the richer insertParty above.
        globalId: Value(UuidV7.generate()),
      ),
    );

    // Auto-post to chart of accounts. Parent codes ('1121', '2111')
    // match the seeded chart — see PartyDao._arParentCode / _apParentCode
    // for the canonical constants used by the richer insertParty() path.
    try {
      if (isCustomer) {
        await _autoPostPartyAccount(
          partyId: partyId,
          partyName: name,
          parentCode: '1121', // Receivables — ذمم عملاء محليون
          accountType: 'asset',
          prefix: 'عميل',
        );
      }
      if (isSupplier) {
        await _autoPostPartyAccount(
          partyId: partyId,
          partyName: name,
          parentCode: '2111', // Payables — ذمم موردون محليون
          accountType: 'liability',
          prefix: 'مورد',
        );
      }
    } catch (e) {
      // Non-critical: party is created even if auto-post fails
      debugPrint('[PARTIES_DAO] Auto-post to COA failed for $name: $e');
    }

    return partyId;
  }

  /// Create a sub-account under the parent account for the party
  Future<void> _autoPostPartyAccount({
    required int partyId,
    required String partyName,
    required String parentCode,
    required String accountType,
    required String prefix,
  }) async {
    // Find parent account
    final parent = await (select(accounts)
          ..where((a) => a.code.equals(parentCode))
          ..limit(1))
        .getSingleOrNull();
    if (parent == null) return;

    // Generate next sub-account code: parentCode + sequential number
    final existingSubs = await customSelect(
      "SELECT MAX(CAST(SUBSTR(code, LENGTH(?) + 1) AS INTEGER)) as max_seq "
      "FROM accounts WHERE code LIKE ? || '%' AND LENGTH(code) > LENGTH(?)",
      variables: [Variable(parentCode), Variable(parentCode), Variable(parentCode)],
      readsFrom: {accounts},
    ).getSingle();
    final nextSeq = ((existingSubs.data['max_seq'] as int?) ?? 0) + 1;
    final subCode = '$parentCode${nextSeq.toString().padLeft(2, '0')}';

    // Check if sub-account already exists for this party name
    final existing = await (select(accounts)
          ..where((a) => a.name.equals('$prefix: $partyName'))
          ..limit(1))
        .getSingleOrNull();
    if (existing != null) return;

    // Create sub-account
    await into(accounts).insert(
      AccountsCompanion(
        code: Value(subCode),
        name: Value('$prefix: $partyName'),
        accountType: Value(accountType),
        parentId: Value(parent.id),
        isActive: const Value(true),
      ),
    );
  }

  /// Update party
  Future<void> updateParty(
    int id, {
    String? name,
    String? phone,
    String? address,
    bool? isCustomer,
    bool? isSupplier,
    double? creditLimit,
  }) async {
    // J3 — a system cash party keeps its role flags.
    if (await systemRoleOfParty(id) != null) {
      isCustomer = null;
      isSupplier = null;
    }
    await (update(parties)..where((p) => p.id.equals(id))).write(
      PartiesCompanion(
        name: name != null ? Value(name) : const Value.absent(),
        phone: phone != null ? Value(phone) : const Value.absent(),
        address: address != null ? Value(address) : const Value.absent(),
        isCustomer: isCustomer != null
            ? Value(isCustomer)
            : const Value.absent(),
        isSupplier: isSupplier != null
            ? Value(isSupplier)
            : const Value.absent(),
        creditLimit: creditLimit != null
            ? Value(creditLimit)
            : const Value.absent(),
      ),
    );
  }

  // Spec 135 silent-drift (c) — the non-atomic adjustPartyBalance that lived
  // here was REMOVED. It was an extension method on AppDatabase, permanently
  // shadowed by the atomic instance method of the same name in
  // party_dao.dart (`part of database.dart` — instance members always win
  // over extension members), so every `db.adjustPartyBalance(...)` call
  // already resolved to the atomic SQL `balance = balance + ?` version with
  // audit logging. This copy did a read-modify-write in Dart (Lost Update
  // race) with no audit trail — a latent double-adjust trap if anyone ever
  // invoked it explicitly. There is now exactly ONE definition
  // (party_dao.dart:971); a structural test pins that.

  /// Delete party — soft delete via `isActive = false`.
  ///
  /// W2 hardening (2026-05-12): this method used to issue a hard
  /// `DELETE FROM parties` which broke FKs on invoices / journal entries
  /// already referencing the party. Routed through the safe
  /// `party_dao.deleteParty` path which also enforces the
  /// transaction-history guard.
  Future<void> deleteParty(int id) async {
    await assertPartyDeletable(id);
    final hasTransactions = await partyHasTransactions(id);
    if (hasTransactions) {
      throw Exception(
        'لا يمكن حذف هذا العميل/المورد - يوجد سجل معاملات مرتبط به. استخدم إلغاء التفعيل بدلاً من ذلك.',
      );
    }
    await (update(parties)..where((p) => p.id.equals(id))).write(
      const PartiesCompanion(isActive: Value(false)),
    );
  }

  /// Get parties with outstanding balance.
  /// W2 hardening: filters inactive (soft-deleted) rows so totals don't
  /// include legacy balances of deactivated parties.
  Future<List<Party>> getPartiesWithBalance() {
    return customSelect(
      'SELECT * FROM parties '
      'WHERE ABS(balance) > 0.01 AND is_active = 1 '
      'ORDER BY ABS(balance) DESC',
      readsFrom: {parties},
    ).get().then((rows) => rows.map((row) => parties.map(row.data)).toList());
  }

  /// Get total customer balances.
  /// W2 hardening: only counts active customers.
  Future<double> getTotalCustomerBalance() async {
    final result = await customSelect(
      'SELECT COALESCE(SUM(balance), 0) as total FROM parties '
      'WHERE is_customer = 1 AND is_active = 1',
    ).getSingle();
    return result.read<double>('total');
  }

  /// Get total supplier balances.
  /// W2 hardening: only counts active suppliers.
  Future<double> getTotalSupplierBalance() async {
    final result = await customSelect(
      'SELECT COALESCE(SUM(balance), 0) as total FROM parties '
      'WHERE is_supplier = 1 AND is_active = 1',
    ).getSingle();
    return result.read<double>('total');
  }
}
