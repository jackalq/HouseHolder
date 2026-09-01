import 'dart:convert';

import 'package:http/http.dart' as http;

import 'merchant_offer.dart';
import 'merchant_offer_provider.dart';
import 'shopping_safety_policy.dart';

class TwPublicWebOfferProvider implements MerchantOfferProvider {
  TwPublicWebOfferProvider({
    required this.providerId,
    required this.merchantId,
    required this.merchantName,
    required this.searchUriBuilder,
    required this.allowedHosts,
    required this.productHrefHints,
    http.Client? client,
    ShoppingSafetyPolicy safetyPolicy = const ShoppingSafetyPolicy(),
    this.maxResults = 12,
  })  : _client = client ?? http.Client(),
        _safetyPolicy = safetyPolicy;

  final String providerId;
  final String merchantId;
  final String merchantName;
  final Uri Function(String query) searchUriBuilder;
  final Set<String> allowedHosts;
  final List<String> productHrefHints;
  final int maxResults;
  final http.Client _client;
  final ShoppingSafetyPolicy _safetyPolicy;

  @override
  String get id => providerId;

  @override
  Future<List<MerchantOffer>> search(ShoppingRequestItem item) async {
    _safetyPolicy.ensureAllowed(item.label);
    final response = await _client.get(
      searchUriBuilder(item.label),
      headers: const {
        'accept': 'text/html,application/xhtml+xml,application/json;q=0.9,*/*;q=0.8',
        'accept-language': 'zh-TW,zh;q=0.9,en;q=0.6',
        'user-agent': 'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 HouseHolder/0.1',
      },
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('$merchantName 搜尋回傳 HTTP ${response.statusCode}。');
    }

    final html = utf8.decode(response.bodyBytes, allowMalformed: true);
    final now = DateTime.now().toUtc();
    final result = <MerchantOffer>[];
    final seen = <String>{};

    for (final product in _extractJsonLdProducts(html)) {
      if (result.length >= maxResults) break;
      final title = _string(product['name']);
      final offer = _firstOffer(product['offers']);
      final price = _price(offer?['price'] ?? offer?['lowPrice'] ?? product['price']);
      final rawUrl = _string(offer?['url']) ?? _string(product['url']);
      final url = _normalizeUrl(rawUrl);
      if (title == null || price == null || url == null || !seen.add(url)) continue;
      final availability = _string(offer?['availability'])?.toLowerCase() ?? '';
      result.add(_offer(
        item: item,
        title: title,
        price: price,
        url: url,
        observedAt: now,
        inStock: !availability.contains('outofstock'),
      ));
    }

    if (result.length < maxResults) {
      for (final card in _extractAnchorCards(html)) {
        if (result.length >= maxResults) break;
        final url = _normalizeUrl(card.url);
        if (url == null || !seen.add(url)) continue;
        result.add(_offer(
          item: item,
          title: card.title,
          price: card.price,
          url: url,
          observedAt: now,
          inStock: true,
        ));
      }
    }
    return result;
  }

  MerchantOffer _offer({
    required ShoppingRequestItem item,
    required String title,
    required int price,
    required String url,
    required DateTime observedAt,
    required bool inStock,
  }) => MerchantOffer(
        itemKey: item.itemKey,
        merchantId: merchantId,
        merchantName: merchantName,
        title: title,
        unitPriceTwd: price,
        shippingFlatTwd: 0,
        freeShippingThresholdTwd: null,
        shippingKnown: false,
        url: url,
        observedAt: observedAt,
        inStock: inStock,
      );

  Iterable<Map<String, Object?>> _extractJsonLdProducts(String html) sync* {
    final pattern = RegExp(
      r'''<script[^>]*type\s*=\s*["']application/ld\+json["'][^>]*>([\s\S]*?)</script>''',
      caseSensitive: false,
    );
    for (final match in pattern.allMatches(html)) {
      final raw = match.group(1)?.trim();
      if (raw == null || raw.isEmpty) continue;
      try {
        yield* _walkProducts(jsonDecode(raw));
      } catch (_) {
        // Public pages occasionally contain malformed metadata. Ignore it.
      }
    }
  }

  Iterable<Map<String, Object?>> _walkProducts(Object? node) sync* {
    if (node is List) {
      for (final value in node) {
        yield* _walkProducts(value);
      }
      return;
    }
    if (node is! Map) return;
    final map = node.map((key, value) => MapEntry(key.toString(), value));
    final type = map['@type'];
    if (type == 'Product' || (type is List && type.contains('Product'))) yield map;
    for (final value in map.values) {
      if (value is Map || value is List) yield* _walkProducts(value);
    }
  }

