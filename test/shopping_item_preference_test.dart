import 'package:family_butler/features/shopping/shopping_item.dart';
import 'package:family_butler/shopping/product_preference.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('shopping item persists product preferences in JSON', () {
    const item = HouseholdShoppingItem(
      id: 'shopping-1',
      name: '鮮乳',
      preference: ProductPreference(
        requiredTerms: ['全脂'],
        excludedTerms: ['保久乳'],
        preferredTerms: ['品牌A'],
        preferredMerchants: ['momo'],
      ),
    );

    final restored = HouseholdShoppingItem.fromJson(item.toJson());
    expect(restored.preference.requiredTerms, ['全脂']);
    expect(restored.preference.excludedTerms, ['保久乳']);
    expect(restored.preference.preferredTerms, ['品牌A']);
    expect(restored.preference.preferredMerchants, ['momo']);
  });

  test('legacy shopping JSON without preference remains compatible', () {
    final restored = HouseholdShoppingItem.fromJson({
      'id': 'shopping-legacy',
      'name': '衛生紙',
      'quantity': 1,
      'unit': '串',
      'done': false,
    });
    expect(restored.preference.isEmpty, isTrue);
  });

  test('comparison request does not duplicate shopping list quantity in label', () {
    const item = HouseholdShoppingItem(
      id: 'shopping-2',
      name: '鮮乳 1000ml',
      quantity: 2,
      unit: '瓶',
      note: '全脂',
    );

    final request = item.toComparisonRequest();
    expect(request.label, '鮮乳 1000ml 全脂');
    expect(request.quantity, 2);
    expect(request.packageQuantity!.baseQuantity, 1000);
  });
}
