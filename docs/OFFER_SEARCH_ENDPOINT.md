# Offer Search Endpoint

HouseHolder does not embed web-search or retailer API secrets in the APK. A deployment can configure a stateless HTTPS endpoint that searches approved merchants and returns normalized offers.

Build-time configuration:

```bash
flutter build apk --debug \
  --dart-define=HOUSEHOLDER_OFFER_ENDPOINT=https://example.com/householder/offers
```

The endpoint receives one POST per shopping-list item:

```json
{
  "itemKey": "shopping-item-id",
  "query": "牛奶 2瓶 低脂",
  "quantity": 2,
  "currency": "TWD",
  "market": "TW"
}
```

It returns:

```json
{
  "offers": [
    {
      "merchantId": "merchant-a",
      "merchantName": "商家 A",
      "title": "低脂鮮乳 936ml",
      "unitPriceTwd": 92,
      "shippingFlatTwd": 60,
      "freeShippingThresholdTwd": 799,
      "url": "https://merchant.example/product/123",
      "observedAt": "2026-08-30T08:00:00Z",
      "inStock": true
    }
  ]
}
```

Rules:

- Search/extraction belongs to the endpoint; arithmetic and plan ranking belong to HouseHolder's deterministic `BasketOptimizer`.
- The endpoint should return only offers it can ground in current merchant pages/APIs and must preserve the purchase URL.
- No autonomous checkout or payment. HouseHolder only opens the merchant page.
- Do not ship provider secrets in Flutter `--dart-define`; secrets belong on the endpoint.
- Production endpoints must use HTTPS.
- The provider must not return age-restricted, weapon, intoxicant, gambling, or other restricted products.
