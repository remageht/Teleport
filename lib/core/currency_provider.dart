import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Режим отображения цен при включенной конвертации.
enum CurrencyDisplayMode {
  /// Двойной: базовая цена в рублях и приблизительный эквивалент в валюте:
  /// «1 200 ₽ (~$12.50)»
  dual,

  /// Только валюта: «$12.50»
  foreignOnly,
}

/// Описание поддерживаемой валюты.
class CurrencyItem {
  final String code;
  final String symbol;
  final String name;
  final double defaultRate;
  final bool symbolBefore;

  const CurrencyItem({
    required this.code,
    required this.symbol,
    required this.name,
    required this.defaultRate,
    this.symbolBefore = true,
  });
}

/// Провайдер конвертации валют (RUB → USD, EUR, CNY, KZT, BYN, USDT, Custom).
/// Хранит настройки в SharedPreferences и реактивно обновляет UI.
class CurrencyProvider extends ChangeNotifier {
  static const String _keyEnabled = 'currency_enabled';
  static const String _keyCode = 'currency_code';
  static const String _keySymbol = 'currency_symbol';
  static const String _keyRate = 'currency_rate';
  static const String _keyMode = 'currency_display_mode';
  static const String _keyLastUpdated = 'currency_last_updated';

  static const List<CurrencyItem> supportedCurrencies = [
    CurrencyItem(
      code: 'USD',
      symbol: '\$',
      name: 'Доллар США',
      defaultRate: 96.0,
      symbolBefore: true,
    ),
    CurrencyItem(
      code: 'EUR',
      symbol: '€',
      name: 'Евро',
      defaultRate: 104.0,
      symbolBefore: true,
    ),
    CurrencyItem(
      code: 'CNY',
      symbol: '¥',
      name: 'Китайский юань',
      defaultRate: 13.5,
      symbolBefore: true,
    ),
    CurrencyItem(
      code: 'KZT',
      symbol: '₸',
      name: 'Казахстанский тенге',
      defaultRate: 0.20,
      symbolBefore: false,
    ),
    CurrencyItem(
      code: 'BYN',
      symbol: 'Br',
      name: 'Белорусский рубль',
      defaultRate: 29.5,
      symbolBefore: false,
    ),
    CurrencyItem(
      code: 'USDT',
      symbol: '₮',
      name: 'Tether USD',
      defaultRate: 96.0,
      symbolBefore: true,
    ),
    CurrencyItem(
      code: 'CUSTOM',
      symbol: 'VAL',
      name: 'Своя валюта',
      defaultRate: 1.0,
      symbolBefore: false,
    ),
  ];

  bool _isEnabled = false;
  String _code = 'USD';
  String _symbol = '\$';
  double _rate = 96.0; // Количество рублей за 1 единицу валюты
  CurrencyDisplayMode _displayMode = CurrencyDisplayMode.dual;
  DateTime? _lastUpdated;
  bool _isFetching = false;

  bool get isEnabled => _isEnabled;
  String get code => _code;
  String get symbol => _symbol;
  double get rate => _rate;
  CurrencyDisplayMode get displayMode => _displayMode;
  DateTime? get lastUpdated => _lastUpdated;
  bool get isFetching => _isFetching;

  CurrencyItem get currentItem {
    final found = supportedCurrencies.where((c) => c.code == _code);
    if (found.isNotEmpty && _code != 'CUSTOM') return found.first;
    return CurrencyItem(
      code: _code,
      symbol: _symbol,
      name: _code == 'CUSTOM' ? 'Своя валюта' : _code,
      defaultRate: _rate,
      symbolBefore: false,
    );
  }

