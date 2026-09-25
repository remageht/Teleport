import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme_provider.dart';
import '../../../core/app_theme.dart';
import '../../../data/db/app_db.dart';
import '../../../models/catalog.dart';
import '../../../services/export_service.dart';
import '../shared/barcode_scan_sheet.dart';
import '../shared/app_background.dart';
import '../shared/printer_sheet.dart';
import '../shared/product_image.dart';
import '../shared/voice_sheet.dart';
import 'catalogs_screen.dart';
import 'product_detail_screen.dart';

/// Склад магазина: поиск, сканер, сетка карточек (WB/Ozon-стиль),
/// добавление и удаление товаров. Параметры — предустановка фильтра
/// при переходе с главного экрана (каталог / поисковый запрос).
class WarehouseScreen extends StatefulWidget {
  final String? initialCategoryId;
  final String? initialQuery;
  const WarehouseScreen(
      {super.key, this.initialCategoryId, this.initialQuery});
  @override
  State<WarehouseScreen> createState() => _WarehouseScreenState();
}

class _WarehouseScreenState extends State<WarehouseScreen> {
  late final TextEditingController _search;
  List<Product> _items = [];
  List<({String id, String name})> _cats = [];
  bool _loading = true;
  SortMode _sort = SortMode.popular;
  bool _onlyAvailable = false;
  bool _onlySold = false;
  bool _onlyLow = false;
  String? _catId; // null = «Все»
  final _selected = <String>{}; // мультивыбор: долгое нажатие по карточке

