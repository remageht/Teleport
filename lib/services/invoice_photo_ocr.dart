import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image/image.dart' as img_lib;
import 'package:path_provider/path_provider.dart';

/// Строка, вытащенная из фото накладной.
typedef OcrLine = ({String name, double qty, double price});

/// Полный результат распознавания накладной.
typedef OcrInvoiceResult = ({
  List<OcrLine> lines,
  String? number,
  String? supplier,
});

/// Распознавание накладной с фото (on-device, офлайн).
/// Латиница и цифры — хорошо, кириллица может кривиться:
/// результат всегда правится руками в карточках строк,
/// а дальше работает общий матчинг с базой (точное — плюсуется,
/// похожее — на выбор).
class InvoicePhotoOcr {
  /// Распознать позиции (обратная совместимость).
  static Future<List<OcrLine>> recognize(String imagePath) async {
    final res = await recognizeFull(imagePath);
    return res.lines;
  }

  /// Полный цикл: фото -> список позиций + номер + поставщик.
  static Future<OcrInvoiceResult> recognizeFull(String imagePath) async {
    final file = File(imagePath);
    if (!await file.exists()) {
      return (lines: <OcrLine>[], number: null, supplier: null);
    }

    String pathToScan = imagePath;
    File? tempFile;

    // 1. Нормализация ориентации по EXIF и подготовка файла
    try {
      final bytes = await file.readAsBytes();
      final decoded = img_lib.decodeImage(bytes);
      if (decoded != null) {
        final oriented = img_lib.bakeOrientation(decoded);
        final tmpDir = await getTemporaryDirectory();
        final tmpPath =
            '${tmpDir.path}/ocr_baked_${DateTime.now().millisecondsSinceEpoch}.jpg';
        final bakedBytes = img_lib.encodeJpg(oriented, quality: 92);
        tempFile = File(tmpPath);
        await tempFile.writeAsBytes(bakedBytes);
        pathToScan = tmpPath;
      }
    } catch (e) {
      debugPrint('EXIF bake warning: $e');
      pathToScan = imagePath;
    }

    try {
      // 2. Первичный проход распознавания
      var res = await _processImage(pathToScan);

      // 3. Если строк не нашлось или их мало (например, документ снят в альбомной
      // ориентации под 90° как на Image 2), пробуем поворот на 90° и 270°.
      if (res.lines.isEmpty && tempFile != null) {
        try {
          final bytes = await tempFile.readAsBytes();
          final img = img_lib.decodeImage(bytes);
          if (img != null) {
            // Поворот 90° CW
            final rot90 = img_lib.copyRotate(img, angle: 90);
            final rot90Path =
                '${tempFile.parent.path}/ocr_rot90_${DateTime.now().millisecondsSinceEpoch}.jpg';
            final rot90File = File(rot90Path);
            await rot90File.writeAsBytes(img_lib.encodeJpg(rot90, quality: 90));
            final rot90Res = await _processImage(rot90Path);
            try {
              await rot90File.delete();
            } catch (_) {}

            if (rot90Res.lines.length > res.lines.length) {
              res = rot90Res;
            }

            // Если всё ещё пусто, пробуем 270° CW
            if (res.lines.isEmpty) {
              final rot270 = img_lib.copyRotate(img, angle: 270);
              final rot270Path =
                  '${tempFile.parent.path}/ocr_rot270_${DateTime.now().millisecondsSinceEpoch}.jpg';
              final rot270File = File(rot270Path);
              await rot270File
                  .writeAsBytes(img_lib.encodeJpg(rot270, quality: 90));
              final rot270Res = await _processImage(rot270Path);
              try {
                await rot270File.delete();
              } catch (_) {}

              if (rot270Res.lines.length > res.lines.length) {
                res = rot270Res;
              }
            }
          }
        } catch (e) {
          debugPrint('Rotation OCR fallback warning: $e');
        }
      }

      return res;
    } finally {
      if (tempFile != null && await tempFile.exists()) {
        try {
          await tempFile.delete();
        } catch (_) {}
      }
    }
  }

