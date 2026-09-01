import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app_services.dart';
import '../../domain/entity_ids.dart';
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
  final _name = TextEditingController();
  late Future<List<HouseholdShoppingItem>> _itemsFuture;
  ShoppingComparison? _comparison;
  bool _busy = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _reload() => _itemsFuture = widget.services.shopping.list(includeDone: true);

  Future<void> _add() async {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    await widget.services.shopping.add(HouseholdShoppingItem(id: EntityIds.generate('shopping'), name: name));
    _name.clear();
    if (mounted) setState(() { _comparison = null; _reload(); });
  }

  Future<void> _setDone(HouseholdShoppingItem item, bool value) async {
    await widget.services.shopping.setDone(item.id, value);
    if (mounted) setState(() { _comparison = null; _reload(); });
  }

  Future<void> _compare(List<HouseholdShoppingItem> allItems) async {
    if (_busy) return;
    final items = allItems.where((item) => !item.done).toList(growable: false);
    if (widget.services.shoppingComparison.providers.isEmpty) {
      setState(() => _message = '目前沒有可用的網路報價來源。');
      return;
    }
    if (items.isEmpty) {
      setState(() => _message = '購物清單目前沒有待購項目。');
      return;
    }
    setState(() { _busy = true; _message = '正在搜尋公開商家頁面並計算購物組合…'; _comparison = null; });
    try {
      final requests = items.map((item) => ShoppingRequestItem(
        itemKey: item.id,
        label: '${item.name} ${item.quantity}${item.unit}${item.note == null ? '' : ' ${item.note}'}',
        quantity: item.quantity,
      )).toList(growable: false);
      final comparison = await widget.services.shoppingComparison.compare(requests);
      if (!mounted) return;
      final failedCount = comparison.providerErrors.length;
      final suffix = failedCount == 0 ? '' : '；另有 $failedCount 個來源暫時無法取得，已保留其他來源結果';
      setState(() {
        _comparison = comparison;
        _message = '找到 ${comparison.offers.length} 筆即時報價$suffix。價格、庫存與運費以商家頁面結帳時為準。';
      });
    } catch (error) {
      if (mounted) setState(() => _message = '比價失敗：$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openUrl(String raw) async {
    final uri = Uri.tryParse(raw);
    if (uri == null || (uri.scheme != 'https' && uri.scheme != 'http')) {
      if (mounted) setState(() => _message = '商家購買連結格式不正確。');
      return;
    }
    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched && mounted) setState(() => _message = '無法開啟商家購買連結。');
  }

  String _strategyName(ShoppingStrategy strategy) => switch (strategy) {
    ShoppingStrategy.lowestDeliveredTotal => '含運最低總價',
    ShoppingStrategy.lowestOneStopTotal => '一站購足最低價',
    ShoppingStrategy.fewestMerchants => '最少商家',
  };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('採購清單與比價')),
      body: SafeArea(
        child: FutureBuilder<List<HouseholdShoppingItem>>(
          future: _itemsFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
            if (snapshot.hasError) return Center(child: Text('讀取購物清單失敗：${snapshot.error}'));
            final items = snapshot.data ?? const [];
            return ListView(
              key: const ValueKey('shopping-list'),
              padding: const EdgeInsets.all(16),
              children: [
                Row(children: [
                  Expanded(child: TextField(key: const ValueKey('shopping-add-input'), controller: _name, decoration: const InputDecoration(labelText: '新增採購品項', border: OutlineInputBorder()), onSubmitted: (_) => _add())),
                  const SizedBox(width: 8),
                  IconButton.filled(key: const ValueKey('shopping-add-button'), onPressed: _add, tooltip: '加入清單', icon: const Icon(Icons.add_shopping_cart)),
                ]),
                const SizedBox(height: 16),
                const Text('採購清單', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600)),
                if (items.isEmpty) const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Text('目前沒有採購項目。')),
                ...items.map((item) => CheckboxListTile(
                  key: ValueKey('shopping-${item.id}'),
                  value: item.done,
                  onChanged: (value) => _setDone(item, value ?? false),
                  title: Text(item.name),
                  subtitle: Text('${item.quantity}${item.unit}${item.note == null ? '' : ' · ${item.note}'}'),
                )),
                const SizedBox(height: 12),
                FilledButton.icon(
                  key: const ValueKey('shopping-compare-button'),
                  onPressed: _busy ? null : () => _compare(items),
                  icon: const Icon(Icons.travel_explore),
                  label: const Text('搜尋商家並比較'),
                ),
                if (_busy) ...[const SizedBox(height: 12), const LinearProgressIndicator()],
                if (_message != null) ...[const SizedBox(height: 12), Card(child: Padding(padding: const EdgeInsets.all(12), child: Text(_message!)))],
                if (_comparison != null) ...[
                  const SizedBox(height: 20),
                  for (final strategy in ShoppingStrategy.values) _PlanCard(title: _strategyName(strategy), plan: _comparison!.plans[strategy], onOpenUrl: _openUrl),
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
          ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: const TextStyle(fontWeight: FontWeight.w600)), const SizedBox(height: 6), const Text('沒有符合此策略的完整購物方案。')])
          : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text('總價 NT\$${value.totalTwd}（商品 ${value.itemSubtotalTwd} + 運費 ${value.shippingTwd}） · ${value.merchantCount} 家'),
              const Divider(),
              for (final line in value.lines) ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('${line.request.label} → ${line.offer.merchantName}'),
                subtitle: Text('${line.offer.title}\n小計 NT\$${line.subtotalTwd}'),
                isThreeLine: true,
                trailing: IconButton(key: ValueKey('purchase-${line.offer.itemKey}-${line.offer.merchantId}'), tooltip: '開啟購買連結', onPressed: () => onOpenUrl(line.offer.url), icon: const Icon(Icons.open_in_new)),
              ),
            ]),
      ),
    );
  }
}
