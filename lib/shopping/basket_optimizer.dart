import 'merchant_offer.dart';

class BasketOptimizer {
  const BasketOptimizer({this.maxOffersPerItem = 8, this.maxItems = 12});

  final int maxOffersPerItem;
  final int maxItems;

  ShoppingPlan optimize({
    required List<ShoppingRequestItem> items,
    required List<MerchantOffer> offers,
    required ShoppingStrategy strategy,
  }) {
    if (items.isEmpty) throw const FormatException('Shopping basket is empty.');
    if (items.length > maxItems) throw FormatException('MVP optimizer supports at most $maxItems items.');
    for (final item in items) {
      if (item.quantity < 1) throw FormatException('Invalid quantity for ${item.itemKey}.');
    }

    final candidates = <List<MerchantOffer>>[];
    for (final item in items) {
      final matches = offers
          .where((offer) => offer.itemKey == item.itemKey && offer.inStock)
          .toList()
        ..sort((a, b) {
          if (a.shippingKnown != b.shippingKnown) return a.shippingKnown ? -1 : 1;
          return a.unitPriceTwd.compareTo(b.unitPriceTwd);
        });
      if (matches.isEmpty) throw StateError('No in-stock offer for ${item.label}.');
      candidates.add(matches.take(maxOffersPerItem).toList(growable: false));
    }

    ShoppingPlan? best;
    final chosen = <ShoppingPlanLine>[];

    void visit(int index) {
      if (index == items.length) {
        final plan = _buildPlan(chosen);
        if (strategy == ShoppingStrategy.lowestOneStopTotal && plan.merchantCount != 1) return;
        if (best == null || _isBetter(plan, best!, strategy)) best = plan;
        return;
      }
      for (final offer in candidates[index]) {
        chosen.add(ShoppingPlanLine(request: items[index], offer: offer));
        visit(index + 1);
        chosen.removeLast();
      }
    }

    visit(0);
    if (best == null) {
      throw StateError(strategy == ShoppingStrategy.lowestOneStopTotal
          ? 'No single merchant covers the whole basket.'
          : 'No valid shopping plan.');
    }
    return best!;
  }

  Map<ShoppingStrategy, ShoppingPlan?> compareStrategies({
    required List<ShoppingRequestItem> items,
    required List<MerchantOffer> offers,
  }) {
    final result = <ShoppingStrategy, ShoppingPlan?>{};
    for (final strategy in ShoppingStrategy.values) {
      try {
        result[strategy] = optimize(items: items, offers: offers, strategy: strategy);
      } on StateError {
        result[strategy] = null;
      }
    }
    return result;
  }

  ShoppingPlan _buildPlan(List<ShoppingPlanLine> lines) {
    final frozen = List<ShoppingPlanLine>.from(lines);
    final subtotals = <String, int>{};
    final offersByMerchant = <String, MerchantOffer>{};
    var itemSubtotal = 0;
    for (final line in frozen) {
      itemSubtotal += line.subtotalTwd;
      subtotals.update(line.offer.merchantId, (value) => value + line.subtotalTwd,
          ifAbsent: () => line.subtotalTwd);
      offersByMerchant[line.offer.merchantId] = line.offer;
    }

    var shipping = 0;
    var shippingKnown = true;
    for (final entry in subtotals.entries) {
      final rule = offersByMerchant[entry.key]!;
      if (!rule.shippingKnown) {
        shippingKnown = false;
        continue;
      }
      final threshold = rule.freeShippingThresholdTwd;
      if (threshold == null || entry.value < threshold) shipping += rule.shippingFlatTwd;
    }
    return ShoppingPlan(
      lines: frozen,
      itemSubtotalTwd: itemSubtotal,
      shippingTwd: shipping,
      totalTwd: itemSubtotal + shipping,
      merchantCount: subtotals.length,
      shippingKnown: shippingKnown,
    );
  }

  bool _isBetter(ShoppingPlan candidate, ShoppingPlan current, ShoppingStrategy strategy) {
    // A plan with verified delivery cost must always beat an otherwise
    // comparable plan whose shipping is unknown. If both are unknown, use the
    // visible subtotal only as a provisional ordering, never as a delivered
    // total claim in the UI.
    if (candidate.shippingKnown != current.shippingKnown) {
      return candidate.shippingKnown;
    }
    return switch (strategy) {
      ShoppingStrategy.lowestDeliveredTotal =>
        candidate.totalTwd < current.totalTwd ||
            (candidate.totalTwd == current.totalTwd && candidate.merchantCount < current.merchantCount),
      ShoppingStrategy.lowestOneStopTotal => candidate.totalTwd < current.totalTwd,
      ShoppingStrategy.fewestMerchants =>
        candidate.merchantCount < current.merchantCount ||
            (candidate.merchantCount == current.merchantCount && candidate.totalTwd < current.totalTwd),
    };
  }
}
