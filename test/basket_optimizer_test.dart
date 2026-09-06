import 'package:family_butler/shopping/basket_optimizer.dart';
import 'package:family_butler/shopping/merchant_offer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const optimizer = BasketOptimizer();
  final now = DateTime.utc(2026, 8, 30);
  const items = [
    ShoppingRequestItem(itemKey: 'milk', label: '牛奶'),
    ShoppingRequestItem(itemKey: 'eggs', label: '雞蛋'),
  ];

  List<MerchantOffer> offers() => [
        MerchantOffer(
          itemKey: 'milk', merchantId: 'a', merchantName: 'A', title: '牛奶',
          unitPriceTwd: 40, shippingFlatTwd: 50, url: 'https://a/milk', observedAt: now,
        ),
        MerchantOffer(
          itemKey: 'eggs', merchantId: 'a', merchantName: 'A', title: '雞蛋',
          unitPriceTwd: 100, shippingFlatTwd: 50, url: 'https://a/eggs', observedAt: now,
        ),
        MerchantOffer(
          itemKey: 'milk', merchantId: 'b', merchantName: 'B', title: '牛奶',
          unitPriceTwd: 60, shippingFlatTwd: 0, url: 'https://b/milk', observedAt: now,
        ),
        MerchantOffer(
          itemKey: 'eggs', merchantId: 'b', merchantName: 'B', title: '雞蛋',
          unitPriceTwd: 50, shippingFlatTwd: 0, url: 'https://b/eggs', observedAt: now,
        ),
      ];

  test('lowest delivered total accounts for merchant shipping once', () {
    final plan = optimizer.optimize(items: items, offers: offers(), strategy: ShoppingStrategy.lowestDeliveredTotal);
    expect(plan.totalTwd, 110);
    expect(plan.merchantCount, 1);
    expect(plan.lines.every((line) => line.offer.merchantId == 'b'), isTrue);
  });

  test('one-stop strategy requires a single merchant', () {
    final plan = optimizer.optimize(items: items, offers: offers(), strategy: ShoppingStrategy.lowestOneStopTotal);
    expect(plan.merchantCount, 1);
    expect(plan.totalTwd, 110);
  });

  test('fewest merchants uses total as tie breaker', () {
    final plan = optimizer.optimize(items: items, offers: offers(), strategy: ShoppingStrategy.fewestMerchants);
    expect(plan.merchantCount, 1);
    expect(plan.totalTwd, 110);
  });
}
