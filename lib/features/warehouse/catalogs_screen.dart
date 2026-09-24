import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/app_theme.dart';
import '../../../data/db/app_db.dart';
import '../shared/app_background.dart';
import 'warehouse_screen.dart';

/// Каталоги отдельным списком: счётчики позиций, создание,
/// переименование, удаление, переход к товарам каталога.
class CatalogsScreen extends StatefulWidget {
  const CatalogsScreen({super.key});
  @override
  State<CatalogsScreen> createState() => _CatalogsScreenState();
}

class _CatalogsScreenState extends State<CatalogsScreen> {
  List<({String id, String name, int count})> _cats = [];
  int _uncategorized = 0;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final db = context.read<AppDb>();
    final cats = await db.categoriesWithCounts();
    final uncat = await db.uncategorizedCount();
    if (mounted) {
      setState(() {
        _cats = cats;
        _uncategorized = uncat;
        _loading = false;
      });
    }
  }

  Future<void> _openCategory(String? id, String title) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(title: Text(title)),
          body: WarehouseScreen(initialCategoryId: id),
        ),
      ),
    );
    await _load();
  }

  Future<void> _addDialog() async {
    final db = context.read<AppDb>();
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Новый каталог'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(
              labelText: 'Название, например «Транзисторы»'),
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
    if (ok != true || ctrl.text.trim().isEmpty) return;
    await db.addCategory(ctrl.text.trim());
    await _load();
  }

  Future<void> _renameDialog(
      ({String id, String name, int count}) c) async {
    final db = context.read<AppDb>();
    final ctrl = TextEditingController(text: c.name);
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Переименовать каталог'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration:
              const InputDecoration(labelText: 'Новое название'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(d, false),
              child: const Text('Отмена')),
          FilledButton(
              onPressed: () => Navigator.pop(d, true),
              child: const Text('Сохранить')),
        ],
      ),
    );
    if (ok != true || ctrl.text.trim().isEmpty) return;
    await db.renameCategory(c.id, ctrl.text.trim());
    await _load();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Каталог переименован')));
    }
  }

  Future<void> _deleteDialog(
      ({String id, String name, int count}) c) async {
    final db = context.read<AppDb>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text('Удалить «${c.name}»?'),
        content: const Text(
            'Каталог будет удалён. Товары останутся в базе, но без каталога.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(d, false),
              child: const Text('Отмена')),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: AppTheme.brand),
            onPressed: () => Navigator.pop(d, true),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await db.deleteCategory(c.id);
    await _load();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Каталог удалён')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Каталоги')),
      body: AppBackground(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: _load,
                child: ListView(
                  padding: const EdgeInsets.all(12),
                  children: [
                    FilledButton.tonalIcon(
                      onPressed: _addDialog,
                      icon: const Icon(Icons.create_new_folder_outlined),
                      label: const Text('Новый каталог'),
                    ),
                    const SizedBox(height: 8),
                    Card(
                      child: ListTile(
                        leading: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Theme.of(context)
                                .colorScheme
                                .surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.inbox_outlined),
                        ),
                        title: const Text('Без каталога'),
                        subtitle: Text('$_uncategorized поз.'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () =>
                            _openCategory('none', 'Без каталога'),
                      ),
                    ),
                    for (final c in _cats)
                      Card(
                        child: ListTile(
                          leading: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: AppTheme.brand
                                  .withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(Icons.folder_outlined,
                                color: AppTheme.brand),
                          ),
                          title: Text(c.name),
                          subtitle: Text('${c.count} поз.'),
                          trailing: PopupMenuButton<String>(
                            onSelected: (v) {
                              if (v == 'rename') {
                                _renameDialog(c);
                              } else {
                                _deleteDialog(c);
                              }
                            },
                            itemBuilder: (_) => const [
                              PopupMenuItem(
                                value: 'rename',
                                child: Text('Переименовать'),
                              ),
                              PopupMenuItem(
                                value: 'delete',
                                child: Text('Удалить'),
                              ),
                            ],
                          ),
                          onTap: () => _openCategory(c.id, c.name),
                        ),
                      ),
                  ],
                ),
              ),
      ),
    );
  }
}
