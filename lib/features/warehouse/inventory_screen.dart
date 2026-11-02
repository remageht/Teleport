import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/app_theme.dart';
import '../../../data/db/app_db.dart';
import '../../../models/catalog.dart';
import '../../../services/export_service.dart';
import '../shared/anim.dart';
import '../shared/barcode_scan_sheet.dart';

typedef InventoryAuditItem = ({
  String productId,
  String warehouseId,
  double actualQty,
  double expectedQty,
  String? cell,
});

/// Экран инвентаризации и сверки остатков склада (Ревизия).
class InventoryScreen extends StatefulWidget {
  final String? initialCategoryId;
  final List<Product>? initialProducts;
  final Future<void> Function(List<InventoryAuditItem> items)? onApplyAudit;

  const InventoryScreen({
    super.key,
    this.initialCategoryId,
    this.initialProducts,
    this.onApplyAudit,
  });

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {
  final _searchCtrl = TextEditingController();
  List<Product> _allProducts = [];
  String? _catId;
  bool _loading = true;

  // Фактические остатки: productId -> actualCount
  final Map<String, double> _actualCounts = {};
  // Проверенные позиции
  final Set<String> _touched = {};

  // Фильтр: 0 = все, 1 = только расхождения, 2 = только проверенные
  int _filterTab = 0;

  @override
  void initState() {
    super.initState();
    _catId = widget.initialCategoryId;
    if (widget.initialProducts != null) {
      _allProducts = List.of(widget.initialProducts!);
      for (final p in _allProducts) {
        _actualCounts.putIfAbsent(p.id, () => p.available);
      }
      _loading = false;
    } else {
      _loadData();
    }
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    try {
      final db = context.read<AppDb>();
      final products = await db.searchProducts('', categoryId: _catId);
      if (mounted) {
        setState(() {
          _allProducts = products;
          // Инициализируем учетные значения
          for (final p in products) {
            _actualCounts.putIfAbsent(p.id, () => p.available);
          }
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<Product> get _filteredProducts {
    final q = _searchCtrl.text.trim().toLowerCase();
    return _allProducts.where((p) {
      if (q.isNotEmpty) {
        final matchName = p.name.toLowerCase().contains(q);
        final matchSku = p.sku.toLowerCase().contains(q);
        final matchBc = p.barcode?.toLowerCase().contains(q) ?? false;
        if (!matchName && !matchSku && !matchBc) return false;
      }
      if (_filterTab == 1) {
        // Только расхождения
        if (!_touched.contains(p.id)) return false;
        final actual = _actualCounts[p.id] ?? p.available;
        if ((actual - p.available).abs() < 0.001) return false;
      } else if (_filterTab == 2) {
        // Только проверенные
        if (!_touched.contains(p.id)) return false;
      }
      return true;
    }).toList();
  }

  void _increment(Product p, double delta) {
    setState(() {
      _touched.add(p.id);
      final current = _actualCounts[p.id] ?? p.available;
      final next = (current + delta).clamp(0.0, 999999.0);
      _actualCounts[p.id] = next;
    });
  }

  Future<void> _setExact(Product p) async {
    final ctrl = TextEditingController(
      text: _formatNum(_actualCounts[p.id] ?? p.available),
    );
    final val = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        title: Text('Факт: ${p.name}', maxLines: 2, overflow: TextOverflow.ellipsis),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Учетный остаток: ${_formatNum(p.available)} ${p.unit}'),
              const SizedBox(height: 12),
              TextField(
                controller: ctrl,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: 'Фактический остаток (${p.unit})',
                  border: const OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () {
              final cleaned = ctrl.text.replaceAll(' ', '').replaceAll(',', '.');
              final parsed = double.tryParse(cleaned);
              Navigator.pop(ctx, parsed);
            },
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (val != null) {
      setState(() {
        _touched.add(p.id);
        _actualCounts[p.id] = val.clamp(0.0, 999999.0);
      });
    }
  }

  void _markAsExpected(Product p) {
    setState(() {
      _touched.add(p.id);
      _actualCounts[p.id] = p.available;
    });
  }

  Future<void> _scanBarcode() async {
    final code = await showBarcodeScanSheet(context);
    if (code == null || code.isEmpty) return;

    final match = _allProducts.where((p) => p.barcode == code);
    if (match.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Товар со штрих-кодом $code не найден')),
        );
      }
      return;
    }

    final p = match.first;
    setState(() {
      _touched.add(p.id);
      final current = _actualCounts[p.id] ?? p.available;
      _actualCounts[p.id] = current + 1.0;
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 1),
          content: Text('${p.name}: факт ${_formatNum(_actualCounts[p.id]!)}'),
        ),
      );
    }
  }

  String _formatNum(double num) {
    return num == num.roundToDouble()
        ? num.toStringAsFixed(0)
        : num.toStringAsFixed(2);
  }

  // Сводка по проверенным позициям
  ({int checked, int surplusCount, int shortageCount, double surplusSum, double shortageSum}) get _summary {
    var surplusCount = 0;
    var shortageCount = 0;
    var surplusSum = 0.0;
    var shortageSum = 0.0;

    for (final id in _touched) {
      final pList = _allProducts.where((e) => e.id == id);
      if (pList.isEmpty) continue;
      final p = pList.first;
      final actual = _actualCounts[id] ?? p.available;
      final diff = actual - p.available;
      if (diff > 0.001) {
        surplusCount++;
        surplusSum += diff * p.price;
      } else if (diff < -0.001) {
        shortageCount++;
        shortageSum += diff.abs() * p.price;
      }
    }

    return (
      checked: _touched.length,
      surplusCount: surplusCount,
      shortageCount: shortageCount,
      surplusSum: surplusSum,
      shortageSum: shortageSum,
    );
  }

  Future<void> _applyAudit() async {
    final s = _summary;
    final diffItems = <({String productId, String warehouseId, double actualQty, double expectedQty, String? cell})>[];

    for (final id in _touched) {
      final p = _allProducts.firstWhere((e) => e.id == id);
      final actual = _actualCounts[id] ?? p.available;
      diffItems.add((
        productId: p.id,
        warehouseId: 'wh-shop',
        actualQty: actual,
        expectedQty: p.available,
        cell: p.cell,
      ));
    }

    if (diffItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Нет проверенных позиций для проведения ревизии')),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        title: const Text('Применить результаты ревизии?'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Проверено позиций: ${s.checked} из ${_allProducts.length}'),
              const SizedBox(height: 8),
              if (s.surplusCount > 0)
                Text(
                  'Излишки: ${s.surplusCount} поз. (+${s.surplusSum.toStringAsFixed(2)} ₽)',
                  style: const TextStyle(color: Colors.teal, fontWeight: FontWeight.bold),
                ),
              if (s.shortageCount > 0)
                Text(
                  'Недостачи: ${s.shortageCount} поз. (-${s.shortageSum.toStringAsFixed(2)} ₽)',
                  style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
                ),
              if (s.surplusCount == 0 && s.shortageCount == 0)
                const Text('Все проверенные позиции сходятся с учётом!',
                    style: TextStyle(color: Colors.green)),
              const SizedBox(height: 12),
              const Text(
                'Остатки на складе будут скорректированы, а расхождения зафиксированы в истории движений.',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppTheme.brand),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Применить'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    if (!mounted) return;

    try {
      if (widget.onApplyAudit != null) {
        await widget.onApplyAudit!(diffItems);
      } else {
        final db = context.read<AppDb>();
        await db.applyInventoryAudit(diffItems);
      }
      if (!mounted) return;

      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => SuccessScreen(
            title: 'Ревизия проведена',
            subtitle: 'Сверено ${s.checked} поз. · Излишек: ${s.surplusCount} · Недостача: ${s.shortageCount}',
          ),
        ),
      );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка проведения ревизии: $e')),
        );
      }
    }
  }

  Future<void> _exportDiscrepancies() async {
    final s = _summary;
    final lines = <String>[];
    lines.add('Акт инвентаризации / ревизии склада');
    lines.add('Дата: ${DateTime.now().toString().substring(0, 19)}');
    lines.add('Проверено позиций: ${s.checked} из ${_allProducts.length}');
    lines.add('Излишки: +${s.surplusSum.toStringAsFixed(2)} ₽');
    lines.add('Недостачи: -${s.shortageSum.toStringAsFixed(2)} ₽');
    lines.add('----------------------------------------------------');
    lines.add('Артикул | Наименование | Учет | Факт | Разница | Сумма');

    for (final id in _touched) {
      final p = _allProducts.firstWhere((e) => e.id == id);
      final actual = _actualCounts[id] ?? p.available;
      final diff = actual - p.available;
      if (diff.abs() > 0.001) {
        lines.add(
          '${p.sku} | ${p.name} | ${_formatNum(p.available)} | ${_formatNum(actual)} | ${_formatNum(diff)} | ${(diff * p.price).toStringAsFixed(2)} ₽',
        );
      }
    }

    try {
      final text = lines.join('\n');
      final exportService = ExportService();
      final path = await exportService.saveTextDocument(
        'reviziya_${DateTime.now().millisecondsSinceEpoch}.txt',
        text,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Акт сохранён: $path')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка экспорта: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = _summary;
    final filtered = _filteredProducts;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Ревизия склада'),
        actions: [
          IconButton(
            icon: const Icon(Icons.qr_code_scanner),
            tooltip: 'Быстрый скан',
            onPressed: _scanBarcode,
          ),
          IconButton(
            icon: const Icon(Icons.file_download_outlined),
            tooltip: 'Экспорт расхождений',
            onPressed: _exportDiscrepancies,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Поиск и фильтры
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
                  child: TextField(
                    controller: _searchCtrl,
                    decoration: InputDecoration(
                      hintText: 'Поиск: артикул, название, штрих-код...',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _searchCtrl.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 20),
                              onPressed: () {
                                _searchCtrl.clear();
                                setState(() {});
                              },
                            )
                          : null,
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),

                // Фильтр табов
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final isCompact = constraints.maxWidth < 360;
                      return SegmentedButton<int>(
                        segments: [
                          ButtonSegment(
                            value: 0,
                            label: Text(isCompact ? 'Все' : 'Все (${_allProducts.length})'),
                          ),
                          ButtonSegment(
                            value: 1,
                            label: Text(isCompact ? 'Разница' : 'Расхождения (${s.surplusCount + s.shortageCount})'),
                          ),
                          ButtonSegment(
                            value: 2,
                            label: Text(isCompact ? 'Сверено' : 'Сверено (${s.checked})'),
                          ),
                        ],
                        selected: {_filterTab},
                        onSelectionChanged: (set) => setState(() => _filterTab = set.first),
                      );
                    },
                  ),
                ),

                // Список товаров для сверки
                Expanded(
                  child: filtered.isEmpty
                      ? const Center(child: Text('Нет подходящих товаров'))
                      : ListView.separated(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          itemCount: filtered.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (ctx, i) {
                            final p = filtered[i];
                            final isTouched = _touched.contains(p.id);
                            final actual = _actualCounts[p.id] ?? p.available;
                            final diff = actual - p.available;

                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  // Индикатор статуса
                                  Container(
                                    width: 8,
                                    height: 48,
                                    decoration: BoxDecoration(
                                      color: !isTouched
                                          ? Colors.grey.shade400
                                          : diff.abs() < 0.001
                                              ? Colors.green
                                              : diff > 0
                                                  ? Colors.teal
                                                  : Colors.red,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                  ),
                                  const SizedBox(width: 10),

                                  // Инфо товара
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          p.name,
                                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        const SizedBox(height: 2),
                                        Wrap(
                                          spacing: 6,
                                          runSpacing: 2,
                                          children: [
                                            Text(
                                              p.sku,
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: themeOf(context).colorScheme.outline,
                                              ),
                                            ),
                                            if (p.cell != null && p.cell!.isNotEmpty)
                                              Text(
                                                'Ячейка: ${p.cell}',
                                                style: const TextStyle(fontSize: 12, color: AppTheme.brand),
                                              ),
                                            Text(
                                              'Учёт: ${_formatNum(p.available)} ${p.unit}',
                                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                                            ),
                                          ],
                                        ),
                                        if (isTouched && diff.abs() > 0.001)
                                          Padding(
                                            padding: const EdgeInsets.only(top: 2),
                                            child: Text(
                                              diff > 0
                                                  ? 'Излишек: +${_formatNum(diff)} ${p.unit}'
                                                  : 'Недостача: ${_formatNum(diff)} ${p.unit}',
                                              style: TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.bold,
                                                color: diff > 0 ? Colors.teal : Colors.red,
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),

                                  // Управление фактическим количеством
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        icon: const Icon(Icons.remove_circle_outline, size: 22),
                                        visualDensity: VisualDensity.compact,
                                        onPressed: () => _increment(p, -1),
                                      ),
                                      InkWell(
                                        onTap: () => _setExact(p),
                                        borderRadius: BorderRadius.circular(6),
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                          decoration: BoxDecoration(
                                            border: Border.all(
                                              color: isTouched ? AppTheme.brand : Colors.grey.shade400,
                                              width: 1.5,
                                            ),
                                            borderRadius: BorderRadius.circular(6),
                                          ),
                                          child: Text(
                                            _formatNum(actual),
                                            style: const TextStyle(
                                              fontSize: 15,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.add_circle_outline, size: 22),
                                        visualDensity: VisualDensity.compact,
                                        onPressed: () => _increment(p, 1),
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.check, size: 18),
                                        tooltip: 'Совпадает с учётом',
                                        visualDensity: VisualDensity.compact,
                                        color: isTouched && diff.abs() < 0.001 ? Colors.green : Colors.grey,
                                        onPressed: () => _markAsExpected(p),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                ),

                // Нижняя панель сводки и кнопка применения
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: isDark ? AppTheme.nightCard : Colors.white,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.08),
                        offset: const Offset(0, -2),
                        blurRadius: 6,
                      ),
                    ],
                  ),
                  child: SafeArea(
                    top: false,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Wrap(
                          alignment: WrapAlignment.spaceBetween,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: 12,
                          runSpacing: 4,
                          children: [
                            Text(
                              'Сверено: ${s.checked} из ${_allProducts.length}',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                            ),
                            if (s.surplusCount > 0)
                              Text(
                                '+${s.surplusSum.toStringAsFixed(0)} ₽',
                                style: const TextStyle(color: Colors.teal, fontWeight: FontWeight.bold, fontSize: 13),
                              ),
                            if (s.shortageCount > 0)
                              Text(
                                '-${s.shortageSum.toStringAsFixed(0)} ₽',
                                style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 13),
                              ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            style: FilledButton.styleFrom(
                              backgroundColor: AppTheme.brand,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                            onPressed: s.checked > 0 ? _applyAudit : null,
                            icon: const Icon(Icons.done_all),
                            label: const FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                'Применить результаты ревизии',
                                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  ThemeData themeOf(BuildContext context) => Theme.of(context);
}
