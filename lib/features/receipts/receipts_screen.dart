import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../data/db/app_db.dart';
import '../shared/app_background.dart';
import 'receipt_edit_screen.dart';

/// Журнал приходных накладных: поставщик, позиции, суммы.
/// Открытие строки — состав накладной.
class ReceiptsScreen extends StatefulWidget {
  const ReceiptsScreen({super.key});
  @override
  State<ReceiptsScreen> createState() => _ReceiptsScreenState();
}

class _ReceiptsScreenState extends State<ReceiptsScreen> {
  List<Map<String, Object?>> _docs = [];
  final _stats = <String, ({int lines, double total})>{};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final db = context.read<AppDb>();
    final docs = await db.receipts();
    final stats = <String, ({int lines, double total})>{};
    for (final d in docs) {
      final moves = await db.receiptMoves(d['id'] as String);
      var total = 0.0;
      for (final m in moves) {
        total += ((m['qty'] as num?)?.toDouble() ?? 0) *
            ((m['price'] as num?)?.toDouble() ?? 0);
      }
      stats[d['id'] as String] =
          (lines: moves.length, total: total);
    }
    if (mounted) {
      setState(() {
        _docs = docs;
        _stats
          ..clear()
          ..addAll(stats);
        _loading = false;
      });
    }
  }

  String _date(String? iso) {
    final d = DateTime.tryParse(iso ?? '');
    if (d == null) return '';
    return '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Накладные')),
      body: AppBackground(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: _load,
                child: ListView(
                  padding: const EdgeInsets.all(12),
                  children: [
                    FilledButton.icon(
                      onPressed: () async {
                        final ok = await Navigator.push<bool>(
                          context,
                          MaterialPageRoute(
                              builder: (_) =>
                                  const ReceiptEditScreen()),
                        );
                        if (ok == true) await _load();
                      },
                      icon: const Icon(Icons.add),
                      label: const Text('Новая накладная'),
                    ),
                    const SizedBox(height: 8),
                    if (_docs.isEmpty)
                      const Card(
                          child: ListTile(
                              title: Text(
                                  'Накладных пока нет — примите первую поставку'))),
                    for (final d in _docs)
                      Card(
                        child: ListTile(
                          leading: const Icon(
                              Icons.receipt_long_outlined),
                          title: Text(
                              '${(d['number'] as String?)?.isNotEmpty == true ? '№${d['number']} · ' : ''}${d['supplier'] ?? 'Поставщик?'}'),
                          subtitle: Text(
                              '${_date(d['created_at'] as String?)} · ${_stats[d['id']]?.lines ?? 0} поз.'),
                          trailing: Text(
                            '${(_stats[d['id']]?.total ?? 0).toStringAsFixed(0)} ₽',
                            style: const TextStyle(
                                fontWeight: FontWeight.bold),
                          ),
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => ReceiptDetailScreen(
                                    docId: d['id'] as String,
                                    title:
                                        'Накладная ${d['number'] ?? ''}')),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
      ),
    );
  }
}

/// Состав накладной: строки движений с ценами.
class ReceiptDetailScreen extends StatelessWidget {
  final String docId;
  final String title;
  const ReceiptDetailScreen(
      {super.key, required this.docId, required this.title});

  @override
  Widget build(BuildContext context) {
    final db = context.read<AppDb>();
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: AppBackground(
        child: FutureBuilder<List<Map<String, Object?>>>(
          future: db.receiptMoves(docId),
          builder: (_, snap) {
            if (!snap.hasData) {
              return const Center(
                  child: CircularProgressIndicator());
            }
            final moves = snap.data!;
            if (moves.isEmpty) {
              return const Center(
                  child: Text('В накладной нет строк'));
            }
            return ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: moves.length,
              itemBuilder: (_, i) {
                final m = moves[i];
                final qty =
                    (m['qty'] as num?)?.toDouble() ?? 0;
                final price =
                    (m['price'] as num?)?.toDouble() ?? 0;
                return Card(
                  child: ListTile(
                    dense: true,
                    title: Text(
                        '${m['pname'] ?? m['sku'] ?? 'Товар'}'),
                    subtitle:
                        Text('${qty.toStringAsFixed(0)} шт × ${price.toStringAsFixed(2)} ₽'),
                    trailing: Text(
                        '${(qty * price).toStringAsFixed(2)} ₽',
                        style: const TextStyle(
                            fontWeight: FontWeight.bold)),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
