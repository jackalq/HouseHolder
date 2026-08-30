import 'basket_optimizer.dart';
import 'merchant_offer.dart';
import 'merchant_offer_provider.dart';

class ShoppingComparison {
  const ShoppingComparison({required this.offers, required this.plans});
  final List<MerchantOffer> offers;
  final Map<ShoppingStrategy, ShoppingPlan?> plans;
}

class ShoppingComparisonService {
  const ShoppingComparisonService({
    required this.providers,
    this.optimizer = const BasketOptimizer(),
  });

  final List<MerchantOfferProvider> providers;
  final BasketOptimizer optimizer;

  Future<ShoppingComparison> compare(List<ShoppingRequestItem> items) async {
    final offers = <MerchantOffer>[];
    for (final item in items) {
      for (final provider in providers) {
        offers.addAll(await provider.search(item));
      }
    }
    final deduped = <String, MerchantOffer>{};
    for (final offer in offers) {
      final key = '${offer.itemKey}|${offer.merchantId}|${offer.url}|${offer.unitPriceTwd}';
      final existing = deduped[key];
      if (existing == null || offer.observedAt.isAfter(existing.observedAt)) deduped[key] = offer;
    }
    final normalized = deduped.values.toList(growable: false);
    return ShoppingComparison(
      offers: normalized,
      plans: optimizer.compareStrategies(items: items, offers: normalized),
    );
  }
}
