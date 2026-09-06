import 'package:family_butler/shopping/basket_optimizer.dart';
import 'package:family_butler/shopping/merchant_offer.dart';
import 'package:flutter_test/flutter_test.dart';

MerchantOffer offer({
  required String itemKey,
  required String merchant,
  required int price,
  required bool shippingKnown,
  int shipping = 0,
}) => MerchantOffer(
      itemKey: itemKey,
      merchantId: merchant,
      merchantName: merchant,
      title: '$itemKey-$merchant',
      unitPriceTwd: price,
      shippingFlatTwd: shipping,
      shippingKnown: shippingKnown,
      url: 'https://example.com/$merchant/$itemKey',
      observedAt: DateTime.utc(2026, 9, 1),
    );

void main() {
  const optimizer = BasketOptimizer();

  test('verified delivered total beats cheaper subtotal with unknown shipping', () {
    const items = [ShoppingRequestItem(itemKey: 'milk', label: '牛奶')];
    final plan = optimizer.optimize(
      items: items,
      offers: [
        offer(itemKey: 'milk', merchant: 'unknown-shop', price: 80, shippingKnown: false),
        offer(itemKey: 'milk', merchant: 'known-shop', price: 90, shippingKnown: true, shipping: 20),
      ],
      strategy: ShoppingStrategy.lowestDeliveredTotal,
    );

    expect(plan.shippingKnown, isTrue);
    expect(plan.lines.single.offer.merchantId, 'known-shop');
    expect(plan.totalTwd, 110);
  });

  test('unknown shipping plan is explicitly marked unknown when no verified option exists', () {
    const items = [ShoppingRequestItem(itemKey: 'milk', label: '牛奶')];
    final plan = optimizer.optimize(
      items: items,
      offers: [offer(itemKey: 'milk', merchant: 'shop', price: 80, shippingKnown: false)],
      strategy: ShoppingStrategy.lowestDeliveredTotal,
    );

    expect(plan.shippingKnown, isFalse);
    expect(plan.itemSubtotalTwd, 80);
    expect(plan.shippingTwd, 0);
  });

  test('fewest merchants remains primary even when shipping is unknown', () {
    const items = [
      ShoppingRequestItem(itemKey: 'milk', label: '牛奶'),
      ShoppingRequestItem(itemKey: 'bread', label: '吐司'),
    ];
    final offers = [
      offer(itemKey: 'milk', merchant: 'one-stop', price: 80, shippingKnown: false),
      offer(itemKey: 'bread', merchant: 'one-stop', price: 50, shippingKnown: false),
      offer(itemKey: 'milk', merchant: 'milk-shop', price: 90, shippingKnown: true),
      offer(itemKey: 'bread', merchant: 'bread-shop', price: 45, shippingKnown: true),
    ];

    final plan = optimizer.optimize(
      items: items,
      offers: offers,
      strategy: ShoppingStrategy.fewestMerchants,
    );

    expect(plan.merchantCount, 1);
    expect(plan.shippingKnown, isFalse);
    expect(plan.lines.every((line) => line.offer.merchantId == 'one-stop'), isTrue);
  });
}
