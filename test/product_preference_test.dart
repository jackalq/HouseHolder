import 'package:family_butler/shopping/basket_optimizer.dart';
import 'package:family_butler/shopping/merchant_offer.dart';
import 'package:family_butler/shopping/product_preference.dart';
import 'package:flutter_test/flutter_test.dart';

MerchantOffer offer(String title, int price, {String merchant = 'shop'}) => MerchantOffer(
  itemKey: 'milk', merchantId: merchant, merchantName: merchant, title: title,
  unitPriceTwd: price, shippingFlatTwd: 0, url: 'https://example.com/$price',
  observedAt: DateTime.utc(2026, 9, 1),
);

void main() {
  const optimizer = BasketOptimizer();

  test('hard required and excluded preferences filter offers', () {
    const item = ShoppingRequestItem(itemKey: 'milk', label: '鮮乳', preference: ProductPreference(
      requiredTerms: ['全脂'], excludedTerms: ['保久乳'],
    ));
    final plan = optimizer.optimize(items: const [item], offers: [
      offer('品牌A 全脂保久乳', 50), offer('品牌A 低脂鮮乳', 55), offer('品牌B 全脂鮮乳', 70),
    ], strategy: ShoppingStrategy.lowestDeliveredTotal);
    expect(plan.lines.single.offer.title, '品牌B 全脂鮮乳');
  });

  test('soft preference ranks preferred product ahead of cheaper alternative', () {
    const item = ShoppingRequestItem(itemKey: 'milk', label: '鮮乳', preference: ProductPreference(
      preferredTerms: ['品牌A'],
    ));
    final plan = optimizer.optimize(items: const [item], offers: [
      offer('品牌B 鮮乳', 60), offer('品牌A 鮮乳', 75),
    ], strategy: ShoppingStrategy.lowestDeliveredTotal);
    expect(plan.lines.single.offer.title, '品牌A 鮮乳');
    expect(plan.preferenceScore, 10);
  });

  test('preferred merchant participates in soft ranking', () {
    const item = ShoppingRequestItem(itemKey: 'milk', label: '鮮乳', preference: ProductPreference(
      preferredMerchants: ['momo'],
    ));
    final plan = optimizer.optimize(items: const [item], offers: [
      offer('同款鮮乳', 60, merchant: 'pchome'), offer('同款鮮乳', 65, merchant: 'momo'),
    ], strategy: ShoppingStrategy.lowestDeliveredTotal);
    expect(plan.lines.single.offer.merchantId, 'momo');
    expect(plan.preferenceScore, 4);
  });
}