  @override
  void initState() {
    super.initState();
    _search = TextEditingController(text: widget.initialQuery ?? '');
    _catId = widget.initialCategoryId;
    _loadCats();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _loadCats() async {
    final rows = await context.read<AppDb>().categories();
    if (mounted) {
      setState(() => _cats = rows
          .map((r) => (id: r['id'] as String, name: r['name'] as String))
          .toList());
    }
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final items = await context.read<AppDb>().searchProducts(
          _search.text,
          sort: _sort,
          onlyAvailable: _onlyAvailable,
          onlySold: _onlySold,
          onlyLow: _onlyLow,
          categoryId: _catId,
        );
    if (mounted) {
      setState(() {
        _items = items;
        _loading = false;
      });
    }
  }

  Future<void> _scan() async {
    final db = context.read<AppDb>();
    final code = await showBarcodeScanSheet(context);
    if (code == null || code.isEmpty) return;
    final p = await db.findByBarcode(code);
    if (!mounted) return;
    if (p == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Штрихкод/артикул «$code» не найден')));
      return;
    }
    _openProduct(p);
  }

  void _openProduct(Product p) => Navigator.push(context,
      MaterialPageRoute(builder: (_) => ProductDetailScreen(product: p)));

  /// Голосовой поиск: надиктовать название, текст подставится в поиск.
  /// Работает на телефоне (системное распознавание), на ПК недоступно.
  Future<void> _voiceSearch() async {
    final text = await showVoiceSheet(context);
    if (!mounted || text == null || text.trim().isEmpty) return;
    _search.text = text.trim();
    await _load();
  }

  /// Диалог добавления нового товара в базу.
  Future<void> _addProductDialog() async {
    final db = context.read<AppDb>();
    final name = TextEditingController();
    final desc = TextEditingController();
    final qty = TextEditingController(text: '1');
    final price = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Новый товар'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                  controller: name,
                  autofocus: true,
                  decoration: const InputDecoration(
                      labelText: 'Наименование *')),
              const SizedBox(height: 8),
              TextField(
                  controller: desc,
                  decoration: const InputDecoration(
                      labelText: 'Описание / характеристика')),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                        controller: qty,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'Кол-во')),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                        controller: price,
                        keyboardType: TextInputType.number,
                        decoration:
                            const InputDecoration(labelText: 'Цена, ₽')),
                  ),
                ],
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Отмена')),
          FilledButton.icon(
              onPressed: () => Navigator.pop(c, true),
              icon: const Icon(Icons.check),
              label: const Text('Добавить')),
        ],
      ),
    );
    if (ok != true || name.text.trim().isEmpty) return;
    await db.addProduct(
      name: name.text.trim(),
      description: desc.text.trim().isEmpty ? null : desc.text.trim(),
      qty: double.tryParse(qty.text) ?? 0,
      price: double.tryParse(price.text) ?? 0,
    );
    await _load();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Товар добавлен в базу')));
    }
  }

  /// Назначить каталог выбранным товарам (список каталогов).
  Future<void> _assignCategorySheet() async {
    final db = context.read<AppDb>();
    final ids = _selected.toList();
    final pick = await showModalBottomSheet<String>(
      context: context,
      builder: (c) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text('Каталог для ${ids.length} поз.',
                  style: Theme.of(context).textTheme.titleMedium),
            ),
            ListTile(
              leading: const Icon(Icons.inbox_outlined),
              title: const Text('Без каталога'),
              onTap: () => Navigator.pop(c, 'none'),
            ),
            for (final k in _cats)
              ListTile(
                leading: const Icon(Icons.folder_outlined,
                    color: AppTheme.brand),
                title: Text(k.name),
                onTap: () => Navigator.pop(c, k.id),
              ),
          ],
        ),
      ),
    );
    if (pick == null) return;
    await db.setProductsCategory(ids, pick == 'none' ? null : pick);
    setState(() => _selected.clear());
    await _load();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content:
              Text('Готово: каталог назначен (${ids.length})')));
    }
  }

  /// Массовая цена: точная для всех или наценка/скидка ±% от текущих.
  Future<void> _bulkPriceDialog() async {
    final db = context.read<AppDb>();
    final ids = _selected.toList();
    var mode = 0; // 0 — точная цена, 1 — наценка %
    final val = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setD) => AlertDialog(
          title: Text('Цена для ${ids.length} поз.'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SegmentedButton<int>(
                segments: const [
                  ButtonSegment(
                      value: 0, label: Text('Точная цена')),
                  ButtonSegment(
                      value: 1, label: Text('Наценка %')),
                ],
                selected: {mode},
                onSelectionChanged: (s) =>
                    setD(() => mode = s.first),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: val,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(
                    signed: true, decimal: true),
                decoration: InputDecoration(
                  labelText: mode == 0
                      ? 'Цена, ₽ (всем одинаково)'
                      : 'Процент, например 10 или −15',
                  prefixIcon: const Icon(Icons.sell_outlined),
                ),
              ),
              if (mode == 1)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text(
                    'Плюс — наценка, минус — скидка. '
                    'Товары без цены пропускаются.',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(c, false),
                child: const Text('Отмена')),
            FilledButton(
                onPressed: () => Navigator.pop(c, true),
                child: const Text('Применить')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    final v =
        double.tryParse(val.text.trim().replaceAll(',', '.'));
    if (v == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Введите число')));
      }
      return;
    }
    if (mode == 0) {
      if (v < 0) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                  content: Text('Цена не может быть отрицательной')));
        }
        return;
      }
      await db.setProductsPrice(ids, v);
    } else {
      final n = await db.applyMarkup(ids, v);
      if (mounted && n < ids.length) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(
                'Обновлено: $n из ${ids.length} (без цены пропущены)')));
      }
    }
    setState(() => _selected.clear());
    await _load();
    if (mounted && mode == 0) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              'Готово: цена ${v.toStringAsFixed(0)} ₽ (${ids.length})')));
    }
  }

  /// Выгрузить выбранные товары в Excel.
  Future<void> _exportSelected() async {
    final ids = _selected.toList();
    final msg = await ExportService()
        .exportProducts(context.read<AppDb>(), ids);
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(msg)));
    }
  }
  /// Формат суммы с пробелами тысяч: 12340 → «12 340 ₽».
  String _fmtSum(double v) {
    final n = v.round().toString();
    final b = StringBuffer();
    for (var i = 0; i < n.length; i++) {
      if (i > 0 && (n.length - i) % 3 == 0) b.write(' ');
      b.write(n[i]);
    }
    return '$b ₽';
  }

  /// Компактная кнопка панели мультивыбора.
  Widget _selBtn(IconData icon, String tooltip, VoidCallback onTap,
      {Color? color}) {    return IconButton(
      tooltip: tooltip,
      icon: Icon(icon, color: color),
      onPressed: onTap,
      style: IconButton.styleFrom(
        minimumSize: const Size(36, 36),
        padding: EdgeInsets.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
  }

  /// Сгенерировать штрих-коды тем выбранным, у кого их нет.
  Future<void> _bulkBarcodes() async {
    final db = context.read<AppDb>();
    var n = 0;
    for (final p in _items.where((e) => _selected.contains(e.id))) {
      if (p.barcode != null && p.barcode!.isNotEmpty) continue;
      await db.setBarcode(p.id, await db.generateBarcode());
      n++;
    }
    await _load();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(n > 0
              ? 'Сгенерировано кодов: $n'
              : 'У всех выбранных коды уже есть')));
    }
  }

  /// Напечатать ценники выбранных (коды догенерируются).
  Future<void> _bulkPrintTags() async {
    final db = context.read<AppDb>();
    final labels = <({String name, double price, String? barcode})>[];
    for (final p in _items.where((e) => _selected.contains(e.id))) {
      var code = p.barcode;
      if (code == null || code.isEmpty) {
        code = await db.generateBarcode();
        await db.setBarcode(p.id, code);
      }
      labels.add((name: p.name, price: p.price, barcode: code));
    }
    await _load();
    if (!mounted || labels.isEmpty) return;
    await PrinterSheet.printLabels(context, labels);
  }

  /// Удалить выбранные товары (с подтверждением).
  Future<void> _deleteSelected() async {
    final db = context.read<AppDb>();
    final n = _selected.length;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Удалить $n поз.?'),
        content: const Text(
            'Товары будут удалены из базы вместе с остатками.\nДействие необратимо.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Отмена')),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: AppTheme.brand),
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final ids = _selected.toList();
    // Заодно сносим файлы фото выбранных товаров.
    for (final p in _items.where((e) => _selected.contains(e.id))) {
      final photo = p.photoPath;
      if (photo == null || photo.isEmpty) continue;
      try {
        final f = File(photo);
        if (f.existsSync()) f.deleteSync();
      } catch (_) {}
    }
    await db.deleteProducts(ids);
    setState(() => _selected.clear());
    await _load();
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Удалено: $n')));
    }
  }

  /// Удаление каталога (долгое нажатие на чипе). Товары остаются.
  Future<void> _deleteCategory(({String id, String name}) c) async {
    final db = context.read<AppDb>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Удалить «${c.name}»?'),
        content: const Text(
            'Каталог будет удалён. Товары останутся в базе, но без каталога.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Отмена')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await db.deleteCategory(c.id);
    if (_catId == c.id) _catId = null;
    await _loadCats();
    await _load();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Каталог удалён')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // Пилюли каталога как на сайте: белые, выбранная — красная.
    TextStyle chipLabel(bool selected) => TextStyle(
          fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
          color: selected
              ? Colors.white
              : (isDark ? Colors.white70 : AppTheme.ink),
        );
    return AppBackground(
      child: Column(
        children: [
          // Панель мультивыбора: назначить каталог / удалить / закрыть.
          if (_selected.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
              child: Card(
                margin: EdgeInsets.zero,
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 13,
                          backgroundColor: AppTheme.brand,
                          child: Text('${_selected.length}',
                              style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white)),
                        ),
                        const SizedBox(width: 8),
                        // Итоговая стоимость выбранного (цена × остаток).
                        Text(
                          'Итог: ${_fmtSum(_selected.fold<double>(0, (s, id) {
                            final p = _items.where((e) => e.id == id);
                            if (p.isEmpty) return s;
                            return s +
                                p.first.price * p.first.available;
                          }))}',
                          style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              color: AppTheme.brand),
                        ),
                        const SizedBox(width: 4),
                      _selBtn(Icons.drive_file_move_outlined,
                          'Назначить каталог', _assignCategorySheet),
                      _selBtn(Icons.sell_outlined,
                          'Цена для выбранных', _bulkPriceDialog),
                      _selBtn(Icons.upload_outlined,
                          'Выгрузить в Excel', _exportSelected),
                      _selBtn(Icons.delete_outline, 'Удалить выбранные',
                          _deleteSelected,
                          color: AppTheme.brand),
                      PopupMenuButton<String>(
                        icon: const Icon(Icons.more_vert),
                        tooltip: 'Ещё',
                        onSelected: (v) {
                          if (v == 'barcodes') {
                            _bulkBarcodes();
                          } else {
                            _bulkPrintTags();
                          }
                        },
                        itemBuilder: (_) => const [
                          PopupMenuItem(
                            value: 'barcodes',
                            child:
                                Text('Сгенерировать штрих-коды'),
                          ),
                          PopupMenuItem(
                            value: 'tags',
                            child: Text('Напечатать ценники'),
                          ),
                        ],
                      ),
                      _selBtn(Icons.close, 'Снять выделение',
                          () => setState(() => _selected.clear())),
                    ],
                    ),
                  ),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _search,
                    decoration: const InputDecoration(
                      hintText: 'Поиск: TDA8138, термопаста, переходник...',
                      prefixIcon: Icon(Icons.search),
                    ),
                    onSubmitted: (_) => _load(),
                    onChanged: (v) {
                      if (v.isEmpty) {
                        _load();
                      }
                    },
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  onPressed: _scan,
                  icon: const Icon(Icons.qr_code_scanner),
                  tooltip: 'Сканировать',
                ),
                const SizedBox(width: 4),
                IconButton.filledTonal(
                  onPressed: _voiceSearch,
                  icon: const Icon(Icons.mic_outlined),
                  tooltip: 'Голосовой поиск',
                ),
                const SizedBox(width: 4),
                IconButton.filledTonal(
                  onPressed: _addProductDialog,
                  icon: const Icon(Icons.add),
                  tooltip: 'Новый товар',
                ),
              ],
            ),
          ),
          // Лента каталогов: Все / каталоги / + добавить.
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    label: const Text('Все'),
                    selected: _catId == null,
                    selectedColor: AppTheme.brand,
                    backgroundColor:
                        isDark ? AppTheme.nightCard : AppTheme.cream,
                    side: BorderSide(
                        color: isDark
                            ? AppTheme.nightBorder
                            : AppTheme.cardBorderLight),
                    labelStyle: chipLabel(_catId == null),
                    onSelected: (_) {
                      _catId = null;
                      _load();
                    },
                  ),
                ),
                for (final c in _cats)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: GestureDetector(
                      onLongPress: () => _deleteCategory(c),
                      child: FilterChip(
                        label: Text(c.name),
                        selected: _catId == c.id,
                        selectedColor: AppTheme.brand,
                        backgroundColor:
                            isDark ? AppTheme.nightCard : AppTheme.cream,
                        side: BorderSide(
                            color: isDark
                                ? AppTheme.nightBorder
                                : AppTheme.cardBorderLight),
                        labelStyle: chipLabel(_catId == c.id),
                        onSelected: (_) {
                          _catId = _catId == c.id ? null : c.id;
                          _load();
                        },
                      ),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ActionChip(
                    avatar:
                        const Icon(Icons.folder_open, size: 16),
                    label: const Text('Каталоги'),
                    onPressed: () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) =>
                                const CatalogsScreen()),
                      );
                      await _loadCats();
                      await _load();
                    },
                  ),
                ),
              ],
            ),
          ),
          // Панель сортировки и фильтров.
          SizedBox(
            height: 44,
            child: Row(
              children: [
                Expanded(
                  child: SegmentedButton<SortMode>(
                    segments: const [
                      ButtonSegment(
                          value: SortMode.popular,
                          label: Text('Популярные'),
                          icon: Icon(Icons.local_fire_department, size: 16)),
                      ButtonSegment(value: SortMode.name, label: Text('А-Я')),
                      ButtonSegment(
                          value: SortMode.price, label: Text('Дорогие')),
                      ButtonSegment(
                          value: SortMode.stock, label: Text('Остаток')),
                    ],
                    selected: {_sort},
                    onSelectionChanged: (s) {
                      _sort = s.first;
                      _load();
                    },
                  ),
                ),
                const SizedBox(width: 8),
                FilterChip(
                  avatar: const Icon(Icons.local_fire_department,
                      size: 14, color: Colors.orange),
                  label: const Text('Продавалось'),
                  selected: _onlySold,
                  onSelected: (v) {
                    _onlySold = v;
                    _load();
                  },
                ),
                const SizedBox(width: 8),
                FilterChip(
                  label: const Text('В наличии'),
                  selected: _onlyAvailable,
                  onSelected: (v) {
                    _onlyAvailable = v;
                    _load();
                  },
                ),
                const SizedBox(width: 8),
                FilterChip(
                  avatar: const Icon(Icons.warning_amber_rounded,
                      size: 14, color: Colors.red),
                  label: const Text('Мало'),
                  selected: _onlyLow,
                  onSelected: (v) {
                    _onlyLow = v;
                    _load();
                  },
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                  '${_items.length} позиций${_loading ? ' · загрузка…' : ''}',
                  style: Theme.of(context).textTheme.bodySmall),
            ),
          ),
          // Сетка карточек (WB/Ozon-стиль): плотность зависит от масштаба
          // в настройках — на планшете колонок больше, на телефоне минимум 2.
          Expanded(
            child: _loading && _items.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : Builder(builder: (context) {
                    final extent = context.watch<ThemeProvider>().gridExtent;
                    final aspect = context.read<ThemeProvider>().cardAspect;
                    return GridView.builder(
                      padding: const EdgeInsets.all(10),
                      gridDelegate:
                          SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent: extent,
                        mainAxisSpacing: 10,
                        crossAxisSpacing: 10,
                        childAspectRatio: aspect,
                      ),
                      itemCount: _items.length,
                      itemBuilder: (_, i) {
                        final p = _items[i];
                        final sel = _selected.contains(p.id);
                        return _ProductCard(
                          p,
                          selected: sel,
                          onTap: () {
                            // В режиме выбора тап переключает, иначе открывает.
                            if (_selected.isNotEmpty) {
                              setState(() {
                                if (sel) {
                                  _selected.remove(p.id);
                                } else {
                                  _selected.add(p.id);
                                }
                              });
                            } else {
                              _openProduct(p);
                            }
                          },
                          onLongPress: () =>
                              setState(() => _selected.add(p.id)),
                        );
                      },
                    );
                  }),
          ),
        ],
      ),
    );
  }
}

