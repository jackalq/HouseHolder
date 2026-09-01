import '../../shopping/product_preference.dart';

class HouseholdShoppingItem {
  const HouseholdShoppingItem({
    required this.id,
    required this.name,
    this.quantity = 1,
    this.unit = '個',
    this.done = false,
    this.note,
    this.preference = const ProductPreference(),
  });

  final String id;
  final String name;
  final int quantity;
  final String unit;
  final bool done;
  final String? note;
  final ProductPreference preference;

  factory HouseholdShoppingItem.fromJson(Map<String, Object?> json) {
    final id = json['id'];
    final name = json['name'];
    final quantity = json['quantity'] ?? 1;
    final unit = json['unit'] ?? '個';
    final done = json['done'] ?? false;
    if (id is! String || id.trim().isEmpty) throw const FormatException('shopping item id is required.');
    if (name is! String || name.trim().isEmpty) throw const FormatException('shopping item name is required.');
    if (quantity is! int || quantity < 1) throw const FormatException('shopping item quantity must be >= 1.');
    if (unit is! String || unit.trim().isEmpty) throw const FormatException('shopping item unit is required.');
    if (done is! bool) throw const FormatException('shopping item done must be boolean.');
    final rawPreference = json['preference'];
    return HouseholdShoppingItem(
      id: id.trim(),
      name: name.trim(),
      quantity: quantity,
      unit: unit.trim(),
      done: done,
      note: json['note'] as String?,
      preference: rawPreference is Map
          ? ProductPreference.fromJson(rawPreference.map((key, value) => MapEntry(key.toString(), value)))
          : const ProductPreference(),
    );
  }

  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        'quantity': quantity,
        'unit': unit,
        'done': done,
        if (note != null && note!.trim().isNotEmpty) 'note': note!.trim(),
        if (!preference.isEmpty) 'preference': preference.toJson(),
      };

  HouseholdShoppingItem copyWith({bool? done, ProductPreference? preference}) => HouseholdShoppingItem(
        id: id,
        name: name,
        quantity: quantity,
        unit: unit,
        done: done ?? this.done,
        note: note,
        preference: preference ?? this.preference,
      );
}
