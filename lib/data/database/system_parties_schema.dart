part of 'database.dart';

/// v190 — الأطرافُ النظاميّة: «عميل نقدي» و«مورد نقدي» (J3، قرارُ المالك).
///
/// Raw SQL outside Drift's table model (no codegen run), following
/// `purchase_invoice_purchase_account_schema.dart`:
///
/// • `parties.system_role` — `NULL` for every ordinary party,
///   [kSystemRoleCashCustomer] / [kSystemRoleCashSupplier] for the ONE system
///   cash customer / cash supplier (a partial UNIQUE index keeps each role on
///   a single row).
/// • [ensureSystemCashParties] runs on every non-client startup: it keeps an
///   existing flagged row, otherwise ADOPTS an existing cash party (the
///   `pos_default_customer_id` setting, then a customer-only / supplier-only
///   party named «عميل نقدي» / «مورد نقدي» / «نقدي»…) so history keeps its
///   references, otherwise creates one through the normal [PartyDao.insertParty]
///   path — which links it to a sub-account under the AR (1121) / AP (2111)
///   control account like every other party. A party that is BOTH customer
///   and supplier is never adopted as a cash party.
/// • System parties cannot be deleted/deactivated and keep their role flags
///   ([lockSystemPartyFields]); their name stays editable (cosmetic) and
///   `trData` shows the English name while it is untouched.
/// • The cash customer is on EVERY route (phase F exception): it is never put
///   in `route_customers` (see `assignCustomerToRoute`), and the cloud serves
///   it to every rep.
///
/// Travels by the generic `SELECT *` delta pull (the column rides `parties`)
/// and by the cloud master push (`systemRole`).
const String kSystemRoleCashCustomer = 'cash_customer';
const String kSystemRoleCashSupplier = 'cash_supplier';
const String kCashCustomerDefaultName = 'عميل نقدي';
const String kCashSupplierDefaultName = 'مورد نقدي';

typedef _SystemPartySpec = ({
  String role,
  String name,
  String code,
  bool isCustomer,
  List<String> candidateNames,
});

const List<_SystemPartySpec> _systemPartySpecs = [
  (
    role: kSystemRoleCashCustomer,
    name: kCashCustomerDefaultName,
    code: 'CUST-CASH',
    isCustomer: true,
    candidateNames: [
      kCashCustomerDefaultName,
      'عميل نقدى',
      'العميل النقدي',
      'نقدي',
      'Cash Customer',
      'Walk-in Customer',
    ],
  ),
  (
    role: kSystemRoleCashSupplier,
    name: kCashSupplierDefaultName,
    code: 'SUP-CASH',
    isCustomer: false,
    candidateNames: [
      kCashSupplierDefaultName,
      'مورد نقدى',
      'المورد النقدي',
      'نقدي',
      'Cash Supplier',
    ],
  ),
];

extension SystemPartiesSchema on AppDatabase {
  Future<void> ensureSystemPartiesSchema() async {
    if (_isPostgres) {
      await customStatement(
          'ALTER TABLE parties ADD COLUMN IF NOT EXISTS system_role TEXT');
    } else {
      final columns = await customSelect('PRAGMA table_info(parties)').get();
      if (!columns.any((c) => c.data['name'] == 'system_role')) {
        try {
          await customStatement(
              'ALTER TABLE parties ADD COLUMN system_role TEXT');
        } catch (error) {
          if (!isIdempotentMigrationError(error.toString())) rethrow;
        }
      }
    }
    await customStatement(
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_parties_system_role '
      'ON parties(system_role) WHERE system_role IS NOT NULL',
    );
  }

  /// The id of the party holding [role] — `null` when none (client before
  /// its first pull, or a test database opened without startup).
  Future<int?> systemPartyId(String role) async {
    final row = await customSelect(
      'SELECT id FROM parties WHERE system_role = ? ORDER BY id LIMIT 1',
      variables: [Variable<String>(role)],
      readsFrom: {parties},
    ).getSingleOrNull();
    return (row?.data['id'] as num?)?.toInt();
  }

  /// The system role of [partyId] — `null` for an ordinary party.
  Future<String?> systemRoleOfParty(int? partyId) async {
    if (partyId == null) return null;
    final row = await customSelect(
      'SELECT system_role FROM parties WHERE id = ?',
      variables: [Variable<int>(partyId)],
      readsFrom: {parties},
    ).getSingleOrNull();
    return row?.data['system_role'] as String?;
  }

  Future<bool> isCashCustomer(int? partyId) async =>
      await systemRoleOfParty(partyId) == kSystemRoleCashCustomer;

  /// partyId → system role, for every system party (badges, pickers).
  Future<Map<int, String>> systemPartyRoles() async {
    final rows = await customSelect(
      'SELECT id, system_role FROM parties WHERE system_role IS NOT NULL',
      readsFrom: {parties},
    ).get();
    return {
      for (final r in rows)
        (r.data['id'] as num).toInt(): r.data['system_role'] as String,
    };
  }

  /// A system party's update keeps it active, undeleted and in its role —
  /// only the cosmetic fields (name, phone, address, …) follow the caller.
  Party lockSystemPartyFields(Party party, String role) => party.copyWith(
        isActive: true,
        deletedAt: const Value(null),
        isCustomer: role == kSystemRoleCashCustomer,
        isSupplier: role == kSystemRoleCashSupplier,
        isDeliveryCompany: false,
      );

