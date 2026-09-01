import 'dart:convert';

import 'package:family_butler/shopping/http_offer_provider.dart';
import 'package:family_butler/shopping/merchant_offer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('parses normalized HTTPS merchant offers', () async {
    late http.Request request;
    final client = MockClient((value) async {
      request = value;
      return http.Response(
        jsonEncode({
          'offers': [
            {
              'merchantId': 'shop-a',
              'merchantName': '商家 A',
              'title': '鮮乳',
              'unitPriceTwd': 95,
              'shippingFlatTwd': 60,
              'freeShippingThresholdTwd': 799,
              'url': 'https://example.com/milk',
              'observedAt': '2026-08-30T08:00:00Z',
              'inStock': true
            }
          ]
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    });
    final provider = HttpMerchantOfferProvider(
      endpoint: Uri.parse('https://offers.example.com/search'),
      client: client,
    );
    final offers = await provider.search(
      const ShoppingRequestItem(itemKey: 'milk', label: '鮮乳 1瓶'),
    );
    expect(request.method, 'POST');
    expect(jsonDecode(request.body)['market'], 'TW');
    expect(offers.single.unitPriceTwd, 95);
    expect(offers.single.shippingFlatTwd, 60);
    expect(offers.single.shippingKnown, isTrue);
  });

  test('missing shipping fields are not interpreted as free shipping', () async {
    final provider = HttpMerchantOfferProvider(
      endpoint: Uri.parse('https://offers.example.com/search'),
      client: MockClient((_) async => http.Response(
        jsonEncode({
          'offers': [
            {
              'merchantId': 'shop-a',
              'merchantName': '商家 A',
              'title': '衛生紙',
              'unitPriceTwd': 199,
              'url': 'https://example.com/tissue'
            }
          ]
        }),
        200,
      )),
    );

    final offers = await provider.search(
      const ShoppingRequestItem(itemKey: 'tissue', label: '衛生紙'),
    );

    expect(offers.single.shippingFlatTwd, 0);
    expect(offers.single.shippingKnown, isFalse);
  });

  test('restricted shopping query is rejected before network request', () async {
    var called = false;
    final provider = HttpMerchantOfferProvider(
      endpoint: Uri.parse('https://offers.example.com/search'),
      client: MockClient((_) async {
        called = true;
        return http.Response('{}', 200);
      }),
    );
    await expectLater(
      provider.search(const ShoppingRequestItem(itemKey: 'x', label: '電子煙')),
      throwsA(isA<UnsupportedError>()),
    );
    expect(called, isFalse);
  });
}
