import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/app_theme.dart';
import '../../../data/db/app_db.dart';
import '../../../models/catalog.dart';
import '../shared/app_background.dart';
import '../shared/printer_sheet.dart';
import '../shared/product_image.dart';

/// Карточка товара: описание, цена, остатки по ячейкам (коробкам),
/// резервирование и инвентаризация.
class ProductDetailScreen extends StatefulWidget {
  final Product product;
  const ProductDetailScreen({super.key, required this.product});
  @override
  State<ProductDetailScreen> createState() => _ProductDetailScreenState();
}

class _ProductDetailScreenState extends State<ProductDetailScreen> {
  late Product _p;
  List<Stock> _cells = [];
  List<({String id, String name})> _cats = [];

  @override
  void initState() {
    super.initState();
    _p = widget.product;
    _load();
  }

  Future<void> _load() async {
    final db = context.read<AppDb>();
    final cells = await db.stockCells(_p.id);
    final fresh = await db.findByBarcode(_p.sku);
    final cats =
        await db.categories();
    if (mounted) {
      setState(() {
        _cells = cells;
        if (fresh != null) _p = fresh;
        _cats = cats
            .map((r) => (id: r['id'] as String, name: r['name'] as String))
            .toList();
      });
    }
  }

  /// Редактирование товара: название, описание, место, цена, каталог.
  Future<void> _edit() async {
    final db = context.read<AppDb>();
    final name = TextEditingController(text: _p.name);
    final desc = TextEditingController(text: _p.description ?? '');
    final cell = TextEditingController(
        text: _cells.isNotEmpty ? (_cells.first.cell ?? '') : '');
    final price = TextEditingController(
        text: _p.price > 0 ? _p.price.toStringAsFixed(2) : '');
    final minQty = TextEditingController(
        text: _p.minQty > 0
            ? _p.minQty.toStringAsFixed(
                _p.minQty % 1 == 0 ? 0 : 2)
            : '');
    final currentQty = _cells.fold<double>(0, (s, e) => s + e.qty);
    final qty = TextEditingController(
        text: currentQty.toStringAsFixed(currentQty % 1 == 0 ? 0 : 2));
    var catId = _p.categoryId;

    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setD) => AlertDialog(
          title: const Text('Редактировать товар'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                    controller: name,
                    autofocus: true,
                    decoration: const InputDecoration(labelText: 'Наименование')),
                const SizedBox(height: 8),
                TextField(
                    controller: desc,
                    maxLines: 2,
                    decoration: const InputDecoration(labelText: 'Описание')),
                const SizedBox(height: 8),
                TextField(
                    controller: cell,
                    decoration: const InputDecoration(
                        labelText: 'Место (Коробка 3 · 2-5)')),
                const SizedBox(height: 8),
                TextField(
                    controller: price,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Цена, ₽')),
                const SizedBox(height: 8),
                TextField(
                    controller: minQty,
                    keyboardType: const TextInputType.numberWithOptions(
                        decimal: true),
                    decoration: const InputDecoration(
                        labelText:
                            'Минимум, шт (пусто — без контроля)')),
                const SizedBox(height: 8),
                TextField(
                    controller: qty,
                    keyboardType: const TextInputType.numberWithOptions(
                        decimal: true),
                    decoration: const InputDecoration(labelText: 'Остаток, шт')),
                const SizedBox(height: 12),
                DropdownButtonFormField<String?>(
                  initialValue: catId,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Каталог'),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('Без каталога')),
                    ..._cats.map((k) => DropdownMenuItem(
                        value: k.id, child: Text(k.name))),
                  ],
                  onChanged: (v) => setD(() => catId = v),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(c, false),
                child: const Text('Отмена')),
            FilledButton(
                onPressed: () => Navigator.pop(c, true),
                child: const Text('Сохранить')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    await db.updateProduct(
      id: _p.id,
      name: name.text,
      description: desc.text.trim().isEmpty ? null : desc.text.trim(),
      cell: cell.text,
      price: double.tryParse(price.text.replaceAll(',', '.')),
      categoryId: catId,
    );
    await db.setMinQty(
        _p.id, double.tryParse(minQty.text.replaceAll(',', '.')) ?? 0);
    final newQty = double.tryParse(qty.text.replaceAll(',', '.'));
    if (newQty != null && newQty != currentQty) {
      await db.setStockQty(_p.id, newQty,
          cell: cell.text.trim().isNotEmpty
              ? cell.text.trim()
              : (_cells.isNotEmpty ? _cells.first.cell : null));
      await db.logMove(
          productId: _p.id,
          type: 'count',
          qty: newQty,
          note:
              'Правка карточки: было ${currentQty.toStringAsFixed(0)}, стало ${newQty.toStringAsFixed(0)}');
      await db.database.insert('outbox', {
        'entity': 'stock_count',
        'op': 'insert',
        'payload':
            '{"product_id":"${_p.id}","qty":$newQty,"sku":"${_p.sku}"}',
        'created_at': DateTime.now().toIso8601String(),
      });
    }
    await _load();
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Сохранено')));
    }
  }

