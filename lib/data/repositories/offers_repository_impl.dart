import '../database/database.dart';
import '../../domain/repositories/offers_repository.dart';

class OffersRepositoryImpl implements IOffersRepository {
  final AppDatabase _db;

  OffersRepositoryImpl(this._db);

  @override
  Stream<List<Offer>> watchOffers() => _db.watchOffers();

  @override
  Stream<List<Offer>> watchActiveOffers() => _db.watchActiveOffers();

  @override
  Future<List<Offer>> getOffers() => _db.getOffers();

  @override
  Future<List<Offer>> getActiveOffers() => _db.getActiveOffers();

  @override
  bool isOfferWithinTimeWindow(Offer offer) => _db.isOfferWithinTimeWindow(offer);

  @override
  Future<int> insertOffer(OffersCompanion offer) async {
    final id = await _db.transaction(() async => _db.into(_db.offers).insert(offer));
    _db.markTablesUpdated({_db.offers});
    return id;
  }

  @override
  Future<bool> updateOffer(Offer offer) async {
    final result = await _db.transaction(() async => _db.update(_db.offers).replace(offer));
    _db.markTablesUpdated({_db.offers});
    return result;
  }

  @override
  Future<void> deleteOffer(int id) async {
    await _db.transaction(() async {
      // Delete items first, then the offer itself
      await (_db.delete(_db.offerItems)
            ..where((t) => t.offerId.equals(id)))
          .go();
      await (_db.delete(_db.offers)..where((t) => t.id.equals(id))).go();
    });
    _db.markTablesUpdated({_db.offers, _db.offerItems});
  }

  @override
  Future<List<OfferItem>> getOfferItems(int offerId) =>
      (_db.select(_db.offerItems)..where((t) => t.offerId.equals(offerId)))
          .get();

  @override
  Future<void> insertOfferItem(OfferItemsCompanion item) async {
    await _db.into(_db.offerItems).insert(item);
    _db.markTablesUpdated({_db.offerItems});
  }

  @override
  Future<void> deleteOfferItems(int offerId) async {
    await (_db.delete(_db.offerItems)..where((t) => t.offerId.equals(offerId)))
        .go();
    _db.markTablesUpdated({_db.offerItems});
  }
}
