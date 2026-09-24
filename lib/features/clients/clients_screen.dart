import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../data/db/app_db.dart';
import '../../../models/catalog.dart';
import 'client_card_screen.dart';

const _weekdays = ['', 'Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс'];

/// База клиентов с фильтром по маршруту и поиску.
class ClientsScreen extends StatefulWidget {
  const ClientsScreen({super.key});
  @override
  State<ClientsScreen> createState() => _ClientsScreenState();
}

class _ClientsScreenState extends State<ClientsScreen> {
  final _search = TextEditingController();
  int _dayFilter = 0; // 0 = все
  List<Client> _clients = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final all = await context.read<AppDb>().allClients();
    final q = _search.text.toLowerCase();
    _clients = all
        .where((c) =>
            (_dayFilter == 0 || c.routeDay == _dayFilter) &&
            (q.isEmpty ||
                c.name.toLowerCase().contains(q) ||
                (c.address ?? '').toLowerCase().contains(q)))
        .toList();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(
            controller: _search,
            decoration: const InputDecoration(
                hintText: 'Поиск клиента', prefixIcon: Icon(Icons.search)),
            onSubmitted: (_) => _load(),
          ),
        ),
        SizedBox(
          height: 40,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            children: [
              for (var d = 0; d <= 7; d++)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    label: Text(d == 0 ? 'Все' : _weekdays[d]),
                    selected: _dayFilter == d,
                    onSelected: (_) {
                      _dayFilter = d;
                      _load();
                    },
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: _clients.length,
            itemBuilder: (_, i) {
              final c = _clients[i];
              return ListTile(
                leading: const CircleAvatar(child: Icon(Icons.storefront)),
                title: Text(c.name),
                subtitle: Text(c.routeDay > 0
                    ? '${_weekdays[c.routeDay]} · ${c.address ?? ''}'
                    : (c.address ?? '')),
                trailing: c.debt > 0
                    ? Text('${c.debt.toStringAsFixed(0)} ₽',
                        style: const TextStyle(color: Colors.orange))
                    : null,
                onTap: () async {
                  await Navigator.push(context, MaterialPageRoute(
                      builder: (_) => ClientCardScreen(client: c)));
                  _load();
                },
              );
            },
          ),
        ),
      ],
    );
  }
}
