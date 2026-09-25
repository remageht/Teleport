import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';

import '../models/trade.dart';

/// Печать чеков/накладных на мобильный Bluetooth-принтер.
/// ESC/POS-команды формируются вручную (без внешних генераторов).
/// На десктопе — экспорт в текстовый файл рядом с приложением.
class ReceiptPrinter {
  Future<List<String>> scanDevices() async {
    if (kIsWeb || Platform.isWindows || Platform.isLinux) return const [];
    final list = await PrintBluetoothThermal.pairedBluetooths;
    return list.map((d) => '${d.name} (${d.macAdress})').toList();
  }

  Future<bool> connect(String mac) async {
    if (kIsWeb || Platform.isWindows || Platform.isLinux) return true;
    return await PrintBluetoothThermal.connect(macPrinterAddress: mac);
  }

  Future<void> printReceipt(Order order, {bool invoice = false}) async {
    final bytes = _build(order, invoice: invoice);
    if (kIsWeb || Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      final f = File('receipt_${order.number}.txt');
      await f.writeAsString(_plainText(order, invoice: invoice));
      return;
    }
    await PrintBluetoothThermal.writeBytes(bytes);
  }

  /// Печать ценника: название, крупная цена, штрих-код CODE128.
  /// На десктопе — текстовый файл. Возвращает сообщение для UI.
  Future<String> printLabels(
      List<({String name, double price, String? barcode})> labels) async {
    if (labels.isEmpty) return 'Нечего печатать';
    if (kIsWeb ||
        Platform.isWindows ||
        Platform.isLinux ||
        Platform.isMacOS) {
      final b = StringBuffer();
      for (final l in labels) {
        b.writeln('------------------------');
        b.writeln(l.name);
        b.writeln(
            '${l.price.toStringAsFixed(l.price % 1 == 0 ? 0 : 2)} RUB');
        if (l.barcode != null && l.barcode!.isNotEmpty) {
          b.writeln('*${l.barcode}*');
        }
      }
      final f = File(
          'cenники_${DateTime.now().millisecondsSinceEpoch}.txt');
      await f.writeAsString(b.toString());
      return 'Файл: ${f.path}';
    }
    for (var i = 0; i < labels.length; i++) {
      final l = labels[i];
      await PrintBluetoothThermal.writeBytes(
          _buildLabel(name: l.name, price: l.price, barcode: l.barcode));
      if (i < labels.length - 1) {
        await Future.delayed(const Duration(milliseconds: 400));
      }
    }
    return labels.length == 1
        ? 'Ценник напечатан'
        : 'Напечатано: ${labels.length}';
  }

  /// Печать произвольного текста (Z-отчёт кассы): транслит + отрезка.
  /// На десктопе — текстовый файл. Возвращает сообщение для UI.
  Future<String> printText(String title, String text) async {
    if (kIsWeb ||
        Platform.isWindows ||
        Platform.isLinux ||
        Platform.isMacOS) {
      final safe =
          title.replaceAll(RegExp(r'[^\w\-]+'), '_');
      final f = File(
          '${safe}_${DateTime.now().millisecondsSinceEpoch}.txt');
      await f.writeAsString(text);
      return 'Файл: ${f.path}';
    }
    final out = BytesBuilder();
    out.add([0x1B, 0x40]); // ESC @
    out.add([0x1B, 0x61, 0x01]); // центр
    out.add(utf8.encode('${_sanitize(translit(text))}\n'));
    out.add([0x1D, 0x56, 0x42, 0x00]); // отрезка
    await PrintBluetoothThermal.writeBytes(out.toBytes());
    return 'Напечатано';
  }

  /// ESC/POS-байты ценника 58мм: название, цена крупно, CODE128.
  Uint8List _buildLabel(
      {required String name,
      required double price,
      String? barcode}) {
    final out = BytesBuilder();
    out.add([0x1B, 0x40]); // ESC @
    out.add([0x1B, 0x61, 0x01]); // центр
    for (final line in _wrap(_sanitize(translit(name)), 32).take(3)) {
      out.add(utf8.encode('$line\n'));
    }
    out.add([0x1D, 0x21, 0x11]); // GS ! — двойная ширина+высота
    final pr =
        '${price.toStringAsFixed(price % 1 == 0 ? 0 : 2)} RUB\n';
    out.add(utf8.encode(pr));
    out.add([0x1D, 0x21, 0x00]); // обычный размер
    if (barcode != null && barcode.isNotEmpty) {
      final data = utf8.encode(barcode);
      out.add([0x1D, 0x68, 0x50]); // высота штрих-кода
      out.add([0x1D, 0x77, 0x02]); // ширина модуля
      out.add([0x1D, 0x6B, 0x49, data.length]); // GS k CODE128
      out.add(data);
      out.add(utf8.encode('\n$barcode\n'));
    }
    out.add([0x1D, 0x56, 0x42, 0x00]); // отрезка
    return out.toBytes();
  }

