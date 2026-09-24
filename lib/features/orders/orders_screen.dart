import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/session.dart';
import '../../../data/db/app_db.dart';
import '../../../models/catalog.dart';
import '../../../models/trade.dart';

/// Список заказов за день текущего агента.
/// Тап — состав заказа и построчные возвраты.
class OrdersScreen extends StatefulWidget {
  const OrdersScreen({super.key});
  @override
  State<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<OrdersScreen> {
  List<Order> _orders = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final session = context.read<Session>();
    final db = context.read<AppDb>();
    final orders = await db.ordersOfDay(DateTime.now(), session.userId ?? '');
    if (!mounted) return;
    setState(() => _orders = orders);
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _load,
      child: _orders.isEmpty
          ? ListView(
              children: const [
                SizedBox(height: 80),
                Center(child: Text('Заказов сегодня нет')),
              ],
            )
          : ListView.builder(
              padding: const EdgeInsets.all(8),
              itemCount: _orders.length,
              itemBuilder: (_, i) {
                final o = _orders[i];
                return Card(
                  child: ListTile(
                    leading: Icon(
                      o.type == OrderType.realization
                          ? Icons.local_shipping
                          : Icons.receipt_long,
                    ),
                    title: Text('${o.number} · ${o.clientName}'),
                    subtitle: Text(
                        '${o.type == OrderType.realization ? 'Реализация' : 'Заказ'} · '
                        '${o.lines.length} поз. · ${o.status.name}'),
                    trailing:
                        Text('${o.total.toStringAsFixed(2)} ₽'),
                    onTap: () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) =>
                                OrderDetailScreen(order: o)),
                      );
                      _load();
                    },
                  ),
                );
              },
            ),
    );
  }
}

/// Состав заказа + построчные возвраты (с учётом уже возвращённого).
class OrderDetailScreen extends StatefulWidget {
  final Order order;
  const OrderDetailScreen({super.key, required this.order});

  @override
  State<OrderDetailScreen> createState() => _OrderDetailScreenState();
}

class _OrderDetailScreenState extends State<OrderDetailScreen> {
  final _names = <String, Product?>{};
  final _returned = <String, double>{};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final db = context.read<AppDb>();
    for (final l in widget.order.lines) {
      _names[l.productId] ??= await db.productById(l.productId);
      _returned[l.productId] = await db.returnedQty(
          widget.order.number, l.productId);
    }
    if (mounted) setState(() {});
  }

  double get _refunded => widget.order.lines.fold(
      0,
      (s, l) =>
          s + (_returned[l.productId] ?? 0) * l.price);

  Future<void> _returnLine(OrderLine l, double max) async {
    final db = context.read<AppDb>();
    final ctrl = TextEditingController(
        text: max.toStringAsFixed(max % 1 == 0 ? 0 : 2));
    final qty = await showDialog<double>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(_names[l.productId]?.name ?? l.productId,
            maxLines: 2),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType:
              const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
              labelText: 'Вернуть, шт (макс ${max.toStringAsFixed(0)})'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c),
              child: const Text('Отмена')),
          FilledButton(
              onPressed: () => Navigator.pop(
                  c,
                  double.tryParse(
                      ctrl.text.replaceAll(',', '.'))),
              child: const Text('Вернуть')),
        ],
      ),
    );
    if (qty == null || qty <= 0) return;
    if (qty > max) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(
                'Больше ${max.toStringAsFixed(0)} вернуть нельзя')));
      }
      return;
    }
    await db.registerReturn(
      l.productId,
      qty,
      price: l.price,
      note: 'Возврат по заказу ${widget.order.number}',
    );
    await _load();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Возврат принят, остаток пополнен')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final o = widget.order;
    return Scaffold(
      appBar: AppBar(title: Text('Заказ ${o.number}')),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(o.clientName,
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text(
                      '${o.type == OrderType.realization ? 'Реализация' : 'Заказ'} · ${o.payType.name}'),
                  const SizedBox(height: 4),
                  Text('Итого: ${o.total.toStringAsFixed(2)} ₽',
                      style: const TextStyle(
                          fontWeight: FontWeight.bold)),
                  if (_refunded > 0)
                    Text(
                        'Возвращено: ${_refunded.toStringAsFixed(2)} ₽',
                        style: const TextStyle(
                            color: Colors.purple,
                            fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          for (final l in o.lines)
            Builder(builder: (_) {
              final ret = _returned[l.productId] ?? 0;
              final max = (l.qty - ret).clamp(0, l.qty).toDouble();
              final name =
                  _names[l.productId]?.name ?? l.productId;
              return Card(
                child: ListTile(
                  dense: true,
                  title: Text(name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis),
                  subtitle: Text(
                      '${l.qty.toStringAsFixed(0)} × ${l.price.toStringAsFixed(2)} ₽'
                      '${ret > 0 ? ' · возвращено ${ret.toStringAsFixed(0)}' : ''}'),
                  trailing: max > 0
                      ? FilledButton.tonal(
                          onPressed: () =>
                              _returnLine(l, max),
                          child: const Text('Вернуть'),
                        )
                      : const Icon(Icons.check,
                          color: Colors.green),
                ),
              );
            }),
        ],
      ),
    );
  }
}
