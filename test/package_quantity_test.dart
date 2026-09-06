import 'package:family_butler/shopping/package_quantity.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('normalizes tissue nested pack count', () {
    final value = PackageQuantity.parse('衛生紙 100抽 x 12包');
    expect(value, isNotNull);
    expect(value!.dimension, PackageDimension.count);
    expect(value.baseQuantity, 1200);
    expect(value.baseUnit, '抽');
  });

  test('normalizes milliliters and liters', () {
    expect(PackageQuantity.parse('鮮乳 936ml')!.baseQuantity, 936);
    expect(PackageQuantity.parse('鮮乳 1.858L')!.baseQuantity, 1858);
  });

  test('normalizes kilograms and multipacks', () {
    expect(PackageQuantity.parse('白米 2kg')!.baseQuantity, 2000);
    expect(PackageQuantity.parse('咖啡豆 500g x 3包')!.baseQuantity, 1500);
  });

  test('normalizes volume multipacks', () {
    final value = PackageQuantity.parse('牛奶 936ml x 2瓶');
    expect(value!.baseQuantity, 1872);
    expect(value.baseUnit, 'ml');
  });

  test('returns null when no comparable package unit exists', () {
    expect(PackageQuantity.parse('家庭號超值組'), isNull);
  });

  test('incompatible dimensions are not comparable', () {
    final volume = PackageQuantity.parse('936ml')!;
    final mass = PackageQuantity.parse('936g')!;
    expect(volume.compatibleWith(mass), isFalse);
  });
}
