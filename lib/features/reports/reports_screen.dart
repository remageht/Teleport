import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/session.dart';
import '../../../data/db/app_db.dart';
import '../../../services/export_service.dart';
import '../cash/cash_screen.dart';
import 'margin_screen.dart';

/// Отчёты: продажи за день, остатки, дебиторка, выполнение плана.
class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});
  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  static const _plan = 50000.0; // план продаж на день (демо)
  double _sales = 0, _debt = 0;
  int _positions = 0;

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
    final debt = await db.totalDebt();
    if (!mounted) return;
    setState(() {
      _sales = orders.fold<double>(0.0, (s, o) => s + o.total);
      _positions = orders.fold(0, (s, o) => s + o.lines.length);
      _debt = debt;
    });
  }

  @override
  Widget build(BuildContext context) {
    final planPct = (_sales / _plan * 100).clamp(0, 999);
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Выполнение плана', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                LinearProgressIndicator(
                    value: (planPct / 100).clamp(0, 1), minHeight: 10),
                const SizedBox(height: 8),
                Text('${_sales.toStringAsFixed(0)} / ${_plan.toStringAsFixed(0)} ₽ '
                    '(${planPct.toStringAsFixed(0)}%)'),
              ],
            ),
          ),
        ),
        _reportTile('Продажи за день', '${_sales.toStringAsFixed(2)} ₽', Icons.payments),
        _reportTile('Позиций продано', '$_positions', Icons.list_alt),
        _reportTile('Дебиторская задолженность', '${_debt.toStringAsFixed(2)} ₽',
            Icons.account_balance_wallet),
        const SizedBox(height: 4),
        Card(
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.point_of_sale,
                    color: Colors.green),
                title: const Text('Касса дня'),
                subtitle: const Text(
                    'Утро, продажи по способам, сверка, Z-отчёт'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const CashScreen())),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.trending_up,
                    color: Colors.teal),
                title: const Text('Маржа по позициям'),
                subtitle: const Text(
                    'Выручка минус последняя закупка'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const MarginScreen())),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Text('Экспорт', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 4),
        Card(
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.table_view, color: Colors.green),
                title: const Text('Экспорт в Excel — за сегодня'),
                subtitle: const Text('Листы «Продажи» и «Накладная»'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _export(false),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.folder_open, color: Colors.blue),
                title: const Text('Экспорт в Excel — всё время'),
                subtitle: const Text('Все продажи с начала работы'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _export(true),
              ),
              const Divider(height: 1),
              ListTile(
                leading:
                    const Icon(Icons.send_outlined, color: Colors.red),
                title: const Text('Прайс для покупателей'),
                subtitle: const Text(
                    'Каталог с ценами и остатками для рассылки'),
                trailing: const Icon(Icons.chevron_right),
                onTap: _buyerPrice,
              ),
            ],
          ),
        ),
        if (_exportMsg != null)
          Padding(
            padding: const EdgeInsets.all(8),
            child: Text(_exportMsg!,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall),
          ),
      ],
    );
  }

  String? _exportMsg;

  Future<void> _export(bool allTime) async {
    setState(() => _exportMsg = 'Формирую файл…');
    final msg = await ExportService()
        .exportSales(context.read<AppDb>(), allTime: allTime);
    if (mounted) setState(() => _exportMsg = msg);
  }

  /// Прайс для покупателей: выбор прайса, затем Excel по каталогам.
  Future<void> _buyerPrice() async {
    final db = context.read<AppDb>();
    final lists = await db.priceLists();
    if (!mounted) return;
    final pick = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Прайс для покупателей'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final l in lists)
              ListTile(
                dense: true,
                title: Text('${l['name']}'),
                subtitle: Text(
                    'Скидка: ${((l['discount_pct'] as num?)?.toDouble() ?? 0).toStringAsFixed(0)}%'),
                onTap: () => Navigator.pop(c, l['id'] as String),
              ),
          ],
        ),
      ),
    );
    if (pick == null) return;
    setState(() => _exportMsg = 'Формирую прайс…');
    final msg =
        await ExportService().exportBuyerPrice(db, priceListId: pick);
    if (mounted) setState(() => _exportMsg = msg);
  }

  Widget _reportTile(String title, String value, IconData icon) => Card(
        child: ListTile(
          leading: Icon(icon),
          title: Text(title),
          trailing: Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
        ),
      );
}
