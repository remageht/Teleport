import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../data/db/app_db.dart';
import '../shared/app_background.dart';
import '../shared/printer_sheet.dart';

/// Касса дня: утренний остаток, продажи по способам оплаты (сами
/// подтягиваются из заказов), ручные внесения/выплаты, вечерняя
/// сверка и Z-отчёт на принтер.
class CashScreen extends StatefulWidget {
  const CashScreen({super.key});
  @override
  State<CashScreen> createState() => _CashScreenState();
}

class _CashScreenState extends State<CashScreen> {
  late final String _day;
  double _opening = 0;
  Map<String, double> _sales = {};
  double _cashIn = 0, _cashOut = 0;
  List<Map<String, Object?>> _moves = [];
  bool _closed = false;
  bool _loading = true;

  static const _methods = {
    'cash': 'Наличные',
    'card': 'Карта',
    'transfer': 'Перевод',
    'deferred': 'Долг',
  };

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _day =
        '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    _load();
  }

  Future<void> _load() async {
    final db = context.read<AppDb>();
    final s = await db.cashDay(_day);
    final moves = await db.cashMoves(_day);
    if (!mounted) return;
    setState(() {
      _opening = s.opening;
      _sales = s.sales;
      _cashIn = s.cashIn;
      _cashOut = s.cashOut;
      _moves = moves;
      _closed = moves.any((m) => m['kind'] == 'close');
      _loading = false;
    });
  }

  double get _cashSales => _sales['cash'] ?? 0;
  double get _expected => _opening + _cashSales + _cashIn - _cashOut;
  double get _totalSales =>
      _sales.values.fold(0, (s, v) => s + v);

  Future<void> _openDay() async {
    final db = context.read<AppDb>();
    final ctrl = TextEditingController();
    final v = await showDialog<double>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Утренний остаток'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType:
              const TextInputType.numberWithOptions(decimal: true),
          decoration:
              const InputDecoration(labelText: 'Наличных в кассе, ₽'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c),
              child: const Text('Отмена')),
          FilledButton(
              onPressed: () => Navigator.pop(
                  c,
                  double.tryParse(
                      ctrl.text.replaceAll(',', '.'))),
              child: const Text('Открыть день')),
        ],
      ),
    );
    if (v == null) return;
    await db.addCashMove(day: _day, kind: 'open', amount: v);
    await _load();
  }

  Future<void> _manualMove() async {
    final db = context.read<AppDb>();
    var kind = 'in';
    var method = 'cash';
    final amount = TextEditingController();
    final note = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setD) => AlertDialog(
          title: const Text('Внесение / выплата'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(
                      value: 'in', label: Text('Внести')),
                  ButtonSegment(
                      value: 'out', label: Text('Выплатить')),
                ],
                selected: {kind},
                onSelectionChanged: (s) =>
                    setD(() => kind = s.first),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: method,
                decoration:
                    const InputDecoration(labelText: 'Способ'),
                items: [
                  for (final e in _methods.entries)
                    DropdownMenuItem(
                        value: e.key, child: Text(e.value)),
                ],
                onChanged: (v) =>
                    setD(() => method = v ?? 'cash'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: amount,
                autofocus: true,
                keyboardType:
                    const TextInputType.numberWithOptions(
                        decimal: true),
                decoration:
                    const InputDecoration(labelText: 'Сумма, ₽ *'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: note,
                decoration: const InputDecoration(
                    labelText: 'Комментарий'),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(c, false),
                child: const Text('Отмена')),
            FilledButton(
                onPressed: () => Navigator.pop(c, true),
                child: const Text('Записать')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    final v =
        double.tryParse(amount.text.replaceAll(',', '.')) ?? 0;
    if (v <= 0) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Укажите сумму')));
      }
      return;
    }
    await db.addCashMove(
          day: _day,
          kind: kind,
          method: method,
          amount: v,
          note: note.text.trim().isEmpty
              ? null
              : note.text.trim(),
        );
    await _load();
  }

  Future<void> _closeDay() async {
    final db = context.read<AppDb>();
    final ctrl = TextEditingController(
        text: _expected.toStringAsFixed(0));
    final actual = await showDialog<double>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Вечерняя сверка'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
                'Должно быть: ${_expected.toStringAsFixed(2)} ₽'),
            const SizedBox(height: 8),
            TextField(
              controller: ctrl,
              autofocus: true,
              keyboardType:
                  const TextInputType.numberWithOptions(
                      decimal: true),
              decoration: const InputDecoration(
                  labelText: 'Посчитано фактически, ₽'),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c),
              child: const Text('Отмена')),
          FilledButton(
              onPressed: () => Navigator.pop(
                  c,
                  double.tryParse(
                      ctrl.text.replaceAll(',', '.'))),
              child: const Text('Закрыть день')),
        ],
      ),
    );
    if (actual == null) return;
    await db.addCashMove(
        day: _day,
        kind: 'close',
        amount: actual,
        note:
            'расхождение ${(actual - _expected).toStringAsFixed(2)}');
    await _load();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(actual >= _expected
              ? 'День закрыт. Излишек ${(actual - _expected).toStringAsFixed(2)} ₽'
              : 'День закрыт. Недостача ${(_expected - actual).toStringAsFixed(2)} ₽')));
    }
  }

  Future<void> _zReport() async {
    final b = StringBuffer();
    b.writeln('Z-OTCHET $_day');
    b.writeln('TELEMASTER');
    b.writeln('--------------------------------');
    b.writeln(
        'Otkrytie: ${_opening.toStringAsFixed(2)}');
    for (final e in _sales.entries) {
      b.writeln(
          '${_methods[e.key] ?? e.key}: ${e.value.toStringAsFixed(2)}');
    }
    b.writeln('Vneseno: ${_cashIn.toStringAsFixed(2)}');
    b.writeln('Vyplaty: ${_cashOut.toStringAsFixed(2)}');
    b.writeln(
        'Itogo prodazh: ${_totalSales.toStringAsFixed(2)}');
    b.writeln(
        'Nalichnyh ozhidaetsya: ${_expected.toStringAsFixed(2)}');
    await PrinterSheet.printText(context, 'Z-отчёт $_day', b.toString());
  }

  String _kindName(String? k) => switch (k) {
        'open' => 'Открытие',
        'in' => 'Внесение',
        'out' => 'Выплата',
        'close' => 'Закрытие',
        _ => k ?? '',
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Касса · $_day')),
      body: AppBackground(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: _load,
                child: ListView(
                  padding: const EdgeInsets.all(12),
                  children: [
                    Card(
                      child: ListTile(
                        leading: const Icon(
                            Icons.lock_open_outlined),
                        title: _opening > 0 || _closed
                            ? Text(
                                'Открытие: ${_opening.toStringAsFixed(2)} ₽')
                            : const Text('День не открыт'),
                        trailing: _opening > 0 || _closed
                            ? null
                            : FilledButton.tonal(
                                onPressed: _openDay,
                                child: const Text('Открыть'),
                              ),
                      ),
                    ),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment:
                              CrossAxisAlignment.start,
                          children: [
                            Text('Продажи',
                                style: Theme.of(context)
                                    .textTheme
                                    .titleMedium
                                    ?.copyWith(
                                        fontWeight:
                                            FontWeight.w700)),
                            const SizedBox(height: 4),
                            if (_sales.isEmpty)
                              const Text('Продаж сегодня нет'),
                            for (final e in _sales.entries)
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment
                                        .spaceBetween,
                                children: [
                                  Text(_methods[e.key] ??
                                      e.key),
                                  Text(
                                      '${e.value.toStringAsFixed(2)} ₽',
                                      style: const TextStyle(
                                          fontWeight:
                                              FontWeight.w600)),
                                ],
                              ),
                            const Divider(),
                            Row(
                              mainAxisAlignment:
                                  MainAxisAlignment.spaceBetween,
                              children: [
                                const Text('Итого',
                                    style: TextStyle(
                                        fontWeight:
                                            FontWeight.bold)),
                                Text(
                                    '${_totalSales.toStringAsFixed(2)} ₽',
                                    style: const TextStyle(
                                        fontWeight:
                                            FontWeight.bold)),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    Card(
                      child: Column(
                        children: [
                          ListTile(
                            leading:
                                const Icon(Icons.swap_vert),
                            title: const Text(
                                'Внесения / выплаты'),
                            subtitle: Text(
                                '+${_cashIn.toStringAsFixed(0)} / −${_cashOut.toStringAsFixed(0)} ₽'),
                            trailing: IconButton.filledTonal(
                              tooltip: 'Записать',
                              icon: const Icon(Icons.add),
                              onPressed: _closed
                                  ? null
                                  : _manualMove,
                            ),
                          ),
                          for (final m in _moves.where((e) =>
                              e['kind'] == 'in' ||
                              e['kind'] == 'out'))
                            ListTile(
                              dense: true,
                              leading: Icon(
                                m['kind'] == 'in'
                                    ? Icons.add_circle_outline
                                    : Icons.remove_circle_outline,
                                color: m['kind'] == 'in'
                                    ? Colors.green
                                    : Colors.red,
                              ),
                              title: Text(
                                  '${_kindName(m['kind'] as String?)} · ${((m['amount'] as num?)?.toDouble() ?? 0).toStringAsFixed(2)} ₽'),
                              subtitle:
                                  (m['note'] as String?)?.isNotEmpty ==
                                          true
                                      ? Text(
                                          m['note'] as String)
                                      : null,
                            ),
                        ],
                      ),
                    ),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment:
                              CrossAxisAlignment.start,
                          children: [
                            Text('Ожидается наличных',
                                style: Theme.of(context)
                                    .textTheme
                                    .titleMedium
                                    ?.copyWith(
                                        fontWeight:
                                            FontWeight.w700)),
                            Text(
                                '${_expected.toStringAsFixed(2)} ₽',
                                style: Theme.of(context)
                                    .textTheme
                                    .headlineSmall
                                    ?.copyWith(
                                        fontWeight:
                                            FontWeight.w800)),
                            Text(
                                'утро ${_opening.toStringAsFixed(0)} + продажи ${_cashSales.toStringAsFixed(0)} + внесения ${_cashIn.toStringAsFixed(0)} − выплаты ${_cashOut.toStringAsFixed(0)}',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(
                                  child: FilledButton.icon(
                                    onPressed: _closed
                                        ? null
                                        : _closeDay,
                                    icon: const Icon(Icons
                                        .lock_outline),
                                    label: Text(_closed
                                        ? 'День закрыт'
                                        : 'Закрыть день'),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                IconButton.filledTonal(
                                  tooltip: 'Z-отчёт на принтер',
                                  icon: const Icon(
                                      Icons.print_outlined),
                                  onPressed: _zReport,
                                ),
                              ],
                            ),
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
}