  Future<void> _reserve() async {
    final db = context.read<AppDb>();
    final qty = await _askQty('Резервировать');
    if (qty == null || qty <= 0) return;
    await db.reserve(_p.id, 'wh-shop', qty);
    await _load();
  }

  Future<void> _count() async {
    final db = context.read<AppDb>();
    final qty = await _askQty('Инвентаризация: фактический остаток');
    if (qty == null) return;
    final before =
        _cells.fold<double>(0, (s, e) => s + e.qty);
    await db.setStockQty(_p.id, qty,
        cell: _cells.isNotEmpty ? _cells.first.cell : null);
    await db.logMove(
        productId: _p.id,
        type: 'count',
        qty: qty,
        note:
            'Инвентаризация: было ${before.toStringAsFixed(0)}, стало ${qty.toStringAsFixed(0)}');
    await db.database.insert('outbox', {
      'entity': 'stock_count',
      'op': 'insert',
      'payload':
          '{"product_id":"${_p.id}","qty":$qty,"sku":"${_p.sku}"}',
      'created_at': DateTime.now().toIso8601String(),
    });
    await _load();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Остаток обновлён')));
    }
  }

  /// Приёмка товара: количество + закупочная цена + место + поставщик.
  Future<void> _receive() async {
    final db = context.read<AppDb>();
    final qty = TextEditingController();
    final buy = TextEditingController();
    final cell = TextEditingController(
        text: _cells.isNotEmpty ? (_cells.first.cell ?? '') : '');
    final note = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Приёмка товара'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                  controller: qty,
                  autofocus: true,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                      labelText: 'Пришло, шт *')),
              const SizedBox(height: 8),
              TextField(
                  controller: buy,
                  keyboardType: const TextInputType.numberWithOptions(
                      decimal: true),
                  decoration: const InputDecoration(
                      labelText: 'Закупочная цена, ₽')),
              const SizedBox(height: 8),
              TextField(
                  controller: cell,
                  decoration: const InputDecoration(
                      labelText: 'Положить в (место)')),
              const SizedBox(height: 8),
              TextField(
                  controller: note,
                  decoration: const InputDecoration(
                      labelText: 'Поставщик / накладная')),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Отмена')),
          FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Принять')),
        ],
      ),
    );
    if (ok != true) return;
    final q = double.tryParse(qty.text.replaceAll(',', '.')) ?? 0;
    if (q <= 0) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Укажите количество')));
      }
      return;
    }
    await db.receiveGoods(
      productId: _p.id,
      qty: q,
      buyPrice:
          double.tryParse(buy.text.replaceAll(',', '.')) ?? 0,
      cell: cell.text,
      note: note.text.trim().isEmpty ? null : note.text.trim(),
    );
    await _load();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Принято: ${q.toStringAsFixed(0)} шт')));
    }
  }

  /// Возврат товара покупателем: плюс к остатку, минус популярность.
  Future<void> _returnProduct() async {
    final db = context.read<AppDb>();
    final qty = TextEditingController();
    final reason = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Возврат товара'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                  controller: qty,
                  autofocus: true,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                      labelText: 'Вернули, шт *')),
              const SizedBox(height: 8),
              TextField(
                  controller: reason,
                  decoration: const InputDecoration(
                      labelText: 'Причина (брак, не подошёл…)')),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Отмена')),
          FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Вернуть')),
        ],
      ),
    );
    if (ok != true) return;
    final q = double.tryParse(qty.text.replaceAll(',', '.')) ?? 0;
    if (q <= 0) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Укажите количество')));
      }
      return;
    }
    await db.registerReturn(
      _p.id,
      q,
      price: _p.price,
      note: reason.text.trim().isEmpty ? null : reason.text.trim(),
    );
    await _load();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              'Возврат принят: ${q.toStringAsFixed(0)} шт')));
    }
  }

  /// Печать ценника на BT-принтер (или в файл на ПК).
  Future<void> _printTag() async {
    final db = context.read<AppDb>();
    var code = _p.barcode;
    if (code == null || code.isEmpty) {
      code = await db.generateBarcode();
      await db.setBarcode(_p.id, code);
      await _load();
    }
    if (!mounted) return;
    await PrinterSheet.printLabels(context, [
      (name: _p.name, price: _p.price, barcode: code),
    ]);
  }

  /// Сгенерировать свой штрих-код, если его нет.
  Future<void> _makeBarcode() async {
    final db = context.read<AppDb>();
    if (_p.barcode != null && _p.barcode!.isNotEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Код уже есть: ${_p.barcode}')));
      }
      return;
    }
    final code = await db.generateBarcode();
    await db.setBarcode(_p.id, code);
    await _load();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Новый код: $code')));
    }
  }

  Future<void> _takePhoto() async {
    final db = context.read<AppDb>();
    final path = await takeProductPhoto(_p.id);
    if (path == null) return;
    await db.setPhotoPath(_p.id, path);
    await _load();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Фото сохранено')));
    }
  }

  Future<void> _delete() async {
    final db = context.read<AppDb>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Удалить товар?'),
        content: Text(
            '«${_p.name}» будет удалён из базы вместе с остатками.\nДействие необратимо.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Отмена')),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(c, true),
            icon: const Icon(Icons.delete_forever),
            label: const Text('Удалить'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    // Удаляем и файл фото, если был.
    final photo = _p.photoPath;
    if (photo != null && File(photo).existsSync()) {
      try {
        File(photo).deleteSync();
      } catch (_) {}
    }
    await db.deleteProduct(_p.id);
    if (mounted) Navigator.pop(context);
  }

  Future<double?> _askQty(String title) {
    final ctrl = TextEditingController();
    return showDialog<double>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(title),
        content: TextField(
            controller: ctrl,
            keyboardType: TextInputType.number,
            autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Отмена')),
          FilledButton(
              onPressed: () => Navigator.pop(c, double.tryParse(ctrl.text)),
              child: const Text('ОК')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = _p;
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(p.sku),
        actions: [
          IconButton(
            tooltip: 'Редактировать',
            icon: const Icon(Icons.edit_outlined),
            onPressed: _edit,
          ),
          // Сфотографировать реальный товар (телефон/планшет).
          if (!kIsWeb &&
              (defaultTargetPlatform == TargetPlatform.android ||
                  defaultTargetPlatform == TargetPlatform.iOS))
            IconButton(
              tooltip: 'Фото товара',
              icon: const Icon(Icons.photo_camera_outlined),
              onPressed: _takePhoto,
            ),
          IconButton(
            tooltip: 'Удалить из базы',
            icon: const Icon(Icons.delete_outline),
            onPressed: _delete,
          ),
        ],
      ),
      body: AppBackground(
        child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          // Большая объёмная обложка с фото товара (интернет/иконка).
          Center(child: ProductImage(product: p, size: 170, radius: 20)),
          const SizedBox(height: 12),
          Text(p.name, textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge),
          if (p.description != null && p.description!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(p.description!, style: Theme.of(context).textTheme.bodyMedium),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              _infoCard(context, 'Остаток',
                  '${p.available.toStringAsFixed(0)} шт',
                  color: p.available > 0 ? scheme.primary : scheme.error,
                  onTap: _count),
              const SizedBox(width: 8),
              _infoCard(context, 'Цена',
                  p.price > 0 ? '${p.price.toStringAsFixed(0)} ₽' : 'по запросу'),
              const SizedBox(width: 8),
              _infoCard(context, 'Покупали',
                  p.soldCount > 0 ? '${p.soldCount} шт' : '—'),
            ],
          ),
          const SizedBox(height: 16),
          Text('Место хранения', style: Theme.of(context).textTheme.titleMedium),
          for (final s in _cells)
            ListTile(
              leading: const Icon(Icons.inventory_2_outlined),
              title: Text(s.cell ?? 'Без ячейки'),
              subtitle: Text(
                  'доступно ${s.available.toStringAsFixed(0)} из ${s.qty.toStringAsFixed(0)}'),
              dense: true,
            ),
          if (_cells.isEmpty)
            const ListTile(
              leading: Icon(Icons.info_outline),
              title: Text('Остатков нет — товар распродан'),
            ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: FilledButton.tonalIcon(
                    onPressed: _reserve,
                    icon: const Icon(Icons.bookmark_add),
                    label: const Text('Резерв')),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.tonalIcon(
                    onPressed: _count,
                    icon: const Icon(Icons.fact_check),
                    label: const Text('Инвентаризация')),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                    onPressed: _receive,
                    icon: const Icon(Icons.add_shopping_cart),
                    label: const Text('Приёмка')),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.tonalIcon(
                    onPressed: _printTag,
                    icon: const Icon(Icons.print_outlined),
                    label: const Text('Ценник')),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
                onPressed: _returnProduct,
                icon: const Icon(Icons.keyboard_return_outlined),
                label: const Text('Оформить возврат'),
                style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.brand)),
          ),
          const SizedBox(height: 16),
          Text('Штрих-код',
              style: Theme.of(context).textTheme.titleMedium),
          Card(
            child: ListTile(
              leading: const Icon(Icons.qr_code_2_outlined),
              title: Text(p.barcode?.isNotEmpty == true
                  ? p.barcode!
                  : 'Нет кода'),
              subtitle: Text('Артикул: ${p.sku}'),
              trailing: p.barcode?.isNotEmpty == true
                  ? null
                  : FilledButton.tonal(
                      onPressed: _makeBarcode,
                      child: const Text('Создать'),
                    ),
              dense: true,
            ),
          ),
          const SizedBox(height: 16),
          Text('История движений',
              style: Theme.of(context).textTheme.titleMedium),
          _MovesList(productId: p.id),
        ],
        ),
      ),
    );
  }

  Widget _infoCard(BuildContext c, String label, String value,
      {Color? color, VoidCallback? onTap}) {
    return Expanded(
      child: Card(
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              children: [
                Text(value,
                    style: Theme.of(c)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold, color: color)),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(label, style: Theme.of(c).textTheme.bodySmall),
                    if (onTap != null) ...[
                      const SizedBox(width: 4),
                      Icon(Icons.edit,
                          size: 11,
                          color: Theme.of(c)
                              .colorScheme
                              .onSurfaceVariant
                              .withValues(alpha: 0.6)),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Мини-график цен продажи в карточке товара (последние продажи).
class _SalePriceChart extends StatelessWidget {
  final List<Map<String, Object?>> moves;
  const _SalePriceChart({required this.moves});

  @override
  Widget build(BuildContext context) {
    final sales = moves
        .where((m) =>
            m['type'] == 'sale' &&
            ((m['price'] as num?)?.toDouble() ?? 0) > 0)
        .toList()
        .reversed
        .toList();
    if (sales.length < 2) return const SizedBox.shrink();
    final pts = sales
        .take(12)
        .map((m) => (
              price: (m['price'] as num).toDouble(),
              label: _shortDate(m['created_at'] as String?),
            ))
        .toList();
    final max =
        pts.map((e) => e.price).reduce((a, b) => a > b ? a : b);
    if (max <= 0) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Цены продажи',
              style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 6),
          SizedBox(
            height: 90,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (final p in pts)
                  Expanded(
                    child: Padding(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 2),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Text(p.price.toStringAsFixed(0),
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(fontSize: 9)),
                          const SizedBox(height: 2),
                          Container(
                            height:
                                8 + 52 * (p.price / max),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  Colors.teal,
                                  Colors.teal.withValues(
                                      alpha: 0.45),
                                ],
                              ),
                              borderRadius:
                                  BorderRadius.circular(4),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(p.label,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(fontSize: 9)),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _shortDate(String? iso) {
    final d = DateTime.tryParse(iso ?? '');
    if (d == null) return '';
    return '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}';
  }
}

/// История движений товара: приёмки, продажи, инвентаризации.
class _MovesList extends StatelessWidget {
  final String productId;
  const _MovesList({required this.productId});

  @override
  Widget build(BuildContext context) {
    final db = context.read<AppDb>();
    return FutureBuilder<List<Map<String, Object?>>>(
      future: db.movesOf(productId),
      builder: (_, snap) {
        if (!snap.hasData) {
          return const Center(
              child: Padding(
                  padding: EdgeInsets.all(8),
                  child: CircularProgressIndicator()));
        }
        final moves = snap.data!;
        if (moves.isEmpty) {
          return const Card(
              child: ListTile(
                  dense: true,
                  title: Text('Движений пока нет — примите товар')));
        }
        // Сводка закупочных цен по приёмкам.
        final buys = moves
            .where((m) =>
                m['type'] == 'receipt' &&
                ((m['price'] as num?)?.toDouble() ?? 0) > 0)
            .map((m) => (m['price'] as num).toDouble())
            .toList();
        return Card(
          child: Column(
            children: [
              if (buys.isNotEmpty)
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.payments_outlined,
                      color: Colors.green),
                  title: Text(
                    'Закупка: посл. ${buys.first.toStringAsFixed(0)} ₽'
                    ' · мин ${buys.reduce((a, b) => a < b ? a : b).toStringAsFixed(0)}'
                    ' · макс ${buys.reduce((a, b) => a > b ? a : b).toStringAsFixed(0)}',
                    style: const TextStyle(
                        fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text('поставок: ${buys.length}'),
                ),
              _SalePriceChart(moves: moves),
              for (final m in moves)
                ListTile(
                  dense: true,
                  leading: Icon(
                    switch (m['type']) {
                      'receipt' => Icons.add_box_outlined,
                      'sale' => Icons.point_of_sale_outlined,
                      'return' => Icons.keyboard_return_outlined,
                      _ => Icons.fact_check_outlined,
                    },
                    color: switch (m['type']) {
                      'receipt' => Colors.green,
                      'sale' => Colors.orange,
                      'return' => Colors.purple,
                      _ => Colors.blue,
                    },
                  ),
                  title: Text(
                      '${_typeName(m['type'] as String?)} · ${(m['qty'] as num?)?.toStringAsFixed(0)} шт'),
                  subtitle: Text([
                    if (((m['price'] as num?)?.toDouble() ?? 0) > 0)
                      '${(m['price'] as num?)?.toDouble().toStringAsFixed(0)} ₽',
                    if ((m['note'] as String?)?.isNotEmpty == true)
                      m['note'] as String,
                    _date(m['created_at'] as String?),
                  ].join(' · ')),
                ),
            ],
          ),
        );
      },
    );
  }

  String _typeName(String? t) => switch (t) {
        'receipt' => 'Приёмка',
        'sale' => 'Продажа',
        'return' => 'Возврат',
        _ => 'Инвентаризация',
      };

  String _date(String? iso) {
    final d = DateTime.tryParse(iso ?? '');
    if (d == null) return '';
    return '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }
}