  Map<String, Object?>? _firstOffer(Object? raw) {
    Object? value = raw;
    if (value is List) value = value.isEmpty ? null : value.first;
    if (value is! Map) return null;
    return value.map((key, value) => MapEntry(key.toString(), value));
  }

  Iterable<_AnchorOffer> _extractAnchorCards(String html) sync* {
    final pattern = RegExp(
      r'''<a\b[^>]*href\s*=\s*["']([^"']+)["'][^>]*>([\s\S]*?)</a>''',
      caseSensitive: false,
    );
    for (final match in pattern.allMatches(html)) {
      final href = _decodeHtml(match.group(1) ?? '');
      if (productHrefHints.isNotEmpty && !productHrefHints.any(href.contains)) continue;
      var text = _decodeHtml(_stripTags(match.group(2) ?? ''))
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      if (text.isEmpty) continue;
      final priceMatch = RegExp(r'(?:NT\$|NTD|\$)\s*([0-9][0-9,]*)', caseSensitive: false).firstMatch(text);
      if (priceMatch == null) continue;
      final price = int.tryParse(priceMatch.group(1)!.replaceAll(',', ''));
      if (price == null || price <= 0) continue;
      text = text.replaceFirst(priceMatch.group(0)!, '').trim();
      if (text.length > 180) text = text.substring(0, 180).trim();
      if (text.isEmpty) continue;
      yield _AnchorOffer(title: text, price: price, url: href);
    }
  }

  String? _normalizeUrl(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    final value = _decodeHtml(raw.trim());
    final parsed = Uri.tryParse(value);
    final baseHost = allowedHosts.first;
    final uri = parsed != null && parsed.hasScheme
        ? parsed
        : Uri.parse('https://$baseHost').resolve(value);
    if (uri.scheme != 'https' && uri.scheme != 'http') return null;
    final allowed = allowedHosts.any((host) => uri.host == host || uri.host.endsWith('.$host'));
    return allowed ? uri.toString() : null;
  }

  int? _price(Object? value) {
    if (value is num) return value.round() > 0 ? value.round() : null;
    if (value is! String) return null;
    final match = RegExp(r'([0-9][0-9,]*(?:\.[0-9]+)?)').firstMatch(value);
    if (match == null) return null;
    final result = double.tryParse(match.group(1)!.replaceAll(',', ''))?.round();
    return result != null && result > 0 ? result : null;
  }

  String? _string(Object? value) {
    if (value is! String) return null;
    final text = _decodeHtml(value).trim();
    return text.isEmpty ? null : text;
  }

  String _stripTags(String value) => value.replaceAll(RegExp(r'<[^>]+>'), ' ');

  String _decodeHtml(String value) => value
      .replaceAll('&amp;', '&')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&nbsp;', ' ');
}

class MomoWebOfferProvider extends TwPublicWebOfferProvider {
  MomoWebOfferProvider({http.Client? client})
      : super(
          providerId: 'momo-web',
          merchantId: 'momo',
          merchantName: 'momo購物網',
          searchUriBuilder: (query) => Uri.https(
            'www.momoshop.com.tw',
            '/search/searchShop.jsp',
            {'keyword': query},
          ),
          allowedHosts: const {'www.momoshop.com.tw', 'momoshop.com.tw'},
          productHrefHints: const ['/goods/GoodsDetail.jsp', 'goods.momo'],
          client: client,
        );
}

class YahooShoppingWebOfferProvider extends TwPublicWebOfferProvider {
  YahooShoppingWebOfferProvider({http.Client? client})
      : super(
          providerId: 'yahoo-shopping-web',
          merchantId: 'yahoo-shopping',
          merchantName: 'Yahoo購物中心',
          searchUriBuilder: (query) => Uri.https(
            'tw.buy.yahoo.com',
            '/search/product',
            {'p': query},
          ),
          allowedHosts: const {'tw.buy.yahoo.com', 'buy.yahoo.com'},
          productHrefHints: const ['/gdsale/', '/product/'],
          client: client,
        );
}

class _AnchorOffer {
  const _AnchorOffer({required this.title, required this.price, required this.url});
  final String title;
  final int price;
  final String url;
}