/// Карточка товара для сетки.
class _ProductCard extends StatelessWidget {
  final Product p;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final bool selected;
  const _ProductCard(this.p,
      {required this.onTap,
      required this.onLongPress,
      required this.selected});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final price =
        p.price > 0 ? '${p.price.toStringAsFixed(0)} ₽' : 'по запросу';
    // Бейдж остатка как на сайте: «В наличии» / «Осталось N шт» / «Нет».
    final String badge;
    final Color badgeBg;
    final Color badgeFg;
    if (p.available <= 0) {
      badge = 'Нет';
      badgeBg = AppTheme.brand;
      badgeFg = Colors.white;
    } else if (p.available <= 12) {
      badge = 'Осталось ${p.available.toStringAsFixed(0)} шт';
      badgeBg = const Color(0xFFFFE3A3);
      badgeFg = const Color(0xFF7A4A00);
    } else {
      badge = 'В наличии';
      badgeBg = isDark ? AppTheme.nightCard : AppTheme.cream;
      badgeFg =
          isDark ? const Color(0xFFF0E2C4) : const Color(0xFF5C5546);
    }
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Stack(
              children: [
                Container(
                  height: 112,
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.06)
                      : AppTheme.sand,
                  alignment: Alignment.center,
                  child: ProductImage(product: p, size: 100, radius: 12),
                ),
                Positioned(
                  top: 6,
                  left: 6,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: badgeBg,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(badge,
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: badgeFg)),
                  ),
                ),
                if (p.soldCount > 0)
                  Positioned(
                    top: 6,
                    right: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.orange.withValues(alpha: 0.92),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.local_fire_department,
                              size: 12, color: Colors.white),
                          const SizedBox(width: 2),
                          Text('${p.soldCount}',
                              style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white)),
                        ],
                      ),
                    ),
                  ),
                // Выделение в режиме мультивыбора.
                if (selected)
                  Positioned.fill(
                    child: Container(
                      color:
                          AppTheme.brand.withValues(alpha: 0.22),
                      alignment: Alignment.center,
                      child: const CircleAvatar(
                        backgroundColor: AppTheme.brand,
                        child: Icon(Icons.check,
                            color: Colors.white),
                      ),
                    ),
                  ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                      p.cell != null && p.cell!.isNotEmpty
                          ? p.cell!
                          : 'АРТ. ${p.sku}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.6,
                          color: p.cell != null &&
                                  p.cell!.isNotEmpty
                              ? AppTheme.brand
                              : (isDark
                                  ? Colors.white54
                                  : AppTheme.mutedLight))),
                  const SizedBox(height: 2),
                  Text(p.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                          height: 1.15)),
                  if (p.description != null &&
                      p.description!.isNotEmpty)
                    Text(p.description!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 11,
                            color: isDark
                                ? Colors.white54
                                : AppTheme.mutedLight)),
                  const Spacer(),
                  const SizedBox(height: 6),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: Text(price,
                            style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                color: p.price > 0
                                    ? (isDark
                                        ? Colors.white
                                        : AppTheme.ink)
                                    : scheme.outline)),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 3),
                        decoration: BoxDecoration(
                          color: p.available > 0
                              ? AppTheme.brand.withValues(
                                  alpha: isDark ? 0.25 : 0.10)
                              : scheme.errorContainer,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '${p.available.toStringAsFixed(0)} шт',
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: p.available > 0
                                  ? (isDark
                                      ? const Color(0xFFFF8A95)
                                      : AppTheme.brand)
                                  : scheme.onErrorContainer),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