  /// Распознать текст из конкретного файла изображения.
  static Future<OcrInvoiceResult> _processImage(String path) async {
    final input = InputImage.fromFilePath(path);
    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final recognized = await recognizer.processImage(input);
      final rawLines = <String>[];

      // Собираем прямые строки из блоков
      for (final block in recognized.blocks) {
        for (final line in block.lines) {
          rawLines.add(line.text);
        }
      }

      // Также собираем строки, сгруппированные по горизонтальной линии (Y-координате),
      // на случай если MLKit разбил таблицу на вертикальные колонки-блоки.
      final tableRows = _reconstructTableRows(recognized.blocks);
      for (final r in tableRows) {
        if (!rawLines.contains(r)) {
          rawLines.add(r);
        }
      }

      final out = <OcrLine>[];
      final seenNames = <String>{};

      for (final line in rawLines) {
        final parsed = parseLine(line);
        if (parsed != null) {
          final norm = parsed.name.toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
          if (!seenNames.contains(norm)) {
            seenNames.add(norm);
            out.add(parsed);
          }
        }
      }

      // Попытка извлечь номер накладной/заказа и поставщика из шапки
      final docInfo = _parseDocInfo(recognized.text);

      return (
        lines: out,
        number: docInfo.number,
        supplier: docInfo.supplier,
      );
    } finally {
      await recognizer.close();
    }
  }

  /// Восстановление строк таблицы при вертикальной разбивке на колонки.
  static List<String> _reconstructTableRows(List<TextBlock> blocks) {
    final allLines = <TextLine>[];
    for (final b in blocks) {
      allLines.addAll(b.lines);
    }
    if (allLines.length < 3) return [];

    // Сортируем по вертикали (top)
    allLines.sort((a, b) => a.boundingBox.top.compareTo(b.boundingBox.top));

    final clusters = <List<TextLine>>[];
    for (final line in allLines) {
      final lineMidY = (line.boundingBox.top + line.boundingBox.bottom) / 2.0;
      final lineH = max(10.0, line.boundingBox.height);
      bool placed = false;
      for (final cluster in clusters) {
        final clusterMidY = cluster
                .map((l) => (l.boundingBox.top + l.boundingBox.bottom) / 2.0)
                .reduce((a, b) => a + b) /
            cluster.length;
        if ((lineMidY - clusterMidY).abs() < lineH * 0.6) {
          cluster.add(line);
          placed = true;
          break;
        }
      }
      if (!placed) {
        clusters.add([line]);
      }
    }

    final result = <String>[];
    for (final cluster in clusters) {
      if (cluster.length <= 1) continue;
      // Сортируем слева направо внутри строки
      cluster.sort((a, b) => a.boundingBox.left.compareTo(b.boundingBox.left));
      final joined = cluster.map((l) => l.text.trim()).join(' ');
      result.add(joined);
    }
    return result;
  }

  static final _skipWords = [
    'итого',
    'всего наименований',
    'всего',
    'к оплате',
    'долг',
    'рублей',
    'копеек',
    'подпись',
    'печать',
    'сдал',
    'принял',
    'заказчик',
    'плательщик',
    'грузополучатель',
    'инн',
    'кпп',
    'банк',
    'бик',
    'р/с',
    'к/с',
    'счет-фактура',
  ];

  /// Разбор одной текстовой строки накладной:
  /// Ищет количество, цену, сумму и очищает название.
  static OcrLine? parseLine(String raw) {
    var line = raw.trim();
    if (line.length < 3) return null;

    final low = line.toLowerCase();
    if (low.startsWith('заказ') ||
        low.startsWith('исполнитель') ||
        low.startsWith('поставщик') ||
        low.startsWith('покупатель') ||
        low.startsWith('клиент') ||
        low.startsWith('накладная') ||
        low.startsWith('счет') ||
        low.startsWith('счёт') ||
        low.startsWith('акт')) {
      return null;
    }

    for (final w in _skipWords) {
      if (low.contains(w)) return null;
    }

    // Пропуск шапки таблицы
    if ((low.contains('артикул') || low.contains('штрихкод') || low.contains('товары')) &&
        (low.contains('количество') || low.contains('цена') || low.contains('сумма'))) {
      return null;
    }

    // 1. Нормализация тысяч с пробелами (например, "2 196,18" -> "2196,18")
    // Проверяем что перед числом пробел или начало строки, а не точка/запятая
    line = line.replaceAllMapped(
      RegExp(r'(?:^|(?<=\s))(\d{1,3})\s+(\d{3}[\.,]\d{2})\b'),
      (m) => '${m.group(1)}${m.group(2)}',
    );

    // 1б. Вырезаем EAN-штрихкоды (12-14 цифр подряд) ПЕРЕД любыми
    // проверками: иначе их куски становятся «количеством» и «ценой»,
    // а сам код проходит под маску телефона.
    line = line.replaceAll(RegExp(r'\b\d{12,14}\b'), ' ');
    line = line.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (line.length < 3) return null;

    // 1а. Структурный мусор, который стоп-слова не ловят (особенно когда
    // кириллица искривлена латиницей): строки валют/итогов, телефоны,
    // адреса. Это не товарные позиции.
    final nospace = line.replaceAll(RegExp(r'\s+'), '');
    if (RegExp(r'RUB', caseSensitive: false).hasMatch(line)) {
      return null; // строка итога/валюты
    }
    if (RegExp(r'8-?\d{3}-?\d{3}-?\d{2}-?\d{2}').hasMatch(nospace) ||
        RegExp(r'\+7\d{10}').hasMatch(nospace)) {
      return null; // телефон
    }
    if (RegExp(r'(Респ|ул\.|Дом|тел\.|Teл|Peсп|Resp|Dom\b|ul\.)',
            caseSensitive: false)
        .hasMatch(line)) {
      return null; // адрес поставщика
    }

    // 2. Убираем единицы измерения и галочки приемки перед ценой ("v шт", "✓ шт", "шт", "wt")
    line = line.replaceAll(
      RegExp(r'(?:[vV✓L\\/|]\s*)?(?:шт|wt|ut|уп|кг|м|л)\b', caseSensitive: false),
      ' ',
    );

    // 3. Ищем все числовые совпадения в строке
    final numMatches = RegExp(r'\d+(?:[\.,]\d+)?').allMatches(line).toList();
    if (numMatches.isEmpty) return null;

    double numVal(String s) =>
        double.tryParse(s.replaceAll(',', '.')) ?? 0.0;

    var qty = 1.0;
    var price = 0.0;
    var nameEndPos = line.length;

    // Проверяем последние 3 числа на соотношение qty * price ≈ sum
    if (numMatches.length >= 3) {
      final m1 = numMatches[numMatches.length - 3];
      final m2 = numMatches[numMatches.length - 2];
      final m3 = numMatches[numMatches.length - 1];

      final between12 = line.substring(m1.end, m2.start).trim();
      final between23 = line.substring(m2.end, m3.start).trim();
      final tailAfter = line.substring(m3.end).trim();

      // Между ценой и суммой только пробелы, после суммы пусто.
      // Между кол-вом и ценой могут быть единицы измерения и галочки ("v шт", "шт", "✓").
      if (between23.isEmpty && tailAfter.isEmpty && between12.length <= 15) {
        final v1 = numVal(m1.group(0)!);
        final v2 = numVal(m2.group(0)!);
        final v3 = numVal(m3.group(0)!);
        if ((v1 * v2 - v3).abs() < max(1.5, v3 * 0.05)) {
          qty = v1;
          price = v2;
          nameEndPos = m1.start;
        } else if ((v2 * v3 - v1).abs() < max(1.5, v1 * 0.05)) {
          qty = v2;
          price = v3;
          nameEndPos = m1.start;
        }
      }
    }

    // Если 3 числа не сошлись, проверяем последние 2 числа
    if (price == 0 && numMatches.length >= 2) {
      final m1 = numMatches[numMatches.length - 2];
      final m2 = numMatches[numMatches.length - 1];

      final between = line.substring(m1.end, m2.start).trim();
      final tailAfter = line.substring(m2.end).trim();

      if (between.length <= 15 && tailAfter.isEmpty) {
        final v1 = numVal(m1.group(0)!);
        final v2 = numVal(m2.group(0)!);

        if (v1 > 0 && v2 > 0) {
          final ratio = v2 / v1;
          if (ratio >= 2 && (ratio - ratio.round()).abs() < 0.05 && ratio < 1000) {
            // v1 - цена, v2 - сумма
            qty = ratio.roundToDouble();
            price = v1;
            nameEndPos = m1.start;
          } else if (v1 <= 500 && v1 == v1.roundToDouble()) {
            // v1 - целое количество, v2 - цена
            qty = v1;
            price = v2;
            nameEndPos = m1.start;
          } else {
            qty = 1.0;
            price = v2;
            nameEndPos = m2.start;
          }
        }
      }
    }

    // Если всё ещё не нашли, берём последнее число как цену
    if (price == 0 && numMatches.isNotEmpty) {
      final lastM = numMatches.last;
      if (line.substring(lastM.end).trim().isEmpty) {
        price = numVal(lastM.group(0)!);
        qty = 1.0;
        nameEndPos = lastM.start;
      }
    }

    if (price <= 0) return null;
    if (qty <= 0) qty = 1.0;

    // 4. Срезаем лидирующие кодовые токены (номер строки, артикул,
    // штрихкод, коды): всё без кириллицы до первого токена с кириллицей.
    // Штрихкоды уже вырезаны раньше; это добивает артикулы вида
    // "GP 24AUA21-2CRS BC4 40/320". Если кириллицы нет вообще
    // (латинское название вроде "TIP36") — оставляем целиком.
    var name = line.substring(0, nameEndPos).trim();
    var toks =
        name.split(' ').where((t) => t.isNotEmpty).toList();
    if (toks.any((t) => RegExp(r'[А-Яа-я]').hasMatch(t))) {
      var cut = 0;
      for (final t in toks) {
        if (RegExp(r'[А-Яа-я]').hasMatch(t)) break;
        cut++;
      }
      if (cut < toks.length) {
        toks = toks.sublist(cut);
      }
      name = toks.join(' ');
    } else {
      name = toks.join(' ');
    }

    // Зачистка знаков препинания на концах
    name = name.replaceAll(RegExp(r'[-.,;:–—|/\\]+$'), '').trim();
    name = name.replaceAll(RegExp(r'^[-.,;:–—|/\\]+'), '').trim();
    name = name.replaceAll(RegExp(r'\s+'), ' ').trim();

    // Должно содержать хотя бы 2 символа и буквы
    if (name.length < 2) return null;
    if (!RegExp(r'[A-Za-zА-Яа-я]').hasMatch(name)) return null;

    return (name: name, qty: qty, price: price);
  }

  /// Извлечение номера накладной и поставщика из шапки документа
  static ({String? number, String? supplier}) _parseDocInfo(String text) {
    String? number;
    String? supplier;

    // Номер документа
    final numMatch = RegExp(
      r'(?:заказ\s+клиента|накладная\s*[№N#]?|счет[- ]фактура\s*[№N#]?|акт\s*[№N#]?)\s*[:№N#]?\s*([A-Za-zА-Яа-я0-9_-]+)',
      caseSensitive: false,
    ).firstMatch(text);
    if (numMatch != null) {
      number = numMatch.group(1)?.trim();
    }

    // Поставщик / Исполнитель
    final supMatch = RegExp(
      r'(?:исполнитель|поставщик|от\s+кого)\s*[:\-]?\s*([^\n,;]+)',
      caseSensitive: false,
    ).firstMatch(text);
    if (supMatch != null) {
      supplier = supMatch.group(1)?.trim();
      if (supplier != null && supplier.length > 50) {
        supplier = supplier.substring(0, 50).trim();
      }
    }

    return (number: number, supplier: supplier);
  }
}
