import 'package:flutter_test/flutter_test.dart';
import 'package:radiotrade/services/invoice_photo_ocr.dart';

void main() {
  group('InvoicePhotoOcr parser tests', () {
    test('parses lines from customer order invoice (Image 1)', () {
      const sample1 =
          '1 00-00022496 4680092062221 Батарейка GoPower ZA675 BL6 Воздушно-цинковая (6/60/600/3000) 6 v шт 26.99 161,94';
      final l1 = InvoicePhotoOcr.parseLine(sample1);
      expect(l1, isNotNull);
      expect(l1!.qty, 6.0);
      expect(l1.price, 26.99);
      expect(l1.name,
          'Батарейка GoPower ZA675 BL6 Воздушно-цинковая (6/60/600/3000)');

      const sample2 =
          '2 ZA675 4043752444926 Батарейка Renata ZA675 BL6 Zinc Air 1.45V (6/60/300/3000) 6 v шт 35,11 210,66';
      final l2 = InvoicePhotoOcr.parseLine(sample2);
      expect(l2, isNotNull);
      expect(l2!.qty, 6.0);
      expect(l2.price, 35.11);
      expect(l2.name,
          'Батарейка Renata ZA675 BL6 Zinc Air 1.45V (6/60/300/3000)');

      const sample7 =
          '7 5638 2850006091636 Приставка для цифрового ТВ Nicedevice T624 DVB-T/T2/C черный 3 v шт 732,06 2 196,18';
      final l7 = InvoicePhotoOcr.parseLine(sample7);
      expect(l7, isNotNull);
      expect(l7!.qty, 3.0);
      expect(l7.price, 732.06);
      expect(l7.name,
          'Приставка для цифрового ТВ Nicedevice T624 DVB-T/T2/C черный');

      const sample9 =
          '9 SBE-10-3-10-N 4690626004726 Удлинитель Smartbuy 3р. Б/З 10А 10.0м ПВС (1/30) 1 v шт 442,84 442,84';
      final l9 = InvoicePhotoOcr.parseLine(sample9);
      expect(l9, isNotNull);
      expect(l9!.qty, 1.0);
      expect(l9.price, 442.84);
      expect(l9.name, 'Удлинитель Smartbuy 3р. Б/З 10А 10.0м ПВС (1/30)');

      const sample10 =
          '10 GP 24AUA21-2CRS BC4 40/320 4891199226366 Батарейка GP ULTRA G-Tech LR03 AAA BL4 Alkaline 1.5V (4/40/320) 12 v шт 37,67 452,04';
      final l10 = InvoicePhotoOcr.parseLine(sample10);
      expect(l10, isNotNull);
      expect(l10!.qty, 12.0);
      expect(l10.price, 37.67);
      expect(l10.name,
          'Батарейка GP ULTRA G-Tech LR03 AAA BL4 Alkaline 1.5V (4/40/320)');

      const sample18 =
          '18 171169 4690408163504 Шнур бельевой Рыжий кот 20м металлический суперпрочный 1 v шт 92,02 92,02';
      final l18 = InvoicePhotoOcr.parseLine(sample18);
      expect(l18, isNotNull);
      expect(l18!.qty, 1.0);
      expect(l18.price, 92.02);
      expect(l18.name,
          'Шнур бельевой Рыжий кот 20м металлический суперпрочный');
    });

    test('ignores header and footer lines', () {
      expect(InvoicePhotoOcr.parseLine('Исполнитель: ЕНВД'), isNull);
      expect(InvoicePhotoOcr.parseLine(
          '№ Артикул Штрихкод Товары (работы, услуги) Количество Цена Сумма'), isNull);
      expect(InvoicePhotoOcr.parseLine('Итого: 7 299,67'), isNull);
      expect(InvoicePhotoOcr.parseLine(
          'Всего наименований: 18, на сумму: 7 299,67 RUB, долг: 771,95 RUB, к оплате: 8 071,62 RUB'),
          isNull);
      expect(InvoicePhotoOcr.parseLine('Заказ клиента HP00-072309 от 16.09.2026 15:24:16'),
          isNull);
    });

    test('strips barcodes and structural garbage', () {
      // Штрихкод внутри строки не должен становиться ценой.
      final b = InvoicePhotoOcr.parseLine(
          'BC4 4680092062221 8 v шт 40.00 320.00');
      expect(b, isNotNull);
      expect(b!.qty, 8.0);
      expect(b.price, 40.00);
      expect(b.name, 'BC4');
      // Строка валют/итогов.
      expect(InvoicePhotoOcr.parseLine(
          'Vsego 18, summa 7319.69 RUB'), isNull);
      // Телефон поставщика.
      expect(InvoicePhotoOcr.parseLine(
          'tel.: 8-978-777-91-51'), isNull);
      // Адрес.
      expect(InvoicePhotoOcr.parseLine(
          'Resp Krym, ul Sovetskaya, Dom 9'), isNull);
    });
  });
}
