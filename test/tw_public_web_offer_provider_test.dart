import 'package:family_butler/shopping/merchant_offer.dart';
import 'package:family_butler/shopping/tw_public_web_offer_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('momo provider parses JSON-LD product without pretending shipping is free', () async {
    late Uri requested;
    final provider = MomoWebOfferProvider(
      client: MockClient((request) async {
        requested = request.url;
        return http.Response('''
<html><head>
<script type="application/ld+json">
{"@type":"Product","name":"家庭號鮮乳 936ml","url":"https://www.momoshop.com.tw/goods/GoodsDetail.jsp?i_code=123","offers":{"@type":"Offer","price":"99","availability":"https://schema.org/InStock"}}
</script>
</head></html>
''', 200, headers: {'content-type': 'text/html; charset=utf-8'});
      }),
    );

    final offers = await provider.search(const ShoppingRequestItem(itemKey: 'milk', label: '鮮乳'));

    expect(requested.host, 'www.momoshop.com.tw');
    expect(requested.queryParameters['keyword'], '鮮乳');
    expect(offers, hasLength(1));
    expect(offers.single.merchantId, 'momo');
    expect(offers.single.unitPriceTwd, 99);
    expect(offers.single.shippingKnown, isFalse);
  });

  test('Yahoo provider parses public anchor fallback and keeps merchant domain', () async {
    final provider = YahooShoppingWebOfferProvider(
      client: MockClient((request) async => http.Response('''
<html><body>
<a href="https://tw.buy.yahoo.com/gdsale/abc-123.html"><span>抽取式衛生紙 12包</span><b>NT\$199</b></a>
<a href="https://evil.example/product/1">不可信商品 NT\$1</a>
</body></html>
''', 200, headers: {'content-type': 'text/html; charset=utf-8'})),
    );

    final offers = await provider.search(const ShoppingRequestItem(itemKey: 'tissue', label: '衛生紙'));

    expect(offers, hasLength(1));
    expect(offers.single.merchantId, 'yahoo-shopping');
    expect(offers.single.unitPriceTwd, 199);
    expect(Uri.parse(offers.single.url).host, 'tw.buy.yahoo.com');
    expect(offers.single.shippingKnown, isFalse);
  });
}
