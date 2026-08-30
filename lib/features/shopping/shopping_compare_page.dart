import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app_services.dart';
import '../../shopping/merchant_offer.dart';
import '../../shopping/shopping_comparison_service.dart';
import 'shopping_item.dart';

class ShoppingComparePage extends StatefulWidget {
  const ShoppingComparePage({super.key, required this.services});

  final AppServices services;

  @override
  State<ShoppingComparePage> createState() => _ShoppingComparePageState();
}

class _ShoppingComparePageState extends State<ShoppingComparePage> {
  late Future<List<HouseholdShoppingItem>> _itemsFuture;
  ShoppingComparison? _comparison;
  bool _busy = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    _itemsFuture = widget.services.shopping.list(includeDone: false);
  }

  Future<void> _compare(List<HouseholdShoppingItem> items) async {
    if (_busy) return;
    if (widget.services.shoppingComparison.providers.isEmpty) {
      setState(() => _message = '尚未設定網路報價 Provider。請依 docs/OFFER_SEARCH_ENDPOINT.md 設定 endpoint。');
      return;
    }
    if (items.isEmpty) {
      setState(() => _message = '購物清單目前沒有待購項目。');
      return;
    }
    setState(() {
      _busy = true;
      _message = '正在取得商家報價並計算購物組合…';
      _comparison = null;
    });
    try {
      final requests = items
          .map(
            (item) => ShoppingRequestItem(
              itemKey: item.id,
              label: '${item.name} ${item.quantity}${item.unit}${item.note == null ? '' : ' ${item.note}'}',
              quantity: item.quantity,
            ),
          )
          .toList(growable: false);
      final comparison = await widget.services.shoppingComparison.compare(requests);
      if (!mounted) return;
      setState(() {
        _comparison = comparison;
        _message = '找到 ${comparison.offers.length} 筆可比較報價。價格與庫存以商家頁面結帳時為準。';
      });
    } catch (error) {
      if (mounted) setState(() => _message = '比價失敗：$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openUrl(String raw) async {
    final uri = Uri.parse(raw);
    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched && mounted) {
      setState(() => _message = '無法開啟商家連結：$raw');
    }
  }

  String _strategyName(ShoppingStrategy strategy) => switch (strategy) {
        ShoppingStrategy.lowestDeliveredTotal => '含運最低總價',
        ShoppingStrategy.lowestOneStopTotal => '一站購足最低價',
        ShoppingStrategy.fewestMerchants => '最少商家',
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('採購比價')),
      body: SafeArea(
        child: FutureBuilder<List<HouseholdShoppingItem>>(
          future: _itemsFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(child: Text('讀取購物清單失敗：${snapshot.error}'));
            }
            final items = snapshot.data ?? const [];
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const Text('待購項目', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                if (items.isEmpty)
                  const Text('目前沒有待購項目。')
                else
                  ...items.map((item) => ListTile(
                        dense: true,
                        leading: const Icon(Icons.shopping_basket_outlined),
                        title: Text(item.name),
                        subtitle: Text('${item.quantity}${item.unit}${item.note == null ? '' : ' · ${item.note}'}'),
                      )),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _busy ? null : () => _compare(items),
                  icon: const Icon(Icons.travel_explore),
                  label: const Text('搜尋商家並比較'),
                ),
                if (_busy) ...[
                  const SizedBox(height: 12),
                  const LinearProgressIndicator(),
                ],
                if (_message != null) ...[
                  const SizedBox(height: 12),
                  Card(child: Padding(padding: const EdgeInsets.all(12), child: Text(_message!))),
                ],
                if (_comparison != null) ...[
                  const SizedBox(height: 20),
                  for (final strategy in ShoppingStrategy.values)
                    _PlanCard(
                      title: _strategyName(strategy),
                      plan: _comparison!.plans[strategy],
                      onOpenUrl: _openUrl,
                    ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({required this.title, required this.plan, required this.onOpenUrl});

  final String title;
  final ShoppingPlan? plan;
  final Future<void> Function(String url) onOpenUrl;

  @override
  Widget build(BuildContext context) {
    final value = plan;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: value == null
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  const Text('沒有符合此策略的完整購物方案。'),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Text('總價 NT\$${value.totalTwd}（商品 ${value.itemSubtotalTwd} + 運費 ${value.shippingTwd}） · ${value.merchantCount} 家'),
                  const Divider(),
                  for (final line in value.lines)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text('${line.request.label} → ${line.offer.merchantName}'),
                      subtitle: Text('${line.offer.title}\n小計 NT\$${line.subtotalTwd}'),
                      isThreeLine: true,
                      trailing: IconButton(
                        tooltip: '開啟購買連結',
                        onPressed: () => onOpenUrl(line.offer.url),
                        icon: const Icon(Icons.open_in_new),
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}
