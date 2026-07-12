// ignore_for_file: avoid_dynamic_calls
import 'package:drift/drift.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ural_erp/data/database/database.dart';
import 'package:ural_erp/services/sync/sync_strategy.dart';

class OffersSyncStrategy extends SyncStrategy {
  OffersSyncStrategy(super.db);

  @override
  String get tableName => 'offers';

  @override
  String get apiEndpoint => '/api/offers';

  /// Returns true if this offer is applicable to the client's configured branch.
  bool _offerAppliesHere({
    required bool isGlobal,
    required String? branchIds,
    required int? clientBranchId,
  }) {
    if (isGlobal || clientBranchId == null) return true;
    if (branchIds == null || branchIds.isEmpty) return true; // treat null as global
    final ids = branchIds.split(',').map((s) => int.tryParse(s.trim())).whereType<int>().toSet();
    return ids.contains(clientBranchId);
  }

  @override
  Future<void> syncFromJson(Map<String, dynamic> json) async {
    final offersList = json['offers'] as List? ?? [];
    final itemsList = json['offerItems'] as List? ?? [];

    // Resolve this client's configured branch (null = no restriction)
    final prefs = await SharedPreferences.getInstance();
    final clientBranchId = prefs.getInt('client_branch_id');

    for (final o in offersList) {
      final isGlobal = parseBool(o['isGlobal'], true);
      final branchIds = o['branchIds'] as String?;

      // Skip offers that don't apply to this client's branch
      if (!_offerAppliesHere(isGlobal: isGlobal, branchIds: branchIds, clientBranchId: clientBranchId)) {
        continue;
      }

      await db.into(db.offers).insertOnConflictUpdate(
        OffersCompanion(
          id: Value(parseInt(o['id'])),
          name: Value(o['name'] as String),
          barcode: Value(o['barcode'] as String?),
          offerPrice: Value((o['offerPrice'] as num).toDouble()),
          startDate: Value(o['startDate'] != null
              ? DateTime.fromMillisecondsSinceEpoch(
                  (o['startDate'] as num).toInt() * 1000)
              : null),
          endDate: Value(o['endDate'] != null
              ? DateTime.fromMillisecondsSinceEpoch(
                  (o['endDate'] as num).toInt() * 1000)
              : null),
          isActive: Value(parseBool(o['isActive'], true)),
          offerType: Value(o['offerType'] as String? ?? 'bundle'),
          discountValue: Value(
              o['discountValue'] != null ? (o['discountValue'] as num).toDouble() : null),
          buyQuantity: Value(parseIntNullable(o['buyQuantity'])),
          getQuantity: Value(parseIntNullable(o['getQuantity'])),
          minQuantity: Value(parseIntNullable(o['minQuantity'])),
          maxUses: Value(parseIntNullable(o['maxUses'])),
          currentUses: Value(parseInt(o['currentUses'])),
          timeStart: Value(o['timeStart'] as String?),
          timeEnd: Value(o['timeEnd'] as String?),
          categoryId: Value(parseIntNullable(o['categoryId'])),
          isGlobal: Value(isGlobal),
          branchIds: Value(branchIds),
        ),
      );
    }

    for (final i in itemsList) {
      // Issue 11 (Feature 018): remap server productId → local id.
      final localProductId = await db.resolveItemFk(
        'products',
        parseInt(i['productId']),
        context: 'offer_items offer=${i['offerId']}',
      );
      await db.into(db.offerItems).insertOnConflictUpdate(
        OfferItemsCompanion(
          id: Value(parseInt(i['id'])),
          offerId: Value(parseInt(i['offerId'])),
          productId: Value(localProductId),
          quantity: Value((i['quantity'] as num).toDouble()),
        ),
      );
    }

    if (offersList.isNotEmpty || itemsList.isNotEmpty) {
      db.markTablesUpdated({db.offers, db.offerItems});
    }
  }

  @override
  Future<int> syncIncremental(DateTime since) async {
    return 0;
  }

  @override
  Future<void> upsert(Insertable record) async {
    if (record is OffersCompanion) {
      await db.into(db.offers).insertOnConflictUpdate(record);
    } else if (record is OfferItemsCompanion) {
      await db.into(db.offerItems).insertOnConflictUpdate(record);
    }
  }
}