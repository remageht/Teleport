import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../data/db/app_db.dart';
import '../../../models/catalog.dart';
import '../../../models/trade.dart';
import '../../../core/session.dart';
import '../shared/anim.dart';
import '../shared/app_background.dart';
import '../warehouse/product_detail_screen.dart';

/// Главный экран дня: живые счётчики, график 7 дней, продажи по
/// каталогам, ТОП-5 «Часто берут», заказы.
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});
  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  double _sales = 0;
  List<Order> _orders = [];
  List<Product> _popular = [];
  List<Product> _low = [];
  List<({String day, double total, int count})> _week = [];
  List<({String name, int qty})> _byCat = [];
  int _positions = 0, _stockValue = 0;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final db = context.read<AppDb>();
    final session = context.read<Session>();
    final now = DateTime.now();
    final orders = await db.ordersOfDay(now, session.userId ?? '');
    final sales = await db.daySales(now, session.userId ?? '');
    final popular = await db.popularProducts(limit: 5);
    final low = await db.lowStock(limit: 8);
    final week = await db.salesByDay(days: 7);
    final byCat = await db.salesByCategory();
    final st = await db.database.rawQuery('''
      SELECT COUNT(DISTINCT product_id) AS cnt, SUM(qty) AS total
      FROM stocks WHERE qty > 0 AND warehouse_id = 'wh-shop'
    ''');
    if (!mounted) return;
    setState(() {
      _orders = orders;
      _sales = sales;
      _popular = popular;
      _low = low;
      _week = week;
      _byCat = byCat;
      _positions = orders.fold(0, (s, o) => s + o.lines.length);
      _stockValue = ((st.first['total'] as num?)?.toDouble() ?? 0).toInt();
      _loaded = true;
    });
  }

  String _dayLabel(String iso) {
    final d = DateTime.tryParse(iso);
    if (d == null) return '';
    return '${d.day}.${d.month}';
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return const Center(child: CircularProgressIndicator());
    }
    final avgTicket = _orders.isEmpty ? 0.0 : _sales / _orders.length;
    final maxWeek = _week.fold<double>(
        0, (m, d) => d.total > m ? d.total : m);
    final catColors = [
      Colors.teal, Colors.indigo, Colors.amber.shade800,
      Colors.pink, Colors.green, Colors.brown,
    ];

    return AppBackground(
      child: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(12),
          children: [
            Row(
              children: [
                _statCard(context, 'Продажи за день', _sales, Colors.green,
                    (v) => '${v.toStringAsFixed(0)} ₽'),
                const SizedBox(width: 8),
                _statCard(context, 'Средний чек', avgTicket, Colors.deepOrange,
                    (v) => '${v.toStringAsFixed(0)} ₽'),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                _statCard(context, 'Позиций продано', _positions.toDouble(),
                    Colors.purple, (v) => v.toStringAsFixed(0)),
                const SizedBox(width: 8),
                _statCard(context, 'Штук на складе', _stockValue.toDouble(),
                    Colors.teal, (v) => v.toStringAsFixed(0)),
              ],
            ),
            const SizedBox(height: 16),
            // График продаж за 7 дней.
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _sectionHead(
                        Icons.show_chart, Colors.green, 'Продажи за 7 дней'),
                    const SizedBox(height: 10),
                    if (_week.isEmpty || maxWeek == 0)
                      const Text('Пока нет данных — оформите первую продажу'),
                    SizedBox(
                      height: 110,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          for (final d in _week.reversed)
                            Expanded(
                              child: Padding(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 3),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    Text(
                                        d.total > 999
                                            ? '${(d.total / 1000).toStringAsFixed(1)}к'
                                            : d.total.toStringAsFixed(0),
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall),
                                    const SizedBox(height: 3),
                                    TweenAnimationBuilder<double>(
                                      tween: Tween(
                                          begin: 0,
                                          end: maxWeek == 0
                                              ? 0.0
                                              : d.total / maxWeek),
                                      duration:
                                          const Duration(milliseconds: 700),
                                      curve: Curves.easeOutCubic,
                                      builder: (_, f, __) => Container(
                                        height: 12 + 70 * f,
                                        decoration: BoxDecoration(
                                          gradient: const LinearGradient(
                                            begin: Alignment.topCenter,
                                            end: Alignment.bottomCenter,
                                            colors: [
                                              Color(0xFF22C55E),
                                              Color(0xFF0D9488),
                                            ],
                                          ),
                                          borderRadius:
                                              BorderRadius.circular(5),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 3),
                                    Text(_dayLabel(d.day),
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
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            // Продажи по каталогам.
            if (_byCat.isNotEmpty)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _sectionHead(Icons.pie_chart_outline, Colors.indigo,
                          'Продажи по каталогам'),
                      const SizedBox(height: 8),
                      for (var i = 0; i < _byCat.length; i++)
                        AnimBar(
                          label: _byCat[i].name,
                          value: '${_byCat[i].qty} шт',
                          fraction: _byCat[i].qty /
                              (_byCat.first.qty * 1.0),
                          color: catColors[i % catColors.length],
                        ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 8),
            // Живой график самых покупаемых.
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: Colors.orange.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const PulsingIcon(
                              icon: Icons.local_fire_department,
                              color: Colors.orange),
                        ),
                        const SizedBox(width: 8),
                        Text('Часто берут — ТОП-${_popular.length}',
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(fontWeight: FontWeight.w700)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (_popular.isEmpty)
                      const Text('Продаж пока нет — оформите первую продажу'),
                    for (final p in _popular)
                      AnimBar(
                        label: p.name,
                        value:
                            '${p.soldCount} шт · ${p.available.toStringAsFixed(0)} на складе'
                            '${p.price > 0 ? ' · ${p.price.toStringAsFixed(0)} ₽' : ''}',
                        fraction: _popular.first.soldCount == 0
                            ? 0
                            : p.soldCount / _popular.first.soldCount,
                        color: Colors.orange,
                        onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) =>
                                    ProductDetailScreen(product: p))),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            // Заканчивается: остаток <= заданного минимума.
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _sectionHead(Icons.warning_amber_rounded,
                        Colors.red, 'Заканчивается'),
                    const SizedBox(height: 8),
                    if (_low.isEmpty)
                      const Text(
                          'Всё в норме. Минимум задаётся в карточке товара (поле «Минимум, шт»)'),
                    for (final p in _low)
                      AnimBar(
                        label: p.name,
                        value:
                            'остаток ${p.available.toStringAsFixed(0)} из мин ${p.minQty.toStringAsFixed(0)}${p.cell?.isNotEmpty == true ? ' · ${p.cell}' : ''}',
                        fraction: p.minQty <= 0
                            ? 0
                            : (p.available / p.minQty)
                                .clamp(0.0, 1.0),
                        color: Colors.red,
                        onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) =>
                                    ProductDetailScreen(product: p))),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Заказы за сегодня',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700)),
                CountUpText(
                  value: _orders.length,
                  format: (v) => v.toStringAsFixed(0),
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ],
            ),
            if (_orders.isEmpty)
              const Card(child: ListTile(title: Text('Заказов сегодня нет'))),
            for (final o in _orders)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.receipt_long),
                  title: Text('${o.number} · ${o.clientName}'),
                  subtitle: Text('${o.lines.length} позиций · ${o.payType.name}'),
                  trailing: Text('${o.total.toStringAsFixed(2)} ₽'),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _statCard(BuildContext c, String label, double value, Color color,
      String Function(double) format) {
    return Expanded(
      child: Card(
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                color.withValues(alpha: 0.14),
                color.withValues(alpha: 0.03),
              ],
            ),
          ),
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                  radius: 14,
                  backgroundColor: color.withValues(alpha: 0.20),
                  child: Icon(Icons.trending_up, size: 16, color: color)),
              const SizedBox(height: 8),
              CountUpText(
                  value: value,
                  format: (v) => format(v.toDouble()),
                  style: Theme.of(c).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                        fontSize: 24,
                      )),
              Text(label, style: Theme.of(c).textTheme.bodySmall),
            ],
          ),
        ),
      ),
    );
  }

  /// Заголовок секции: иконка в тонированном квадрате + жирный текст.
  Widget _sectionHead(IconData icon, Color color, String title) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 18, color: color),
        ),
        const SizedBox(width: 8),
        Text(title,
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w700)),
      ],
    );
  }
}
