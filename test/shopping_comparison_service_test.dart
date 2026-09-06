import 'package:family_butler/shopping/merchant_offer.dart';
import 'package:family_butler/shopping/merchant_offer_provider.dart';
import 'package:family_butler/shopping/shopping_comparison_service.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeProvider implements MerchantOfferProvider {
  const _FakeProvider();

  @override
  String get id => 'fake';

  @override
  Future<List<MerchantOffer>> search(ShoppingRequestItem item) async {
    final now = DateTime.utc(2026, 8, 31);
    return [
      MerchantOffer(
        itemKey: item.itemKey,
        merchantId: 'shop-a',
        merchantName: '商家 A',
        title: '${item.label} A',
        unitPriceTwd: item.itemKey == 'milk' ? 90 : 45,
        shippingFlatTwd: 60,
        freeShippingThresholdTwd: 500,
        url: 'https://shop-a.example/${item.itemKey}',
        observedAt: now,
      ),
      MerchantOffer(
        itemKey: item.itemKey,
        merchantId: 'shop-b',
        merchantName: '商家 B',
        title: '${item.label} B',
        unitPriceTwd: item.itemKey == 'milk' ? 100 : 40,
        shippingFlatTwd: 0,
        url: 'https://shop-b.example/${item.itemKey}',
        observedAt: now,
      ),
    ];
  }
}

void main() {
  test('comparison returns all strategies with usable purchase URLs', () async {
    const service = ShoppingComparisonService(providers: [_FakeProvider()]);
    const items = [
      ShoppingRequestItem(itemKey: 'milk', label: '牛奶 1瓶'),
      ShoppingRequestItem(itemKey: 'bread', label: '吐司 1包'),
    ];

    final result = await service.compare(items);

    expect(result.offers, hasLength(4));
    for (final strategy in ShoppingStrategy.values) {
      final plan = result.plans[strategy];
      expect(plan, isNotNull, reason: '$strategy should have a complete plan');
      expect(plan!.lines, hasLength(2));
      expect(plan.purchaseUrls, isNotEmpty);
      expect(plan.purchaseUrls.every((url) => Uri.parse(url).scheme == 'https'), isTrue);
    }

    final delivered = result.plans[ShoppingStrategy.lowestDeliveredTotal]!;
    expect(delivered.totalTwd, 140);
    expect(delivered.purchaseUrls, contains('https://shop-b.example/milk'));
    expect(delivered.purchaseUrls, contains('https://shop-b.example/bread'));
  });
}
