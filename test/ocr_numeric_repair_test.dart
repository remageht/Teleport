import 'package:flutter_test/flutter_test.dart';
import 'package:radiotrade/services/invoice_photo_ocr.dart';

void main() {
  group('parseLine: починка цифр, искажённых OCR (Э/О/б/З вместо 0/3/6)', () {
    test('Э вместо 3 в цене — арифметика подтверждает', () {
      final l = InvoicePhotoOcr.parseLine(
          '1 00-00022496 Батарейка GoPower ZA675 BL6 6 v шт 26,Э9 161,94');
      expect(l, isNotNull);
      expect(l!.qty, 6.0);
      expect(l.price, 26.39,
          reason: '26,Э9 → 26,39: 6 × 26.39 = 161.94');
    });

    test('б и О вместо 6 и 0 в цене и сумме', () {
      final l = InvoicePhotoOcr.parseLine(
          '10 GP 24AUA21-2CRS BC4 40/320 Батарейка GP ULTRA '
          'LR03 AAA BL4 12 шт 37,б7 452,О4');
      expect(l, isNotNull);
      expect(l!.qty, 12.0);
      expect(l.price, 37.67,
          reason: '37,б7 → 37.67: 12 × 37.67 = 452.04');
    });

    test('латинские коды в названии не портятся', () {
      final l = InvoicePhotoOcr.parseLine(
          'Батарейка BL6 ZA675 2 шт 30,98 61,96');
      expect(l, isNotNull);
      expect(l!.name, 'Батарейка BL6 ZA675');
      expect(l.qty, 2.0);
      expect(l.price, 30.98);
    });

    test('одиночная цена с О чинится даже без суммы', () {
      final l = InvoicePhotoOcr.parseLine('Приставка Nicedevice T624 732,О6');
      expect(l, isNotNull);
      expect(l!.price, 732.06, reason: '732,О6 → 732.06');
      expect(l.qty, 1.0);
    });

    test('чистая кириллица в токене не превращается в цифры', () {
      // «ЗО» без единой настоящей цифры — не число, не трогаем.
      final l = InvoicePhotoOcr.parseLine('Удлинитель ЗО 40,64 81,28');
      expect(l, isNotNull);
      expect(l!.name, 'Удлинитель ЗО');
      expect(l.price, 40.64);
    });
  });

  group('parseLine: разреженные тысячи и потерянная запятая', () {
    test('кол-во и цена не склеиваются в мусор (2 130,40 260,80)', () {
      final l = InvoicePhotoOcr.parseLine(
          '13 00-00024537 4680092063488 Кабель питания 2 130,40 260,80');
      expect(l, isNotNull);
      expect(l!.qty, 2.0, reason: '2 × 130,40 = 260,80');
      expect(l.price, 130.40);
    });

    test('склейка только последней группы (2 813,69 1 627,38)', () {
      final l = InvoicePhotoOcr.parseLine(
          '8 5801Selenga 4673754692164 Модем 8800 2 813,69 1 627,38');
      expect(l, isNotNull);
      expect(l!.qty, 2.0, reason: '2 × 813,69 = 1627,38');
      expect(l.price, 813.69);
    });

    test('потерянная запятая в цене (2 15120 302,40)', () {
      final l = InvoicePhotoOcr.parseLine(
          '5 00-00026400 4680092063839 Патч-корд 1м 2 15120 302,40');
      expect(l, isNotNull);
      expect(l!.qty, 2.0, reason: '2 × 151,20 = 302,40');
      expect(l.price, 151.20);
    });

    test('склейка тысячи в сумме всё ещё работает (3 732,06 2 196,18)', () {
      final l = InvoicePhotoOcr.parseLine(
          '7 5638 2850006081636 Модем 1924 3 732,06 2 196,18');
      expect(l, isNotNull);
      expect(l!.qty, 3.0);
      expect(l.price, 732.06);
    });

    test('двухчисельный хвост с потерянной запятой (15120 302,40)', () {
      final l = InvoicePhotoOcr.parseLine('Патч-корд CCA 15120 302,40');
      expect(l, isNotNull);
      expect(l!.qty, 2.0);
      expect(l.price, 151.20);
    });

    test('разрыв дробной части пробелом чинится (3 732,06 2 196, 18)', () {
      final l = InvoicePhotoOcr.parseLine(
          '7 5638 2850006081636 рот ТВ Nicedevice 3 732,06 2 196, 18');
      expect(l, isNotNull);
      expect(l!.qty, 3.0);
      expect(l.price, 732.06);
    });

    test('фасовка в скобках (1/100) не принимается за количество', () {
      final l = InvoicePhotoOcr.parseLine(
          '12 Кабель питания черный (1/100) 130,40');
      expect(l, isNotNull);
      expect(l!.qty, 1.0, reason: '(1/100) — фасовка в названии, а не кол-во');
      expect(l.price, 130.40);
    });

    test('хвост с потерянной запятой в обеих колонках (13040 13040)', () {
      final l = InvoicePhotoOcr.parseLine(
          'Кабель питания microUSB (1/100) 13040 13040');
      expect(l, isNotNull);
      expect(l!.qty, 1.0);
      expect(l.price, 130.40);
    });
  });
}
