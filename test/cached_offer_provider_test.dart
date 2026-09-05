import 'package:family_butler/shopping/cached_offer_provider.dart';
import 'package:family_butler/shopping/merchant_offer.dart';
import 'package:family_butler/shopping/merchant_offer_provider.dart';
import 'package:flutter_test/flutter_test.dart';

class _CountingProvider implements MerchantOfferProvider {
  int calls = 0;

  @override
  String get id => 'counting';

  @override
  Future<List<MerchantOffer>> search(ShoppingRequestItem item) async {
    calls += 1;
    return [
      MerchantOffer(
        itemKey: item.itemKey,
        merchantId: 'shop',
        merchantName: '商家',
        title: item.label,
        unitPriceTwd: 100 + calls,
        url: 'https://example.com/${item.itemKey}',
        observedAt: DateTime.now().toUtc(),
      ),
    ];
  }
}

void main() {
  test('reuses fresh offers instead of crawling again', () async {
    final inner = _CountingProvider();
    final cached = CachedMerchantOfferProvider(
      inner: inner,
      ttl: const Duration(minutes: 15),
    );
    const item = ShoppingRequestItem(itemKey: 'milk', label: '鮮乳');

    final first = await cached.search(item);
    final second = await cached.search(item);

    expect(inner.calls, 1);
    expect(first.single.unitPriceTwd, second.single.unitPriceTwd);
  });

  test('clear forces the next request to refresh', () async {
    final inner = _CountingProvider();
    final cached = CachedMerchantOfferProvider(inner: inner);
    const item = ShoppingRequestItem(itemKey: 'milk', label: '鮮乳');

    await cached.search(item);
    cached.clear();
    await cached.search(item);

    expect(inner.calls, 2);
  });
}
