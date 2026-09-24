import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../data/db/app_db.dart';
import '../../../models/catalog.dart';
import '../orders/order_edit_screen.dart';

/// Карточка клиента: контакты, долг, прайс-лист, новый заказ/визит.
class ClientCardScreen extends StatefulWidget {
  final Client client;
  const ClientCardScreen({super.key, required this.client});
  @override
  State<ClientCardScreen> createState() => _ClientCardScreenState();
}

class _ClientCardScreenState extends State<ClientCardScreen> {
  List<Map<String, Object?>> _lists = [];
  String? _listId;

  @override
  void initState() {
    super.initState();
    _listId = widget.client.priceListId ?? 'pl-base';
    _loadLists();
  }

  Future<void> _loadLists() async {
    final lists = await context.read<AppDb>().priceLists();
    if (mounted) {
      var id = _listId;
      if (lists.every((l) => l['id'] != id)) id = 'pl-base';
      setState(() {
        _lists = lists;
        _listId = id;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final client = widget.client;
    return Scaffold(
      appBar: AppBar(title: Text(client.name)),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _row(Icons.badge_outlined, client.inn ?? 'ИНН не указан'),
                  _row(Icons.place_outlined, client.address ?? '—'),
                  _row(Icons.person_outline, client.contact ?? '—'),
                  _row(Icons.phone_outlined, client.phone ?? '—'),
                  const Divider(),
                  _row(Icons.account_balance_wallet_outlined,
                      'Долг: ${client.debt.toStringAsFixed(2)} ₽'),
                  _row(Icons.credit_score_outlined,
                      'Кредитный лимит: ${client.creditLimit.toStringAsFixed(0)} ₽'),
                  _row(Icons.percent_outlined,
                      'Скидка клиента: ${client.discountPct.toStringAsFixed(0)}%'),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Icon(Icons.discount_outlined, size: 18),
                      const SizedBox(width: 8),
                      const Text('Прайс:'),
                      const SizedBox(width: 8),
                      Expanded(
                        child: DropdownButton<String>(
                          value: _listId,
                          isExpanded: true,
                          items: [
                            for (final l in _lists)
                              DropdownMenuItem(
                                value: l['id'] as String,
                                child: Text(
                                    '${l['name']} (−${((l['discount_pct'] as num?)?.toDouble() ?? 0).toStringAsFixed(0)}%)'),
                              ),
                          ],
                          onChanged: (v) async {
                            if (v == null) return;
                            await context
                                .read<AppDb>()
                                .setClientPriceList(client.id, v);
                            setState(() => _listId = v);
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                      content:
                                          Text('Прайс клиента сохранён')));
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  icon: const Icon(Icons.add_shopping_cart),
                  label: const Text('Новый заказ'),
                  onPressed: () => Navigator.push(context, MaterialPageRoute(
                      builder: (_) => OrderEditScreen(client: client))),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.photo_camera_outlined),
                  label: const Text('Фотоотчёт'),
                  onPressed: () => _photoReport(context),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _row(IconData i, String t) =>
      Padding(padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(children: [
            Icon(i, size: 18),
            const SizedBox(width: 8),
            Expanded(child: Text(t)),
          ]));

  Future<void> _photoReport(BuildContext context) async {
    // Фотоотчёт мерчандайзинга: в нативной сборке — image_picker,
    // пути сохраняются в визит и уходят в 1С при синхронизации.
    final db = context.read<AppDb>();
    await db.database.insert('outbox', {
      'entity': 'photo_report',
      'op': 'insert',
      'payload':
          '{"client_id":"${widget.client.id}","photos":[],"created_at":"${DateTime.now().toIso8601String()}"}',
      'created_at': DateTime.now().toIso8601String(),
    });
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Фотоотчёт поставлен в очередь')));
    }
  }
}
