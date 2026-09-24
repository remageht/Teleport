import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/session.dart';
import '../../../data/db/app_db.dart';

/// Список заказов за день текущего агента.
class OrdersScreen extends StatefulWidget {
  const OrdersScreen({super.key});
  @override
  State<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<OrdersScreen> {
  final _orders = <Map<String, Object?>>[];

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
    setState(() {
      _orders..clear()
        ..addAll(orders.map((o) => <String, Object?>{
              'order': o,
            }));
    });
  }

  @override
  Widget build(BuildContext context) {
    return _orders.isEmpty
        ? const Center(child: Text('Заказов сегодня нет'))
        : ListView.builder(
            padding: const EdgeInsets.all(8),
            itemCount: _orders.length,
            itemBuilder: (_, i) {
              final o = _orders[i]['order'] as dynamic;
              return Card(
                child: ListTile(
                  leading: Icon(
                    o.type.name == 'realization'
                        ? Icons.local_shipping
                        : Icons.receipt_long,
                  ),
                  title: Text('${o.number} · ${o.clientName}'),
                  subtitle: Text(
                      '${o.type.name == 'realization' ? 'Реализация' : 'Заказ'} · '
                      '${o.lines.length} поз. · ${o.status.name}'),
                  trailing: Text('${o.total.toStringAsFixed(2)} ₽'),
                ),
              );
            },
          );
  }
}
