import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/app_theme.dart';
import '../../../core/currency_provider.dart';

/// Интерактивный диалог быстрого калькулятора валют.
/// Позволяет мгновенно пересчитывать суммы из рублей в валюту и обратно.
class CurrencyCalculatorDialog extends StatefulWidget {
  const CurrencyCalculatorDialog({super.key});

  static Future<void> show(BuildContext context) {
    return showDialog<void>(
      context: context,
      builder: (_) => const CurrencyCalculatorDialog(),
    );
  }

  @override
  State<CurrencyCalculatorDialog> createState() =>
      _CurrencyCalculatorDialogState();
}

class _CurrencyCalculatorDialogState extends State<CurrencyCalculatorDialog> {
  late final TextEditingController _rubCtrl;
  late final TextEditingController _foreignCtrl;
  bool _updatingFromRub = false;
  bool _updatingFromForeign = false;

  @override
  void initState() {
    super.initState();
    _rubCtrl = TextEditingController(text: '1000');
    _foreignCtrl = TextEditingController();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _recalcFromRub();
    });
  }

  @override
  void dispose() {
    _rubCtrl.dispose();
    _foreignCtrl.dispose();
    super.dispose();
  }

  void _recalcFromRub() {
    if (_updatingFromForeign) return;
    _updatingFromRub = true;
    final currency = context.read<CurrencyProvider>();
    final rubText = _rubCtrl.text.replaceAll(' ', '').replaceAll(',', '.');
    final rubVal = double.tryParse(rubText) ?? 0.0;
    final foreignVal = currency.convert(rubVal);
    _foreignCtrl.text = foreignVal > 0 ? foreignVal.toStringAsFixed(2) : '';
    _updatingFromRub = false;
  }

  void _recalcFromForeign() {
    if (_updatingFromRub) return;
    _updatingFromForeign = true;
    final currency = context.read<CurrencyProvider>();
    final fText = _foreignCtrl.text.replaceAll(' ', '').replaceAll(',', '.');
    final fVal = double.tryParse(fText) ?? 0.0;
    final rubVal = currency.convertToRub(fVal);
    _rubCtrl.text = rubVal > 0 ? rubVal.toStringAsFixed(2) : '';
    _updatingFromForeign = false;
  }

  void _addRub(double delta) {
    final cur = double.tryParse(
            _rubCtrl.text.replaceAll(' ', '').replaceAll(',', '.')) ??
        0.0;
    final next = (cur + delta).clamp(0.0, 99999999.0);
    _rubCtrl.text = next == next.roundToDouble()
        ? next.toStringAsFixed(0)
        : next.toStringAsFixed(2);
    _recalcFromRub();
  }

  void _setForeign(double val) {
    _foreignCtrl.text = val.toStringAsFixed(0);
    _recalcFromForeign();
  }

  void _reset() {
    _rubCtrl.clear();
    _foreignCtrl.clear();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final currency = context.watch<CurrencyProvider>();
    final item = currency.currentItem;

    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.currency_exchange, color: AppTheme.brand),
          const SizedBox(width: 10),
          const Expanded(child: Text('Калькулятор валют')),
          IconButton(
            icon: const Icon(Icons.close, size: 20),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
      content: SizedBox(
        width: 360,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Текущий курс и быстрый выбор валюты
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '1 ${item.code} = ${currency.rate.toStringAsFixed(2)} ₽',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                    const SizedBox(width: 8),
                    DropdownButton<String>(
                      value: currency.code,
                      underline: const SizedBox.shrink(),
                      isDense: true,
                      items: CurrencyProvider.supportedCurrencies
                          .map((c) => DropdownMenuItem(
                                value: c.code,
                                child: Text('${c.code} (${c.symbol})'),
                              ))
                          .toList(),
                      onChanged: (code) {
                        if (code != null) {
                          currency.setCurrency(code);
                          _recalcFromRub();
                        }
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Поле рублей
              TextField(
                controller: _rubCtrl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: 'Сумма в рублях',
                  suffixText: '₽',
                  prefixIcon: const Icon(Icons.payments_outlined),
                  border: const OutlineInputBorder(),
                  suffixIcon: _rubCtrl.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () {
                          _rubCtrl.clear();
                          _recalcFromRub();
                        },
                      )
                    : null,
                ),
                onChanged: (_) => _recalcFromRub(),
              ),
              const SizedBox(height: 12),

              // Стрелка направления
              const Center(
                child: Icon(Icons.swap_vert, color: AppTheme.brand),
              ),
              const SizedBox(height: 12),

              // Поле иностранной валюты
              TextField(
                controller: _foreignCtrl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: 'В валюте (${item.name})',
                  suffixText: item.symbol,
                  prefixIcon: const Icon(Icons.monetization_on_outlined),
                  border: const OutlineInputBorder(),
                  suffixIcon: _foreignCtrl.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () {
                          _foreignCtrl.clear();
                          _recalcFromForeign();
                        },
                      )
                    : null,
                ),
                onChanged: (_) => _recalcFromForeign(),
              ),
              const SizedBox(height: 16),

              // Быстрые кнопки добавления сумм
              Wrap(
                spacing: 6,
                runSpacing: 6,
                alignment: WrapAlignment.center,
                children: [
                  ActionChip(
                    label: const Text('+1 000 ₽'),
                    onPressed: () => _addRub(1000),
                  ),
                  ActionChip(
                    label: const Text('+5 000 ₽'),
                    onPressed: () => _addRub(5000),
                  ),
                  ActionChip(
                    label: const Text('+10 000 ₽'),
                    onPressed: () => _addRub(10000),
                  ),
                  ActionChip(
                    label: Text('100 ${item.symbol}'),
                    onPressed: () => _setForeign(100),
                  ),
                  ActionChip(
                    avatar: const Icon(Icons.refresh, size: 16),
                    label: const Text('Сброс'),
                    onPressed: _reset,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Готово'),
        ),
      ],
    );
  }
}
