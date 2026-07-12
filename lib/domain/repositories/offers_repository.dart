import '../../data/database/database.dart';

abstract class IOffersRepository {
  Stream<List<Offer>> watchOffers();
  Stream<List<Offer>> watchActiveOffers();
  Future<List<Offer>> getOffers();
  Future<List<Offer>> getActiveOffers();
  Future<int> insertOffer(OffersCompanion offer);
  Future<bool> updateOffer(Offer offer);
  Future<void> deleteOffer(int id);

  Future<List<OfferItem>> getOfferItems(int offerId);
  Future<void> insertOfferItem(OfferItemsCompanion item);
  Future<void> deleteOfferItems(int offerId);

  /// Check if an offer is within its configured time window (start/end time).
  bool isOfferWithinTimeWindow(Offer offer);
}
