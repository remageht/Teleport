import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/app_theme.dart';

/// Результат проведения оплаты на кассе.
class PosCheckoutResult {
  final bool confirmed;
  final double tendered;
  final double change;
  final bool printReceipt;

  const PosCheckoutResult({
    required this.confirmed,
    required this.tendered,
    required this.change,
    required this.printReceipt,
  });
}

/// Модальный экран кассового обслуживания: расчёт сдачи и выбор печати чека.
class PosCashCheckoutSheet extends StatefulWidget {
  final double total;
  final String? clientName;

  const PosCashCheckoutSheet({
    super.key,
    required this.total,
    this.clientName,
  });

  static Future<PosCheckoutResult?> show(
    BuildContext context, {
    required double total,
    String? clientName,
  }) {
    return showModalBottomSheet<PosCheckoutResult>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => PosCashCheckoutSheet(
        total: total,
        clientName: clientName,
      ),
    );
  }

  @override
  State<PosCashCheckoutSheet> createState() => _PosCashCheckoutSheetState();
}

class _PosCashCheckoutSheetState extends State<PosCashCheckoutSheet> {
  static const _prefPrintReceiptKey = 'pos_auto_print_receipt';

  final _tenderedCtrl = TextEditingController();
  bool _printReceipt = false;
  double _tendered = 0.0;

  @override
  void initState() {
    super.initState();
    _tendered = widget.total;
    _tenderedCtrl.text = _formatNum(widget.total);
    _loadPrintPref();
  }

  @override
  void dispose() {
    _tenderedCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadPrintPref() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _printReceipt = prefs.getBool(_prefPrintReceiptKey) ?? false;
      });
    }
  }

  Future<void> _togglePrint(bool val) async {
    setState(() => _printReceipt = val);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefPrintReceiptKey, val);
  }

  void _onTenderChanged(String text) {
    final cleaned = text.replaceAll(' ', '').replaceAll(',', '.');
    final val = double.tryParse(cleaned) ?? 0.0;
    setState(() {
      _tendered = val;
    });
  }

  void _setTendered(double val) {
    setState(() {
      _tendered = val;
      _tenderedCtrl.text = _formatNum(val);
    });
  }

  void _addTendered(double delta) {
    final cur = _tendered;
    final next = cur + delta;
    _setTendered(next);
  }

  String _formatNum(double num) {
    return num == num.roundToDouble()
        ? num.toStringAsFixed(0)
        : num.toStringAsFixed(2);
  }

  double get _change => _tendered - widget.total;

  /// Список подходящих банкнот и округлений
  List<double> _recommendedAmounts() {
    final result = <double>{};
    const denominations = [100.0, 200.0, 500.0, 1000.0, 2000.0, 5000.0];
    for (final d in denominations) {
      if (d >= widget.total) {
        result.add(d);
      }
    }
    // Ближайшее округление вверх до 50/100/500/1000
    if (widget.total > 0) {
      final round100 = (widget.total / 100).ceil() * 100.0;
      if (round100 > widget.total) result.add(round100);
      final round500 = (widget.total / 500).ceil() * 500.0;
      if (round500 > widget.total) result.add(round500);
      final round1000 = (widget.total / 1000).ceil() * 1000.0;
      if (round1000 > widget.total) result.add(round1000);
    }
    final list = result.toList()..sort();
    return list.take(5).toList();
  }

  @override
  Widget build(BuildContext context) {
    final isSufficient = _change >= -0.001;
    final theme = Theme.of(context);
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Шапка с заголовком и кнопкой закрытия
                Row(
                  children: [
                    const Icon(Icons.point_of_sale, color: AppTheme.brand, size: 28),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Оплата наличными',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          if (widget.clientName != null &&
                              widget.clientName!.isNotEmpty)
                            Text(
                              widget.clientName!,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Плашка суммы к оплате
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      Text(
                        'К оплате:',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          '${widget.total.toStringAsFixed(2)} ₽',
                          style: theme.textTheme.headlineSmall?.copyWith(
                            color: AppTheme.brand,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Ввод полученных денег
                TextField(
                  controller: _tenderedCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                  decoration: InputDecoration(
                    labelText: 'Получено от покупателя',
                    prefixIcon: const Icon(Icons.payments_outlined),
                    suffixText: '₽',
                    suffixIcon: _tenderedCtrl.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 20),
                            onPressed: () => _setTendered(0),
                          )
                        : null,
                    border: const OutlineInputBorder(),
                  ),
                  onChanged: _onTenderChanged,
                ),
                const SizedBox(height: 12),

                // Быстрые кнопки купюр
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ActionChip(
                      avatar: const Icon(Icons.check_circle_outline, size: 16),
                      label: const Text('Без сдачи'),
                      onPressed: () => _setTendered(widget.total),
                    ),
                    for (final amt in _recommendedAmounts())
                      ActionChip(
                        label: Text('${_formatNum(amt)} ₽'),
                        onPressed: () => _setTendered(amt),
                      ),
                    ActionChip(
                      label: const Text('+100 ₽'),
                      onPressed: () => _addTendered(100),
                    ),
                    ActionChip(
                      label: const Text('+500 ₽'),
                      onPressed: () => _addTendered(500),
                    ),
                    ActionChip(
                      label: const Text('+1 000 ₽'),
                      onPressed: () => _addTendered(1000),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Блок сдачи или нехватки
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isSufficient
                        ? Colors.green.withValues(alpha: 0.12)
                        : Colors.red.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isSufficient ? Colors.green : Colors.red,
                      width: 1.5,
                    ),
                  ),
                  child: Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            isSufficient
                                ? Icons.change_circle_outlined
                                : Icons.warning_amber_rounded,
                            color: isSufficient ? Colors.green : Colors.red,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            isSufficient ? 'Сдача:' : 'Не хватает:',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: isSufficient
                                  ? Colors.green.shade800
                                  : Colors.red.shade800,
                            ),
                          ),
                        ],
                      ),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          isSufficient
                              ? '${_formatNum(_change.abs())} ₽'
                              : '${_formatNum(_change.abs())} ₽',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: isSufficient
                                ? Colors.green.shade800
                                : Colors.red.shade800,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // Чекбокс печати чека
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _printReceipt,
                  title: const Text('Печатать товарный чек'),
                  subtitle: const Text('Отправить на подключенный принтер'),
                  secondary: const Icon(Icons.print_outlined),
                  onChanged: (val) => _togglePrint(val ?? false),
                ),
                const SizedBox(height: 16),

                // Кнопка подтверждения
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    backgroundColor: isSufficient ? AppTheme.brand : Colors.grey,
                  ),
                  onPressed: isSufficient
                      ? () {
                          Navigator.of(context).pop(
                            PosCheckoutResult(
                              confirmed: true,
                              tendered: _tendered,
                              change: _change < 0 ? 0.0 : _change,
                              printReceipt: _printReceipt,
                            ),
                          );
                        }
                      : null,
                  icon: const Icon(Icons.check),
                  label: const FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      'Принять оплату и провести',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
