import 'product_preference.dart';

class ShoppingRequestItem {
  const ShoppingRequestItem({
    required this.itemKey,
    required this.label,
    this.quantity = 1,
    this.preference = const ProductPreference(),
  });

  final String itemKey;
  final String label;
  final int quantity;
  final ProductPreference preference;
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
    this.shippingKnown = true,
    this.inStock = true,
  });

  final String itemKey;
  final String merchantId;
  final String merchantName;
  final String title;
  final int unitPriceTwd;
  final int shippingFlatTwd;
  final int? freeShippingThresholdTwd;
  final bool shippingKnown;
  final String url;
  final DateTime observedAt;
  final bool inStock;
}

class ShoppingPlanLine {
  const ShoppingPlanLine({required this.request, required this.offer});
  final ShoppingRequestItem request;
  final MerchantOffer offer;
  int get subtotalTwd => request.quantity * offer.unitPriceTwd;
  int get preferenceScore => request.preference.score(
        title: offer.title,
        merchantId: offer.merchantId,
        merchantName: offer.merchantName,
      );
}

class ShoppingPlan {
  const ShoppingPlan({
    required this.lines,
    required this.itemSubtotalTwd,
    required this.shippingTwd,
    required this.totalTwd,
    required this.merchantCount,
    required this.shippingKnown,
    this.preferenceScore = 0,
  });

  final List<ShoppingPlanLine> lines;
  final int itemSubtotalTwd;
  final int shippingTwd;
  final int totalTwd;
  final int merchantCount;
  final bool shippingKnown;
  final int preferenceScore;

  List<String> get purchaseUrls => lines.map((line) => line.offer.url).toSet().toList(growable: false);
}

enum ShoppingStrategy { lowestDeliveredTotal, lowestOneStopTotal, fewestMerchants }
