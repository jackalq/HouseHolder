class ShoppingRequestItem {
  const ShoppingRequestItem({required this.itemKey, required this.label, this.quantity = 1});

  final String itemKey;
  final String label;
  final int quantity;
}

class MerchantOffer {
  const MerchantOffer({
    required this.itemKey,
    required this.merchantId,
    required this.merchantName,
    required this.title,
    required this.unitPriceTwd,
    required this.url,
    required this.observedAt,
    this.shippingFlatTwd = 0,
    this.freeShippingThresholdTwd,
    this.inStock = true,
  });

  final String itemKey;
  final String merchantId;
  final String merchantName;
  final String title;
  final int unitPriceTwd;
  final int shippingFlatTwd;
  final int? freeShippingThresholdTwd;
  final String url;
  final DateTime observedAt;
  final bool inStock;
}

class ShoppingPlanLine {
  const ShoppingPlanLine({required this.request, required this.offer});
  final ShoppingRequestItem request;
  final MerchantOffer offer;
  int get subtotalTwd => request.quantity * offer.unitPriceTwd;
}

class ShoppingPlan {
  const ShoppingPlan({
    required this.lines,
    required this.itemSubtotalTwd,
    required this.shippingTwd,
    required this.totalTwd,
    required this.merchantCount,
  });

  final List<ShoppingPlanLine> lines;
  final int itemSubtotalTwd;
  final int shippingTwd;
  final int totalTwd;
  final int merchantCount;

  List<String> get purchaseUrls => lines.map((line) => line.offer.url).toSet().toList(growable: false);
}

enum ShoppingStrategy { lowestDeliveredTotal, lowestOneStopTotal, fewestMerchants }
