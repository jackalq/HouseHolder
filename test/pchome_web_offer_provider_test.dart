import 'package:family_butler/shopping/merchant_offer.dart';
import 'package:family_butler/shopping/pchome_web_offer_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('parses public JSON-LD products from PChome search HTML', () async {
    late http.Request request;
    final provider = PchomeWebOfferProvider(
      client: MockClient((value) async {
        request = value;
        return http.Response('''
<html><head>
<script type="application/ld+json">
{
  "@context":"https://schema.org",
  "@graph":[
    {
      "@type":"Product",
      "name":"測試鮮乳 936ml",
      "url":"https://24h.pchome.com.tw/prod/DBABCD-A900TEST1",
      "offers":{
        "@type":"Offer",
        "price":"95",
        "priceCurrency":"TWD",
        "availability":"https://schema.org/InStock"
      }
    },
    {
      "@type":"Product",
      "name":"第二款鮮乳",
      "offers":{
        "price":"1,299",
        "url":"/prod/DBABCD-A900TEST2"
      }
    }
  ]
}
</script>
</head></html>
''', 200, headers: {'content-type': 'text/html; charset=utf-8'});
      }),
    );

    final offers = await provider.search(
      const ShoppingRequestItem(itemKey: 'milk', label: '鮮乳'),
    );

    expect(request.method, 'GET');
    expect(request.url.host, '24h.pchome.com.tw');
    expect(request.url.queryParameters['q'], '鮮乳');
    expect(offers, hasLength(2));
    expect(offers.first.merchantName, 'PChome 24h購物');
    expect(offers.first.unitPriceTwd, 95);
    expect(offers.last.unitPriceTwd, 1299);
    expect(offers.last.url, contains('/prod/DBABCD-A900TEST2'));
  });

  test('falls back to product anchors when structured metadata is absent', () async {
    final provider = PchomeWebOfferProvider(
      client: MockClient((_) async => http.Response('''
<a href="/prod/DMABCD-A900XYZ">家庭用衛生紙 12包 <span>NT\$299</span></a>
''', 200)),
    );

    final offers = await provider.search(
      const ShoppingRequestItem(itemKey: 'tissue', label: '衛生紙'),
    );
    expect(offers.single.title, contains('家庭用衛生紙'));
    expect(offers.single.unitPriceTwd, 299);
  });

  test('restricted query is rejected before crawling', () async {
    var called = false;
    final provider = PchomeWebOfferProvider(
      client: MockClient((_) async {
        called = true;
        return http.Response('', 200);
      }),
    );
    await expectLater(
      provider.search(const ShoppingRequestItem(itemKey: 'x', label: '電子煙')),
      throwsA(isA<UnsupportedError>()),
    );
    expect(called, isFalse);
  });
}
