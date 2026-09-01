import 'dart:convert';

import 'package:http/http.dart' as http;

import 'merchant_offer.dart';
import 'merchant_offer_provider.dart';
import 'shopping_safety_policy.dart';

/// Direct public-web offer discovery for PChome 24h.
///
/// This deliberately uses only publicly reachable search/product data. It does
/// not attempt to bypass login, CAPTCHA, rate limits, or other access controls.
class PchomeWebOfferProvider implements MerchantOfferProvider {
  PchomeWebOfferProvider({
    http.Client? client,
    ShoppingSafetyPolicy safetyPolicy = const ShoppingSafetyPolicy(),
    this.maxResults = 12,
  })  : _client = client ?? http.Client(),
        _safetyPolicy = safetyPolicy;

  final http.Client _client;
  final ShoppingSafetyPolicy _safetyPolicy;
  final int maxResults;

  @override
  String get id => 'pchome-24h-web';

  @override
  Future<List<MerchantOffer>> search(ShoppingRequestItem item) async {
    _safetyPolicy.ensureAllowed(item.label);
    final uri = Uri.https('24h.pchome.com.tw', '/search/', {'q': item.label});
    final response = await _client.get(
      uri,
      headers: const {
        'accept': 'text/html,application/xhtml+xml,application/json;q=0.9,*/*;q=0.8',
        'accept-language': 'zh-TW,zh;q=0.9,en;q=0.6',
        'user-agent': 'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 HouseHolder/0.1',
      },
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('PChome 搜尋回傳 HTTP ${response.statusCode}。');
    }

    final html = utf8.decode(response.bodyBytes, allowMalformed: true);
    final now = DateTime.now().toUtc();
    final offers = <MerchantOffer>[];
    final seenUrls = <String>{};

    for (final product in _extractJsonLdProducts(html)) {
      if (offers.length >= maxResults) break;
      final title = _string(product['name']);
      final offerNode = _firstOffer(product['offers']);
      final price = _price(offerNode?['price'] ?? offerNode?['lowPrice'] ?? product['price']);
      final rawUrl = _string(offerNode?['url']) ?? _string(product['url']);
      final url = _normalizeProductUrl(rawUrl);
      if (title == null || price == null || url == null || !seenUrls.add(url)) continue;
      final availability = _string(offerNode?['availability'])?.toLowerCase() ?? '';
      offers.add(MerchantOffer(
        itemKey: item.itemKey,
        merchantId: 'pchome-24h',
        merchantName: 'PChome 24h購物',
        title: title,
        unitPriceTwd: price,
        shippingFlatTwd: 0,
        freeShippingThresholdTwd: null,
        shippingKnown: false,
        url: url,
        observedAt: now,
        inStock: !availability.contains('outofstock'),
      ));
    }

    if (offers.length < maxResults) {
      for (final fallback in _extractAnchorCards(html)) {
        if (offers.length >= maxResults) break;
        final url = _normalizeProductUrl(fallback.url);
        if (url == null || !seenUrls.add(url)) continue;
        offers.add(MerchantOffer(
          itemKey: item.itemKey,
          merchantId: 'pchome-24h',
          merchantName: 'PChome 24h購物',
          title: fallback.title,
          unitPriceTwd: fallback.price,
          shippingFlatTwd: 0,
          freeShippingThresholdTwd: null,
          shippingKnown: false,
          url: url,
          observedAt: now,
          inStock: true,
        ));
      }
    }

    return offers;
  }

  Iterable<Map<String, Object?>> _extractJsonLdProducts(String html) sync* {
    final scripts = RegExp(
      r'''<script[^>]*type\s*=\s*["']application/ld\+json["'][^>]*>([\s\S]*?)</script>''',
      caseSensitive: false,
    );
    for (final match in scripts.allMatches(html)) {
      final raw = match.group(1)?.trim();
      if (raw == null || raw.isEmpty) continue;
      try {
        final decoded = jsonDecode(raw);
        yield* _walkProducts(decoded);
      } catch (_) {
        // Ignore malformed metadata and continue with the next public block.
      }
    }
  }

  Iterable<Map<String, Object?>> _walkProducts(Object? node) sync* {
    if (node is List) {
      for (final child in node) {
        yield* _walkProducts(child);
      }
      return;
    }
    if (node is! Map) return;
    final map = node.map((key, value) => MapEntry(key.toString(), value));
    final type = map['@type'];
    final isProduct = type == 'Product' || (type is List && type.contains('Product'));
    if (isProduct) yield map;
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

  Iterable<_FallbackOffer> _extractAnchorCards(String html) sync* {
    final anchorPattern = RegExp(
      r'''<a\b[^>]*href\s*=\s*["']([^"']*(?:/prod/|/prod\?)[^"']*)["'][^>]*>([\s\S]*?)</a>''',
      caseSensitive: false,
    );
    for (final match in anchorPattern.allMatches(html)) {
      final href = _decodeHtml(match.group(1) ?? '');
      final body = _decodeHtml(_stripTags(match.group(2) ?? '')).replaceAll(RegExp(r'\s+'), ' ').trim();
      if (body.isEmpty) continue;
      final priceMatch = RegExp(r'(?:NT\$|\$)\s*([0-9][0-9,]*)').firstMatch(body);
      if (priceMatch == null) continue;
      final price = int.tryParse(priceMatch.group(1)!.replaceAll(',', ''));
      if (price == null || price <= 0) continue;
      var title = body.replaceFirst(priceMatch.group(0)!, '').trim();
      if (title.length > 160) title = title.substring(0, 160).trim();
      if (title.isEmpty) continue;
      yield _FallbackOffer(title: title, price: price, url: href);
    }
  }

  String? _normalizeProductUrl(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    final value = _decodeHtml(raw.trim());
    final uri = Uri.tryParse(value);
    final resolved = uri != null && uri.hasScheme
        ? uri
        : Uri.parse('https://24h.pchome.com.tw').resolve(value);
    if (resolved.scheme != 'https' && resolved.scheme != 'http') return null;
    if (resolved.host != '24h.pchome.com.tw' && !resolved.host.endsWith('.pchome.com.tw')) return null;
    return resolved.toString();
  }

  int? _price(Object? value) {
    if (value is num) return value.round() > 0 ? value.round() : null;
    if (value is! String) return null;
    final match = RegExp(r'([0-9][0-9,]*(?:\.[0-9]+)?)').firstMatch(value);
    if (match == null) return null;
    final parsed = double.tryParse(match.group(1)!.replaceAll(',', ''))?.round();
    return parsed != null && parsed > 0 ? parsed : null;
  }

  String? _string(Object? value) {
    if (value is! String) return null;
    final trimmed = _decodeHtml(value).trim();
    return trimmed.isEmpty ? null : trimmed;
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

class _FallbackOffer {
  const _FallbackOffer({required this.title, required this.price, required this.url});
  final String title;
  final int price;
  final String url;
}
