import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/session.dart';
import '../../../data/db/app_db.dart';
import '../../../models/catalog.dart';
import '../../../models/trade.dart';
import '../shared/barcode_scan_sheet.dart';
import '../shared/anim.dart';
import '../shared/product_image.dart';

/// Оформление продажи/заказа: поиск или скан товара, позиции,
/// оплата, итог. При van-selling списывает остаток и поднимает
/// счётчик популярности товара.
class OrderEditScreen extends StatefulWidget {
  final Client? client;
  const OrderEditScreen({super.key, this.client});
  @override
  State<OrderEditScreen> createState() => _OrderEditScreenState();
}

class _OrderEditScreenState extends State<OrderEditScreen> {
  final _search = TextEditingController();
  final _lines = <OrderLine>[];
  OrderType _type = OrderType.realization;
  PayType _payType = PayType.cash;
  late final String _warehouseId;
  final _clientName = 'Покупатель (розница)';

  @override
  void initState() {
    super.initState();
    final s = context.read<Session>();
    _type = s.mode == WorkMode.vanSelling
        ? OrderType.realization
        : OrderType.preOrder;
    _warehouseId = s.warehouseId ?? 'wh-shop';
  }

  Future<List<Product>> _searchProducts(String q) =>
      context.read<AppDb>().searchProducts(q, sort: SortMode.popular);

  /// Диалог выбора товара из результатов поиска.
  Future<void> _pickAndAdd(String q) async {
    final items = await _searchProducts(q);
    if (!mounted) return;
    final picked = await showDialog<Product>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Найдено: ${items.length}'),
        content: SizedBox(
          width: 400,
          height: 380,
          child: items.isEmpty
              ? const Center(child: Text('Ничего не найдено'))
              : ListView.builder(
                  itemCount: items.length,
                  itemBuilder: (_, i) {
                    final p = items[i];
                    return ListTile(
                      dense: true,
                      leading: ProductImage(product: p, size: 44, radius: 10),
                      title: Text(p.name,
                          maxLines: 2, overflow: TextOverflow.ellipsis),
                      subtitle: Text(
                          '${p.sku} · остаток ${p.available.toStringAsFixed(0)} шт'),
                      trailing: Text(p.price > 0
                          ? '${p.price.toStringAsFixed(0)} ₽'
                          : '—'),
                      onTap: () => Navigator.pop(c, p),
                    );
                  },
                ),
        ),
      ),
    );
    if (picked != null) await _addProduct(picked);
  }

  Future<void> _addProduct(Product p) async {
    final db = context.read<AppDb>();
    // Цена с учётом прайса клиента и скидки каталога.
    final price = await db.effectivePrice(p.id,
        priceListId: widget.client?.priceListId);
    final avail = await db.availableQty(p.id, _warehouseId);
    final qty = await _askQty(p, price, avail);
    if (qty == null || qty <= 0) return;
    if (_type == OrderType.realization && qty > avail) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content:
              Text('На складе только $avail шт')));
      return;
    }
    setState(() {
      _lines.add(OrderLine(
        productId: p.id,
        sku: p.sku,
        name: p.name,
        qty: qty,
        price: price,
        discountPct: 0,
      ));
    });
  }

  Future<double?> _askQty(Product p, double price, double avail) {
    final ctrl = TextEditingController(text: '1');
    return showDialog<double>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(p.name, maxLines: 3),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Цена: ${price.toStringAsFixed(2)} ₽ / ${p.unit} · на складе: ${avail.toStringAsFixed(0)}'),
            TextField(
                controller: ctrl,
                autofocus: true,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Количество')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Отмена')),
          FilledButton(
              onPressed: () => Navigator.pop(c, double.tryParse(ctrl.text)),
              child: const Text('Добавить')),
        ],
      ),
    );
  }

  Future<void> _scan() async {
    final db = context.read<AppDb>();
    final code = await showBarcodeScanSheet(context);
    if (code == null || code.isEmpty) return;
    final p = await db.findByBarcode(code);
    if (p == null) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Не найден: $code')));
      }
      return;
    }
    await _addProduct(p);
  }

  double get _total => _lines.fold(0, (s, l) => s + l.total);

  Future<void> _save() async {
    if (_lines.isEmpty) return;
    final session = context.read<Session>();
    final db = context.read<AppDb>();
    final now = DateTime.now();
    final order = Order(
      id: 'ord-${now.microsecondsSinceEpoch}',
      number: '${now.day}${now.month}/${now.hour}${now.minute}',
      clientId: widget.client?.id ?? 'retail',
      clientName: widget.client?.name ?? _clientName,
      type: _type,
      warehouseId: _warehouseId,
      agentId: session.userId ?? '',
      payType: _payType,
      clientDiscountPct: widget.client?.discountPct ?? 0,
      createdAt: now,
      lines: _lines,
    );
    await db.saveOrder(order);
    if (_type == OrderType.realization) {
      for (final l in _lines) {
        await db.registerSale(l.productId, l.qty,
            price: l.price, note: order.number);
      }
    }
    if (!mounted) return;
    // Живой экран успеха: галочка + сумма, авто-возврат.
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SuccessScreen(
          title: _type == OrderType.realization ? 'Продажа проведена' : 'Заказ сохранён',
          subtitle: '${_total.toStringAsFixed(2)} ₽ · ${_lines.length} позиций',
        ),
      ),
    );
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
          title: Text(_type == OrderType.realization
              ? 'Продажа'
              : 'Заказ · ${widget.client?.name ?? _clientName}')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _search,
                    decoration: const InputDecoration(
                        hintText: 'Поиск: LM2596, переходник, флюс...',
                        prefixIcon: Icon(Icons.search)),
                    onSubmitted: (q) async {
                      if (q.isNotEmpty) {
                        await _pickAndAdd(q);
                        _search.clear();
                      }
                    },
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                    onPressed: _scan,
                    icon: const Icon(Icons.qr_code_scanner)),
              ],
            ),
          ),
          Expanded(
            child: _lines.isEmpty
                ? const Center(child: Text('Добавьте товары поиском или сканером'))
                : ListView.builder(
                    itemCount: _lines.length,
                    itemBuilder: (_, i) {
                      final l = _lines[i];
                      return ListTile(
                        title: Text(l.name,
                            maxLines: 2, overflow: TextOverflow.ellipsis),
                        subtitle: Text(
                            '${l.qty.toStringAsFixed(0)} × ${l.price.toStringAsFixed(2)} ₽'),
                        trailing: Text('${l.total.toStringAsFixed(2)} ₽'),
                        onLongPress: () => setState(() => _lines.removeAt(i)),
                      );
                    },
                  ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  SegmentedButton<PayType>(
                    segments: const [
                      ButtonSegment(value: PayType.cash, label: Text('Наличные')),
                      ButtonSegment(value: PayType.card, label: Text('Карта')),
                      ButtonSegment(value: PayType.transfer, label: Text('Перевод')),
                      ButtonSegment(value: PayType.deferred, label: Text('Долг')),
                    ],
                    selected: {_payType},
                    onSelectionChanged: (s) => setState(() => _payType = s.first),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Text('Итого: ${_total.toStringAsFixed(2)} ₽',
                          style: Theme.of(context).textTheme.titleLarge),
                      const Spacer(),
                      FilledButton.icon(
                        onPressed: _lines.isEmpty ? null : _save,
                        icon: const Icon(Icons.check),
                        label: const Text('Провести'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
