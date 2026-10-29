import 'package:flutter_test/flutter_test.dart';
import 'package:radiotrade/core/currency_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('CurrencyProvider', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('дефолтное состояние выключено и форматирует в рублях', () async {
      final p = CurrencyProvider();
      await p.load();

      expect(p.isEnabled, isFalse);
      expect(p.code, equals('USD'));
      expect(p.symbol, equals('\$'));
      expect(p.rate, greaterThan(0));

      // Когда выключено — всегда чистые рубли
      expect(p.format(1000), equals('1 000 ₽'));
      expect(p.format(1234567), equals('1 234 567 ₽'));
      expect(p.format(15.5), equals('15.50 ₽'));
    });

    test('математическая конвертация convert и convertToRub', () async {
      final p = CurrencyProvider();
      await p.load();
      await p.setCurrency('USD');
      await p.setRate(100.0);

      expect(p.convert(500), closeTo(5.0, 0.0001));
      expect(p.convertToRub(5.0), closeTo(500.0, 0.0001));
      expect(p.convert(0), equals(0.0));
      expect(p.convertToRub(0), equals(0.0));
    });

    test('режимы отображения dual и foreignOnly', () async {
      final p = CurrencyProvider();
      await p.load();
      await p.setEnabled(true);
      await p.setCurrency('USD');
      await p.setRate(100.0);

      // Двойной режим (по умолчанию)
      expect(p.displayMode, equals(CurrencyDisplayMode.dual));
      expect(p.format(1000), equals(r'1 000 ₽ (~$10.00)'));
      expect(p.format(1000, showApprox: false), equals(r'1 000 ₽ ($10.00)'));

      // Режим только валюты
      await p.setDisplayMode(CurrencyDisplayMode.foreignOnly);
      expect(p.format(1000), equals(r'$10.00'));
    });

    test('позиционирование символов валют (префикс/постфикс)', () async {
      final p = CurrencyProvider();
      await p.load();
      await p.setEnabled(true);

      // Евро: перед суммой
      await p.setCurrency('EUR');
      await p.setRate(100.0);
      expect(p.formatForeign(50.0), equals('€50.00'));

      // Тенге: после суммы с пробелом
      await p.setCurrency('KZT');
      await p.setRate(0.20);
      expect(p.formatForeign(1000.0), equals('1 000.00 ₸'));

      // Белорусский рубль: после суммы с пробелом
      await p.setCurrency('BYN');
      await p.setRate(30.0);
      expect(p.formatForeign(15.0), equals('15.00 Br'));

      // USDT: перед суммой
      await p.setCurrency('USDT');
      await p.setRate(96.0);
      expect(p.formatForeign(10.0), equals('₮10.00'));
    });

    test('сохранение и восстановление настроек из SharedPreferences', () async {
      final p1 = CurrencyProvider();
      await p1.load();
      await p1.setEnabled(true);
      await p1.setCurrency('CNY');
      await p1.setRate(14.25);
      await p1.setDisplayMode(CurrencyDisplayMode.foreignOnly);

      // Создаём новый экземпляр провайдера и проверяем чтение сохранённых данных
      final p2 = CurrencyProvider();
      await p2.load();

      expect(p2.isEnabled, isTrue);
      expect(p2.code, equals('CNY'));
      expect(p2.symbol, equals('¥'));
      expect(p2.rate, closeTo(14.25, 0.0001));
      expect(p2.displayMode, equals(CurrencyDisplayMode.foreignOnly));
    });

    test('кастомная валюта пользователя', () async {
      final p = CurrencyProvider();
      await p.load();
      await p.setEnabled(true);
      await p.setCurrency('CUSTOM', customRate: 26.5, customSymbol: 'AED');

      expect(p.code, equals('CUSTOM'));
      expect(p.symbol, equals('AED'));
      expect(p.rate, equals(26.5));
      expect(p.convert(265), closeTo(10.0, 0.0001));
      expect(p.formatForeign(10.0), equals('10.00 AED'));
    });
  });
}
