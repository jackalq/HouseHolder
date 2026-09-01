import 'package:family_butler/shopping/basket_optimizer.dart';
import 'package:family_butler/shopping/merchant_offer.dart';
import 'package:flutter_test/flutter_test.dart';

MerchantOffer offer(String title, int price, String merchant) => MerchantOffer(
      itemKey: 'milk',
      merchantId: merchant,
      merchantName: merchant,
      title: title,
      unitPriceTwd: price,
      url: 'https://example.com/$merchant',
      observedAt: DateTime.utc(2026, 9, 1),
    );

void main() {
  const optimizer = BasketOptimizer();

  test('buys enough merchant packages to satisfy requested volume', () {
    const request = ShoppingRequestItem(
      itemKey: 'milk',
      label: '鮮乳 2000ml',
    );
    final plan = optimizer.optimize(
      items: const [request],
      offers: [offer('鮮乳 936ml', 90, 'small')],
      strategy: ShoppingStrategy.lowestDeliveredTotal,
    );

    final line = plan.lines.single;
    expect(line.usesNormalizedFulfillment, isTrue);
    expect(line.packagesToBuy, 3);
    expect(line.fulfilledBaseQuantity, 2808);
    expect(line.subtotalTwd, 270);
  });

  test('optimizer compares actual fulfillment cost instead of sticker price', () {
    const request = ShoppingRequestItem(
      itemKey: 'milk',
      label: '鮮乳 2000ml',
    );
    final plan = optimizer.optimize(
      items: const [request],
      offers: [
        offer('鮮乳 936ml', 90, 'small'),
        offer('鮮乳 2000ml', 230, 'large'),
      ],
      strategy: ShoppingStrategy.lowestDeliveredTotal,
    );

    expect(plan.lines.single.offer.merchantId, 'large');
    expect(plan.lines.single.packagesToBuy, 1);
    expect(plan.itemSubtotalTwd, 230);
  });

  test('requested household quantity multiplies normalized requirement', () {
    const request = ShoppingRequestItem(
      itemKey: 'milk',
      label: '鮮乳 1000ml',
      quantity: 2,
    );
    final line = ShoppingPlanLine(
      request: request,
      offer: offer('鮮乳 600ml', 60, 'shop'),
    );

    expect(line.packagesToBuy, 4);
    expect(line.fulfilledBaseQuantity, 2400);
    expect(line.subtotalTwd, 240);
  });

  test('incompatible units fall back to requested item count', () {
    const request = ShoppingRequestItem(
      itemKey: 'milk',
      label: '鮮乳 2瓶',
      quantity: 2,
    );
    final line = ShoppingPlanLine(
      request: request,
      offer: offer('鮮乳 936ml', 90, 'shop'),
    );

    expect(line.usesNormalizedFulfillment, isFalse);
    expect(line.packagesToBuy, 2);
    expect(line.subtotalTwd, 180);
  });
}
