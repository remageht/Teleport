import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../data/db/app_db.dart';
import '../shared/app_background.dart';

/// Маржа по проданным позициям: выручка минус последняя закупка.
/// Без закупки (не было приёмок) — прибыль равна выручке и строка
/// помечена, чтобы не вводить в заблуждение.
class MarginScreen extends StatefulWidget {
  const MarginScreen({super.key});
  @override
  State<MarginScreen> createState() => _MarginScreenState();
}

class _MarginScreenState extends State<MarginScreen> {
  List<
      ({
        String sku,
        String name,
        double qty,
        double revenue,
        double buyPrice,
        double profit
      })> _rows = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final rows =
        await context.read<AppDb>().marginReport(limit: 200);
    if (mounted) {
      setState(() {
        _rows = rows;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final revenue =
        _rows.fold<double>(0, (s, r) => s + r.revenue);
    final profit =
        _rows.fold<double>(0, (s, r) => s + r.profit);
    final pct = revenue <= 0 ? 0.0 : profit / revenue * 100;
    return Scaffold(
      appBar: AppBar(title: const Text('Маржа')),
      body: AppBackground(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: _load,
                child: ListView(
                  padding: const EdgeInsets.all(12),
                  children: [
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Row(
                          mainAxisAlignment:
                              MainAxisAlignment.spaceAround,
                          children: [
                            _num(context, revenue.toStringAsFixed(0),
                                'выручка, ₽'),
                            _num(context, profit.toStringAsFixed(0),
                                'прибыль, ₽'),
                            _num(context,
                                '${pct.toStringAsFixed(1)}%',
                                'маржа'),
                          ],
                        ),
                      ),
                    ),
                    if (_rows.isEmpty)
                      const Card(
                          child: ListTile(
                              title: Text(
                                  'Продаж пока нет — нечего считать'))),
                    for (final r in _rows)
                      Card(
                        child: ListTile(
                          dense: true,
                          title: Text(r.name,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis),
                          subtitle: Text(
                              '${r.qty.toStringAsFixed(0)} шт · выручка ${r.revenue.toStringAsFixed(0)} ₽'
                              '${r.buyPrice > 0 ? ' · закупка ${r.buyPrice.toStringAsFixed(0)}' : ' · без закупки'}'),
                          trailing: Column(
                            mainAxisAlignment:
                                MainAxisAlignment.center,
                            crossAxisAlignment:
                                CrossAxisAlignment.end,
                            children: [
                              Text(
                                  '${r.profit >= 0 ? '+' : ''}${r.profit.toStringAsFixed(0)} ₽',
                                  style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: r.profit >= 0
                                          ? Colors.green
                                          : Colors.red)),
                              if (r.revenue > 0)
                                Text(
                                    '${(r.profit / r.revenue * 100).toStringAsFixed(0)}%',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _num(BuildContext c, String v, String label) => Column(
        children: [
          Text(v,
              style: Theme.of(c)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.w800)),
          Text(label, style: Theme.of(c).textTheme.bodySmall),
        ],
      );
}