  /// Загрузка состояния из SharedPreferences.
  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _isEnabled = prefs.getBool(_keyEnabled) ?? false;
    _code = prefs.getString(_keyCode) ?? 'USD';
    _symbol = prefs.getString(_keySymbol) ?? _findDefaultSymbol(_code);
    _rate = prefs.getDouble(_keyRate) ?? _findDefaultRate(_code);
    final modeStr = prefs.getString(_keyMode);
    _displayMode = modeStr == CurrencyDisplayMode.foreignOnly.name
        ? CurrencyDisplayMode.foreignOnly
        : CurrencyDisplayMode.dual;
    final updatedMs = prefs.getInt(_keyLastUpdated);
    if (updatedMs != null && updatedMs > 0) {
      _lastUpdated = DateTime.fromMillisecondsSinceEpoch(updatedMs);
    }
    notifyListeners();
  }

  /// Включение / выключение конвертации.
  Future<void> setEnabled(bool enabled) async {
    if (_isEnabled == enabled) return;
    _isEnabled = enabled;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyEnabled, _isEnabled);
  }

  /// Смена текущей валюты.
  Future<void> setCurrency(String newCode,
      {double? customRate, String? customSymbol}) async {
    _code = newCode.toUpperCase().trim();
    if (customSymbol != null && customSymbol.isNotEmpty) {
      _symbol = customSymbol.trim();
    } else {
      _symbol = _findDefaultSymbol(_code);
    }

    if (customRate != null && customRate > 0) {
      _rate = customRate;
    } else {
      _rate = _findDefaultRate(_code);
    }

    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyCode, _code);
    await prefs.setString(_keySymbol, _symbol);
    await prefs.setDouble(_keyRate, _rate);
  }

  /// Установка курса обмена вручную (рублей за 1 единицу валюты).
  Future<void> setRate(double newRate) async {
    if (newRate <= 0) return;
    _rate = newRate;
    _lastUpdated = DateTime.now();
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_keyRate, _rate);
    await prefs.setInt(_keyLastUpdated, _lastUpdated!.millisecondsSinceEpoch);
  }

  /// Смена режима отображения (двойной / только валюта).
  Future<void> setDisplayMode(CurrencyDisplayMode mode) async {
    if (_displayMode == mode) return;
    _displayMode = mode;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyMode, _displayMode.name);
  }

  /// Пересчёт суммы из рублей в иностранную валюту.
  double convert(double rub) {
    if (!rub.isFinite || _rate <= 0 || !_rate.isFinite) return 0.0;
    return rub / _rate;
  }

  /// Пересчёт суммы из иностранной валюты в рубли.
  double convertToRub(double foreign) {
    if (!foreign.isFinite || _rate <= 0 || !_rate.isFinite) return 0.0;
    return foreign * _rate;
  }

  /// Форматирование валютной суммы (например «$12.50» или «12.50 ₸»).
  String formatForeign(double foreign, {bool compact = false}) {
    if (!foreign.isFinite) foreign = 0.0;
    final item = currentItem;
    final valStr = compact && foreign == foreign.roundToDouble()
        ? foreign.toStringAsFixed(0)
        : foreign.toStringAsFixed(2);

    final grouped = _formatThousands(valStr);
    return item.symbolBefore ? '$_symbol$grouped' : '$grouped $_symbol';
  }

  /// Форматирование рублей (например «1 200 ₽»).
  String formatRub(double rub) {
    if (!rub.isFinite) rub = 0.0;
    final isRound = (rub - rub.roundToDouble()).abs() < 0.001;
    final valStr = isRound ? rub.toStringAsFixed(0) : rub.toStringAsFixed(2);
    return '${_formatThousands(valStr)} ₽';
  }

  /// Универсальное форматирование цены:
  /// - Если конвертация выключена: «1 200 ₽»
  /// - Если включена и mode == dual: «1 200 ₽ (~$12.50)»
  /// - Если включена и mode == foreignOnly: «$12.50»
  String format(double rub, {bool showApprox = true, bool compact = false}) {
    if (!_isEnabled || _rate <= 0) {
      return formatRub(rub);
    }

    final foreign = convert(rub);
    final foreignStr = formatForeign(foreign, compact: compact);

    if (_displayMode == CurrencyDisplayMode.foreignOnly) {
      return foreignStr;
    }

    final rubStr = formatRub(rub);
    final approxPrefix = showApprox ? '~' : '';
    return '$rubStr ($approxPrefix$foreignStr)';
  }

  /// Загрузка актуальных курсов валют с открытого API ЦБ РФ (cbr-xml-daily.ru).
  /// Возвращает статус успешности и текстовое сообщение для пользователя.
  Future<({bool success, String message})> fetchCbrRates() async {
    if (_isFetching) {
      return (success: false, message: 'Загрузка уже выполняется');
    }
    _isFetching = true;
    notifyListeners();

    try {
      final uri = Uri.parse('https://www.cbr-xml-daily.ru/daily_json.js');
      final res = await http.get(uri).timeout(const Duration(seconds: 8));

      if (res.statusCode != 200) {
        return (
          success: false,
          message: 'Сервер ЦБ ответил кодом ${res.statusCode}',
        );
      }

      final data = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
      final valute = data['Valute'] as Map<String, dynamic>?;
      if (valute == null) {
        return (success: false, message: 'Неверный формат ответа ЦБ');
      }

      // Если текущая валюта USDT, берем курс USD
      final targetKey = _code == 'USDT' ? 'USD' : _code;
      final curData = valute[targetKey] as Map<String, dynamic>?;

      if (curData != null) {
        final val = (curData['Value'] as num?)?.toDouble();
        final nominal = (curData['Nominal'] as num?)?.toDouble() ?? 1.0;
        if (val != null && nominal > 0) {
          final computedRate = val / nominal;
          await setRate(computedRate);
          return (
            success: true,
            message: 'Курс $_code обновлён: ${computedRate.toStringAsFixed(4)} ₽',
          );
        }
      }

      return (
        success: false,
        message: 'Валюта $_code не найдена в котировках ЦБ',
      );
    } on TimeoutException {
      return (
        success: false,
        message: 'Таймаут соединения с сервером ЦБ РФ',
      );
    } catch (e) {
      return (
        success: false,
        message: 'Ошибка при обновлении курса: $e',
      );
    } finally {
      _isFetching = false;
      notifyListeners();
    }
  }

  static String _formatThousands(String numStr) {
    final isNegative = numStr.startsWith('-');
    final raw = isNegative ? numStr.substring(1) : numStr;
    final parts = raw.split('.');
    final whole = parts[0];
    final b = StringBuffer();
    for (var i = 0; i < whole.length; i++) {
      if (i > 0 && (whole.length - i) % 3 == 0) b.write(' ');
      b.write(whole[i]);
    }
    if (parts.length > 1) {
      b.write('.');
      b.write(parts[1]);
    }
    return isNegative ? '-$b' : b.toString();
  }

  static String _findDefaultSymbol(String code) {
    final found = supportedCurrencies.where((c) => c.code == code);
    return found.isNotEmpty ? found.first.symbol : code;
  }

  static double _findDefaultRate(String code) {
    final found = supportedCurrencies.where((c) => c.code == code);
    return found.isNotEmpty ? found.first.defaultRate : 1.0;
  }
}
