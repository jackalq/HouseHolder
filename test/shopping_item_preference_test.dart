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
}
