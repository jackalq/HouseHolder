import 'dart:convert';

import 'package:http/http.dart' as http;

import 'merchant_offer.dart';
import 'merchant_offer_provider.dart';
import 'shopping_safety_policy.dart';

class HttpMerchantOfferProvider implements MerchantOfferProvider {
  HttpMerchantOfferProvider({
    required this.endpoint,
    http.Client? client,
    ShoppingSafetyPolicy safetyPolicy = const ShoppingSafetyPolicy(),
  })  : _client = client ?? http.Client(),
        _safetyPolicy = safetyPolicy {
    final secure = endpoint.scheme == 'https';
    final local = endpoint.host == 'localhost' || endpoint.host == '127.0.0.1';
    if (!secure && !local) {
      throw ArgumentError.value(endpoint, 'endpoint', 'Offer endpoint must use HTTPS.');
    }
  }

  @override
  String get id => 'householder-http-offers';

  final Uri endpoint;
  final http.Client _client;
  final ShoppingSafetyPolicy _safetyPolicy;

  @override
  Future<List<MerchantOffer>> search(ShoppingRequestItem item) async {
    _safetyPolicy.ensureAllowed(item.label);
    final response = await _client.post(
      endpoint,
      headers: const {'content-type': 'application/json; charset=utf-8'},
      body: jsonEncode({
        'itemKey': item.itemKey,
        'query': item.label,
        'quantity': item.quantity,
        'currency': 'TWD',
        'market': 'TW',
      }),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('Offer endpoint returned HTTP ${response.statusCode}.');
    }
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (decoded is! Map || decoded['offers'] is! List) {
      throw const FormatException('Offer endpoint must return {"offers": [...]}.');
    }

    final result = <MerchantOffer>[];
    for (final raw in decoded['offers'] as List) {
      if (raw is! Map) throw const FormatException('Each offer must be an object.');
      final offer = raw.map((key, value) => MapEntry(key.toString(), value));
      result.add(_parse(item.itemKey, offer));
    }
    return result;
  }

  MerchantOffer _parse(String itemKey, Map<String, Object?> json) {
    String requiredString(String key) {
      final value = json[key];
      if (value is! String || value.trim().isEmpty) throw FormatException('$key is required.');
      return value.trim();
    }

    int nonNegativeInt(String key, {int fallback = 0}) {
      final value = json[key] ?? fallback;
      if (value is! num || value < 0 || value.toInt() != value) {
        throw FormatException('$key must be a non-negative integer.');
      }
      return value.toInt();
    }

    final price = nonNegativeInt('unitPriceTwd');
    if (price <= 0) throw const FormatException('unitPriceTwd must be > 0.');
    final url = Uri.tryParse(requiredString('url'));
    if (url == null || (url.scheme != 'https' && url.scheme != 'http')) {
      throw const FormatException('Offer url must be HTTP(S).');
    }
    final thresholdRaw = json['freeShippingThresholdTwd'];
    final threshold = thresholdRaw == null ? null : nonNegativeInt('freeShippingThresholdTwd');
    final observedText = json['observedAt'];
    final observedAt = observedText is String ? DateTime.tryParse(observedText) : null;
    final inStock = json['inStock'] ?? true;
    if (inStock is! bool) throw const FormatException('inStock must be boolean.');

    return MerchantOffer(
      itemKey: itemKey,
      merchantId: requiredString('merchantId'),
      merchantName: requiredString('merchantName'),
      title: requiredString('title'),
      unitPriceTwd: price,
      shippingFlatTwd: nonNegativeInt('shippingFlatTwd'),
      freeShippingThresholdTwd: threshold,
      url: url.toString(),
      observedAt: observedAt?.toUtc() ?? DateTime.now().toUtc(),
      inStock: inStock,
    );
  }
}
