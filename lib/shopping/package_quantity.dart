enum PackageDimension { volume, mass, count }

class PackageQuantity {
  const PackageQuantity({
    required this.dimension,
    required this.baseQuantity,
    required this.baseUnit,
  });

  final PackageDimension dimension;
  final double baseQuantity;
  final String baseUnit;

  double unitPrice(int priceTwd) => priceTwd / baseQuantity;

  static PackageQuantity? parse(String text) {
    final normalized = text
        .toLowerCase()
        .replaceAll('×', 'x')
        .replaceAll('*', 'x')
        .replaceAll(RegExp(r'\s+'), ' ');

    final volume = RegExp(r'(\d+(?:\.\d+)?)\s*(ml|毫升|l|公升|公升裝)(?:\s*x\s*(\d+)\s*(?:瓶|罐|盒|入|包)?)?')
        .allMatches(normalized)
        .toList();
    if (volume.isNotEmpty) {
      final match = volume.last;
      var value = double.parse(match.group(1)!);
      final unit = match.group(2)!;
      if (unit == 'l' || unit.startsWith('公升')) value *= 1000;
      final multiplier = int.tryParse(match.group(3) ?? '') ?? 1;
      return PackageQuantity(dimension: PackageDimension.volume, baseQuantity: value * multiplier, baseUnit: 'ml');
    }

    final mass = RegExp(r'(\d+(?:\.\d+)?)\s*(kg|公斤|g|公克)(?:\s*x\s*(\d+)\s*(?:包|袋|盒|罐|入)?)?')
        .allMatches(normalized)
        .toList();
    if (mass.isNotEmpty) {
      final match = mass.last;
      var value = double.parse(match.group(1)!);
      final unit = match.group(2)!;
      if (unit == 'kg' || unit == '公斤') value *= 1000;
      final multiplier = int.tryParse(match.group(3) ?? '') ?? 1;
      return PackageQuantity(dimension: PackageDimension.mass, baseQuantity: value * multiplier, baseUnit: 'g');
    }

    // Nested consumables such as 100抽 x 12包 are normalized by the inner
    // consumable unit, because that is what users compare between packages.
    final nestedCount = RegExp(r'(\d+(?:\.\d+)?)\s*(抽|片|顆|枚|張)\s*x\s*(\d+)\s*(?:包|袋|盒|入|捲|卷|組)')
        .allMatches(normalized)
        .toList();
    if (nestedCount.isNotEmpty) {
      final match = nestedCount.last;
      return PackageQuantity(
        dimension: PackageDimension.count,
        baseQuantity: double.parse(match.group(1)!) * int.parse(match.group(3)!),
        baseUnit: match.group(2)!,
      );
    }

    final count = RegExp(r'(\d+(?:\.\d+)?)\s*(入|包|瓶|罐|盒|顆|片|抽|張|捲|卷|組)')
        .allMatches(normalized)
        .toList();
    if (count.isNotEmpty) {
      final match = count.last;
      final unit = match.group(2)! == '卷' ? '捲' : match.group(2)!;
      return PackageQuantity(
        dimension: PackageDimension.count,
        baseQuantity: double.parse(match.group(1)!),
        baseUnit: unit,
      );
    }
    return null;
  }

  bool compatibleWith(PackageQuantity other) =>
      dimension == other.dimension && baseUnit == other.baseUnit;
}
