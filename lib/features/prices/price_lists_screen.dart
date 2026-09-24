import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/app_theme.dart';
import '../../../data/db/app_db.dart';
import '../shared/app_background.dart';

/// Прайсы и скидки: прайс-листы (розница/опт/своим) со скидкой
/// от базовых цен + скидка на каждый каталог. Итоговая цена
/// в заказах = база − скидка прайса − скидка каталога.
class PriceListsScreen extends StatefulWidget {
  const PriceListsScreen({super.key});
  @override
  State<PriceListsScreen> createState() => _PriceListsScreenState();
}

class _PriceListsScreenState extends State<PriceListsScreen> {
  List<Map<String, Object?>> _lists = [];
  List<Map<String, Object?>> _cats = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final db = context.read<AppDb>();
    final lists = await db.priceLists();
    final cats = await db.categories();
    if (mounted) {
      setState(() {
        _lists = lists;
        _cats = cats;
      });
    }
  }

  Future<double?> _pctDialog(String title, double initial) async {
    final ctrl =
        TextEditingController(text: initial.toStringAsFixed(0));
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(
              decimal: true),
          decoration:
              const InputDecoration(labelText: 'Скидка, %', suffixText: '%'),
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
    );
    if (ok != true) return null;
    final v = double.tryParse(ctrl.text.replaceAll(',', '.'));
    if (v == null || v < 0 || v > 90) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Скидка: от 0 до 90%')));
      }
      return null;
    }
    return v;
  }

  Future<void> _addListDialog() async {
    final db = context.read<AppDb>();
    final name = TextEditingController();
    final pct = TextEditingController(text: '5');
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Новый прайс'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
                controller: name,
                autofocus: true,
                decoration:
                    const InputDecoration(labelText: 'Название')),
            const SizedBox(height: 8),
            TextField(
                controller: pct,
                keyboardType: const TextInputType.numberWithOptions(
                    decimal: true),
                decoration: const InputDecoration(
                    labelText: 'Скидка от розницы, %')),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Отмена')),
          FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Создать')),
        ],
      ),
    );
    if (ok != true || name.text.trim().isEmpty) return;
    final v =
        double.tryParse(pct.text.replaceAll(',', '.')) ?? 0;
    await db.addPriceList(name.text.trim(), v.clamp(0, 90).toDouble());
    await _load();
  }

  Future<void> _renameListDialog(Map<String, Object?> l) async {
    final db = context.read<AppDb>();
    final ctrl =
        TextEditingController(text: l['name'] as String? ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Переименовать прайс'),
        content: TextField(controller: ctrl, autofocus: true),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Отмена')),
          FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Сохранить')),
        ],
      ),
    );
    if (ok != true || ctrl.text.trim().isEmpty) return;
    await db.renamePriceList(l['id'] as String, ctrl.text.trim());
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Прайсы и скидки')),
      body: AppBackground(
        child: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            padding: const EdgeInsets.all(12),
            children: [
              Text('Прайсы',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text(
                  'Скидка считается от розничных цен. Прайс выбирается в карточке клиента.',
                  style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 8),
              for (final l in _lists)
                Card(
                  child: ListTile(
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppTheme.brand.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        (l['is_default'] as int? ?? 0) == 1
                            ? Icons.star_outlined
                            : Icons.discount_outlined,
                        color: AppTheme.brand,
                      ),
                    ),
                    title: Text('${l['name']}'),
                    subtitle: Text(
                        'Скидка: ${((l['discount_pct'] as num?)?.toDouble() ?? 0).toStringAsFixed(0)}%'),
                    trailing: ((l['is_default'] as int? ?? 0) == 1)
                        ? const Chip(
                            label: Text('база'),
                            visualDensity: VisualDensity.compact)
                        : PopupMenuButton<String>(
                            onSelected: (v) async {
                              final db = context.read<AppDb>();
                              if (v == 'rename') {
                                await _renameListDialog(l);
                              } else {
                                await db.deletePriceList(
                                    l['id'] as String);
                                await _load();
                              }
                            },
                            itemBuilder: (_) => const [
                              PopupMenuItem(
                                  value: 'rename',
                                  child: Text('Переименовать')),
                              PopupMenuItem(
                                  value: 'delete',
                                  child: Text('Удалить')),
                            ],
                          ),
                    onTap: () async {
                      final db = context.read<AppDb>();
                      final v = await _pctDialog(
                          'Скидка «${l['name']}»',
                          ((l['discount_pct'] as num?)?.toDouble() ??
                              0));
                      if (v == null) return;
                      await db.setPriceListDiscount(
                          l['id'] as String, v);
                      await _load();
                    },
                  ),
                ),
              const SizedBox(height: 8),
              FilledButton.tonalIcon(
                onPressed: _addListDialog,
                icon: const Icon(Icons.add),
                label: const Text('Новый прайс'),
              ),
              const SizedBox(height: 16),
              Text('Скидки на каталоги',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text('Применяются поверх прайса, например −10% на разъёмы.',
                  style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 8),
              for (final c in _cats)
                Card(
                  child: ListTile(
                    dense: true,
                    leading: const Icon(Icons.folder_outlined,
                        color: AppTheme.brand),
                    title: Text('${c['name']}'),
                    trailing: Text(
                      '−${((c['discount_pct'] as num?)?.toDouble() ?? 0).toStringAsFixed(0)}%',
                      style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: AppTheme.brand),
                    ),
                    onTap: () async {
                      final db = context.read<AppDb>();
                      final v = await _pctDialog(
                          'Скидка «${c['name']}»',
                          ((c['discount_pct'] as num?)?.toDouble() ??
                              0));
                      if (v == null) return;
                      await db.setCategoryDiscount(
                          c['id'] as String, v);
                      await _load();
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
