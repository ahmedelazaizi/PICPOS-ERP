// ═══════════════════════════════════════════════════════════════════════════
// OFFERS DAO - Offers/Bundles Operations
// ═══════════════════════════════════════════════════════════════════════════
//
// This file contains all offers-related database operations extracted from
// the main database.dart file for better organization and maintainability.
//
// Usage: Import in database.dart and access via AppDatabase instance.
// ═══════════════════════════════════════════════════════════════════════════

part of '../database.dart';

/// Extension for Offers-related database operations
extension OffersDao on AppDatabase {
  // ═══════════════════════════════════════════════════════════════════════
  // OFFERS CRUD
  // ═══════════════════════════════════════════════════════════════════════

  /// Watch all offers
  Stream<List<Offer>> watchOffers() {
    return select(offers).watch();
  }

  /// Get all offers
  Future<List<Offer>> getOffers() => select(offers).get();

  /// Watch active offers (null-safe date handling: null start/end = no date limit)
  Stream<List<Offer>> watchActiveOffers() {
    final now = DateTime.now();
    return (select(offers)..where(
          (o) =>
              o.isActive.equals(true) &
              (o.startDate.isNull() |
                  o.startDate.isSmallerOrEqual(Variable(now))) &
              (o.endDate.isNull() | o.endDate.isBiggerOrEqual(Variable(now))),
        ))
        .watch();
  }

  /// Get active offers (for use from non-part-of files)
  Future<List<Offer>> getActiveOffers() async {
    final now = DateTime.now();
    return (select(offers)..where(
          (o) =>
              o.isActive.equals(true) &
              (o.startDate.isNull() |
                  o.startDate.isSmallerOrEqual(Variable(now))) &
              (o.endDate.isNull() | o.endDate.isBiggerOrEqual(Variable(now))),
        ))
        .get();
  }

  /// Get offer by ID
  Future<Offer?> getOfferById(int id) {
    return (select(offers)..where((o) => o.id.equals(id))).getSingleOrNull();
  }

  /// Get active offer by barcode
  Future<Offer?> getOfferByBarcode(String barcode) async {
    final now = DateTime.now();
    return (select(offers)..where(
          (o) =>
              o.barcode.equals(barcode) &
              o.isActive.equals(true) &
              (o.startDate.isNull() |
                  o.startDate.isSmallerOrEqual(Variable(now))) &
              (o.endDate.isNull() | o.endDate.isBiggerOrEqual(Variable(now))),
        ))
        .getSingleOrNull();
  }

  /// Check if offer barcode exists (for validation)
  Future<bool> offerBarcodeExists(String barcode) async {
    final offer = await (select(
      offers,
    )..where((o) => o.barcode.equals(barcode))).getSingleOrNull();
    return offer != null;
  }

  /// Insert an offer
  Future<int> insertOffer(OffersCompanion offer) {
    return into(offers).insert(offer);
  }

  /// Update an offer
  Future<bool> updateOffer(Offer offer) {
    return update(offers).replace(offer);
  }

  /// Delete an offer
  Future<int> deleteOfferById(int id) {
    return (delete(offers)..where((o) => o.id.equals(id))).go();
  }

  /// Toggle offer active status
  Future<void> toggleOfferStatus(int id, bool isActive) async {
    await (update(offers)..where((o) => o.id.equals(id))).write(
      OffersCompanion(isActive: Value(isActive)),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // OFFER ITEMS
  // ═══════════════════════════════════════════════════════════════════════

  /// Get items for an offer
  Future<List<OfferItem>> getOfferItems(int offerId) {
    return (select(offerItems)..where((i) => i.offerId.equals(offerId))).get();
  }

  /// Watch items for an offer
  Stream<List<OfferItem>> watchOfferItems(int offerId) {
    return (select(
      offerItems,
    )..where((i) => i.offerId.equals(offerId))).watch();
  }

  /// Insert an offer item
  Future<int> insertOfferItem(OfferItemsCompanion item) {
    return into(offerItems).insert(item);
  }

  /// Delete an offer item
  Future<int> deleteOfferItem(int id) {
    return (delete(offerItems)..where((i) => i.id.equals(id))).go();
  }

  /// Delete all items for an offer
  Future<int> deleteOfferItems(int offerId) {
    return (delete(offerItems)..where((i) => i.offerId.equals(offerId))).go();
  }

  /// Create offer with items (transaction)
  Future<int> createOfferWithItems(
    OffersCompanion offer,
    List<OfferItemsCompanion> items,
  ) {
    return transaction(() async {
      final offerId = await into(offers).insert(offer);
      for (final item in items) {
        await into(offerItems).insert(item.copyWith(offerId: Value(offerId)));
      }
      return offerId;
    });
  }

  // ═══════════════════════════════════════════════════════════════════════
  // ADVANCED OFFERS
  // ═══════════════════════════════════════════════════════════════════════

  /// Get offers by type
  Future<List<Offer>> getOffersByType(String type) async {
    return (select(
      offers,
    )..where((o) => o.offerType.equals(type) & o.isActive.equals(true))).get();
  }

  /// Check if offer is within its daily time window
  bool isOfferWithinTimeWindow(Offer offer) {
    if (offer.timeStart == null || offer.timeEnd == null) return true;

    final now = DateTime.now();
    final currentTime =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    return currentTime.compareTo(offer.timeStart!) >= 0 &&
        currentTime.compareTo(offer.timeEnd!) <= 0;
  }

  /// Get active offers filtered by branch (global or branch-specific)
  Future<List<Offer>> getActiveOffersForBranch(int? branchId) async {
    final all = await getActiveOffers();
    if (branchId == null) return all;
    return all.where((o) {
      if (o.isGlobal) return true;
      final ids = o.branchIds?.split(',').map((s) => int.tryParse(s.trim())).whereType<int>().toSet() ?? {};
      return ids.contains(branchId);
    }).toList();
  }

  /// Get applicable offers for a product (checks product items, category, time, usage)
  Future<List<Offer>> getApplicableOffers({
    int? productId,
    int? categoryId,
    double quantity = 1,
    int? branchId,
  }) async {
    final activeOffers = await getActiveOffersForBranch(branchId);
    final List<Offer> applicable = [];

    for (final offer in activeOffers) {
      // Check time window
      if (!isOfferWithinTimeWindow(offer)) continue;

      // Check usage limits
      if (offer.maxUses != null && offer.currentUses >= offer.maxUses!) {
        continue;
      }

      // Check minimum quantity
      if (offer.minQuantity != null && quantity < offer.minQuantity!) continue;

      // Match by category
      if (offer.categoryId != null && offer.categoryId == categoryId) {
        applicable.add(offer);
        continue;
      }

      // Match by product items (for bundle/buy_x_get_y)
      if (productId != null) {
        final items = await getOfferItems(offer.id);
        if (items.any((i) => i.productId == productId)) {
          applicable.add(offer);
        }
      }
    }

    return applicable;
  }

  /// Increment offer usage counter
  Future<void> incrementOfferUses(int offerId) async {
    await customStatement(
      'UPDATE offers SET current_uses = current_uses + 1 WHERE id = ?',
      [offerId],
    );
  }

  /// Reset offer usage counter
  Future<void> resetOfferUses(int offerId) async {
    await (update(offers)..where((o) => o.id.equals(offerId))).write(
      const OffersCompanion(currentUses: Value(0)),
    );
  }
}
