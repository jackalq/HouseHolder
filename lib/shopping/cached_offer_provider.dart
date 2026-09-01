import 'merchant_offer.dart';
import 'merchant_offer_provider.dart';

class CachedMerchantOfferProvider implements MerchantOfferProvider {
  CachedMerchantOfferProvider({
    required this.inner,
    this.ttl = const Duration(minutes: 15),
  });

  final MerchantOfferProvider inner;
  final Duration ttl;
  final Map<String, _CacheEntry> _cache = {};

  @override
  String get id => 'cached:${inner.id}';

  @override
  Future<List<MerchantOffer>> search(ShoppingRequestItem item) async {
    final key = '${item.itemKey}|${item.label}|${item.quantity}';
    final now = DateTime.now().toUtc();
    final cached = _cache[key];
    if (cached != null && now.difference(cached.createdAt) < ttl) {
      return cached.offers;
    }

    final fresh = List<MerchantOffer>.unmodifiable(await inner.search(item));
    _cache[key] = _CacheEntry(createdAt: now, offers: fresh);
    return fresh;
  }

  void clear() => _cache.clear();
}

class _CacheEntry {
  const _CacheEntry({required this.createdAt, required this.offers});
  final DateTime createdAt;
  final List<MerchantOffer> offers;
}
