import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app_services.dart';
import '../../domain/entity_ids.dart';
import '../../shopping/merchant_offer.dart';
import '../../shopping/package_quantity.dart';
import '../../shopping/product_preference.dart';
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

  List<String> _terms(String value) => value
      .split(RegExp(r'[,，]'))
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .toSet()
      .toList(growable: false);

  Future<void> _editPreference(HouseholdShoppingItem item) async {
    final required = TextEditingController(text: item.preference.requiredTerms.join('，'));
    final excluded = TextEditingController(text: item.preference.excludedTerms.join('，'));
    final preferred = TextEditingController(text: item.preference.preferredTerms.join('，'));
    final merchants = TextEditingController(text: item.preference.preferredMerchants.join('，'));
    final result = await showDialog<ProductPreference>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${item.name} 商品偏好'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: required, decoration: const InputDecoration(labelText: '必須包含（逗號分隔）', hintText: '例如：全脂，無糖')),
            TextField(controller: excluded, decoration: const InputDecoration(labelText: '不要包含', hintText: '例如：保久乳，香味')),
            TextField(controller: preferred, decoration: const InputDecoration(labelText: '優先偏好', hintText: '例如：品牌A，補充包')),
            TextField(controller: merchants, decoration: const InputDecoration(labelText: '偏好商家', hintText: '例如：momo，PChome')),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
          FilledButton(
            onPressed: () => Navigator.pop(context, ProductPreference(
              requiredTerms: _terms(required.text),
              excludedTerms: _terms(excluded.text),
              preferredTerms: _terms(preferred.text),
              preferredMerchants: _terms(merchants.text),
            )),
            child: const Text('儲存'),
          ),
        ],
      ),
    );
    required.dispose(); excluded.dispose(); preferred.dispose(); merchants.dispose();
    if (result == null) return;
    await widget.services.shopping.setPreference(item.id, result);
    if (mounted) setState(() { _comparison = null; _reload(); });
  }

  String _preferenceSummary(ProductPreference p) {
    final parts = <String>[];
    if (p.requiredTerms.isNotEmpty) parts.add('必須 ${p.requiredTerms.join('、')}');
    if (p.excludedTerms.isNotEmpty) parts.add('排除 ${p.excludedTerms.join('、')}');
    if (p.preferredTerms.isNotEmpty) parts.add('偏好 ${p.preferredTerms.join('、')}');
    if (p.preferredMerchants.isNotEmpty) parts.add('商家 ${p.preferredMerchants.join('、')}');
    return parts.isEmpty ? '未設定商品偏好' : parts.join(' · ');
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
    setState(() { _busy = true; _message = '正在搜尋公開商家頁面並依商品偏好計算購物組合…'; _comparison = null; });
    try {
      final requests = items.map((item) => ShoppingRequestItem(
        itemKey: item.id,
        label: '${item.name}${item.note == null ? '' : ' ${item.note}'}',
        quantity: item.quantity,
        preference: item.preference,
      )).toList(growable: false);
      final comparison = await widget.services.shoppingComparison.compare(requests);
      if (!mounted) return;
      final parts = <String>[];
      if (comparison.providerErrors.isNotEmpty) {
        parts.add('另有 ${comparison.providerErrors.length} 個來源暫時無法取得，已保留其他來源結果');
      }
      if (comparison.staleOfferCount > 0) {
        parts.add('已排除 ${comparison.staleOfferCount} 筆過期報價');
      }
      final suffix = parts.isEmpty ? '' : '；${parts.join('；')}';
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
                  subtitle: Text('${item.quantity}${item.unit}${item.note == null ? '' : ' · ${item.note}'}\n${_preferenceSummary(item.preference)}'),
                  secondary: IconButton(
                    key: ValueKey('shopping-preference-${item.id}'),
                    tooltip: '商品偏好',
                    onPressed: () => _editPreference(item),
                    icon: const Icon(Icons.tune),
                  ),
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

  String _number(double value) => value.toStringAsFixed(value % 1 == 0 ? 0 : 1);

  String _packagePrice(MerchantOffer offer) {
    final package = PackageQuantity.parse(offer.title);
    if (package == null || package.baseQuantity <= 0) return '規格無法正規化';
    final divisor = package.baseUnit == 'ml' || package.baseUnit == 'g' ? 100 : 1;
    final price = offer.unitPriceTwd / package.baseQuantity * divisor;
    final basis = divisor == 1 ? package.baseUnit : '100${package.baseUnit}';
    return '規格 ${_number(package.baseQuantity)} ${package.baseUnit} · 約 NT\$${price.toStringAsFixed(2)}/$basis';
  }

  String _fulfillment(ShoppingPlanLine line) {
    if (!line.usesNormalizedFulfillment) return '購買 ${line.packagesToBuy} 件（規格無法安全換算）';
    final requested = line.requestedPackageQuantity!;
    final target = requested.baseQuantity * line.request.quantity;
    final fulfilled = line.fulfilledBaseQuantity!;
    return '需求 ${_number(target)} ${requested.baseUnit} · 購買 ${line.packagesToBuy} 組 · 實得 ${_number(fulfilled)} ${requested.baseUnit}';
  }

  @override
  Widget build(BuildContext context) {
    final value = plan;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: value == null
          ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: const TextStyle(fontWeight: FontWeight.w600)), const SizedBox(height: 6), const Text('沒有符合此策略與商品偏好的完整購物方案。')])
          : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text(value.shippingKnown
                  ? '總價 NT\$${value.totalTwd}（商品 ${value.itemSubtotalTwd} + 運費 ${value.shippingTwd}） · ${value.merchantCount} 家'
                  : '商品小計 NT\$${value.itemSubtotalTwd} · 運費待商家頁確認 · ${value.merchantCount} 家'),
              if (value.preferenceScore > 0) Text('商品偏好分數 ${value.preferenceScore}'),
              if (!value.shippingKnown)
                const Padding(
                  padding: EdgeInsets.only(top: 4),
                  child: Text('此方案不能宣稱為真正的含運最低價；系統會優先選擇有明確運費資料的方案。'),
                ),
              const Divider(),
              for (final line in value.lines) ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('${line.request.label} → ${line.offer.merchantName}'),
                subtitle: Text('${line.offer.title}\n${_packagePrice(line.offer)}\n${_fulfillment(line)}\n小計 NT\$${line.subtotalTwd} · ${line.offer.shippingKnown ? '運費已取得' : '運費待確認'}\n價格時間 ${line.offer.observedAt.toLocal()}'),
                isThreeLine: true,
                trailing: IconButton(key: ValueKey('purchase-${line.offer.itemKey}-${line.offer.merchantId}'), tooltip: '開啟購買連結', onPressed: () => onOpenUrl(line.offer.url), icon: const Icon(Icons.open_in_new)),
              ),
            ]),
      ),
    );
  }
}
