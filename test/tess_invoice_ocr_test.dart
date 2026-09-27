import 'package:flutter_test/flutter_test.dart';
import 'package:radiotrade/services/tess_invoice_ocr.dart';

void main() {
  group('TessInvoiceOcr.parseRaw', () {
    /// Симулирует типичный вывод Tesseract: строки через \n, пустые строки,
    /// шапка таблицы и настоящие товарные позиции вперемешку.
    test('parses valid lines and skips junk', () {
      const raw = '''
Заказ клиента НР00-072309 от 16.09.2026

№ Артикул Штрихкод Товары Количество Цена Сумма

1 00-00022496 4680092062221 Батарейка GoPower ZA675 BL6 Воздушно-цинковая (6/60/600/3000) 6 шт 26,99 161,94

2 ZA675 4043752454928 Батарейка Renata ZA675 BL6 Zinc Air 1.45V (6/60/300/3000) 6 шт 35,11 210,66

Итого: 372,60

Всего наименований: 2, на сумму: 372,60 RUB
''';

      final lines = TessInvoiceOcr.parseRaw(raw);
      expect(lines.length, 2,
          reason: 'шапка, итого и строка RUB должны быть отфильтрованы');

      expect(lines[0].qty, 6.0);
      expect(lines[0].price, 26.99);
      expect(lines[0].name,
          'Батарейка GoPower ZA675 BL6 Воздушно-цинковая (6/60/600/3000)');

      expect(lines[1].qty, 6.0);
      expect(lines[1].price, 35.11);
      expect(lines[1].name,
          'Батарейка Renata ZA675 BL6 Zinc Air 1.45V (6/60/300/3000)');
    });

    test('returns empty list for empty or whitespace-only input', () {
      expect(TessInvoiceOcr.parseRaw(''), isEmpty);
      expect(TessInvoiceOcr.parseRaw('   \n\n  '), isEmpty);
    });

    test('deduplicates identical parsed names', () {
      // Tesseract может повторить строку дважды из-за блочной разбивки.
      const raw = '''
7 5638 2850006081636 Приставка для цифрового ТВ Nicedevice T624 DVB-T/T2/C черный 3 шт 732,06 2 196,18
7 5638 2850006081636 Приставка для цифрового ТВ Nicedevice T624 DVB-T/T2/C черный 3 шт 732,06 2 196,18
''';
      final lines = TessInvoiceOcr.parseRaw(raw);
      expect(lines.length, 1, reason: 'дубликат должен быть убран');
    });

    test('skips supplier address and RUB footer even in raw Tesseract output', () {
      const raw = '''
BapkriOB A. O., 296500 Respublika 8-978-777-91-51
RUB, A 1 1771.95
BC 4 40160.00
''';
      final lines = TessInvoiceOcr.parseRaw(raw);
      expect(lines, isEmpty,
          reason: 'адрес поставщика, RUB-хвост и аномальная цена — не товар');
    });
  });
}
