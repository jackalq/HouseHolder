import 'merchant_offer.dart';

abstract interface class MerchantOfferProvider {
  String get id;
  Future<List<MerchantOffer>> search(ShoppingRequestItem item);
}
