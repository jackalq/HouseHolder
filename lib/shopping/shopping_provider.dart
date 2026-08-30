class ShoppingOffer {
  final String provider;
  final String title;
  final int priceTwd;
  final int shippingTwd;
  final String url;
  final DateTime observedAt;

  const ShoppingOffer({required this.provider, required this.title, required this.priceTwd, required this.shippingTwd, required this.url, required this.observedAt});
  int get totalTwd => priceTwd + shippingTwd;
}

abstract class ShoppingProvider {
  String get id;
  Future<List<ShoppingOffer>> search(String query);
  Future<Uri?> buildCartHandoff(List<String> itemNames);

  Future<void> addToCart(List<String> itemNames) =>
      throw UnsupportedError('Direct cart integration not supported');
}
