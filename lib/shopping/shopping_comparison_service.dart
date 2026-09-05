import 'basket_optimizer.dart';
import 'merchant_offer.dart';
import 'merchant_offer_provider.dart';

class ShoppingComparison {
  const ShoppingComparison({
    required this.offers,
    required this.plans,
    this.providerErrors = const {},
    this.staleOfferCount = 0,
  });

  final List<MerchantOffer> offers;
  final Map<ShoppingStrategy, ShoppingPlan?> plans;

  /// Provider id -> human-readable error. A crawler failure is isolated so
  /// other merchants can still contribute live offers.
  final Map<String, String> providerErrors;

  /// Offers older than the accepted freshness window are not used for plans.
  final int staleOfferCount;
}

class ShoppingComparisonService {
  const ShoppingComparisonService({
    required this.providers,
    this.optimizer = const BasketOptimizer(),
    this.maxOfferAge = const Duration(days: 7),
    this.now,
  });

  final List<MerchantOfferProvider> providers;
  final BasketOptimizer optimizer;
  final Duration maxOfferAge;
  final DateTime Function()? now;

  Future<ShoppingComparison> compare(List<ShoppingRequestItem> items) async {
    final offers = <MerchantOffer>[];
    final providerErrors = <String, String>{};
    for (final item in items) {
      for (final provider in providers) {
        try {
          offers.addAll(await provider.search(item));
        } on UnsupportedError {
          rethrow;
        } catch (error) {
          providerErrors[provider.id] = error.toString();
        }
      }
    }
    final deduped = <String, MerchantOffer>{};
    for (final offer in offers) {
      final key = '${offer.itemKey}|${offer.merchantId}|${offer.url}|${offer.unitPriceTwd}';
      final existing = deduped[key];
      if (existing == null || offer.observedAt.isAfter(existing.observedAt)) deduped[key] = offer;
    }

    final cutoff = (now?.call() ?? DateTime.now().toUtc()).toUtc().subtract(maxOfferAge);
    var staleOfferCount = 0;
    final normalized = deduped.values.where((offer) {
      final fresh = !offer.observedAt.toUtc().isBefore(cutoff);
      if (!fresh) staleOfferCount++;
      return fresh;
    }).toList(growable: false);

    return ShoppingComparison(
      offers: normalized,
      plans: optimizer.compareStrategies(items: items, offers: normalized),
      providerErrors: Map.unmodifiable(providerErrors),
      staleOfferCount: staleOfferCount,
    );
  }
}
