import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/app_theme.dart';
import '../../../core/session.dart';
import '../../../data/db/app_db.dart';
import '../../../models/catalog.dart';
import '../shared/anim.dart';
import '../shared/app_background.dart';
import '../shared/product_image.dart';
import '../warehouse/catalogs_screen.dart';
import '../warehouse/product_detail_screen.dart';
import '../receipts/receipts_screen.dart';
import '../warehouse/warehouse_screen.dart';

/// Главный экран-витрина в стиле сайта: шапка магазина, поиск,
/// каталоги-пилюли, хиты продаж и сводка сегодняшнего дня.
class HomeScreen extends StatefulWidget {
  final void Function(int tab) onOpenTab;
  const HomeScreen({super.key, required this.onOpenTab});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _search = TextEditingController();
  List<({String id, String name})> _cats = [];
  List<Product> _hits = [];
  double _sales = 0;
  int _ordersCount = 0;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final db = context.read<AppDb>();
    final session = context.read<Session>();
    final now = DateTime.now();
    final cats = await db.categories();
    final hits = await db.popularProducts(limit: 8);
    final sales = await db.daySales(now, session.userId ?? '');
    final orders = await db.ordersOfDay(now, session.userId ?? '');
    if (!mounted) return;
    setState(() {
      _cats = cats
          .map((r) => (id: r['id'] as String, name: r['name'] as String))
          .toList();
      _hits = hits;
      _sales = sales;
      _ordersCount = orders.length;
      _loaded = true;
    });
  }

  void _openWarehouse({String? categoryId, String? query, String? title}) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: title == null ? null : AppBar(title: Text(title)),
          body: WarehouseScreen(
            initialCategoryId: categoryId,
            initialQuery: query,
          ),
        ),
      ),
    );
  }

  void _openProduct(Product p) => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => ProductDetailScreen(product: p)),
      );

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return AppBackground(
      child: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Шапка как на сайте: плашка, заголовок, подзаголовок, CTA.
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: isDark
                      ? [
                          AppTheme.brand.withValues(alpha: 0.35),
                          AppTheme.nightCard,
                        ]
                      : [
                          AppTheme.cream,
                          AppTheme.sand,
                        ],
                ),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isDark
                      ? AppTheme.nightBorder
                      : AppTheme.cardBorderLight,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: isDark
                          ? AppTheme.brand.withValues(alpha: 0.25)
                          : AppTheme.brandSoft,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      'МАГАЗИН РАДИОДЕТАЛЕЙ',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.2,
                        color: isDark
                            ? const Color(0xFFFFD9DE)
                            : AppTheme.brandDeep,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Телемастер',
                    style:
                        Theme.of(context).textTheme.headlineMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Отправляем заказы каждый день · Самовывоз со склада',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: () => widget.onOpenTab(2),
                          icon:
                              const Icon(Icons.grid_view_rounded),
                          label: const Text('Каталог'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) =>
                                    const ReceiptsScreen()),
                          ),
                          icon: const Icon(
                              Icons.receipt_long_outlined),
                          label: const Text('Накладная'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            // Поиск по складу.
            TextField(
              controller: _search,
              decoration: const InputDecoration(
                hintText: 'Поиск по артикулу или названию...',
                prefixIcon: Icon(Icons.search),
              ),
              textInputAction: TextInputAction.search,
              onSubmitted: (q) {
                if (q.trim().isEmpty) {
                  widget.onOpenTab(2);
                } else {
                  _openWarehouse(query: q.trim(), title: 'Поиск: $q');
                }
              },
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Каталоги',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700)),
                TextButton(
                  onPressed: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) =>
                              const CatalogsScreen()),
                    );
                    _load();
                  },
                  child: const Text('Все'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (!_loaded)
              const Center(child: CircularProgressIndicator())
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final c in _cats)
                    FilterChip(
                      label: Text(c.name),
                      selected: false,
                      selectedColor: AppTheme.brand,
                      backgroundColor:
                          isDark ? AppTheme.nightCard : AppTheme.cream,
                      side: BorderSide(
                          color: isDark
                              ? AppTheme.nightBorder
                              : AppTheme.cardBorderLight),
                      labelStyle: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white70 : AppTheme.ink,
                      ),
                      onSelected: (_) => _openWarehouse(
                          categoryId: c.id, title: c.name),
                    ),
                ],
              ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Хиты продаж',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700)),
                TextButton(
                  onPressed: () => widget.onOpenTab(2),
                  child: const Text('Все товары'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (!_loaded)
              const Center(child: CircularProgressIndicator())
            else if (_hits.isEmpty)
              const Card(
                  child: ListTile(
                      title: Text(
                          'Хитов пока нет — оформите первую продажу'))),
            if (_hits.isNotEmpty)
              SizedBox(
                height: 210,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: _hits.length,
                  separatorBuilder: (_, __) =>
                      const SizedBox(width: 10),
                  itemBuilder: (_, i) =>
                      _HitCard(_hits[i], onTap: () => _openProduct(_hits[i])),
                ),
              ),
            const SizedBox(height: 16),
            // Сводка дня → вкладка «День».
            Card(
              margin: EdgeInsets.zero,
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () => widget.onOpenTab(1),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: AppTheme.brand
                              .withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.today_outlined,
                            color: AppTheme.brand),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment:
                              CrossAxisAlignment.start,
                          children: [
                            Text('Сегодня',
                                style: Theme.of(context)
                                    .textTheme
                                    .titleMedium
                                    ?.copyWith(
                                        fontWeight: FontWeight.w700)),
                            const SizedBox(height: 2),
                            if (!_loaded)
                              const Text('Загрузка...')
                            else
                              CountUpText(
                                value: _sales,
                                format: (v) =>
                                    '${v.toDouble().toStringAsFixed(0)} ₽ · $_ordersCount зак.',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodyMedium,
                              ),
                          ],
                        ),
                      ),
                      const Icon(Icons.chevron_right),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Компактная карточка хита для горизонтальной ленты.
class _HitCard extends StatelessWidget {
  final Product p;
  final VoidCallback onTap;
  const _HitCard(this.p, {required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return SizedBox(
      width: 150,
      child: Card(
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                height: 96,
                color: isDark
                    ? Colors.white.withValues(alpha: 0.06)
                    : AppTheme.sand,
                alignment: Alignment.center,
                child:
                    ProductImage(product: p, size: 84, radius: 10),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(p.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                            height: 1.2)),
                    const SizedBox(height: 4),
                    Text(
                      p.price > 0
                          ? '${p.price.toStringAsFixed(0)} ₽'
                          : 'по запросу',
                      style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.brand),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