  /// Throws when [partyId] is a system party (delete / deactivate guard).
  Future<void> assertPartyDeletable(int partyId) async {
    final role = await systemRoleOfParty(partyId);
    if (role == null) return;
    throw Exception(
      role == kSystemRoleCashCustomer
          ? 'لا يمكن حذف «عميل نقدي» — طرفٌ نظاميٌّ يعتمد عليه البيعُ النقدي.'
          : 'لا يمكن حذف «مورد نقدي» — طرفٌ نظاميٌّ يعتمد عليه الشراءُ النقدي.',
    );
  }

  /// «حفظ كعميل دائم» (J3): a real customer from a cash-customer sale — credit
  /// limit 0 (cash only until management sets one), linked to its AR
  /// sub-account by [insertParty], and appended to the END of [routeId]'s
  /// sequence (effective now) when given.
  ///
  /// Idempotent by [globalId] (the cloud field-customer document): a re-post
  /// returns the party already created. [routeCustomerGlobalId] keeps the
  /// cloud's `route_customers` identity so both sides converge on one row.
  Future<int> createPermanentCustomerFromCashSale({
    required String name,
    String? phone,
    String? address,
    int? routeId,
    String? globalId,
    String? routeCustomerGlobalId,
  }) {
    return transaction(() async {
      final trimmed = name.trim();
      if (trimmed.isEmpty) throw Exception('اسم العميل مطلوب.');
      if (globalId != null) {
        final existing = await _idOfGlobalId(globalId);
        if (existing != null) return existing;
      }
      String? clean(String? v) =>
          v == null || v.trim().isEmpty ? null : v.trim();
      final id = await insertParty(PartiesCompanion(
        name: Value(trimmed),
        phone: Value(clean(phone)),
        address: Value(clean(address)),
        isCustomer: const Value(true),
        isSupplier: const Value(false),
        creditLimit: const Value(0),
        balance: const Value(0),
        globalId: globalId == null ? const Value.absent() : Value(globalId),
      ));
      if (routeId != null) {
        await assignCustomerToRoute(
          customerId: id,
          routeId: routeId,
          globalId: routeCustomerGlobalId,
        );
      }
      return id;
    });
  }

  /// Seeds (or adopts) the system cash customer and cash supplier. Idempotent;
  /// a failure on one role never blocks the other or the startup.
  Future<void> ensureSystemCashParties() async {
    for (final spec in _systemPartySpecs) {
      try {
        await _ensureSystemParty(spec);
      } catch (e) {
        debugPrint('[Startup] system party ${spec.role}: $e');
      }
    }
  }

  Future<void> _ensureSystemParty(_SystemPartySpec spec) async {
    final existing = await systemPartyId(spec.role);
    if (existing != null) {
      await _normalizeSystemParty(existing, spec);
      return;
    }
    final adopted = await _cashPartyCandidate(spec) ??
        await _idOfGlobalId(_systemPartyGlobalId(spec.role));
    final id = adopted ??
        await insertParty(PartiesCompanion(
          name: Value(spec.name),
          code: Value(await isPartyCodeInUse(spec.code) ? null : spec.code),
          isCustomer: Value(spec.isCustomer),
          isSupplier: Value(!spec.isCustomer),
          creditLimit: const Value(0),
          balance: const Value(0),
          isGlobal: const Value(true),
          globalId: Value(_systemPartyGlobalId(spec.role)),
        ));
    await customUpdate(
      'UPDATE parties SET system_role = ? WHERE id = ?',
      variables: [Variable<String>(spec.role), Variable<int>(id)],
      updates: {parties},
    );
    await _normalizeSystemParty(id, spec);
  }

  /// Re-asserts the role flags of an existing system row (a sync or a manual
  /// edit may have deactivated it or flipped its type).
  Future<void> _normalizeSystemParty(int id, _SystemPartySpec spec) async {
    await (update(parties)
          ..where((p) =>
              p.id.equals(id) &
              (p.isActive.equals(false) |
                  p.deletedAt.isNotNull() |
                  p.isCustomer.equals(!spec.isCustomer) |
                  p.isSupplier.equals(spec.isCustomer))))
        .write(PartiesCompanion(
      isActive: const Value(true),
      deletedAt: const Value(null),
      isCustomer: Value(spec.isCustomer),
      isSupplier: Value(!spec.isCustomer),
    ));
  }

  String _systemPartyGlobalId(String role) =>
      UuidV7.deriveSeedGlobalId(table: 'parties', seedKey: 'system:$role');

  Future<int?> _idOfGlobalId(String gid) async {
    final row = await (select(parties)..where((p) => p.globalId.equals(gid)))
        .getSingleOrNull();
    return row?.id;
  }

  /// An existing cash party to adopt — never a party that is both customer
  /// and supplier, nor a delivery company.
  Future<int?> _cashPartyCandidate(_SystemPartySpec spec) async {
    bool fits(Party p) =>
        p.deletedAt == null &&
        p.isDeliveryCompany != true &&
        (spec.isCustomer
            ? p.isCustomer && !p.isSupplier
            : p.isSupplier && !p.isCustomer);
    if (spec.isCustomer) {
      final configured =
          int.tryParse(await getSettingValue('pos_default_customer_id') ?? '');
      if (configured != null) {
        final p = await (select(parties)..where((x) => x.id.equals(configured)))
            .getSingleOrNull();
        if (p != null && fits(p)) return p.id;
      }
    }
    final rows = await (select(parties)
          ..where((p) => p.name.isIn(spec.candidateNames))
          ..orderBy([(p) => OrderingTerm.asc(p.id)]))
        .get();
    for (final name in spec.candidateNames) {
      for (final p in rows) {
        if (p.name == name && fits(p)) return p.id;
      }
    }
    return null;
  }
}
