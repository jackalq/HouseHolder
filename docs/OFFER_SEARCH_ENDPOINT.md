# Offer Search Sources

HouseHolder now includes built-in public-web search providers for Taiwan shopping sites. Ordinary users do **not** need to maintain a price table or configure `HOUSEHOLDER_OFFER_ENDPOINT` just to compare prices.

Current built-in providers:

- PChome 24h
- momo購物網
- Yahoo購物中心

They read only publicly reachable search/product metadata and links. They do not bypass login, CAPTCHA, rate limits, or other access controls. Results are cached briefly in the app to avoid repeatedly hitting merchant sites.

`HOUSEHOLDER_OFFER_ENDPOINT` is optional. It remains useful for deployments that want additional merchant APIs, server-side parsers, affiliate feeds, or credentials that must not be embedded in the APK.

Optional build-time configuration:

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

It returns normalized offers:

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
      "shippingKnown": true,
      "url": "https://merchant.example/product/123",
      "observedAt": "2026-09-01T07:00:00Z",
      "inStock": true
    }
  ]
}
```

When a merchant page does not expose enough information to calculate delivery, providers must set `shippingKnown: false` (or omit all shipping fields). HouseHolder must not interpret missing shipping data as free shipping. Such plans are shown as provisional item subtotals until the merchant page confirms delivery cost.

Rules:

- Search/extraction belongs to providers; arithmetic and plan ranking belong to HouseHolder's deterministic `BasketOptimizer`.
- Providers should return only offers grounded in current merchant pages/APIs and preserve the purchase URL.
- One failing provider must not discard valid results from other providers.
- No autonomous checkout or payment. HouseHolder opens the merchant page for final confirmation.
- Do not ship provider secrets in Flutter `--dart-define`; secrets belong on the optional endpoint.
- Production endpoints must use HTTPS.
- Restricted product categories are rejected before crawler/API requests are made.