  /// Транслитерация кириллицы: дешёвые BT-принтеры не знают русские буквы.
  static String translit(String s) {
    const base = {
      'А': 'A', 'Б': 'B', 'В': 'V', 'Г': 'G', 'Д': 'D', 'Е': 'E',
      'Ё': 'E', 'Ж': 'ZH', 'З': 'Z', 'И': 'I', 'Й': 'Y', 'К': 'K',
      'Л': 'L', 'М': 'M', 'Н': 'N', 'О': 'O', 'П': 'P', 'Р': 'R',
      'С': 'S', 'Т': 'T', 'У': 'U', 'Ф': 'F', 'Х': 'H', 'Ц': 'TS',
      'Ч': 'CH', 'Ш': 'SH', 'Щ': 'SCH', 'Ъ': '', 'Ы': 'Y', 'Ь': '',
      'Э': 'E', 'Ю': 'YU', 'Я': 'YA',
    };
    final b = StringBuffer();
    for (final r in s.runes) {
      final ch = String.fromCharCode(r);
      final lat = base[ch.toUpperCase()];
      if (lat == null) {
        b.write(ch);
      } else {
        b.write(ch == ch.toUpperCase() ? lat : lat.toLowerCase());
      }
    }
    return b.toString();
  }

  /// Только ASCII для принтера + перенос по словам.
  static String _sanitize(String s) => s
      .replaceAll('—', '-')
      .replaceAll('–', '-')
      .replaceAll('«', '"')
      .replaceAll('»', '"')
      .replaceAll('№', '#')
      .replaceAll(RegExp(r'[^\x20-\x7E]'), '');

  static List<String> _wrap(String s, int width) {
    final words = s.split(' ');
    final lines = <String>[];
    var cur = '';
    for (final w in words) {
      if ((cur.isEmpty ? w : '$cur $w').length > width) {
        if (cur.isNotEmpty) lines.add(cur);
        cur = w;
      } else {
        cur = cur.isEmpty ? w : '$cur $w';
      }
    }
    if (cur.isNotEmpty) lines.add(cur);
    return lines.isEmpty ? [''] : lines;
  }

  /// Текстовое представление (для файла на десктопе).
  String _plainText(Order order, {required bool invoice}) {
    final b = StringBuffer();
    b.writeln(invoice ? 'НАКЛАДНАЯ №${order.number}' : 'КАССОВЫЙ ЧЕК №${order.number}');
    b.writeln('RadioTrade');
    b.writeln('Клиент: ${order.clientName}');
    b.writeln('--------------------------------');
    for (final l in order.lines) {
      b.writeln('${l.sku} x${_f(l.qty)} @ ${_f(l.price)} = ${_f(l.total)}');
    }
    b.writeln('--------------------------------');
    b.writeln('ИТОГО: ${_f(order.total)} руб.');
    b.writeln('Оплата: ${order.payType.name}');
    return b.toString();
  }

  /// Сырые ESC/POS-байты для Bluetooth-принтера.
  Uint8List _build(Order order, {required bool invoice}) {
    final out = BytesBuilder();
    out.add([0x1B, 0x40]); // ESC @ — инициализация
    out.add([0x1B, 0x61, 0x01]); // центрирование
    out.add([0x1B, 0x21, 0x30]); // крупный шрифт
    out.add(utf8.encode(invoice ? 'NAKLADNAYA #${order.number}\n' : 'CHEK #${order.number}\n'));
    out.add([0x1B, 0x21, 0x00]); // обычный шрифт
    out.add(utf8.encode('RadioTrade\n\n'));
    out.add([0x1B, 0x61, 0x00]); // влево
    out.add(utf8.encode('Client: ${order.clientName}\n'));
    for (final l in order.lines) {
      out.add(utf8.encode('${l.sku} x${_f(l.qty)} @ ${_f(l.price)}\n'));
    }
    out.add(utf8.encode('--------------------------------\n'));
    out.add([0x1B, 0x61, 0x02]); // вправо
    out.add(utf8.encode('TOTAL: ${_f(order.total)} RUB\n\n\n'));
    out.add([0x1D, 0x56, 0x42, 0x00]); // отрезка бумаги
    return out.toBytes();
  }

  String _f(double v) => v.toStringAsFixed(2);
}

/// Сканер штрихкодов: камера (mobile_scanner) или HID/клавиатурный сканер.
/// HID-сканер эмулирует клавиатуру — строка приходит в фокусированное
/// TextField; этот сервис — для аппаратных сканеров терминалов (TSD/Zebra).
class BarcodeScanner {
  static const _ch = MethodChannel('radiotrade/scanner');
  Future<String?> scanWithHw() async {
    try {
      return await _ch.invokeMethod<String>('scan');
    } on PlatformException {
      return null;
    }
  }
}
