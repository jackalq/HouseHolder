import 'package:family_butler/shopping/merchant_offer.dart';
import 'package:family_butler/shopping/merchant_offer_provider.dart';
import 'package:family_butler/shopping/shopping_comparison_service.dart';
import 'package:flutter_test/flutter_test.dart';

class _StaleProvider implements MerchantOfferProvider {
  const _StaleProvider();

  @override
  String get id => 'stale-test';

  @override
  Future<List<MerchantOffer>> search(ShoppingRequestItem item) async => [
        MerchantOffer(
          itemKey: item.itemKey,
          merchantId: 'old-shop',
          merchantName: '舊報價商家',
          title: '鮮乳 936ml',
          unitPriceTwd: 80,
          url: 'https://old.example/milk',
          observedAt: DateTime.utc(2026, 9, 1, 8),
        ),
        MerchantOffer(
          itemKey: item.itemKey,
          merchantId: 'fresh-shop',
          merchantName: '新報價商家',
          title: '鮮乳 936ml',
          unitPriceTwd: 95,
          url: 'https://fresh.example/milk',
          observedAt: DateTime.utc(2026, 9, 1, 11, 30),
        ),
      ];
}

void main() {
  test('stale offers are excluded before basket optimization', () async {
    final service = ShoppingComparisonService(
      providers: const [_StaleProvider()],
      maxOfferAge: const Duration(hours: 1),
      now: () => DateTime.utc(2026, 9, 1, 12),
    );

    final result = await service.compare(const [
      ShoppingRequestItem(itemKey: 'milk', label: '鮮乳'),
    ]);

    expect(result.staleOfferCount, 1);
    expect(result.offers, hasLength(1));
    expect(result.offers.single.merchantId, 'fresh-shop');
    expect(
      result.plans[ShoppingStrategy.lowestDeliveredTotal]!.lines.single.offer.merchantId,
      'fresh-shop',
    );
  });
}
